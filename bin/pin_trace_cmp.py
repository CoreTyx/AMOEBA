#!/usr/bin/env python3
"""Compare two pin-bench runs (hvl/pin): RTL against netlist, golden against new.

    pin_trace_cmp.py <runA> <runB> [--no-cycles | --cycle-slack=N | --reorder=N] [--only-link]

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
later than the RTL's.  --reorder=N also lets transactions to different
addresses swap places, as the I- and D-cache fills do when a timing shift
changes which one reaches the bus first: every record must still appear in both
traces with the same content, the records for each address (and for each T, I
and E kind) must come in the same order, writes must stay in order with each
other, and each record's cycle may differ from its counterpart's by at most N.
--only-link compares pin_trace.log alone (the
pre-postpnr behaviour).
Exit 0 on match, 1 on mismatch, 2 on usage error.
"""
import gzip
import os
import sys
from collections import Counter, defaultdict

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


def link_group(rec):
    """Records in one group must keep their relative order under --reorder: one address, or one T/I/E kind."""
    p = rec.split()
    if p[0] == "L":
        return ("L", p[2])
    if p[0] == "I":
        return ("I", p[1])
    return (p[0],)


def first_unpaired(a_keys, b_keys):
    """The first record of a_keys with no counterpart left in b_keys."""
    left = Counter(b_keys)
    for k in a_keys:
        if left[k] == 0:
            return k
        left[k] -= 1
    return None


def cmp_link_reorder(pa, pb, window):
    a, b = load_link(pa, True), load_link(pb, True)
    a_recs = [(n, *split_cyc(r)) for n, r in a]
    b_recs = [(n, *split_cyc(r)) for n, r in b]
    a_keys = [k for _, _, k in a_recs]
    b_keys = [k for _, _, k in b_recs]
    if Counter(a_keys) != Counter(b_keys):
        only_a = first_unpaired(a_keys, b_keys)
        only_b = first_unpaired(b_keys, a_keys)
        out = [f"MISMATCH link trace: the two runs do not make the same transactions ({pa} vs {pb})"]
        if only_a:
            out.append(f"  only in A: {only_a}")
        if only_b:
            out.append(f"  only in B: {only_b}")
        return False, out

    a_writes = [k for k in a_keys if k.split()[1] == "W"]
    b_writes = [k for k in b_keys if k.split()[1] == "W"]
    if a_writes != b_writes:
        i = next(i for i, (x, y) in enumerate(zip(a_writes, b_writes)) if x != y)
        return False, [f"MISMATCH link trace: write {i} differs in order ({pa} vs {pb})",
                       f"  A    : {a_writes[i]}", f"  B    : {b_writes[i]}"]

    groups_b = defaultdict(list)
    for ib, (n, cyc, k) in enumerate(b_recs):
        groups_b[link_group(k)].append((ib, n, cyc, k))
    taken = Counter()
    shift = 0
    worst = None
    max_moved = 0
    in_place_shift = 0
    for ia, (n, cyc, k) in enumerate(a_recs):
        g = link_group(k)
        ib, nb, cb, kb = groups_b[g][taken[g]]
        taken[g] += 1
        if kb != k:
            return False, [f"MISMATCH link trace: records for {' '.join(g)} come in a different order "
                           f"({pa}:{n} vs {pb}:{nb})", f"  A    : {k}", f"  B    : {kb}"]
        if cyc is not None and cb is not None:
            if abs(cb - cyc) > window:
                return False, [f"MISMATCH link trace: same transaction, but cycle {cb} vs {cyc} is a shift of "
                               f"{cb - cyc:+d}, beyond --reorder {window} ({pa}:{n} vs {pb}:{nb})",
                               f"  A    : {k}", f"  B    : {kb}"]
            moved_by = abs(ib - ia)
            max_moved = max(max_moved, moved_by)
            if moved_by == 0:
                in_place_shift = max(in_place_shift, abs(cb - cyc))
            if worst is None or abs(cb - cyc) > abs(worst[2] - worst[1]):
                worst = (k, cyc, cb, moved_by, n, nb)
            shift = max(shift, abs(cb - cyc))

    moved = sum(1 for x, y in zip(a_keys, b_keys) if x != y)
    errs = sum(1 for k in a_keys if k.startswith("E"))
    msg = (f"link {len(a)} records, {moved} out of place (cycle shift +-{shift}, within --reorder {window}; "
           f"moved at most {max_moved} places; records in place shift +-{in_place_shift})"
           f"{f', but both contain {errs} checker errors' if errs else ''}")
    out = [msg]
    if worst and worst[2] != worst[1]:
        k, ca, cb, moved_by, na, nb = worst
        out.append(f"  largest shift: {k}, cycle {ca} -> {cb} ({cb - ca:+d}), moved {moved_by} places "
                   f"({pa}:{na} vs {pb}:{nb})")
    return errs == 0, out


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


def cycles_option(argv, name):
    """--name=N -> N; absent -> 0; not a whole number -> None."""
    v = 0
    for a in [a for a in argv if a.startswith(f"--{name}=")]:
        n = a.split("=", 1)[1]
        if not n.isdigit():
            print(f"--{name}=N needs a whole number of cycles, not '{n}'")
            return None
        v = int(n)
    return v


def main(argv):
    slack = cycles_option(argv, "cycle-slack")
    window = cycles_option(argv, "reorder")
    if slack is None or window is None:
        return 2
    flags = {a for a in argv if a.startswith("--") and "=" not in a}
    args = [a for a in argv if not a.startswith("--")]
    loose_modes = ("--no-cycles" in flags) + (slack > 0) + (window > 0)
    if len(args) != 2 or flags - {"--no-cycles", "--only-link"} or loose_modes > 1:
        print(__doc__)
        return 2
    cycles = "--no-cycles" not in flags

    def link(la, lb):
        return cmp_link_reorder(la, lb, window) if window else cmp_link(la, lb, cycles, slack)
    A, B = args
    results = []
    if os.path.isdir(A) and os.path.isdir(B):
        la, lb = find(A, "pin_trace.log"), find(B, "pin_trace.log")
        if not (la and lb):
            print(f"MISMATCH: pin_trace.log missing in {A if not la else B}")
            return 1
        results.append(link(la, lb))
        if "--only-link" not in flags:
            ca = find(A, "pin_cycle.log.gz", "pin_cycle.log")
            cb = find(B, "pin_cycle.log.gz", "pin_cycle.log")
            if loose_modes:
                results.append((True, ["per-cycle pin trace not compared"]))
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
        if is_cycle_file(A) and loose_modes:
            print("--no-cycles, --cycle-slack and --reorder do not apply to a per-cycle trace")
            return 2
        results.append(cmp_cycle(A, B) if is_cycle_file(A) else link(A, B))
    else:
        print(f"usage: both arguments must be run directories or both files: {A}, {B}")
        return 2
    ok = all(r[0] for r in results)
    if ok:
        print("MATCH: " + "; ".join(r[1][0] for r in results))
        for r in results:
            for detail in r[1][1:]:
                print(detail)
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
