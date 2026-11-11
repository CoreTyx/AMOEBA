"""The bring-up gateware on the PYNQ-Z2, driven the way tb_fbu_vs_pin's PS model
drives it in simulation (fpga/bringup/tb/tb_fbu_vs_pin.sv, BOARD_TOP)."""

import hashlib
import os
import struct
import sys
import time

import numpy as np

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
from amoeba.mmio import Mmio  # noqa: E402
from amoeba import pl  # noqa: E402

from . import regs as R  # noqa: E402

MASK64 = (1 << 64) - 1
EXT_MEM_BASE = 0x8000_0000
EXT_MEM_END = 0x9000_0000
PRESCALE = 1


def prng_seed_state(seed: int) -> int:
    """fbu_pkg::prng_seed_state: pin_link_agent's generator seeding."""
    p = (0x9E37_79B9_7F4A_7C15 ^ (seed * 0x2545_F491_4F6C_DD1D)) & MASK64
    return p or 1


def mix64(z: int) -> int:
    """pin_link_agent's unwritten-memory pattern."""
    z = ((z ^ (z >> 30)) * 0xBF58_476D_1CE4_E5B9) & MASK64
    z = ((z ^ (z >> 27)) * 0x94D0_49BB_1331_11EB) & MASK64
    return z ^ (z >> 31)


def read_lst(path: str) -> dict:
    """bin/generate_memory_file.py -8 output: {word index: 64-bit word}."""
    words = {}
    index = 0
    with open(path) as fh:
        for line in fh:
            line = line.strip()
            if not line or line[0] in "/#":
                continue
            if line[0] == "@":
                index = int(line[1:], 16)
                continue
            words[index] = int(line, 16)
            index += 1
    return words


def contiguous_runs(image: dict):
    """(first word index, [words]) for each run of consecutive word indices."""
    run_start = None
    run = []
    for k in sorted(image):
        if run and k != run_start + len(run):
            yield run_start, run
            run = []
        if not run:
            run_start = k
        run.append(image[k])
    if run:
        yield run_start, run


# What this boot last loaded (/run is cleared at boot).  Reloading the DDR
# build wedges the PS after a few loads (the configuration DMA's DDR reads
# time out), so a bitstream already in the PL is not loaded again.
LOADED_MARK = "/run/forte_loaded"


def file_md5(path: str) -> str:
    with open(path, "rb") as fh:
        return hashlib.md5(fh.read()).hexdigest()


def program_once(bitstream: str, fclk_mhz: float) -> bool:
    """True when it loaded the PL, False when the bitstream was already there."""
    digest = file_md5(bitstream)
    try:
        with open(LOADED_MARK) as fh:
            loaded = fh.read().strip()
    except OSError:
        loaded = ""
    if loaded == digest and pl._fpga_state() == "operating":
        print(f"# {os.path.basename(bitstream)} already loaded; FCLK0 -> {pl.set_fclk0_mhz(fclk_mhz):.3f} MHz")
        return False
    pl.program(bitstream, fclk_mhz=fclk_mhz)
    with open(LOADED_MARK, "w") as fh:
        fh.write(digest + "\n")
    return True


