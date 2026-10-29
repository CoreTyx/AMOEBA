#!/usr/bin/env python3
"""Measure the link's timing eye on a LINK_PINS bitstream.

Two instruments, both on the FPGA end; the chip is the DUT and is not touched.

  --sweep phase   (default) the forwarded clock comes from an MMCM whose fine
                  phase shift is stepped through one full aclk period
                  (56 x MMCM_MULT steps, ~22 ps each at 25 MHz).  The chip's
                  whole timing moves against the slave's, so BOTH directions
                  of the link cross their capture edges somewhere in the
                  sweep.  This is the coarse eye, and the one that means
                  something at 10-33 MHz.
  --sweep idelay  the IDELAYE2 tap on the slave's inbound pins, 0..31 x 78 ps:
                  2.5 ns of range, so a fine per-pin trim rather than an eye
                  at these periods.

At each point: halt, set the instrument, load the image, release the core
(which trains the link), dwell --seconds, read what the slave counted.  A point
PASSES if training took first time, no training word mismatched, no beat came
back with HRESP, tohost did not fire, and the core retired within 1 % of the
best point.  The pass map is the eye:

    phase  0        200       400  ...
    25M    XXXXXXXXXX..........XXXXXXXXXXXXXXXXXXXXXXXXXXXXX
    eye = 42 points x 16 steps x 22.3 ps = 15.0 ns wide, failing 160..320

Its WIDTH in ns is the number synth/constraints.sdc's PLACEHOLDER I/O delays
are waiting for (the FPGA-and-board half); its POSITION relative to step 0
is where training lands, which is what stage C exists to check across FCLK.

    sudo python3 link_eye.py --bitstream ../amoeba.bit \\
         --image ../images/heartbeat_app.elf --seconds 1 --save eye_25.json

Use an image that runs for as long as it is left to (heartbeat_app), so every
point sees the same traffic.
"""

import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

from amoeba import image as _image  # noqa: E402
from amoeba import regs as R  # noqa: E402
from amoeba.device import Amoeba, AmoebaError  # noqa: E402

TAP_PS = 78.0


