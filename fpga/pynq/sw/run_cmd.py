#!/usr/bin/env python3
"""Run one program on the FPGA-emulated chip, as the pin bench would.

  sudo python3 run_cmd.py <image.lst> [script.cmd] [--bitstream forte.bit]
                          [--seed N --gap PCT --lat N --wdog N --mutate N --nodet]
                          [--boot-gate] [--out runs/NAME]

Writes RESULT, uart.log and pin_trace.log into the run directory, the layout
of sim/pin/runs/, so `hvl/pin/pin.sh compare` works on board runs.  Without a
script: load, reset 16, run to tohost, expect exit code 0."""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from forte.device import Forte  # noqa: E402
from forte.cmdscript import Run  # noqa: E402
from forte import regs as R  # noqa: E402


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("image")
    ap.add_argument("script", nargs="?")
    ap.add_argument("--bitstream")
    ap.add_argument("--fclk", type=float, default=25.0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--gap", type=int, default=0)
    ap.add_argument("--lat", type=int, default=0)
    ap.add_argument("--wdog", type=int, default=1000)
    ap.add_argument("--mutate", type=int, default=0)
    ap.add_argument("--nodet", action="store_true")
    ap.add_argument("--max-errors", type=int, default=1)
    ap.add_argument("--timeout", type=int, default=10_000_000)
    ap.add_argument("--boot-gate", action="store_true")
    ap.add_argument("--out")
    a = ap.parse_args()

    name = os.path.splitext(os.path.basename(a.image))[0]
    out = a.out or os.path.join("runs", name)
    os.makedirs(out, exist_ok=True)

    dev = Forte(a.bitstream, a.fclk)
    dev.configure(seed=a.seed, gap_pct=a.gap, rd_lat=a.lat, wdog=a.wdog, mutate=a.mutate,
                  det=not a.nodet, stop_on_error=a.max_errors == 1, boot_gate=a.boot_gate)
    run = Run(dev, os.path.join(out, "pin_trace.log"), os.path.join(out, "uart.log"), a.max_errors)

    if a.script:
        image = os.path.abspath(a.image)
        lines = [l.replace("$MEM", image).replace("$RUN", os.path.abspath(out)) for l in open(a.script)]
    else:
        lines = [f"load_lst {a.image}", "reset 16", f"run_until_tohost {a.timeout}", "expect_tohost 0"]

    result = ""
    for n, line in enumerate(lines, 1):
        result = run.execute(line, n)
        if result:
            break
    result = run.verdict(result or "PASS")

    line = f"PIN_TB_RESULT: {result}"
    print(f"[FORTE] link_rd={dev.rd(R.REG_LINK_RD)} link_wr={dev.rd(R.REG_LINK_WR)} errors={run.total_errors()} "
          f"trace_dropped={dev.rd(R.REG_TRACE_DROPPED)}")
    print(line)
    with open(os.path.join(out, "RESULT"), "w") as fh:
        fh.write(line + "\n")
    return 0 if result == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
