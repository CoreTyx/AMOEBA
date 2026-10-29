#!/usr/bin/env python3
"""Boot the testcode/linux image on the soft core and stream the console.

  sudo python3 run_linux.py --bitstream ../amoeba.bit --dir ../linux --timeout 600

Expects --dir to hold boot_shim.bin and fw_payload.bin from
`make -C testcode/linux CONFIG=baremetal_linux TIMEBASE_HZ=25000000`
(TIMEBASE_HZ MUST be the real FCLK0: MTIME ticks off HCLK, and a kernel whose
declared timebase is 4x the true rate runs every sleep and timeout 4x slow --
functionally "working" and useless.  The FreeRTOS soak mode exists because of
exactly this class of bug.)

Differences from run_freertos.py, each load-bearing:

- TWO blobs, not one: the shim at the reset vector and fw_payload (OpenSBI +
  embedded DT + kernel + initramfs) at +2 MB, per testcode/linux/README.md.
- tohost is IGNORED.  The AXI bus monitor watches 0x8080_0000, and that
  address is INSIDE fw_payload's span -- the kernel writes it as ordinary
  memory, so tohost_valid latching means nothing here.  The run ends on
  timeout, a pass pattern, or a fail pattern, never on tohost.
- Milestones from testcode/linux/README.md are stamped with wall time and PL
  cycles as they fly by, so a stall names the phase it stalled in.
"""

import argparse
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import console as _console  # noqa: E402

from amoeba import Amoeba, AmoebaError, regs as R  # noqa: E402

SHIM_ADDR    = 0x8000_0000
PAYLOAD_ADDR = 0x8020_0000

MILESTONES = [
    ("M0 firmware",   re.compile(rb"OpenSBI v1\.")),
    ("M1 kernel",     re.compile(rb"Linux version 6\.6")),
    ("M2 console",    re.compile(rb"printk: bootconsole")),
    ("M3 mmu",        re.compile(rb"Initmem setup node 0")),
    ("M4 init done",  re.compile(rb"Freeing unused kernel image")),
    ("M5 userspace",  re.compile(rb"AMOEBA_LINUX_BOOT_OK")),
]
FAIL = re.compile(rb"Kernel panic|Unable to handle kernel|Oops:|SBI panic")


def _load_blob(dev, path, addr, verify):
    blob = open(path, "rb").read()
    off = addr - R.EXT_MEM_BASE
    t0 = time.monotonic()
    dev.mem.write_bytes(off, blob)
    if verify:
        back = dev.mem.read_bytes(off, len(blob))
        if back != blob:
            bad = next(i for i in range(len(blob)) if back[i] != blob[i])
            raise AmoebaError(f"{os.path.basename(path)}: verify failed at "
                              f"0x{addr + bad:08x}")
    print(f"# {os.path.basename(path)}: {len(blob)} bytes at 0x{addr:08x} "
          f"({time.monotonic() - t0:.1f} s{', verified' if verify else ''})")
    return len(blob)