class Forte:
    def __init__(self, bitstream: str = None, fclk_mhz: float = 25.0):
        loaded = bool(bitstream) and program_once(bitstream, fclk_mhz)
        self.ctl = Mmio(R.CTL_BASE, R.CTL_SPAN)
        found = self.ctl.read(R.REG_ID)
        if found != R.FBU_ID:
            raise RuntimeError(f"ID reads 0x{found:08X}, expected 0x{R.FBU_ID:08X}: wrong bitstream?")
        if loaded:
            self.check_config_reset()
        caps = self.ctl.read(R.REG_CAPS)
        self.is_ddr = bool(caps & R.CAPS_MEM_AXI)
        self.has_sink = bool(caps & R.CAPS_SINK)
        self.sink = None
        if self.has_sink:
            # A run that died without hold() may have left the rings on, over
            # memory its process has since freed.
            self.sink_stop()
        # O_SYNC (Mmio) maps the carve-out uncached: HP0 is not coherent with
        # the A9's caches, so a cached write could sit in L2 while the chip
        # reads stale DDR.
        if self.is_ddr:
            self.mem = Mmio(R.DDR_CARVEOUT, R.DDR_SPAN, wordwise=False)
        else:
            self.mem = Mmio(R.MEM_BASE, R.MEM_SPAN)

    # ---- registers ----
    def rd(self, reg: int) -> int:
        return self.ctl.read(reg)

    def wr(self, reg: int, value: int) -> None:
        self.ctl.write(reg, value)

    def rd64(self, lo: int) -> int:
        return self.ctl.read(lo) | (self.ctl.read(lo + 4) << 32)

    def cycles(self) -> int:
        return self.rd64(R.REG_CYC_TOTAL_LO)

    def link_cycles(self) -> int:
        return self.rd64(R.REG_LINK_CYC_LO)

    # ---- configuration ----
    def check_config_reset(self) -> None:
        """Straight after a load: regs.CONFIG_RESET must be the RTL's reset values."""
        wrong = [(a, v, self.rd(a)) for a, v in R.CONFIG_RESET if a in R.CONFIG_RESET_READABLE and self.rd(a) != v]
        if wrong:
            raise RuntimeError("regs.CONFIG_RESET disagrees with the bitstream's reset values: " +
                               ", ".join(f"0x{a:03X} table 0x{v:X} PL 0x{got:X}" for a, v, got in wrong))

    def restore_config(self) -> None:
        """The configuration a fresh load gives (regs.CONFIG_RESET), fault injection stopped."""
        self.wr(R.REG_FI_CTRL, R.pack(R.REG_FI_CTRL, stop=1))
        self.wr(R.REG_SCAN_CTRL, 0)
        for addr, value in R.CONFIG_RESET:
            self.wr(addr, value)

    def configure(self, *, seed=1, gap_pct=0, rd_lat=0, wdog=1000, mutate=0, det=True,
                  tohost=0x8080_0000, stop_on_error=True, boot_gate=False,
                  boot_gate_selftest=False, boot_gate_retries=2, trace=True):
        self.wr(R.REG_PIN_CTRL, 0)
        self.wr(R.REG_SOFT_RESET, 1)
        self.restore_config()
        self.wr(R.REG_LINK_CFG, R.pack(R.REG_LINK_CFG, det=int(det), gap_pct=gap_pct, rd_lat=rd_lat))
        self.wr(R.REG_LINK_WDOG, R.pack(R.REG_LINK_WDOG, wdog=wdog, mutate=mutate))
        init = prng_seed_state(seed)
        self.wr(R.REG_PRNG_INIT_LO, init & 0xFFFF_FFFF)
        self.wr(R.REG_PRNG_INIT_HI, init >> 32)
        self.wr(R.REG_PRNG_LOAD, 1)
        self.wr(R.REG_TOHOST_ADDR, tohost)
        self.wr(R.REG_TRACE_CLEAR, 1)
        self.wr(R.REG_TRACE_CTRL, R.pack(R.REG_TRACE_CTRL, enable=int(trace), stop_on_error=int(stop_on_error)))
        self.wr(R.REG_UART_CLEAR, 1)
        self.wr(R.REG_BOOTGATE, R.pack(R.REG_BOOTGATE, enable=int(boot_gate), selftest=int(boot_gate_selftest),
                                       retries=boot_gate_retries, timeout=1000))
        self.seed = seed
        self.uart_div(1)

    # ---- memory ----
    @staticmethod
    def window_of(addr: int):
        for w, (base, size) in enumerate(R.MEM_WINDOWS):
            if base <= addr < base + size:
                return w
        return None

    @staticmethod
    def port_b_offset(addr: int) -> int:
        w = Forte.window_of(addr)
        return (w << 18) + addr - R.MEM_WINDOWS[w][0]

    def unwritten_word(self, k: int, policy: str) -> int:
        """The pin bench's memory where nothing was loaded (word index k)."""
        return 0 if policy == "zero" else mix64(k ^ (self.seed << 40))

    def load_lst(self, path: str, policy: str = "rand", fill: bool = True) -> dict:
        """Fill every window with what the pin bench's memory would hold there,
        then load the image and read it back.  Refuses while the chip is
        released.  In DDR builds the image may lie anywhere in EXT_MEM, and
        fill=False skips the windows' pattern (a Linux image needs none)."""
        if self.rd(R.REG_PIN_CTRL) & 1:
            raise RuntimeError("load while the chip is released")
        image = read_lst(path)
        if self.is_ddr:
            self._load_ddr(image, policy, fill)
        else:
            self._load_bram(image, policy)
        return image

    def _load_bram(self, image: dict, policy: str) -> None:
        outside = [k for k in image if EXT_MEM_BASE <= k * 8 < EXT_MEM_END and self.window_of(k * 8) is None]
        if outside:
            raise RuntimeError(f"{len(outside)} image words fall outside the memory windows, "
                               f"first at 0x{outside[0] * 8:08X}")
        for w, (base, size) in enumerate(R.MEM_WINDOWS):
            self.mem.write(R.MEM_REG_WINDOW_BASE + 4 * w, base)
            for off in range(0, size, 8):
                k = (base + off) >> 3
                word = image[k] if k in image else self.unwritten_word(k, policy)
                self.mem.write((w << 18) + off, word & 0xFFFF_FFFF)
                self.mem.write((w << 18) + off + 4, word >> 32)
        bad = 0
        for k, word in image.items():
            if self.window_of(k * 8) is None:
                continue
            o = self.port_b_offset(k * 8)
            if self.mem.read(o) | (self.mem.read(o + 4) << 32) != word:
                bad += 1
        if bad:
            raise RuntimeError(f"{bad} image words read back wrong")

    def _load_ddr(self, image: dict, policy: str, fill: bool) -> None:
        # Words outside EXT_MEM (generate_memory_file.py's UART LSR word for the
        # sim models) are the chip's own registers, as in _load_bram.
        image = {k: w for k, w in image.items() if EXT_MEM_BASE <= k * 8 < EXT_MEM_END}
        if fill:
            for base, size in R.MEM_WINDOWS:
                blob = bytearray(size)
                for off in range(0, size, 8):
                    k = (base + off) >> 3
                    struct.pack_into("<Q", blob, off, image[k] if k in image else self.unwritten_word(k, policy))
                self.mem.write_bytes(base - EXT_MEM_BASE, bytes(blob))
        for start, words in contiguous_runs(image):
            self.mem.write_bytes(start * 8 - EXT_MEM_BASE, struct.pack(f"<{len(words)}Q", *words))
        bad = 0
        for start, words in contiguous_runs(image):
            back = self.mem.read_bytes(start * 8 - EXT_MEM_BASE, 8 * len(words))
            bad += sum(a != b for a, b in zip(struct.unpack(f"<{len(words)}Q", back), words))
        if bad:
            raise RuntimeError(f"{bad} image words read back wrong")

    def read_mem64(self, addr: int) -> int:
        if self.is_ddr:
            return struct.unpack("<Q", self.mem.read_bytes(addr - EXT_MEM_BASE, 8))[0]
        o = self.port_b_offset(addr)
        return self.mem.read(o) | (self.mem.read(o + 4) << 32)

    def mem_status(self) -> dict:
        """fbu_mem_axi_hp's counters (all zero in BRAM builds).  They count from
        the PL's load, not the run: the error flag is sticky and lat_max is the
        worst since the load."""
        stat = self.rd(R.REG_MEM_STAT)
        reads = self.rd(R.REG_MEM_READS)
        lat_sum = self.rd64(R.REG_MEM_LAT_SUM_LO)
        return {"err": stat & 1, "err_resp": (stat >> 8) & 3, "err_addr": self.rd(R.REG_MEM_ERR_ADDR),
                "reads": reads, "writes": self.rd(R.REG_MEM_WRITES), "dropped": self.rd(R.REG_MEM_DROPPED),
                "lat_max": self.rd(R.REG_MEM_LAT_MAX), "lat_sum": lat_sum,
                "lat_mean": lat_sum / reads if reads else 0.0,
                "hist": [self.rd(R.REG_MEM_LAT_HIST + 4 * b) for b in range(R.MEM_LAT_BINS)]}

    # ---- DDR sink (fbu_dma_sink): trace and console rings in PS memory ----
    def sink_start(self, trace_log2: int = 16, console_log2: int = 20, trace: bool = True) -> None:
        """Rings of 2**trace_log2 records and 2**console_log2 console bytes, in
        uncached CMA buffers: the PL writes them through HP2, which the A9's
        caches do not see.  hold() turns the rings off before they are freed."""
        from pynq import allocate
        self.sink_stop()
        trace_buf = allocate(shape=(R.SINK_TRACE_SLOT << trace_log2,), dtype="u1", cacheable=False)
        console_buf = allocate(shape=(R.SINK_CONSOLE_ENTRY << console_log2,), dtype="u1", cacheable=False)
        self.sink = {"trace": trace_buf, "console": console_buf, "trace_log2": trace_log2,
                     "console_log2": console_log2, "trace_read": 0, "console_read": 0}
        self.wr(R.REG_SINK_CTRL, 1 << 8)
        self.wr(R.REG_SINK_TRACE_BASE, trace_buf.physical_address)
        self.wr(R.REG_SINK_TRACE_LOG2, trace_log2)
        self.wr(R.REG_SINK_CON_BASE, console_buf.physical_address)
        self.wr(R.REG_SINK_CON_LOG2, console_log2)
        self.wr(R.REG_SINK_CTRL, (1 if trace else 0) | 2)

    def sink_stop(self) -> None:
        """Rings off, and no write in flight, before any buffer goes away."""
        self.wr(R.REG_SINK_CTRL, 0)
        for _ in range(1000):
            if not self.rd(R.REG_SINK_STAT) >> 16 & 1:
                break
        if self.sink is not None:
            self.sink["trace"].freebuffer()
            self.sink["console"].freebuffer()
            self.sink = None

    def sink_status(self) -> dict:
        stat = self.rd(R.REG_SINK_STAT)
        return {"err": stat & 1, "err_resp": stat >> 8 & 3,
                "trace": self.sink["trace_read"] if self.sink else 0,
                "console": self.sink["console_read"] if self.sink else 0}

    def output_pending(self) -> bool:
        """Anything the chip produced that drain_uart/drain_trace have not returned."""
        if self.rd(R.REG_UART_RX_DATA) >> 31 or self.rd(R.REG_TRACE_STAT) & 1:
            return True
        if self.sink is None:
            return False
        return bool(self.rd(R.REG_SINK_STAT) >> 16 & 1 or
                    self.rd(R.REG_SINK_TRACE_WR) != self.sink["trace_read"] & 0xFFFF_FFFF or
                    self.rd(R.REG_SINK_CON_WR) != self.sink["console_read"] & 0xFFFF_FFFF)

    # ---- pins ----
    def set_pins(self, **fields) -> None:
        """Read-modify-write: triggers change PIN_CTRL's irq bits too."""
        word = self.rd(R.REG_PIN_CTRL)
        for name, value in fields.items():
            lsb, width = R.FIELDS[R.REG_PIN_CTRL][name]
            word = (word & ~(((1 << width) - 1) << lsb)) | (value << lsb)
        self.wr(R.REG_PIN_CTRL, word)

    def reset(self, cycles: int) -> None:
        self.wr(R.REG_RST_PULSE, cycles + 1)
        self.set_pins(release=1)

    def hold(self) -> None:
        """Hold the chip in reset and let the memory backend finish what it
        started.  Every run ends here: a chip left running keeps HP0 busy, and
        reprogramming the PL under an HP0 transaction wedges the PS (the next
        load's DMA fails, then the PS locks up)."""
        self.set_pins(release=0)
        time.sleep(0.01)
        if self.has_sink:
            self.sink_stop()

    def irq(self, line: int, level: int) -> None:
        irq = R.unpack(R.REG_PIN_CTRL, self.rd(R.REG_PIN_CTRL), "irq")
        irq = (irq & ~(1 << line)) | (level << line)
        self.set_pins(irq=irq)

    # ---- console ----
    def uart_div(self, div: int) -> None:
        bit = 16 * (div << PRESCALE)
        self.wr(R.REG_UART_RX_BIT, bit)
        self.wr(R.REG_UART_TX_PERIOD, bit << 8)

    def uart_send(self, data: bytes, kind: int = R.UART_TX_BYTE) -> None:
        for b in data:
            while self.rd(R.REG_UART_STAT) & 0b10:
                pass
            self.wr(R.REG_UART_TX_PUSH, R.pack(R.REG_UART_TX_PUSH, data=b, kind=kind))

    def set_match(self, matcher: int, text: bytes) -> None:
        if len(text) > 32:
            raise ValueError("a match pattern is at most 32 bytes")
        base = R.REG_UART_MATCH0 if matcher == 0 else R.REG_UART_MATCH1
        rev = text[::-1].ljust(32, b"\0")
        for w in range(8):
            self.wr(base + 4 * w, int.from_bytes(rev[4 * w:4 * w + 4], "little"))
        lens = self.rd(R.REG_UART_MATCH_LEN)
        lens = (lens & ~(0xFF << (8 * matcher))) | (len(text) << (8 * matcher))
        self.wr(R.REG_UART_MATCH_LEN, lens)
        self.wr(R.REG_UART_MATCH_CTRL, 1 << matcher)

    def match_hit(self, matcher: int) -> bool:
        return bool(self.rd(R.REG_UART_MATCH_CTRL) >> matcher & 1)

    def drain_uart(self, limit: int = 4096):
        """Received bytes, and the framing errors among them."""
        out = bytearray()
        framing = []
        if self.sink is not None:
            return self._sink_console(limit)
        for _ in range(limit):
            d = self.rd(R.REG_UART_RX_DATA)
            if not d >> 31:
                break
            self.wr(R.REG_UART_RX_POP, 1)
            if d >> 8 & 1:
                framing.append(d & 0xFF)
            else:
                out.append(d & 0xFF)
        return bytes(out), framing

    # ---- trace ----
    def drain_trace(self, limit: int = 4096):
        records = []
        if self.sink is not None:
            return self._sink_trace(limit)
        for _ in range(limit):
            if not self.rd(R.REG_TRACE_STAT) & 1:
                break
            words = [self.rd(R.REG_TRACE_HEAD + 4 * i) for i in range(10)]
            self.wr(R.REG_TRACE_POP, 1)
            records.append(sum(w << (32 * i) for i, w in enumerate(words)))
        return records

    def _sink_console(self, limit: int):
        sk = self.sink
        wr = self.rd(R.REG_SINK_CON_WR)
        n = min((wr - sk["console_read"]) & 0xFFFF_FFFF, max(limit, 1 << 16))
        size = 1 << sk["console_log2"]
        entries = sk["console"].view("<u2")[(sk["console_read"] + np.arange(n)) % size]
        bad = (entries >> 8 & 1).astype(bool)
        out = (entries[~bad] & 0xFF).astype("u1").tobytes()
        framing = [int(e & 0xFF) for e in entries[bad]]
        if n:
            sk["console_read"] += n
            self.wr(R.REG_SINK_CON_RD, sk["console_read"] & 0xFFFF_FFFF)
        return bytes(out), framing

    def _sink_trace(self, limit: int):
        sk = self.sink
        wr = self.rd(R.REG_SINK_TRACE_WR)
        n = min((wr - sk["trace_read"]) & 0xFFFF_FFFF, max(limit, 1 << 12))
        size = 1 << sk["trace_log2"]
        buf = sk["trace"]
        records = []
        for i in range(n):
            at = ((sk["trace_read"] + i) % size) * R.SINK_TRACE_SLOT
            records.append(int.from_bytes(bytes(buf[at:at + R.SINK_RECORD_BYTES]), "little"))
        if n:
            sk["trace_read"] += n
            self.wr(R.REG_SINK_TRACE_RD, sk["trace_read"] & 0xFFFF_FFFF)
        return records

    # ---- triggers ----
    def arm_trigger(self, slot: int, source: int, action: int, *, line: int = 0, length: int = 0,
                    arg0: int = 0, arg1: int = 0, repeat: bool = False) -> None:
        base = R.REG_TRIG + 16 * slot
        self.wr(base + 4, arg0)
        self.wr(base + 8, arg1)
        self.wr(base, R.pack(R.REG_TRIG, source=source, action=action, repeat=int(repeat),
                             line=line, length=length, arm=1))

    def trigger_fired(self, slot: int) -> int:
        return self.rd(R.REG_TRIG + 16 * slot + 12)

    def disarm_trigger(self, slot: int) -> None:
        self.wr(R.REG_TRIG + 16 * slot, R.pack(R.REG_TRIG, disarm=1))

    # ---- fault_inject ----
    def fault_pattern(self, mode: int, arg0: int = 0, arg1: int = 0, seed: int = 1,
                      phases=(), start: bool = True) -> None:
        mask = 0
        for p in phases:
            mask |= 1 << (p & 0x1FF)
        for w in range(16):
            self.wr(R.REG_FI_PHASE_MASK + 4 * w, mask >> (32 * w) & 0xFFFF_FFFF)
        self.wr(R.REG_FI_ARG0, arg0)
        self.wr(R.REG_FI_ARG1, arg1)
        self.wr(R.REG_FI_SEED, seed)
        self.wr(R.REG_FI_CTRL, R.pack(R.REG_FI_CTRL, mode=mode, clear_counts=1))
        if start:
            self.wr(R.REG_FI_CTRL, R.pack(R.REG_FI_CTRL, mode=mode, start=1))

    def fault_stop(self) -> None:
        mode = R.unpack(R.REG_FI_CTRL, self.rd(R.REG_FI_CTRL), "mode")
        self.wr(R.REG_FI_CTRL, R.pack(R.REG_FI_CTRL, mode=mode, stop=1))

    def fault_running(self) -> bool:
        return bool(R.unpack(R.REG_FI_CTRL, self.rd(R.REG_FI_CTRL), "running"))

    def fault_events(self) -> dict:
        return {g: self.rd(R.REG_FI_EVENTS + 4 * i) for i, g in enumerate(R.FI_GROUPS)}

    def scan_session(self, pattern, scan_en_from_pattern: bool = True) -> list:
        """One test-mode session (fbu_scan): pattern entries are (io[7:0], scan_en);
        returns io[15:8] as captured each cycle.  test_mode is raised for the
        session and dropped after it."""
        ctrl = 2 if scan_en_from_pattern else 0
        self.wr(R.REG_SCAN_CTRL, ctrl)
        self.wr(R.REG_SCAN_ADDR, 0)
        for value, scan_en in pattern:
            self.wr(R.REG_SCAN_PATTERN, (int(scan_en) << 8) | value)
        self.wr(R.REG_SCAN_LEN, len(pattern))
        pin_ctrl = self.rd(R.REG_PIN_CTRL)
        self.wr(R.REG_PIN_CTRL, pin_ctrl | 0x4)
        self.wr(R.REG_SCAN_CTRL, ctrl | 1)
        while self.rd(R.REG_SCAN_CTRL) & 0x100:
            pass
        self.wr(R.REG_PIN_CTRL, pin_ctrl)
        captured = []
        for i in range(len(pattern)):
            self.wr(R.REG_SCAN_ADDR, i)
            captured.append(self.rd(R.REG_SCAN_CAPTURE) & 0xFF)
        return captured

    def status_clear(self) -> None:
        self.wr(R.REG_STAT_CLASS, 0)

    def status(self) -> dict:
        """The status pin's statistics (fbu_status_mon): half-periods in cycles."""
        cls = self.rd(R.REG_STAT_CLASS)
        return {"class": R.STATUS_CLASSES[cls & 3], "level": (cls >> 8) & 1,
                "last": self.rd(R.REG_STAT_LAST), "min": self.rd(R.REG_STAT_MIN),
                "max": self.rd(R.REG_STAT_MAX), "edges": self.rd(R.REG_STAT_EDGES),
                "glitches": self.rd(R.REG_STAT_GLITCH),
                "clkout_edges": self.rd(R.REG_CLKOUT_EDGES), "clkout_window": self.rd(R.REG_CLKOUT_WINDOW)}

    # ---- status ----
    def link_errors(self) -> int:
        return self.rd(R.REG_LINK_ERR_COUNT)

    def tohost(self):
        if not self.rd(R.REG_TOHOST_STAT) & 1:
            return None
        return self.rd64(R.REG_TOHOST_VAL_LO)


def record_lines(record: int, beats: int = 2):
    """pin_trace.log lines of one fbu_link_trace record, with its sort cycle."""
    kind = record >> 28 & 0xF
    at = record >> 32 & MASK64
    if kind == 1:
        line = " ".join(f"{record >> (128 + 64 * b) & MASK64:016x}" for b in range(beats))
        end = record >> 256 & MASK64
        return end, [f"L {at} {'W' if record >> 27 & 1 else 'R'} {record >> 96 & 0xFFFF_FFFF:08x} {line}"]
    if kind == 2:
        return at, [f"T {at} {record >> 128 & MASK64:016x}"]
    if kind == 3:
        bits = record >> 96 & 0xFFFF_FFFF
        return at, [f"E {at} {R.LINK_ERRORS.get(i, i)}" for i in range(1, 32) if bits >> i & 1]
    if kind == 4:
        return at, [f"I {at} {record >> 24 & 3} {record >> 23 & 1}"]
    return at, [f"? {at} unknown record kind {kind}"]
