"""The bring-up gateware on the PYNQ-Z2, driven the way tb_fbu_vs_pin's PS model
drives it in simulation (fpga/bringup/tb/tb_fbu_vs_pin.sv, BOARD_TOP)."""

import os
import sys
import time

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


class Forte:
    def __init__(self, bitstream: str = None, fclk_mhz: float = 25.0):
        if bitstream:
            pl.program(bitstream, fclk_mhz=fclk_mhz)
        self.ctl = Mmio(R.CTL_BASE, R.CTL_SPAN)
        self.mem = Mmio(R.MEM_BASE, R.MEM_SPAN)
        found = self.ctl.read(R.REG_ID)
        if found != R.FBU_ID:
            raise RuntimeError(f"ID reads 0x{found:08X}, expected 0x{R.FBU_ID:08X}: wrong bitstream?")

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
    def configure(self, *, seed=1, gap_pct=0, rd_lat=0, wdog=1000, mutate=0, det=True,
                  tohost=0x8080_0000, stop_on_error=True, boot_gate=False,
                  boot_gate_selftest=False, boot_gate_retries=2):
        self.wr(R.REG_PIN_CTRL, 0)
        self.wr(R.REG_SOFT_RESET, 1)
        self.wr(R.REG_LINK_CFG, R.pack(R.REG_LINK_CFG, det=int(det), gap_pct=gap_pct, rd_lat=rd_lat))
        self.wr(R.REG_LINK_WDOG, R.pack(R.REG_LINK_WDOG, wdog=wdog, mutate=mutate))
        init = prng_seed_state(seed)
        self.wr(R.REG_PRNG_INIT_LO, init & 0xFFFF_FFFF)
        self.wr(R.REG_PRNG_INIT_HI, init >> 32)
        self.wr(R.REG_PRNG_LOAD, 1)
        self.wr(R.REG_TOHOST_ADDR, tohost)
        self.wr(R.REG_TRACE_CLEAR, 1)
        self.wr(R.REG_TRACE_CTRL, R.pack(R.REG_TRACE_CTRL, enable=1, stop_on_error=int(stop_on_error)))
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

    def load_lst(self, path: str, policy: str = "rand") -> dict:
        """Fill every window with what the pin bench's memory would hold there,
        then read the image back.  Refuses while the chip is released."""
        if self.rd(R.REG_PIN_CTRL) & 1:
            raise RuntimeError("load while the chip is released")
        image = read_lst(path)
        outside = [k for k in image if EXT_MEM_BASE <= k * 8 < EXT_MEM_END and self.window_of(k * 8) is None]
        if outside:
            raise RuntimeError(f"{len(outside)} image words fall outside the memory windows, "
                               f"first at 0x{outside[0] * 8:08X}")
        for w, (base, size) in enumerate(R.MEM_WINDOWS):
            self.mem.write(R.MEM_REG_WINDOW_BASE + 4 * w, base)
            for off in range(0, size, 8):
                k = (base + off) >> 3
                if k in image:
                    word = image[k]
                elif policy == "zero":
                    word = 0
                else:
                    word = mix64(k ^ (self.seed << 40))
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
        return image

    def read_mem64(self, addr: int) -> int:
        o = self.port_b_offset(addr)
        return self.mem.read(o) | (self.mem.read(o + 4) << 32)

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
        for _ in range(limit):
            if not self.rd(R.REG_TRACE_STAT) & 1:
                break
            words = [self.rd(R.REG_TRACE_HEAD + 4 * i) for i in range(10)]
            self.wr(R.REG_TRACE_POP, 1)
            records.append(sum(w << (32 * i) for i, w in enumerate(words)))
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
