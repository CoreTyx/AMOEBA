#!/usr/bin/env python3
"""Is the external AHB driven while the core is held in reset?

    sudo python3 probe_reset.py --bitstream ../amoeba.bit --fclk 25

The core is halted and NEVER started, and no image is loaded.  Nothing should
move.  If the transfer counters advance anyway, the traffic we have been
attributing to the core's first instruction fetch is not the core's at all --
which changes the bug from "the bridge rejects our fetch" to "something drives
this bus when nothing should".

Deliberately not part of run_freertos.py: the whole value here is that it does
LESS.  No image, no release, no console -- so anything observed cannot be
blamed on the program or on the core running.
"""

import argparse
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from amoeba import Amoeba, AmoebaError, regs as R      # noqa: E402

FIELDS = [("XACT", "R_BUS_XACT"), ("BEAT", "R_BUS_BEAT"),
          ("ERR", "R_BUS_ERR"), ("STALL", "R_BUS_STALL"),
          ("RSTXACT", "R_BUS_RSTXACT"), ("CYCLES", "R_CYCLES_LO")]


def sample(dev):
    return {k: dev.ctl.read(getattr(R, a)) for k, a in FIELDS}


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--bitstream", default=None)
    ap.add_argument("--fclk", type=float, default=25.0)
    ap.add_argument("--seconds", type=float, default=2.0)
    args = ap.parse_args()

    dev = Amoeba(bitstream=args.bitstream,
                 fclk_mhz=args.fclk if args.fclk > 0 else None)
    print(f"# {dev.describe()}")

    dev.halt()
    dev.clear_monitors()
    print("# core halted, monitors cleared, no image loaded")
    print(f"# CTRL reads back 0x{dev.ctl.read(R.R_CTRL):08x} "
          f"(bit0 = core_reset)")

    a = sample(dev)
    st_a = dev.ctl.read(R.R_BUS_STATE)
    time.sleep(args.seconds)
    b = sample(dev)
    st_b = dev.ctl.read(R.R_BUS_STATE)

    print(f"# after {args.seconds} s with the core held:")
    moved = False
    for k, _ in FIELDS:
        d = b[k] - a[k]
        flag = ""
        if k not in ("CYCLES",) and d:
            moved = True
            flag = "   <-- MOVED"
        print(f"#   {k:8s} {a[k]:12d} -> {b[k]:12d}  (+{d}){flag}")

    print(f"# bus state at start: {R.decode_bus_state(st_a)}")
    print(f"# bus state at end:   {R.decode_bus_state(st_b)}")

    print()
    if moved:
        print("VERDICT: the AHB is being driven WITH THE CORE HELD IN RESET.")
        print("  The core cannot be the source, so the transfers counted during")
        print("  a normal run are not its instruction fetches either.")
    else:
        print("VERDICT: the bus is quiet while the core is held, as it should")
        print("  be.  The traffic in a normal run therefore does belong to the")
        print("  core, and the reset-window count came from somewhere else.")
    dev.close()
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except AmoebaError as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(2)
