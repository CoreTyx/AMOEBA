#!/usr/bin/env python3
"""Compare two pin traces written by hvl/pin/pin_link_agent.sv.

    pin_trace_cmp.py <runA> <runB> [--no-cycles]

Each argument is a run directory (containing pin_trace.log) or a trace file.
Record types: L <cyc> R|W <addr> <beats...>  link transaction
              T <cyc> <value>                 tohost write
              I <cyc> <idx> <level>           irq pin change
              E <cyc> <message>               checker error
By default the comparison is cycle-exact: a netlist must do the same thing on
the same link cycle as its RTL.  --no-cycles compares content and order only
(for runs whose timing legitimately differs, e.g. different FPGA latencies).
Exit 0 on match, 1 on mismatch, 2 on usage error.
"""
import os
import sys


def load(path, cycles):
    if os.path.isdir(path):
        path = os.path.join(path, "pin_trace.log")
    recs = []
    with open(path) as f:
        for n, line in enumerate(f, 1):
            parts = line.split()
            if not parts:
                continue
            if not cycles and len(parts) > 1:
                parts = [parts[0]] + parts[2:]
            recs.append((n, " ".join(parts)))
    return path, recs


def main(argv):
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 2 or any(a not in ("--no-cycles",) for a in argv if a.startswith("--")):
        print(__doc__)
        return 2
    cycles = "--no-cycles" not in argv
    pa, a = load(args[0], cycles)
    pb, b = load(args[1], cycles)
    for i, (ra, rb) in enumerate(zip(a, b)):
        if ra[1] != rb[1]:
            print(f"MISMATCH at record {i} ({pa}:{ra[0]} vs {pb}:{rb[0]})")
            for j in range(max(0, i - 3), i):
                print(f"  same : {a[j][1]}")
            print(f"  A    : {ra[1]}")
            print(f"  B    : {rb[1]}")
            return 1
    if len(a) != len(b):
        short, longer, pl = (pa, b, pb) if len(a) < len(b) else (pb, a, pa)
        print(f"MISMATCH: {short} ends after {min(len(a), len(b))} records; {pl} continues with:")
        print(f"  {longer[min(len(a), len(b))][1]}")
        return 1
    errs = sum(1 for _, r in a if r.startswith("E"))
    print(f"MATCH: {len(a)} records{'' if cycles else ' (cycles ignored)'}"
          f"{f', but both contain {errs} checker errors' if errs else ''}")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
