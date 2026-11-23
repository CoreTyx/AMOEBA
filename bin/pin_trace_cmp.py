#!/usr/bin/env python3
"""Compare two pin-bench runs (hvl/pin): RTL against netlist, golden against new.

    pin_trace_cmp.py <runA> <runB> [--no-cycles | --cycle-slack=N] [--only-link]

Each argument is a run directory or a single trace file.  For a directory,
every trace both runs have is compared, and the result is the worst of them:

  pin_trace.log         link transactions (hvl/pin/pin_link_agent.sv):
                          L <cyc> R|W <addr> <beats...>   T <cyc> <tohost>
                          I <cyc> <idx> <level>           E <cyc> <error>
  pin_cycle.log[.gz]    every forte_top port, every core cycle after reset
                        (hvl/pin/pin_cycle_trace.sv), written on change:
                          R <n>   C <cyc> <io_in> <rdy><rv> <irq> <rx> <tm><se><fi> | <io_out> <req><wr> <tx> <st>
  uart.log              the console bytes the chip sent

A directory with pin_cycle in one run but not the other is a mismatch: a
comparison that silently skipped the strict trace would look like a pass.

By default everything is cycle-exact: a netlist must do the same thing on the
same cycle as its RTL.  --no-cycles compares the transaction trace by content
and order only (runs whose timing legitimately differs, e.g. different FPGA
latencies) and skips the per-cycle trace.  --cycle-slack=N sits between: the
transaction trace must match record for record in content and order, and each
record's cycle may differ by at most N (the largest shift is reported as
"cycle shift +-S"); the console still matches byte for byte; the per-cycle
trace is not compared, since a shifted run differs on every cycle after the
shift.  For a netlist whose clock-domain crossings resolve an edge earlier or
later than the RTL's.  --only-link compares pin_trace.log alone (the
pre-postpnr behaviour).
Exit 0 on match, 1 on mismatch, 2 on usage error.
"""
import gzip
import os
import sys

CYCLE_FIELDS = ["io_in", "ready", "rvalid", "irq", "uart_rx", "test_mode", "scan_en",
                "fault_inject", "io_out", "req", "wr", "uart_tx", "status"]
OUT_FIELDS = {"io_out", "req", "wr", "uart_tx", "status"}


def opener(path):
    return gzip.open(path, "rt") if path.endswith(".gz") else open(path)


def find(d, *names):
    for n in names:
        p = os.path.join(d, n)
        if os.path.exists(p):
            return p
    return None


# ---- pin_trace.log ----------------------------------------------------------
def load_link(path, cycles):
    recs = []
    with opener(path) as f:
        for n, line in enumerate(f, 1):
            parts = line.split()
            if not parts:
                continue
            if not cycles and len(parts) > 1:
                parts = [parts[0]] + parts[2:]
            recs.append((n, " ".join(parts)))
    return recs


def split_cyc(rec):
    """'L 573 R addr ...' -> (573, 'L R addr ...'); a record with no cycle -> (None, rec)."""
    p = rec.split()
    if len(p) > 1 and p[1].lstrip("-").isdigit():
        return int(p[1]), " ".join([p[0]] + p[2:])
    return None, rec


