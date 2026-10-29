#!/usr/bin/env python3
"""Does the DDR carve-out actually hold what we put in it?

  sudo python3 probe_ddr.py                 # 1 MiB at the OpenSBI address, 30 s
  sudo python3 probe_ddr.py --seconds 120 --mb 8

Everything the core runs from lives in a window of PS DRAM that the PS kernel
is supposed to leave alone (mem=256M on its command line; see patch_bootscr.py).
"Supposed to" is the operative phrase, and when it does not hold, the symptom
is not a memory error -- it is a program that loads and verifies, runs a few
instructions, and then traps forever, because its text was overwritten
underneath it.  That looks exactly like a core bug and is not one.

This writes a pattern, waits, and reads it back, with the core HELD IN RESET
the whole time.  Nothing but the PS can touch that memory during the wait, so
a mismatch means something on the PS side owns memory it should not.

  --churn allocates and touches memory on the PS during the wait, which is what
  a real run does (Python, the driver, page cache) and is the condition under
  which a too-small reservation actually bites.
"""

import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from amoeba import Amoeba, regs as R  # noqa: E402

OPENSBI_ADDR = 0x8020_0000


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--bitstream")
    ap.add_argument("--fclk", type=float, default=25.0)
    ap.add_argument("--addr", type=lambda s: int(s, 0), default=OPENSBI_ADDR,
                    help="guest address to test (default 0x80200000, where OpenSBI runs)")
    ap.add_argument("--mb", type=int, default=1, help="how much to write (default 1 MiB)")
    ap.add_argument("--seconds", type=float, default=30.0, help="how long to wait")
    ap.add_argument("--churn", action="store_true",
                    help="allocate and touch PS memory during the wait")
    args = ap.parse_args()

    try:
        dev = Amoeba(bitstream=args.bitstream, fclk_mhz=args.fclk)
    except PermissionError:
        print("error: need root for /dev/mem (try sudo)", file=sys.stderr)
        return 2
    print(f"# {dev.describe()}")
    if dev.is_bram:
        print("error: this is a block-RAM bitstream; there is no DDR carve-out "
              "to test", file=sys.stderr)
        return 2

    dev.halt()                       # nothing but the PS touches memory now
    off = args.addr - R.EXT_MEM_BASE
    n = args.mb << 20
    blob = os.urandom(n)

    t0 = time.monotonic()
    dev.mem.write_bytes(off, blob)
    w = time.monotonic() - t0
    back = dev.mem.read_bytes(off, n)
    if back != blob:
        bad = next(i for i in range(n) if back[i] != blob[i])
        print(f"FAIL  immediate readback differs at 0x{args.addr + bad:08x} "
              f"-- the write itself did not land")
        return 1
    print(f"# wrote and verified {args.mb} MiB at 0x{args.addr:08x} in {w:.1f} s; "
          f"core held, waiting {args.seconds:.0f} s")

    churn = []
    deadline = time.monotonic() + args.seconds
    while time.monotonic() < deadline:
        if args.churn:
            try:
                churn.append(bytearray(16 << 20))     # touched: bytearray zeroes it
                if len(churn) > 8:
                    churn.pop(0)
            except MemoryError:
                churn.clear()
        time.sleep(0.5)

    back = dev.mem.read_bytes(off, n)
    if back == blob:
        print(f"PASS  {args.mb} MiB unchanged after {args.seconds:.0f} s"
              f"{' with PS churn' if args.churn else ''} -- the carve-out holds")
        return 0

    bad = [i for i in range(n) if back[i] != blob[i]]
    print(f"FAIL  {len(bad)} of {n} bytes changed while the core was HELD IN RESET.")
    print(f"      first at 0x{args.addr + bad[0]:08x}: "
          f"wrote {blob[bad[0]]:#04x}, read {back[bad[0]]:#04x}")
    print(f"      last  at 0x{args.addr + bad[-1]:08x}")
    print("      Nothing but the PS can have done that.  Check that the PS kernel")
    print("      is booted with mem=256M (cat /proc/cmdline) and that no other")
    print("      process has the carve-out mapped.")
    return 1


if __name__ == "__main__":
    sys.exit(main())
