#!/usr/bin/env python3
"""Load a FreeRTOS image onto the soft core, run it, and report.

  ./run_freertos.py --image freertos_wally.elf --bitstream amoeba.bit
  ./run_freertos.py --image freertos_wally.elf --soak 30      # heartbeat

Exits with the program's HTIF code, so this drops straight into a regression
harness.

The soak mode is the interesting one.  It measures the PL's cycle counter
against the host's wall clock to get the true fabric clock, and separately
measures the guest's heartbeat rate to get the clock the guest BELIEVES it is
running at.  Those two being equal is the check; when they are not, the ratio
is exactly the factor configCPU_CLOCK_HZ is wrong by.  Nothing else in the test
suite can catch that -- a terminating test verifies ordering and results, not
rates, so it passes just as happily on a 4x-wrong clock.
"""

import argparse
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from amoeba import Amoeba, AmoebaError, image as _image, psmon, regs as R  # noqa: E402

HB_START = re.compile(rb"HB start period_ms=(\d+) tick_hz=(\d+) cpu_hz=(\d+)")
HB_BEAT = re.compile(rb"HB seq=(\d+) tick=(\d+)")


def main() -> int:
    """Wrapper so every exit path releases the device mappings.

    _main() returns from a dozen places; a try/finally here is one thing to
    get right instead of a dozen.
    """
    dev_box = {}
    try:
        return _main(dev_box)
    finally:
        d = dev_box.get("dev")
        if d is not None:
            d.close()


