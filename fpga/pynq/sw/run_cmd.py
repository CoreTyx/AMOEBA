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
import signal
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
    ap.add_argument("--no-sink", action="store_true",
                    help="drain trace and console through registers even when the bitstream has the DDR sink")
    ap.add_argument("--no-trace", action="store_true", help="no link trace (long runs: Linux)")
    ap.add_argument("--out")
    a = ap.parse_args()

    name = os.path.splitext(os.path.basename(a.image))[0]
    out = a.out or os.path.join("runs", name)
    os.makedirs(out, exist_ok=True)

    # A timeout's SIGTERM must still reach dev.hold() below.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(143))
    dev = Forte(a.bitstream, a.fclk)
    dev.configure(seed=a.seed, gap_pct=a.gap, rd_lat=a.lat, wdog=a.wdog, mutate=a.mutate, trace=not a.no_trace,
                  det=not a.nodet, stop_on_error=a.max_errors == 1, boot_gate=a.boot_gate)
    run = Run(dev, os.path.join(out, "pin_trace.log"), os.path.join(out, "uart.log"), a.max_errors)
    # The bitstream is loaded once per boot, so this run's DDR traffic is the
    # difference from here.
    mem_before = dev.mem_status() if dev.is_ddr else None
    if dev.has_sink and not a.no_sink:
        dev.sink_start(trace=not a.no_trace)

    if a.script:
        image = os.path.abspath(a.image)
        lines = [l.replace("$MEM", image).replace("$RUN", os.path.abspath(out)) for l in open(a.script)]
    else:
        lines = [f"load_lst {a.image}", "reset 16", f"run_until_tohost {a.timeout}", "expect_tohost 0"]

    result = ""
    sink = None
    try:
        for n, line in enumerate(lines, 1):
            result = run.execute(line, n)
            if result:
                break
        result = run.verdict(result or "PASS")
        sink = dev.sink_status() if dev.sink is not None else None
    finally:
        dev.hold()

    print(f"[FORTE] link_rd={dev.rd(R.REG_LINK_RD)} link_wr={dev.rd(R.REG_LINK_WR)} errors={run.total_errors()} "
          f"trace_dropped={dev.rd(R.REG_TRACE_DROPPED)}")
    if dev.is_ddr:
        m = dev.mem_status()
        reads = m["reads"] - mem_before["reads"]
        lat_mean = (m["lat_sum"] - mem_before["lat_sum"]) / reads if reads else 0.0
        print(f"[FORTE] ddr reads={reads} writes={m['writes'] - mem_before['writes']} "
              f"dropped={m['dropped'] - mem_before['dropped']} lat_mean={lat_mean:.1f} "
              f"lat_max_since_load={m['lat_max']} err={m['err']}")
        hist = [after - before for after, before in zip(m["hist"], mem_before["hist"])]
        print("[FORTE] ddr read latency histogram (cycles: reads): " +
              " ".join(f"{4 * b}{'+' if b == len(hist) - 1 else f'-{4 * b + 3}'}:{n}"
                       for b, n in enumerate(hist) if n))
        if mem_before["err"]:
            print(f"[FORTE] note: HP0 error flag was already set before this run "
                  f"(response {m['err_resp']} on line 0x{m['err_addr']:08x}); reload the bitstream to clear it")
        elif m["err"] and result == "PASS":
            print(f"[FORTE] ERROR: HP0 response {m['err_resp']} on line 0x{m['err_addr']:08x}")
            result = "FAIL"
    if sink is not None:
        print(f"[FORTE] sink trace={sink['trace']} console={sink['console']} err={sink['err']}")
        if sink["err"] and result == "PASS":
            print(f"[FORTE] ERROR: HP2 response {sink['err_resp']} writing a ring")
            result = "FAIL"
    line = f"PIN_TB_RESULT: {result}"
    print(line)
    with open(os.path.join(out, "RESULT"), "w") as fh:
        fh.write(line + "\n")
    return 0 if result == "PASS" else 1


if __name__ == "__main__":
    sys.exit(main())
