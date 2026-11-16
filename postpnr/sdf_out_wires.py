#!/usr/bin/env python3
"""The SDF's INTERCONNECT delays that end at forte_top's own output ports.

    sdf_out_wires.py <file.sdf>

VCS annotates the SDF at pin_tb.dut, so a wire from a cell pin inside the chip
to one of forte_top's output ports ends "up-hierarchy": VCS cannot apply it,
reports SDFCOM_UHICD and keeps only the driving cell's delay.  In simulation
the output pin then changes earlier than on silicon, by up to that wire delay.

This prints, as shell assignments, the largest such delay per output group
(any rise/fall value, any of min:typ:max, in ps, never below 0), so run.sh can
make the max corner's output-window check stricter by exactly that much:

    WIRES_N=<entries>  WIRES_LINK_PS=<io_out/req/wr>  WIRES_SLOW_PS=<uart_tx/status>
    WIRES_CLK_PS=<clk_out>
"""
import re
import sys

GROUPS = {"io_out": "LINK", "req": "LINK", "wr": "LINK",
          "uart_tx": "SLOW", "status": "SLOW", "clk_out": "CLK"}
NUM = re.compile(r"-?(?:\d+\.?\d*|\.\d+)(?:[eE][-+]?\d+)?")


def main(argv):
    if len(argv) != 1:
        print(__doc__, file=sys.stderr)
        return 2
    divider = "/"
    unit_ns = 1.0                      # (TIMESCALE ...): SDF values are in this unit
    worst = {"LINK": 0.0, "SLOW": 0.0, "CLK": 0.0}
    n = 0
    with open(argv[0], errors="replace") as f:
        for line in f:
            s = line.strip()
            if s.startswith("(DIVIDER"):
                m = re.match(r"\(DIVIDER\s+(\S)\s*\)", s)
                if m:
                    divider = m.group(1)
                continue
            if s.startswith("(TIMESCALE"):
                m = re.match(r"\(TIMESCALE\s+([\d.]+)\s*(ps|ns|us|fs)\s*\)", s)
                if m:
                    unit_ns = float(m.group(1)) * {"fs": 1e-6, "ps": 1e-3, "ns": 1.0, "us": 1e3}[m.group(2)]
                continue
            if not s.startswith("(INTERCONNECT"):
                continue
            parts = s[len("(INTERCONNECT"):].split(None, 2)
            if len(parts) < 3:
                continue
            src, dst, rest = parts
            dst = dst.lstrip("\\")
            port = re.sub(r"\[\d+\]$", "", dst)
            if divider in dst or port not in GROUPS or divider not in src:
                continue
            vals = [float(v) for v in NUM.findall(rest)]
            if not vals:
                continue
            n += 1
            g = GROUPS[port]
            worst[g] = max(worst[g], max(vals))
    ps = {g: int(round(v * unit_ns * 1000)) for g, v in worst.items()}
    print(f"WIRES_N={n}")
    for g in ("LINK", "SLOW", "CLK"):
        print(f"WIRES_{g}_PS={ps[g]}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