def _main(dev_box) -> int:
    t_launch = time.monotonic()
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--image", required=True, help="ELF, or flat binary with --base")
    ap.add_argument("--base", type=lambda s: int(s, 0), default=None,
                    help="load address for a flat binary")
    ap.add_argument("--bitstream",
                    help="program the PL first (uses pynq if importable, "
                         "otherwise the kernel's fpga_manager)")
    ap.add_argument("--fclk", type=float, default=25.0,
                    help="PL clock in MHz to program and then verify "
                         "(default 25, which is what the design closed "
                         "timing at); 0 disables both")
    ap.add_argument("--timeout", type=float, default=30.0)
    ap.add_argument("--soak", type=float, default=0.0,
                    help="run for N seconds without expecting an exit, and "
                         "report heartbeat timing")
    ap.add_argument("--expect-exit", type=int, default=None)
    ap.add_argument("--no-verify", action="store_true",
                    help="skip image readback (faster, and a bad idea)")
    ap.add_argument("--quiet", action="store_true", help="do not echo the console")
    ap.add_argument("--afi", action="store_true",
                    help="also sample the PS-side HP0 port registers, to tell "
                         "a bridge that swallowed the request from a PS that "
                         "did not answer it.  Requires --fclk.  RISK: these "
                         "reads cannot time out; see amoeba/psmon.py")
    ap.add_argument("--legacy-axi-reset", action="store_true",
                    help="workaround for bitstreams built before "
                         "amoeba_mem_bram got its own s_axi_aresetn, where "
                         "the first write to the image window deadlocks the "
                         "PS.  Releases the core across the load.")
    args = ap.parse_args()

    img = _image.load(args.image, base=args.base)

    try:
        dev = Amoeba(bitstream=args.bitstream,
                     fclk_mhz=args.fclk if args.fclk > 0 else None)
    except PermissionError:
        print("error: need root for /dev/mem (try sudo)", file=sys.stderr)
        return 2
    except AmoebaError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    dev_box["dev"] = dev
    print(f"# {dev.describe()}")

    # Before anything else touches the core: confirm the PL is running at the
    # frequency this bitstream was closed for.  Measured against wall time, not
    # read back from the SLCR -- a register that agrees with the value we just
    # wrote proves only that the write landed.
    if args.fclk > 0:
        try:
            got = dev.check_fclk(args.fclk)
            print(f"# fabric clock verified: {got/1e6:.3f} MHz")
        except AmoebaError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2

    print(f"# image {os.path.basename(img.path)}: "
          f"0x{img.load_base:08x}..0x{img.load_end:08x}, "
          f"{img.file_bytes} bytes to load, entry 0x{img.entry:08x}")

    # Sampled with the core still halted, so anything that moves afterwards is
    # the core's doing and not the load's.  dev.run() writes the image through
    # the PS's own DDR mapping, which does not touch an HP port at all.
    #
    # OPT-IN, AND IT STAYS OPT-IN UNTIL IT HAS SURVIVED A BOARD.  Every read in
    # here is a PS access that cannot time out: get the port or the clock wrong
    # and the machine hangs hard enough to need the power switch.  That is too
    # much to spend by default on a diagnostic, so a run only pays it when it
    # is asked to.  See amoeba/psmon.py for the two ways to get it wrong.
    afi = afi_before = None
    if args.afi:
        if args.fclk <= 0:
            print("error: --afi needs --fclk so the fabric clock is verified "
                  "first; HP0's\n"
                  "       register block is clocked from FCLK0 and reading it "
                  "before that clock\n"
                  "       exists hangs the PS.", file=sys.stderr)
            return 2
        afi = psmon.open_quietly()
        afi_before = afi.read() if afi else None

    t_load = time.monotonic()
    # Counters read at the end cannot say WHEN they moved.  Sampling in the
    # window after clear and before release splits "the bus was driven while
    # the core was held" from "the core did this once it started", and those
    # two have nothing in common as bugs.
    armed_snap = {}

    def _snap(d):
        for name in ("R_BUS_XACT", "R_BUS_RSTXACT", "R_BUS_ERR",
                     "R_BUS_STATE"):
            armed_snap[name] = d.ctl.read(getattr(R, name))

    try:
        dev.run(img, verify=not args.no_verify, on_armed=_snap,
                legacy_axi_reset=args.legacy_axi_reset)
    except AmoebaError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    # Attributed, because the wait before a run starts is long enough to look
    # like a symptom.  Loading is uncached DDR writes plus a readback; the rest
    # is Python startup and moving 4 MB of bitstream around on an SD card.
    now = time.monotonic()
    print(f"# setup {now - t_launch:.1f} s "
          f"(load+verify {now - t_load:.1f} s)")

    t0 = time.monotonic()
    c0 = dev.cycles
    hb = _Heartbeat()
    out = bytearray()

    timeout = args.soak if args.soak else args.timeout
    try:
        for chunk in dev.stream_console(timeout, until_tohost=not args.soak):
            out += chunk
            hb.feed(chunk, time.monotonic())
            if not args.quiet:
                sys.stdout.buffer.write(chunk)
                sys.stdout.flush()
    except KeyboardInterrupt:
        print("\n# interrupted", file=sys.stderr)

    wall = time.monotonic() - t0
    cycles = dev.cycles - c0

    if out and not out.endswith(b"\n") and not args.quiet:
        sys.stdout.buffer.write(b"\n")
        sys.stdout.flush()

    # ---- the PL's own view -------------------------------------------------
    print(f"# ran {wall:.3f} s wall, {cycles} cycles, "
          f"{dev.retired} retired, {dev.traps} traps")
    if dev.uart_overflow:
        print("# WARNING: console FIFO overflowed -- output above has gaps",
              file=sys.stderr)

    # A soak that ends on its own timer never trips the timeout ladder, so a
    # run that retired nothing would otherwise print three numbers and stop --
    # which is exactly the case where the bus probe has something to say.
    if cycles > 0 and dev.retired == 0:
        print("# nothing retired in that whole run:", file=sys.stderr)
        _diagnose_bus(dev, afi, afi_before, armed_snap)

    # The authoritative clock measurement: PL cycles against host wall time.
    # Involves no guest software at all.
    if wall > 0.5 and cycles > 0:
        fclk = cycles / wall
        print(f"# fabric clock (PL cycles / wall time): {fclk / 1e6:.3f} MHz")
        hb.report(fclk)
    elif args.soak:
        print("# too short to measure the clock; try --soak 5 or more")

    # ---- exit --------------------------------------------------------------
    if args.soak:
        return 0

    if not dev.tohost_valid:
        print(f"# TIMEOUT after {args.timeout} s with no tohost write",
              file=sys.stderr)
        _diagnose(dev, cycles, afi, afi_before, armed_snap)
        return 124

    code = dev.exit_code
    print(f"# exit {code}")
    if args.expect_exit is not None and code != args.expect_exit:
        print(f"# FAIL: expected exit {args.expect_exit}", file=sys.stderr)
        return 1
    return code


def _diagnose(dev, cycles: int, afi=None, afi_before=None,
              armed_snap=None) -> None:
    """The ladder from BRINGUP.md, applied automatically on a timeout."""
    if cycles == 0:
        print("#   CYCLES did not advance: the core is not clocked, or reset "
              "was never released.", file=sys.stderr)
    elif dev.retired == 0:
        print("#   CYCLES advanced but RETIRED is 0: the core is fetching but "
              "nothing commits.", file=sys.stderr)
        _diagnose_bus(dev, afi, afi_before, armed_snap)
    elif dev.traps > 0:
        print(f"#   RETIRED advanced and TRAPS is {dev.traps}: it is probably "
              "trapping in a loop.", file=sys.stderr)
    else:
        print("#   The core ran and retired instructions but never wrote "
              "tohost.\n"
              "#   If the console looked right, suspect the tohost address: "
              "see BRINGUP.md 0.1.", file=sys.stderr)


