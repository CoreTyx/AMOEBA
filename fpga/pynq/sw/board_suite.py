#!/usr/bin/env python3
"""Run the pin-bench comparison set on the board and print one table.

  sudo python3 board_suite.py [--bitstream ../forte.bit] [--images ../images]
                              [--scripts ../scripts] [--quick]

The same programs and knob sets as fpga/bringup/tb/fbu_vs_pin.sh, each into
runs/<image>/<knobs>/ (RESULT, uart.log, pin_trace.log), so the traces can be
compared with the bench's on the development machine.  --quick runs only the
default knob set.  The bitstream is programmed once."""

import argparse
import glob
import os
import subprocess
import sys

KNOBS = [
    ("d", []),
    ("g30s1", ["--gap", "30", "--seed", "1"]),
    ("g30s2l2", ["--gap", "30", "--seed", "2", "--lat", "2"]),
    ("g60s3", ["--gap", "60", "--seed", "3"]),
    ("g10s4l7", ["--gap", "10", "--seed", "4", "--lat", "7"]),
]
SCRIPTED = ["irq", "uart_echo", "uart_lsr"]
# fpga/bringup/tests programs wait on their own fbu scripts (run_cmd.py with
# ../scripts/<name>.cmd); without one they would never reach tohost.
OWN_SCRIPT_PREFIX = "fe_"


def force_lat(extra, rd_lat):
    """extra with any --lat replaced by rd_lat (None leaves it alone)."""
    if rd_lat is None:
        return extra
    kept = []
    skip = False
    for arg in extra:
        if skip:
            skip = False
        elif arg == "--lat":
            skip = True
        else:
            kept.append(arg)
    return kept + ["--lat", str(rd_lat)]


def run(here, image, script, out, extra, bitstream):
    cmd = [sys.executable, os.path.join(here, "run_cmd.py"), image]
    if script:
        cmd.append(script)
    cmd += ["--out", out] + extra
    if bitstream:
        cmd += ["--bitstream", bitstream]
    proc = subprocess.run(cmd, capture_output=True, text=True)
    with open(os.path.join(out, "run.log"), "w") as fh:
        fh.write(proc.stdout + proc.stderr)
    result = next((l for l in proc.stdout.splitlines() if l.startswith("PIN_TB_RESULT")), "PIN_TB_RESULT: FAIL no verdict")
    summary = next((l for l in proc.stdout.splitlines() if l.startswith("[FORTE] link_rd")), "")
    return result.split(":", 1)[1].strip(), summary.replace("[FORTE] ", "")


def main():
    here = os.path.dirname(os.path.abspath(__file__))
    ap = argparse.ArgumentParser()
    ap.add_argument("--bitstream", default=os.path.join(here, "..", "forte.bit"))
    ap.add_argument("--images", default=os.path.join(here, "..", "images"))
    ap.add_argument("--scripts", default=os.path.join(here, "..", "scripts"))
    ap.add_argument("--quick", action="store_true")
    ap.add_argument("--rd-lat", type=int,
                    help="one rd_latency for every run, in place of the knobs' (the DDR build "
                         "needs one above its worst read latency, as FORCE_RD_LAT in the gate)")
    ap.add_argument("--nodet", action="store_true",
                    help="natural link timing (LINK-10): the DDR's own latency, not the DET-mode slot")
    a = ap.parse_args()
    common = ["--nodet"] if a.nodet else []

    bitstream = a.bitstream
    rows = []
    for image in sorted(glob.glob(os.path.join(a.images, "*.lst"))):
        name = os.path.splitext(os.path.basename(image))[0]
        if name.startswith(OWN_SCRIPT_PREFIX):
            continue
        if name in SCRIPTED:
            out = os.path.join("runs", name, "script")
            os.makedirs(out, exist_ok=True)
            rows.append((name, "script") + run(here, image, os.path.join(a.scripts, name + ".cmd"), out,
                                               force_lat(common, a.rd_lat), bitstream))
            bitstream = None
            continue
        for knob, extra in (KNOBS[:1] if a.quick else KNOBS):
            out = os.path.join("runs", name, knob)
            os.makedirs(out, exist_ok=True)
            rows.append((name, knob) + run(here, image, None, out, force_lat(extra + common, a.rd_lat), bitstream))
            bitstream = None
        print(f"  {name} done", flush=True)

    passed = sum(1 for r in rows if r[2] == "PASS")
    print()
    for name, knob, result, summary in rows:
        print(f"{'ok  ' if result == 'PASS' else 'FAIL'} {name:24} {knob:8} {result:28} {summary}")
    print(f"board_suite: {passed}/{len(rows)} passed")
    return 0 if passed == len(rows) else 1


if __name__ == "__main__":
    sys.exit(main())