def cmp_link(pa, pb, cycles, slack=0):
    a, b = load_link(pa, cycles), load_link(pb, cycles)
    shift = 0
    for i, (ra, rb) in enumerate(zip(a, b)):
        if slack:
            (ca, ka), (cb, kb) = split_cyc(ra[1]), split_cyc(rb[1])
            if ka == kb and ca is not None and cb is not None:
                if abs(cb - ca) > slack:
                    return False, [f"MISMATCH link trace at record {i}: same transaction, but cycle {cb} vs {ca} "
                                   f"is a shift of {cb - ca:+d}, beyond --cycle-slack {slack} ({pa}:{ra[0]} vs {pb}:{rb[0]})",
                                   f"  A    : {ra[1]}", f"  B    : {rb[1]}"]
                shift = max(shift, abs(cb - ca))
                continue
        if ra[1] != rb[1]:
            out = [f"MISMATCH link trace at record {i} ({pa}:{ra[0]} vs {pb}:{rb[0]})"]
            for j in range(max(0, i - 3), i):
                out.append(f"  same : {a[j][1]}")
            out.append(f"  A    : {ra[1]}")
            out.append(f"  B    : {rb[1]}")
            return False, out
    if len(a) != len(b):
        short, longer, pl = (pa, b, pb) if len(a) < len(b) else (pb, a, pa)
        return False, [f"MISMATCH link trace: {short} ends after {min(len(a), len(b))} records; {pl} continues with:",
                       f"  {longer[min(len(a), len(b))][1]}"]
    errs = sum(1 for _, r in a if r.startswith("E"))
    how = (f" (cycle shift +-{shift}, within --cycle-slack {slack})" if slack
           else "" if cycles else " (cycles ignored)")
    msg = (f"link {len(a)} records{how}"
           f"{f', but both contain {errs} checker errors' if errs else ''}")
    return errs == 0, [msg]


# ---- pin_cycle.log ------------------------------------------------------------
def parse_cycle(line):
    """'C 12 81 01 00 1 000 | 00 00 1 0' -> (12, {field: value})."""
    p = line.split()
    io_in, rr, irq, rx, tse, bar, io_out, rw, tx, st = p[2:12]
    if bar != "|":
        raise ValueError(line)
    v = {"io_in": io_in, "ready": rr[0], "rvalid": rr[1], "irq": irq, "uart_rx": rx,
         "test_mode": tse[0], "scan_en": tse[1], "fault_inject": tse[2],
         "io_out": io_out, "req": rw[0], "wr": rw[1], "uart_tx": tx, "status": st}
    return int(p[1]), v


def load_cycle(path):
    recs = []
    with opener(path) as f:
        for n, line in enumerate(f, 1):
            s = line.strip()
            if not s or s.startswith("#"):
                continue
            recs.append((n, s))
    return recs


def link_context(run_dir, near_cyc, k=2):
    """The last k link transactions that started at or before near_cyc."""
    p = run_dir and find(run_dir, "pin_trace.log")
    if not p:
        return []
    ls = []
    with open(p) as f:
        for line in f:
            t = line.split()
            if len(t) > 2 and t[0] == "L" and int(t[1]) <= near_cyc:
                ls.append(line.rstrip())
    return ls[-k:]


def cmp_cycle(pa, pb, da=None, db=None):
    a, b = load_cycle(pa), load_cycle(pb)
    unknown_b = None
    for i, (ra, rb) in enumerate(zip(a, b)):
        if ra[1] == rb[1]:
            continue
        out = [f"MISMATCH pin cycle trace at record {i} ({pa}:{ra[0]} vs {pb}:{rb[0]})"]
        for j in range(max(0, i - 3), i):
            out.append(f"  same : {a[j][1]}")
        out.append(f"  A    : {ra[1]}")
        out.append(f"  B    : {rb[1]}")
        if ra[1][0] == "C" and rb[1][0] == "C":
            ca, va = parse_cycle(ra[1])
            cb, vb = parse_cycle(rb[1])
            if ca != cb:
                out.append(f"  pins first differ in cycle {min(ca, cb)} "
                           f"(A changes at {ca}, B at {cb}: the change in the earlier one is missing or early in the other)")
            diff = [f for f in CYCLE_FIELDS if va[f] != vb[f]]
            for f in diff:
                kind = "output" if f in OUT_FIELDS else "input"
                xs = " (X/Z)" if any(c in "xXzZ" for c in vb[f]) else ""
                out.append(f"  {kind:6s} {f:12s} A={va[f]:4s} B={vb[f]}{xs}")
            near = min(ca, cb)
            for tag, d in (("A", da), ("B", db)):
                for l in link_context(d, near):
                    out.append(f"  {tag} link: {l}")
        return False, out
    if len(a) != len(b):
        short, longer, pl = (pa, b, pb) if len(a) < len(b) else (pb, a, pa)
        last = a[min(len(a), len(b)) - 1][1] if min(len(a), len(b)) else "(nothing)"
        return False, [f"MISMATCH pin cycle trace: {short} ends after {min(len(a), len(b))} records "
                       f"(last: {last}); {pl} continues with:",
                       f"  {longer[min(len(a), len(b))][1]}"]
    last_c = next((parse_cycle(r)[0] for _, r in reversed(a) if r.startswith("C")), 0)
    xa = sum(1 for _, r in a if r.startswith("C") and any(c in "xXzZ" for c in r.split("|")[1]))
    msg = f"pins {len(a)} changes over {last_c} cycles"
    if xa:
        return False, [msg + f", but both have X/Z on outputs in {xa} records"]
    return True, [msg]