def _diagnose_bus(dev, afi=None, afi_before=None,
                  armed_snap=None) -> None:
    """Split "nothing commits" into its actual causes using the AHB probe.

    Without this the reading is ambiguous between a bad image, a bad reset
    vector, and a memory backend that never answers -- which look identical
    from the core's counters and have nothing in common as fixes.
    """
    st = dev.ctl.read(R.R_BUS_STATE)
    xact = dev.ctl.read(R.R_BUS_XACT)
    beat = dev.ctl.read(R.R_BUS_BEAT)
    err = dev.ctl.read(R.R_BUS_ERR)
    stall = dev.ctl.read(R.R_BUS_STALL)
    addr = dev.ctl.read(R.R_BUS_ADDR)
    xaddr = dev.ctl.read(R.R_BUS_XADDR)
    mwait = dev.ctl.read(R.R_BUS_WAIT)
    ewait = dev.ctl.read(R.R_BUS_ERRWAIT)
    exact = dev.ctl.read(R.R_BUS_ERRXACT)

    print(f"#   AHB: {xact} transfers started, {beat} beats OK, "
          f"{err} error responses", file=sys.stderr)
    if armed_snap:
        a_x = armed_snap.get("R_BUS_XACT", 0)
        a_e = armed_snap.get("R_BUS_ERR", 0)
        # a_x and xact are the same counter read at two times, so the
        # subtraction is sound.  It is NOT sound against R_BUS_RSTXACT, which
        # counts address phases (NONSEQ or SEQ) where this counts burst starts
        # (NONSEQ only); an earlier version mixed the two and printed a
        # difference in no units at all.  The capture's per-cycle rst= bit is
        # the thing to trust when these disagree.
        print(f"#   AHB: of those, {a_x} burst starts and {a_e} errors had "
              f"ALREADY happened\n"
              f"#        before the core was released "
              f"({xact - a_x} burst starts after).", file=sys.stderr)
        print(f"#   AHB at release: "
              f"{R.decode_bus_state(armed_snap.get('R_BUS_STATE', 0))}",
              file=sys.stderr)
    print(f"#   AHB: {stall} data-phase wait cycles, longest single wait "
          f"{mwait}", file=sys.stderr)
    print(f"#   AHB: {R.decode_bus_state(st)}", file=sys.stderr)
    if xact:
        print(f"#   AHB: first access core 0x{addr:08x} -> bus 0x{xaddr:08x}",
              file=sys.stderr)

    if xact == 0:
        print("#   The core never issued a bus transfer at all.  It is not "
              "the memory backend:\n"
              "#   suspect the reset vector, or HSELEXT never asserting.",
              file=sys.stderr)
    # ERRORS ARE TESTED BEFORE "no beats completed", because on this bridge
    # they are not independent: HRESP is sticky and beat_ok is gated on
    # !HRESP, so any error pins the beat count at zero for the rest of the
    # run.  Testing beats first shadowed the error branch permanently and
    # printed "the memory backend is not answering" at a bridge that was
    # answering, with an error, every single time.
    elif err:
        # HRESP on ahblite_axi_bridge is sticky -- it latches on failure and is
        # only cleared by a transfer that succeeds -- so `err` counts samples
        # of a stuck flag, not distinct errors, and `beat` cannot advance once
        # it is set.  The first error is the only real event here.
        print(f"#   AHB: first error was on transfer #{exact + 1}, after "
              f"{ewait} wait cycles", file=sys.stderr)
        print("#   (HRESP on this bridge is sticky: it latches on the first "
              "failure and only\n"
              "#    clears on a transfer that succeeds, so the totals above "
              "describe the flag,\n"
              "#    not the transfers.)", file=sys.stderr)
        # The peak wait is what separates the two, and they have nothing in
        # common as fixes.  C_AHB_AXI_TIMEOUT is 256, so a transfer that sat
        # near that long was waiting on an AXI side that never answered; one
        # that errored with no wait at all was refused by the bridge itself
        # and never became an AXI transaction.
        # THREE OUTCOMES, NOT TWO.  A wait of zero means the bridge refused
        # the transfer itself and no AXI existed.  A wait near
        # C_AHB_AXI_TIMEOUT (256) means it issued AXI and nothing ever came
        # back.  Anything in between is the interesting one and used to be
        # lumped in with "refused on the spot": the bridge issued AXI, the PS
        # answered in that many cycles, and the answer was an error.
        if ewait == 0:
            print(f"#   {err} errors with NO wait at all: the bridge refused "
                  "these transfers\n"
                  "#   itself and never issued AXI.  Suspect what the core is "
                  "driving --\n"
                  "#   HBURST, HSIZE, an unaligned address -- not the PS side.",
                  file=sys.stderr)
        elif ewait < 200:
            print(f"#   First error came back after {ewait} wait cycles -- too "
                  "few to be the\n"
                  f"#   bridge's {256}-cycle timeout, so AXI WAS ISSUED AND THE "
                  "PS ANSWERED,\n"
                  "#   with SLVERR or DECERR.  The AHB side is fine; the fault "
                  "is the AXI\n"
                  "#   address, the protocol converter, or HP0's access "
                  "permissions.", file=sys.stderr)
        else:
            print(f"#   {err} errors after waits of up to {mwait} cycles: the "
                  "bridge timed out.\n"
                  "#   It DID issue AXI and got nothing back -- look at HP0, "
                  "the converter, the\n"
                  "#   address, not at the AHB side.", file=sys.stderr)
    elif beat == 0:
        # Reached only when there were no errors at all -- see the ordering
        # note above.
        print("#   Transfers were issued and NOTHING completed: the memory "
              "backend is not answering.\n"
              "#   On an AXI build check the bridge, the protocol converter "
              "and the HP0 path;\n"
              "#   compare the two addresses above -- 'bus' is what actually "
              "left this module.", file=sys.stderr)
    else:
        print("#   The bus is working; suspect the image or the reset vector.",
              file=sys.stderr)

    # Brackets the same fault from the far side.  The AHB probe says what the
    # core asked for; this says whether the PS ever heard it.  A gap between
    # the two localises the fault to the bridge and the HP path, which is the
    # one stretch neither end can see on its own.
    if dev.is_bram:
        return
    _dump_capture(dev)

    if afi is None or afi_before is None:
        print("#   AFI: not sampled.  Re-run with --afi to ask whether the PS "
              "side saw\n"
              "#        this traffic at all.", file=sys.stderr)
        return
    psmon.report(afi_before, afi.read())