def _run_cmds(dev, cmds, *, settle: float = 2.0, timeout: float = 30.0) -> int:
    """Type commands at the guest's shell and check what comes back.

    An EXPECT=<string> entry applies to the command before it: the output has
    to contain that string or the run fails.  This is what makes a shell a
    regression vehicle rather than a demo.
    """
    time.sleep(settle)
    dev.read_serial()                    # drop the boot tail and the prompt
    rc = 0
    pending = None
    for cmd in cmds:
        if cmd.startswith("EXPECT="):
            want = cmd[len("EXPECT="):].encode()
            if pending is None:
                print("# --cmd EXPECT= with no preceding command", file=sys.stderr)
                return 5
            if want not in pending:
                print(f"# FAIL  expected {want!r} in the output of that command",
                      file=sys.stderr)
                rc = 6
            pending = None
            continue
        print(f"# $ {cmd}", file=sys.stderr)
        dev.write_serial(cmd.encode() + b"\n")
        out = bytearray()
        deadline = time.monotonic() + timeout
        quiet_since = None
        while time.monotonic() < deadline:
            chunk = dev.read_serial()
            if chunk:
                out += chunk
                sys.stdout.buffer.write(chunk)
                sys.stdout.flush()
                quiet_since = None
            else:
                # The shell has stopped talking for long enough to call it done.
                quiet_since = quiet_since or time.monotonic()
                if time.monotonic() - quiet_since > 1.0 and out:
                    break
                time.sleep(0.01)
        pending = bytes(out)
        if not pending:
            print(f"# FAIL  no output from {cmd!r}", file=sys.stderr)
            rc = 7
    return rc


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", required=True,
                    help="directory holding boot_shim.bin and fw_payload.bin")
    ap.add_argument("--bitstream")
    ap.add_argument("--fclk", type=float, default=25.0)
    ap.add_argument("--timeout", type=float, default=600.0)
    ap.add_argument("--no-verify", action="store_true")
    ap.add_argument("--recheck", action="store_true",
                    help="after the run, halt and compare memory against the "
                         "blobs again -- catches an image overwritten while it ran")
    ap.add_argument("--quiet", action="store_true")
    ap.add_argument("--interactive", action="store_true",
                    help="after M5, hand the console to console.py -- a shell, "
                         "if the initramfs provides one (INIT=sh)")
    ap.add_argument("--cmd", action="append", default=[],
                    help="type this at the prompt after M5 and expect its output; "
                         "repeatable.  Use EXPECT= to require a string: "
                         "--cmd 'uname -m' --cmd 'EXPECT=riscv64'")
    args = ap.parse_args()

    shim = os.path.join(args.dir, "boot_shim.bin")
    payload = os.path.join(args.dir, "fw_payload.bin")
    for p in (shim, payload):
        if not os.path.exists(p):
            print(f"error: {p} not found", file=sys.stderr)
            return 2

    dev = Amoeba(bitstream=args.bitstream,
                 fclk_mhz=args.fclk if args.fclk > 0 else None)
    try:
        print(f"# {dev.describe()}")
        if dev.is_bram:
            print("error: the Linux image needs the AXI/DDR backend",
                  file=sys.stderr)
            return 2
        got = dev.check_fclk(args.fclk)
        print(f"# fabric clock verified: {got / 1e6:.3f} MHz")
        if abs(got - 25e6) > 25e4:
            print("# WARNING: image was built TIMEBASE_HZ=25000000; the "
                  "kernel's clock will be wrong", file=sys.stderr)

        dev.halt()
        end = _load_blob(dev, shim, SHIM_ADDR, not args.no_verify)
        _load_blob(dev, payload, PAYLOAD_ADDR, not args.no_verify)
        dev.clear_monitors()
        dev.start()
        print(f"# core released; streaming console for up to "
              f"{args.timeout:.0f} s (tohost is ignored on purpose: "
              f"0x80800000 lies inside the image)")

        t0 = time.monotonic()
        c0 = dev.cycles
        tail = b""
        hit = set()
        rc = 1
        try:
            for chunk in dev.stream_console(args.timeout, until_tohost=False,
                                            poll=0.001):
                if not args.quiet:
                    sys.stdout.buffer.write(chunk)
                    sys.stdout.flush()
                tail = (tail + chunk)[-4096:]
                for name, pat in MILESTONES:
                    if name not in hit and pat.search(tail):
                        hit.add(name)
                        print(f"\n# --- {name} at {time.monotonic() - t0:7.2f} s, "
                              f"{dev.cycles - c0} cycles ---", file=sys.stderr)
                if "M5 userspace" in hit:
                    rc = 0
                    break
                if FAIL.search(tail):
                    print("\n# FAIL pattern seen", file=sys.stderr)
                    rc = 3
                    break
        except KeyboardInterrupt:
            print("\n# interrupted", file=sys.stderr)

        # Read the counters BEFORE anything halts the core: amoeba_retire
        # holds its counters in reset while core_reset is asserted
        # ("counters restart with the core"), so a halt zeroes retired and
        # traps.  cycles lives in amoeba_bus_mon and survives.
        n_cycles, n_retired, n_traps = dev.cycles - c0, dev.retired, dev.traps

        # Print the bus probe whenever the boot never started -- not just when
        # nothing retired.  A handful of instructions followed by a trap storm
        # is a fetch that returned garbage, and the capture ring holds the
        # address it was fetching when that happened, which is the one thing
        # the counters cannot tell you.
        if "M0 firmware" not in hit:
            why = ("the core never completed an instruction"
                   if n_retired == 0 else
                   f"the core retired {n_retired} instruction(s) and then took "
                   f"{n_traps} traps -- it executed something that was not code")
            print(f"# BOOT NEVER STARTED: {why}.  The external bus probe says:",
                  file=sys.stderr)
            print(dev.bus_report(), file=sys.stderr)

        if args.recheck:
            dev.halt()
            for path, addr in ((shim, SHIM_ADDR), (payload, PAYLOAD_ADDR)):
                want = open(path, "rb").read()
                got = dev.mem.read_bytes(addr - R.EXT_MEM_BASE, len(want))
                if got == want:
                    print(f"# recheck {os.path.basename(path)}: intact "
                          f"({len(want)} bytes)", file=sys.stderr)
                    continue
                bad = [i for i in range(len(want)) if got[i] != want[i]]
                # A kernel that got anywhere rewrites this region as a matter
                # of course: BSS, page tables, and the initramfs it unpacks all
                # live inside the payload's span.  Only a run that executed
                # nothing makes this measurement mean "something overwrote me".
                expected = n_retired > 0
                print(f"# recheck {os.path.basename(path)}: "
                      f"{len(bad)} of {len(want)} bytes changed while it ran"
                      + ("  (expected -- the guest ran and writes its own BSS, "
                         "page tables and initramfs here)" if expected
                         else "  -- and the core retired NOTHING, so this is "
                              "something else writing to it"),
                      file=sys.stderr)
                print(f"#   first 0x{addr + bad[0]:08x}: "
                      f"loaded {want[bad[0]]:#04x}, now {got[bad[0]]:#04x}",
                      file=sys.stderr)
                print(f"#   last  0x{addr + bad[-1]:08x}", file=sys.stderr)

        wall = time.monotonic() - t0
        print(f"# ran {wall:.1f} s, {n_cycles} cycles, "
              f"{n_retired} retired, {n_traps} traps", file=sys.stderr)
        if dev.uart_overflow:
            print("# WARNING: console FIFO overflowed -- log has gaps",
                  file=sys.stderr)
        if dev.is_asic_link:
            ls = dev.link_stats()
            print(f"# link: {ls['xact']} transactions ({ls['rd']} rd, "
                  f"{ls['wr']} wr), retrains={ls['retrain']}, "
                  f"train_err={ls['train_err']}, hresp_err={ls['hresp_err']}, "
                  f"idle={ls['wdog']} cycles", file=sys.stderr)
        if rc == 0 and (args.interactive or args.cmd):
            if not dev.has_serial:
                print("# --interactive needs a bitstream with the serial "
                      "transceiver (CAPS[10])", file=sys.stderr)
                rc = 4
            else:
                st = dev.serial_stats()
                print(f"# serial: {st['baud']} baud (tick {st['tick']}), "
                      f"LCR {st['lcr']:#04x}", file=sys.stderr)
                if args.cmd:
                    rc = _run_cmds(dev, args.cmd)
                if args.interactive and rc == 0:
                    print("# attached; Ctrl-] to detach", file=sys.stderr)
                    _console.attach(dev, source="serial")

        missed = [n for n, _ in MILESTONES if n not in hit]
        if missed:
            print(f"# milestones not reached: {', '.join(missed)}",
                  file=sys.stderr)
        return rc
    finally:
        dev.close()


if __name__ == "__main__":
    sys.exit(main())
