"""The Amoeba class: everything the PS can do to the soft core.

The organizing rule, which every method here assumes: THE PS OWNS THE CORE'S
RESET, and it comes out of configuration asserted.  So the core is halted after
the bitstream loads, and the image load, trigger setup and monitor clear all
happen in a quiescent design.  Nothing here races the core, because anything
that would is done while it is held.
"""

import time
from typing import Iterator, Optional

from . import image as _image
from . import regs as R
from . import pl as _pl
from .mmio import Mmio


PAGE_BYTES = 4096


class AmoebaError(RuntimeError):
    pass


class Amoeba:
    def __init__(self, bitstream: Optional[str] = None, *,
                 check_id: bool = True, fclk_mhz: Optional[float] = 25.0):
        """`fclk_mhz` is programmed after download, and must be.

        Nothing else sets it.  The block design records 25 MHz in the .hwh, but
        only pynq.Overlay reads that field, and we use pynq.Bitstream on
        purpose so an unparseable .hwh cannot block bring-up.  Left alone, the
        PL runs at whatever the boot default was -- usually 100 MHz, against a
        design that closed timing at 25.5.  Pass None only if something else
        has already set the clock.
        """
        if bitstream:
            _pl.program(bitstream, fclk_mhz=fclk_mhz)
        self.ctl = Mmio(R.CTL_BASE, R.CTL_SIZE)
        self._mem: Optional[Mmio] = None
        if check_id:
            self.check_id()

    def measure_fclk(self, seconds: float = 0.5) -> float:
        """PL cycles against host wall time -- the clock, measured not assumed.

        This is the only statement about the fabric clock that does not depend
        on the SLCR arithmetic in pl.py being correct, so it is what the
        callers check against.  The core does not need to be running; the cycle
        counter is free-running whenever the core is out of reset.
        """
        was_reset = self.in_reset
        if was_reset:
            self.start()
        c0, t0 = self.cycles, time.monotonic()
        time.sleep(seconds)
        c1, t1 = self.cycles, time.monotonic()
        if was_reset:
            self.halt()
        dt = t1 - t0
        return (c1 - c0) / dt if dt > 0 else 0.0

    def check_fclk(self, expect_mhz: float = 25.0, tol: float = 0.05) -> float:
        """Measure the fabric clock and refuse to continue if it is wrong.

        A PL running at 4x its timing-closed frequency does not announce
        itself: registers still read back, the core still fetches, and what
        comes out is garbage that looks like a logic bug.  Checking here turns
        a day of debugging into one line.
        """
        got = self.measure_fclk()
        if got <= 0:
            raise AmoebaError(
                "the PL cycle counter is not advancing: FCLK0 is stopped, or "
                "the core is held in reset by something other than us.")
        if abs(got - expect_mhz * 1e6) / (expect_mhz * 1e6) > tol:
            raise AmoebaError(
                f"fabric clock measures {got/1e6:.3f} MHz, expected "
                f"{expect_mhz:.3f} MHz.\n"
                "  The design closed timing at 25.5 MHz; running it faster "
                "produces wrong results, not an error.\n"
                "  Set it with:  python3 -c 'from amoeba import pl; "
                "pl.set_fclk0_mhz(25)'")
        return got

    # ---- identity ---------------------------------------------------------
    def check_id(self) -> None:
        """First thing, always.

        A wrong magic here means the overlay did not load or the base address
        is wrong, and every subsequent symptom -- a core that never runs, a
        console that stays empty -- is downstream of it.  Fail here, loudly,
        rather than letting it present as dead hardware.
        """
        got = self.ctl.read(R.R_ID)
        if got != R.ID_MAGIC:
            raise AmoebaError(
                f"ID at 0x{R.CTL_BASE:08x} reads 0x{got:08x}, expected "
                f"0x{R.ID_MAGIC:08x} ('AMOB').\n"
                "  The bitstream is not loaded, or is not this design, or "
                "CTL_BASE in regs.py does not match tcl/bd_pynq.tcl."
            )

    @property
    def version(self) -> int:
        return self.ctl.read(R.R_VERSION)

    @property
    def caps(self) -> int:
        return self.ctl.read(R.R_CAPS)

    @property
    def mem_kb(self) -> int:
        return R.caps_mem_kb(self.caps)

    @property
    def is_bram(self) -> bool:
        return R.caps_is_bram(self.caps)

    @property
    def has_trace(self) -> bool:
        return R.caps_has_trace(self.caps)

    def describe(self) -> str:
        v = self.version
        kib = self.mem_bytes // 1024
        size = f"{kib} KiB" if kib < 1024 else f"{kib // 1024} MiB"
        return (f"amoeba v{(v >> 16) & 0xFF}.{(v >> 8) & 0xFF}.{v & 0xFF}  "
                f"mem={size}  "
                f"backend={'BRAM' if self.is_bram else 'AXI/DDR'}  "
                f"trace={'yes' if self.has_trace else 'no'}")

    # ---- reset and monitors ----------------------------------------------
    @property
    def in_reset(self) -> bool:
        return bool(self.ctl.read(R.R_STATUS) & R.ST_CORE_RESET)

    def halt(self) -> None:
        self.ctl.write(R.R_CTRL, R.CTRL_CORE_RESET)

    def clear_monitors(self) -> None:
        """One-cycle pulse; the reset bit must be preserved across it."""
        keep = self.ctl.read(R.R_CTRL) & R.CTRL_CORE_RESET
        self.ctl.write(R.R_CTRL, keep | R.CTRL_MON_CLEAR | R.CTRL_TRACE_CLEAR)
        self.ctl.write(R.R_CTRL, keep)

    def start(self) -> None:
        self.ctl.write(R.R_CTRL, 0)

    # ---- image ------------------------------------------------------------
    @property
    def mem_bytes(self) -> int:
        """The core's memory, in bytes, whichever backend provides it.

        Not CAPS.mem_kb: that field carries the MEM_KB build parameter
        verbatim and an AXI build leaves it at its default, so it reports a
        128 KiB block RAM that is not there.  See regs.caps_mem_kb.
        """
        return self.mem_kb * 1024 if self.is_bram else R.DDR_CARVEOUT_SIZE

    @staticmethod
    def _carveout_is_reserved(base: int, size: int,
                              iomem: str = "/proc/iomem") -> "Optional[str]":
        """None if the carve-out is outside Linux's RAM, else what overlaps.

        THIS IS NOT A TIDINESS CHECK.  The carve-out is ordinary DDR: if Linux
        was not told to stay out of it, those pages hold running processes and
        kernel data.  Loading an image there scribbles over whatever is live,
        and the PL writes over it again from the other side.  The symptom is
        not a failed load -- the readback verifies fine, because nothing has
        reused the pages yet -- it is segfaults minutes later in unrelated
        programs, an fpga_manager that returns EBUSY, and an SD card that
        slowly fills with corruption.  It also silently invalidates any
        measurement taken on that boot.

        /proc/iomem lists what the kernel claims.  An overlap with a "System
        RAM" region means the reservation was never made.
        """
        end = base + size
        try:
            with open(iomem) as fh:
                lines = fh.read().splitlines()
        except OSError:
            return None                # cannot tell; do not block on it
        for line in lines:
            head, _, name = line.partition(":")
            name = name.strip()
            if name != "System RAM":
                continue
            try:
                lo_s, _, hi_s = head.strip().partition("-")
                lo, hi = int(lo_s, 16), int(hi_s, 16) + 1
            except ValueError:
                continue
            if lo < end and base < hi:
                return f"{lo:#x}-{hi - 1:#x} is System RAM"
        return None

    @property
    def mem(self) -> Mmio:
        """A window onto the core's memory.

        Two different things behind one name, deliberately, so load() does not
        have to care:

        - BRAM build: the AXI4-Lite image window, port B of the dual-port
          block RAM, at a PL address.  Word-at-a-time, because it is a
          peripheral.
        - AXI build: the DDR carve-out at its PS physical address.  The bridge
          maps core 0x8000_0000 to this, so the same
          `offset = paddr - EXT_MEM_BASE` arithmetic addresses both.  Written
          with memcpy, because it is DRAM and 256 MiB a word at a time is not
          a thing that finishes.
        """
        if self._mem is None:
            if self.is_bram:
                self._mem = Mmio(R.MEM_BASE, self.mem_kb * 1024)
            else:
                clash = self._carveout_is_reserved(R.DDR_CARVEOUT_BASE,
                                                   R.DDR_CARVEOUT_SIZE)
                if clash:
                    raise AmoebaError(
                        f"the DDR carve-out 0x{R.DDR_CARVEOUT_BASE:08x}.."
                        f"0x{R.DDR_CARVEOUT_BASE + R.DDR_CARVEOUT_SIZE - 1:08x}"
                        f" is inside Linux's own RAM ({clash}).\n"
                        "  Loading an image there overwrites live kernel and "
                        "process memory, and the\n"
                        "  PL writes over it from the other side.  It does not "
                        "fail cleanly: the\n"
                        "  readback verifies, and then unrelated programs "
                        "segfault minutes later,\n"
                        "  fpga_manager starts returning EBUSY, and every "
                        "measurement from that\n"
                        "  boot is suspect.\n"
                        "  Reserve it on the PS side and reboot -- add "
                        "'mem=256M' to the kernel\n"
                        "  command line on the SD card, or a reserved-memory "
                        "node in the devicetree.\n"
                        "  See fpga/pynq/DESIGN.md 'carve-out'.")
                self._mem = Mmio(R.DDR_CARVEOUT_BASE, R.DDR_CARVEOUT_SIZE,
                                 wordwise=False)
        return self._mem

    def load(self, img: "_image.Image", *, verify: bool = True,
             zero: bool = True, zero_all: bool = False,
             legacy_axi_reset: bool = False) -> None:
        """Load a program while the core is held in reset.

        Checks three things before writing anything, because each of them
        produces a confusing failure much later:

        - that the core is actually halted.  The two BRAM ports are not
          arbitrated -- they are never meant to be live at once -- so writing
          while the core runs corrupts memory silently.
        - that the image fits.  amoeba_mem_bram truncates rather than faulting,
          so an over-large image wraps onto its own start.
        - that the program's `tohost` matches the address the bus monitor is
          watching.  If those drift, the run prints correct console output and
          then hangs forever waiting for an exit that was never seen.
        """
        if not self.in_reset:
            raise AmoebaError("core is running; call halt() before load()")

        size = self.mem_bytes
        end = img.load_end - R.EXT_MEM_BASE
        if img.load_base < R.EXT_MEM_BASE or end > size:
            if self.is_bram:
                where = f"{size // 1024} KiB window at 0x{R.EXT_MEM_BASE:08x}"
                fix = ("  The block RAM truncates rather than faulting, so "
                       "this would wrap onto itself.  Rebuild with a matching "
                       "linker script, or raise MEM_KB.")
            else:
                where = (f"{size // (1024 * 1024)} MiB DDR carve-out mapped "
                         f"at 0x{R.EXT_MEM_BASE:08x}")
                fix = ("  The block design clamps the core to the carve-out, "
                       "so this would fault on the bus rather than wrap.  "
                       "Rebuild with a matching linker script, or widen "
                       "ddr_carveout/ddr_size in tcl/bd_pynq.tcl -- and if "
                       "you widen it, reserve the extra range from the PS "
                       "too.")
            raise AmoebaError(
                f"image spans 0x{img.load_base:08x}..0x{img.load_end:08x}, "
                f"outside the {where}.\n" + fix)

        want = R.tohost_addr(self.mem_kb, self.is_bram)
        have = img.tohost()
        if have is not None and have != want:
            # Name the actual mistake when it is recognisable.  An image built
            # for the OTHER backend is by far the most common cause of this,
            # and generic advice here is worse than none: telling someone on a
            # DDR build to "build with TARGET=pynq" sends them to rebuild the
            # image exactly the way it already is.
            other = R.tohost_addr(self.mem_kb, not self.is_bram)
            if have == other:
                # A PAIR IS MISMATCHED; EITHER HALF COULD BE THE WRONG ONE.
                # Naming only the image is a trap: someone deploying a BRAM
                # bitstream who forgot BITDIR gets told to rebuild images that
                # were right all along, and rebuilding them makes it worse.
                # The bitstream is the likelier culprit anyway -- it is the
                # half deploy.sh takes from an environment variable.
                mine, theirs = (("AXI/DDR", "block RAM") if not self.is_bram
                                else ("block RAM", "AXI/DDR"))
                target = "pynq-ddr" if not self.is_bram else "pynq"
                bitdir = ("baremetal_linux-AXI" if not self.is_bram
                          else "baremetal_linux-BRAM")
                imgdir = "images" if not self.is_bram else "images-bram"
                why = (f"  0x{have:08x} is where a {theirs} build puts it, but "
                       f"this bitstream is {mine}.\n"
                       f"  One of the two is the wrong one, and which depends "
                       f"on what you meant to run.\n"
                       f"\n"
                       f"  If you meant to run {mine} -- the bitstream now on "
                       f"the board -- fix the image:\n"
                       f"      make -C fpga/pynq images IMAGE_TARGET={target}\n"
                       f"      BITDIR=$PWD/bit/{bitdir} ./sw/deploy.sh "
                       f"<board> {imgdir}/*.elf\n"
                       f"\n"
                       f"  If you meant to run {theirs}, the BITSTREAM is the "
                       f"stale half: redeploy\n"
                       f"  with BITDIR pointing at that build.  Check the "
                       f"'backend=' line above --\n"
                       f"  it reports what is actually programmed, not what "
                       f"you intended.")
            else:
                why = ("  It matches neither backend's address, so it is not "
                       "simply the wrong TARGET: check MEM_KB against the "
                       "bitstream, and the PROVIDE(tohost) in the linker "
                       "script.")
            raise AmoebaError(
                f"{img.path} puts tohost at 0x{have:08x}; the bus monitor "
                f"watches 0x{want:08x}.\n"
                f"  Exit detection would never fire.\n{why}")

        if legacy_axi_reset and not self.is_bram:
            raise AmoebaError(
                "--legacy-axi-reset is a block-RAM workaround and is unsafe "
                "on an AXI/DDR build.\n"
                "  It releases the core before writing the image.  That is "
                "defensible against block RAM, where the array is zeroed by "
                "configuration and the core just spins taking access faults "
                "on an illegal instruction.  DDR is not zeroed: it still "
                "holds the LAST run's program, so the core would execute it "
                "while the PS overwrites it underneath.\n"
                "  An AXI build has no image window and never needed the "
                "workaround -- drop the flag.")

        if legacy_axi_reset:
            # Workaround for bitstreams built before amoeba_mem_bram got its
            # own s_axi_aresetn.  In those, port B is reset from HRESETn, which
            # the SoC asserts while the core is halted -- so the load port is
            # dead exactly when loading happens, and the first write deadlocks
            # the PS on an AXI transaction that never completes.
            #
            # Releasing the core first raises HRESETn and makes the port
            # answer.  That is safe here only because of what the core does
            # meanwhile: block RAM is zeroed by configuration, all-zero decodes
            # as an illegal instruction, and the trap vector resets to 0, which
            # is outside the memory map -- so it spins taking access faults and
            # never retires a store.  It cannot touch the image being written.
            #
            # Do not reach for this on a fixed bitstream.
            self.start()
        try:
            self._load_body(img, verify=verify, zero=zero, zero_all=zero_all)
        finally:
            if legacy_axi_reset:
                self.halt()

    def _zero_for(self, img: "_image.Image", *, everything: bool) -> None:
        """Clear the memory the program will use.

        Block RAM comes up zeroed in the bitstream, so the first run after
        programming is clean -- but the second starts on the first's memory,
        which is a fine way to spend an afternoon on a bug that only appears
        on re-runs.

        SCOPE.  For block RAM this is the whole window, which costs nothing.
        For the DDR carve-out it is the image's span plus the HTIF page, and
        deliberately not the other 255 MiB: that mapping is uncached (see
        mmio.py) so a full scrub runs at tens of MB/s, and it would spend
        seconds per run clearing memory no program reads.

        The HTIF page is not optional even though it sits above the image.  A
        stale exit word left there by the previous run is read by the bus
        monitor the moment the core starts, and the run "finishes" instantly
        with the last run's exit code.
        """
        if everything or self.is_bram:
            self.mem.fill(0, self.mem_bytes, 0)
            return

        end = min(img.load_end - R.EXT_MEM_BASE, self.mem_bytes)
        self.mem.fill(0, end, 0)

        page = R.tohost_addr(self.mem_kb, self.is_bram) - R.EXT_MEM_BASE
        if end <= page and page + PAGE_BYTES <= self.mem_bytes:
            self.mem.fill(page, PAGE_BYTES, 0)

    def _load_body(self, img: "_image.Image", *, verify: bool,
                   zero: bool, zero_all: bool = False) -> None:
        if zero:
            self._zero_for(img, everything=zero_all)

        for seg in img.segments:
            self.mem.write_bytes(seg.paddr - R.EXT_MEM_BASE, seg.data)

        if verify:
            for seg in img.segments:
                off = seg.paddr - R.EXT_MEM_BASE
                got = self.mem.read_bytes(off, len(seg.data))
                if got != seg.data:
                    bad = next(i for i, (a, b) in enumerate(zip(got, seg.data))
                               if a != b)
                    raise AmoebaError(
                        f"image readback differs at 0x{seg.paddr + bad:08x}: "
                        f"wrote 0x{seg.data[bad]:02x}, read 0x{got[bad]:02x}")

    # ---- console ----------------------------------------------------------
    def read_console(self, limit: int = 4096) -> bytes:
        """Drain the console FIFO.

        UART_LEVEL first so an empty FIFO costs one register read rather than
        one per poll -- this gets called in a tight loop.
        """
        n = min(self.ctl.read(R.R_UART_LEVEL), limit)
        out = bytearray()
        for _ in range(n):
            w = self.ctl.read(R.R_UART_DATA)      # reading pops
            if not (w & R.UART_VALID):
                break
            out.append(w & R.UART_BYTE)
        return bytes(out)

    # ---- counters ---------------------------------------------------------
    def _read64(self, lo: int, hi: int) -> int:
        """LO first, always.

        Reading LO latches the high half into a shadow that the HI read
        returns.  Without that, a carry landing between the two reads yields a
        value that never existed.
        """
        low = self.ctl.read(lo)
        return (self.ctl.read(hi) << 32) | low

    @property
    def cycles(self) -> int:
        return self._read64(R.R_CYCLES_LO, R.R_CYCLES_HI)

    @property
    def retired(self) -> int:
        return self._read64(R.R_RETIRED_LO, R.R_RETIRED_HI)

    @property
    def traps(self) -> int:
        return self.ctl.read(R.R_TRAPS)

    @property
    def status(self) -> int:
        return self.ctl.read(R.R_STATUS)

    @property
    def tohost_valid(self) -> bool:
        return bool(self.status & R.ST_TOHOST_VALID)

    @property
    def tohost(self) -> int:
        return self._read64(R.R_TOHOST_LO, R.R_TOHOST_HI)

    @property
    def exit_code(self) -> int:
        """HTIF encodes exit as (code << 1) | 1."""
        return self.tohost >> 1

    @property
    def uart_overflow(self) -> bool:
        return bool(self.status & R.ST_UART_OVERFLOW)

    # ---- orchestration ----------------------------------------------------
    def run(self, img: "_image.Image", *, trace_mode: int = R.TRACE_OFF,
            on_armed=None, **load_kw) -> None:
        """Halt, load, clear, release -- in that order, which is the point.

        `on_armed` is called after the monitors are cleared and before the core
        is released, which is the only moment a counter reading means "this
        happened during the load" rather than "this happened at some point".
        Attribution is the whole difficulty in reading these counters.
        """
        self.halt()
        self.load(img, **load_kw)
        if self.has_trace:
            self.ctl.write(R.R_TRACE_MODE, trace_mode)
        self.clear_monitors()
        if on_armed is not None:
            on_armed(self)
        self.start()

    def stream_console(self, timeout: float, *,
                       until_tohost: bool = True,
                       poll: float = 0.002) -> Iterator[bytes]:
        """Yield console bytes until tohost, timeout, or KeyboardInterrupt.

        Drains once more after tohost fires: the exit write and the last
        characters of output race each other through different paths, and
        stopping on the flag alone reliably truncates the final line.
        """
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            chunk = self.read_console()
            if chunk:
                yield chunk
                continue
            if until_tohost and self.tohost_valid:
                break
            time.sleep(poll)
        tail = self.read_console()
        if tail:
            yield tail

    def close(self) -> None:
        """Release the register and memory mappings.

        Not strictly required -- the kernel reclaims them -- but explicit
        teardown means the process is not unmapping device memory during
        interpreter shutdown, when ordering is nobody's contract.
        """
        for attr in ("_ctl", "_mem"):
            m = getattr(self, attr, None)
            if m is not None:
                try:
                    m.close()
                except Exception:
                    pass
                setattr(self, attr, None)

    def __enter__(self):
        return self

    def __exit__(self, *a):
        self.close()