def _dump_capture(dev) -> None:
    """The first CAP_DEPTH cycles from the first select, cycle by cycle.

    Counters proved a transfer fails; they cannot show what was on the wire
    while it did.  This can, and it is the only view that distinguishes a
    slave rejecting our transfer from a slave that was already in an error
    state before we asked.
    """
    pre = dev.ctl.read(R.R_BUS_PRESTATE)
    print(f"#   AHB before the first select: {R.decode_bus_state(pre)}",
          file=sys.stderr)
    if pre & R.BUS_HRESP:
        print("#   HRESP WAS ALREADY ASSERTED with nothing selected.  That is "
              "not a response\n"
              "#   to any transfer of ours -- the slave came up in an error "
              "state.", file=sys.stderr)

    nrst = dev.ctl.read(R.R_BUS_RSTXACT)
    if nrst:
        print(f"#   {nrst} transfers left this module WHILE THE CORE WAS HELD "
              "IN RESET.\n"
              "#   amoeba_pynq_top gates HSEL and HTRANS with the core's reset, "
              "so this should\n"
              "#   be impossible -- a non-zero count means that gate is not "
              "working.\n"
              "#   Nothing should drive the bus then.  The bridge takes such a "
              "transfer, issues\n"
              "#   AXI for it, and is still waiting when the core is finally "
              "released -- which\n"
              "#   puts it in a stuck state before the core's first fetch ever "
              "happens.",
              file=sys.stderr)

    # Did it capture at all?  An unarmed buffer used to read back as a quiet
    # bus, which is the most misleading thing a probe can do.
    stat = dev.ctl.read(R.R_BUS_CAPSTAT)
    done, ptr = bool(stat & (1 << 6)), stat & 0x3F
    if not done and ptr == 0:
        print("#   capture buffer NEVER ARMED (done=0, ptr=0).  It triggers on "
              "the first select\n"
              "#   after core_reset releases, so this means no select was seen "
              "while running.",
              file=sys.stderr)
        return

    # Prove the index register works before trusting 64 reads through it.  If
    # writes to CAPSEL are dropped, every read returns entry 0 and the run
    # collapse below prints one line -- which looks exactly like a bus that
    # never changed.
    dev.ctl.write(R.R_BUS_CAPSEL, R.CAP_DEPTH - 1)
    if dev.ctl.read(R.R_BUS_CAPSEL) != R.CAP_DEPTH - 1:
        print("#   CAPSEL does not read back what was written: the capture "
              "index register is\n"
              "#   broken, so entries below cannot be trusted.", file=sys.stderr)
        return

    print(f"#   captured AHB cycles from the first select "
          f"(done={int(done)} ptr={ptr}):", file=sys.stderr)
    last = None
    shown = 0
    for i in range(R.CAP_DEPTH):
        dev.ctl.write(R.R_BUS_CAPSEL, i)
        w = dev.ctl.read(R.R_BUS_CAPDAT)
        rd = dev.ctl.read(R.R_BUS_CAPRDAT)
        # Collapse runs: 64 lines of an idle bus buries the two that matter.
        if (w, rd) == last:
            continue
        last = (w, rd)
        shown += 1
        print(f"#     +{i:02d}  {R.decode_cap(w)} rdata={rd:08x}",
              file=sys.stderr)
    if shown <= 1:
        print("#   (one distinct value across all 64 entries -- the bus did "
              "not change at all\n"
              "#    during the window.)", file=sys.stderr)


