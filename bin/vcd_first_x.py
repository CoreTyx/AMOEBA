#!/usr/bin/env python3
"""Find where an X starts: the first signals in a VCD to go from known to X.

    vcd_first_x.py <file.vcd> [--after NS] [--top N] [--scope PREFIX] [--match REGEX]

Signals that are X from the start and never become known (uninitialised
arrays, unused nets) are ignored; what is reported is each signal's first
transition from a fully known value to a value with X or Z bits, after time
--after (ns, default 0: use a time after reset has been released).  Sorted
by time, the first few lines are where the X entered; everything after them
is it spreading.  --scope keeps only signals whose hierarchical name starts
with PREFIX (e.g. pin_tb.dut.chip.soc).  --match keeps only names matching a
regular expression -- e.g. control (pointers, valids, state) rather than data
paths, which go X harmlessly whenever their valid is low.

Made for hvl/pin/pin_tb.sv's +PIN_VCD dumps (build with WAVES=1).
"""
import sys

UNITS = {"s": 1e9, "ms": 1e6, "us": 1e3, "ns": 1.0, "ps": 1e-3, "fs": 1e-6}


def main(argv):
    if not argv or argv[0].startswith("-"):
        print(__doc__)
        return 2
    import re
    path, after, top, scope, match = argv[0], 0.0, 30, "", None
    i = 1
    while i < len(argv):
        if argv[i] == "--after":
            after = float(argv[i + 1]); i += 2
        elif argv[i] == "--top":
            top = int(argv[i + 1]); i += 2
        elif argv[i] == "--scope":
            scope = argv[i + 1]; i += 2
        elif argv[i] == "--match":
            match = re.compile(argv[i + 1]); i += 2
        else:
            print(f"unknown argument {argv[i]}"); return 2

    names = {}          # id code -> [hierarchical names]
    stack = []
    ns_per_tick = 1.0
    known = {}          # id -> True once a fully known value has been seen
    first_x = {}        # id -> time (ns) of first known -> X transition
    t = 0.0

    with open(path, "r", errors="replace") as f:
        # header
        tokens = []
        for line in f:
            tokens += line.split()
            if "$enddefinitions" in tokens:
                break
        j = 0
        while j < len(tokens):
            tok = tokens[j]
            if tok == "$timescale":
                spec = []
                j += 1
                while tokens[j] != "$end":
                    spec.append(tokens[j]); j += 1
                spec = "".join(spec)
                num = "".join(c for c in spec if c.isdigit()) or "1"
                unit = spec[len(num):]
                ns_per_tick = int(num) * UNITS.get(unit, 1.0)
            elif tok == "$scope":
                stack.append(tokens[j + 2]); j += 3
            elif tok == "$upscope":
                stack.pop(); j += 1
            elif tok == "$var":
                # $var <type> <width> <id> <name> [range] $end
                k = j + 1
                while tokens[k] != "$end":
                    k += 1
                vid, name = tokens[j + 3], tokens[j + 4]
                full = ".".join(stack + [name])
                if full.startswith(scope) and (match is None or match.search(full)):
                    names.setdefault(vid, []).append(full)
                j = k
            j += 1

        def change(vid, val):
            if vid not in names or vid in first_x:
                return
            bad = any(c in "xXzZ" for c in val)
            if not bad:
                known[vid] = True
            elif known.get(vid) and t >= after:
                first_x[vid] = t

        # value changes
        for line in f:
            line = line.strip()
            if not line:
                continue
            c = line[0]
            if c == "#":
                t = int(line[1:]) * ns_per_tick
            elif c in "01xXzZ":
                change(line[1:], c)
            elif c in "bB":
                val, vid = line[1:].split()
                change(vid, val)
            elif c in "rR":
                pass                       # reals carry no X

    hits = sorted((tm, vid) for vid, tm in first_x.items())
    import os
    print(f"read {path}: {os.path.getsize(path)} bytes, {len(names)} signals"
          f"{' in ' + scope if scope else ''}, last time {t:.3f} ns, "
          f"{sum(1 for v in known if v in names)} ever known")
    if not hits:
        print(f"no signal went from known to X after {after} ns")
        return 0
    print(f"{len(hits)} signals went from known to X after {after} ns; first {min(top, len(hits))}:")
    for tm, vid in hits[:top]:
        print(f"  {tm:12.3f} ns  {names[vid][0]}" + (f"  (+{len(names[vid]) - 1} aliases)" if len(names[vid]) > 1 else ""))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