# ---- uart.log ------------------------------------------------------------------
def cmp_uart(pa, pb):
    with open(pa, "rb") as f:
        a = f.read()
    with open(pb, "rb") as f:
        b = f.read()
    if a == b:
        return True, [f"uart {len(a)} bytes"]
    n = next((i for i in range(min(len(a), len(b))) if a[i] != b[i]), min(len(a), len(b)))
    return False, [f"MISMATCH uart: byte {n} differs ({len(a)} vs {len(b)} bytes)",
                   f"  A: {a[max(0, n - 40):n + 20]!r}", f"  B: {b[max(0, n - 40):n + 20]!r}"]


def is_cycle_file(path):
    with opener(path) as f:
        return f.readline().startswith("# pin_cycle")


def main(argv):
    slack = 0
    for a in [a for a in argv if a.startswith("--cycle-slack=")]:
        v = a.split("=", 1)[1]
        if not v.isdigit():
            print(f"--cycle-slack=N needs a whole number of cycles, not '{v}'")
            return 2
        slack = int(v)
    flags = {a for a in argv if a.startswith("--") and not a.startswith("--cycle-slack=")}
    args = [a for a in argv if not a.startswith("--")]
    if len(args) != 2 or flags - {"--no-cycles", "--only-link"} or (slack and "--no-cycles" in flags):
        print(__doc__)
        return 2
    cycles = "--no-cycles" not in flags
    A, B = args
    results = []
    if os.path.isdir(A) and os.path.isdir(B):
        la, lb = find(A, "pin_trace.log"), find(B, "pin_trace.log")
        if not (la and lb):
            print(f"MISMATCH: pin_trace.log missing in {A if not la else B}")
            return 1
        results.append(cmp_link(la, lb, cycles, slack))
        if "--only-link" not in flags and cycles:
            ca = find(A, "pin_cycle.log.gz", "pin_cycle.log")
            cb = find(B, "pin_cycle.log.gz", "pin_cycle.log")
            if slack:
                results.append((True, [f"per-cycle pin trace not compared (--cycle-slack {slack})"]))
            elif ca and cb:
                results.append(cmp_cycle(ca, cb, A, B))
            elif ca or cb:
                results.append((False, [f"MISMATCH: pin_cycle.log only in {A if ca else B}"]))
            ua, ub = find(A, "uart.log"), find(B, "uart.log")
            if ua and ub:
                results.append(cmp_uart(ua, ub))
    elif os.path.isfile(A) and os.path.isfile(B):
        if is_cycle_file(A) != is_cycle_file(B):
            print("MISMATCH: one file is a pin cycle trace and the other is not")
            return 1
        if is_cycle_file(A) and slack:
            print("--cycle-slack does not apply to a per-cycle trace")
            return 2
        results.append(cmp_cycle(A, B) if is_cycle_file(A) else cmp_link(A, B, cycles, slack))
    else:
        print(f"usage: both arguments must be run directories or both files: {A}, {B}")
        return 2
    ok = all(r[0] for r in results)
    if ok:
        print("MATCH: " + "; ".join(r[1][0] for r in results))
    else:
        bad = [r for r in results if not r[0]]
        lines = [l for r in bad for l in r[1]]
        if not lines[0].startswith("MISMATCH"):
            lines[0] = "MISMATCH: " + lines[0]
        print("\n".join(lines))
        good = [r[1][0] for r in results if r[0]]
        if good:
            print("  (matched: " + "; ".join(good) + ")")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