class _Heartbeat:
    """Parse heartbeat_app.c output and time the beats."""

    def __init__(self):
        self.buf = bytearray()
        self.cfg = None            # (period_ms, tick_hz, cpu_hz)
        self.stamps = []           # wall time of each beat
        self.ticks = []

    def feed(self, chunk: bytes, now: float) -> None:
        self.buf += chunk
        while b"\n" in self.buf:
            line, _, rest = self.buf.partition(b"\n")
            self.buf = bytearray(rest)
            m = HB_START.search(line)
            if m:
                self.cfg = tuple(int(g) for g in m.groups())
                continue
            m = HB_BEAT.search(line)
            if m:
                self.stamps.append(now)
                self.ticks.append(int(m.group(2)))

    def report(self, fclk_hz: float) -> None:
        if self.cfg is None or len(self.stamps) < 3:
            return
        period_ms, tick_hz, cpu_hz = self.cfg
        period_s = period_ms / 1000.0

        gaps = [b - a for a, b in zip(self.stamps, self.stamps[1:])]
        mean = sum(gaps) / len(gaps)
        jitter = max(gaps) - min(gaps)

        print(f"# heartbeat: {len(self.stamps)} beats, "
              f"mean {mean * 1e3:.2f} ms, jitter {jitter * 1e3:.2f} ms "
              f"(guest intends {period_ms} ms)")

        # CALIBRATION.  The guest schedules N = cpu_hz * period_s mtime
        # increments per beat, and mtime advances once per fabric clock, so a
        # beat actually takes N / fclk seconds.  Beats arriving late by exactly
        # the ratio cpu_hz / fclk is the signature of a wrong
        # configCPU_CLOCK_HZ -- and comparing the measured period against the
        # INTENDED one is the only way to see it.  (Comparing an "implied
        # clock" against the measured fabric clock does not work: both are
        # estimates of the same quantity and agree by construction whether or
        # not the guest's constant is right.)
        implied = (cpu_hz * period_s) / mean
        drift = (mean - period_s) / period_s * 100.0

        if abs(drift) > 5.0:
            print(f"# MISMATCH: beats arrive every {mean * 1e3:.1f} ms, not "
                  f"{period_ms} ms ({drift:+.0f}%).\n"
                  f"#   configCPU_CLOCK_HZ is {cpu_hz}, but the core is running "
                  f"at about {implied / 1e6:.3f} MHz, so every interval in the "
                  f"guest is off by {cpu_hz / implied:.2f}x.\n"
                  f"#   Rebuild with FPGA_CLOCK_HZ={int(round(implied))}.",
                  file=sys.stderr)
        else:
            print(f"# clock calibration OK ({drift:+.1f}% off the intended "
                  f"period)")

        # CONSISTENCY.  Two independent estimates of the same fabric clock: one
        # from the guest's timer, one from the PL counter against host wall
        # time.  They should agree regardless of whether cpu_hz is right.  If
        # they do not, mtime and the PL cycle counter are not counting the same
        # thing, which would be a hardware problem rather than a build one.
        skew = (implied - fclk_hz) / fclk_hz * 100.0
        note = "consistent" if abs(skew) < 5.0 else "INCONSISTENT"
        print(f"# clock cross-check: guest timer says {implied / 1e6:.3f} MHz, "
              f"PL counter says {fclk_hz / 1e6:.3f} MHz ({skew:+.1f}%, {note})")
        if abs(skew) >= 5.0:
            print("#   mtime and the PL cycle counter disagree; they are both "
                  "supposed to be FCLK_CLK0.", file=sys.stderr)


if __name__ == "__main__":
    sys.exit(main())