def run_point(dev, img, setup, seconds):
    """One measurement: setup() positions the instrument with the core halted."""
    dev.halt()
    setup()
    r = {"trained": False, "error": None}
    try:
        dev.load(img, verify=False)
        dev.clear_monitors()
        dev.start()                       # blocks on STATUS.link_trained
        r["trained"] = True
    except (RuntimeError, AmoebaError) as exc:
        r["error"] = str(exc).splitlines()[0]
        r.update(dev.link_stats())
        dev.halt()
        return r
    time.sleep(seconds)
    r.update(dev.link_stats())
    r["cycles"] = dev.cycles
    r["retired"] = dev.retired
    r["traps"] = dev.traps
    r["tohost"] = dev.tohost_valid
    r["console"] = len(dev.read_console())
    dev.halt()
    return r


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--image", required=True, help="a program that runs indefinitely")
    ap.add_argument("--bitstream")
    ap.add_argument("--fclk", type=float, default=25.0)
    ap.add_argument("--seconds", type=float, default=1.0, help="dwell per point")
    ap.add_argument("--sweep", choices=("phase", "idelay"), default="phase")
    ap.add_argument("--step", type=int, default=16,
                    help="phase: MMCM steps between points (default 16 = ~0.36 ns at 25 MHz)")
    ap.add_argument("--taps", default="0-31", help="idelay: tap range, e.g. 4-20")
    ap.add_argument("--save", help="write the per-point records to this JSON file")
    args = ap.parse_args()

    img = _image.load(args.image)
    try:
        dev = Amoeba(bitstream=args.bitstream, fclk_mhz=args.fclk)
    except PermissionError:
        print("error: need root for /dev/mem (try sudo)", file=sys.stderr)
        return 2
    print(f"# {dev.describe()}")
    if not dev.is_asic_link:
        print("error: not a DUT=asic bitstream", file=sys.stderr)
        return 2
    got = dev.check_fclk(args.fclk)
    period_ns = 1e3 / (got / 1e6)
    print(f"# fabric clock verified: {got / 1e6:.3f} MHz, {period_ns:.1f} ns period")

    if args.sweep == "phase":
        if not dev.mmcm_locked:
            print("error: MMCM not locked -- not a LINK_PINS bitstream?", file=sys.stderr)
            return 2
        per = dev.phase_steps_per_period
        unit_ps = period_ns * 1e3 / per
        points = list(range(0, per, args.step))
        print(f"# phase sweep: {per} steps per period, {unit_ps:.1f} ps each, "
              f"{len(points)} points {args.step} steps apart ({args.step * unit_ps / 1e3:.2f} ns)")
        dev.phase_set(0)
        def setup_for(p):
            return lambda: dev.phase_set(p)
        label = "phase"
    else:
        if not dev.idelay_ready:
            print("error: IDELAYCTRL not ready -- not a LINK_PINS bitstream, or no 200 MHz "
                  "reference (FCLK_CLK1)", file=sys.stderr)
            return 2
        lo, _, hi = args.taps.partition("-")
        points = list(range(int(lo), int(hi or lo) + 1))
        unit_ps = TAP_PS
        print(f"# idelay sweep: taps {points[0]}..{points[-1]}, {TAP_PS:.0f} ps each")
        def setup_for(p):
            return lambda: dev.set_idelay(p)
        label = "tap"

    results = []
    try:
        for p in points:
            r = run_point(dev, img, setup_for(p), args.seconds)
            r[label] = p
            results.append(r)
            if r["trained"]:
                print(f"{label} {p:5d}: trained  retrain={r['retrain']} train_err={r['train_err']} "
                      f"hresp_err={r['hresp_err']} retired={r['retired']} tohost={int(r['tohost'])}")
            else:
                print(f"{label} {p:5d}: NOT TRAINED  retrain={r.get('retrain')} "
                      f"train_err={r.get('train_err')}  ({r['error']})")
    finally:
        dev.halt()
        if args.sweep == "phase":
            try:
                dev.phase_set(0)
            except RuntimeError:
                pass
        dev.close()

    # A point passes if it trained cleanly and retired within 1 % of the best.
    best = max((r.get("retired", 0) for r in results), default=0)
    def ok(r):
        return (r["trained"] and r["retrain"] == 0 and r["train_err"] == 0
                and r["hresp_err"] == 0 and not r["tohost"]
                and best and abs(r["retired"] - best) <= best // 100)
    row = "".join("X" if ok(r) else "." for r in results)
    print()
    print(f"{label:>6} " + " ".join(f"{p}" for p in points[::max(1, len(points) // 8)]))
    print(f"{got / 1e6:5.1f}M  {row}")
    # The widest passing run; a phase sweep wraps, so join a run at the end
    # to one at the start.
    runs = [(i, len(g)) for i, g in _runs(row)]
    passing = [(i, n) for i, n in runs if row[i] == "X"]
    if passing:
        if args.sweep == "phase" and len(passing) >= 2 and row[0] == "X" and row[-1] == "X":
            first_i, first_n = passing[0]
            last_i, last_n = passing[-1]
            passing = passing[1:-1] + [(last_i, last_n + first_n)]
        start, width = max(passing, key=lambda t: t[1])
        spacing = (args.step if args.sweep == "phase" else 1)
        print(f"eye = {width} points = {width * spacing * unit_ps / 1e3:.2f} ns"
              f"{' of a ' + f'{period_ns:.1f}' + ' ns period' if args.sweep == 'phase' else ''}, "
              f"starting at {label} {points[start % len(points)]}; "
              f"training lands at {label} 0, {'inside' if row[0] == 'X' else 'OUTSIDE'} the eye")
        failing = [(i, n) for i, n in runs if row[i] == "."]
        for i, n in failing:
            print(f"  fails {label} {points[i]}..{points[min(i + n - 1, len(points) - 1)]}")
    else:
        print("no passing point")

    if args.save:
        with open(args.save, "w") as fh:
            json.dump({"fclk_hz": got, "sweep": args.sweep, "unit_ps": unit_ps,
                       "step": args.step, "points": results, "row": row}, fh, indent=1)
        print(f"# saved {args.save}")
    return 0 if "X" in row else 1


def _runs(row):
    i = 0
    while i < len(row):
        j = i
        while j < len(row) and row[j] == row[i]:
            j += 1
        yield i, row[i:j]
        i = j


if __name__ == "__main__":
    sys.exit(main())
