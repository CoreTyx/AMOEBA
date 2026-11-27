#!/usr/bin/env python3
"""Scandef and logical-phase file from a discovery run (scan_discover.svh).

    discover_meta.py scandef --probes probes.tsv --discover discover.tsv -o forte_top.scandef
    discover_meta.py phase   --discover discover.tsv --probes probes.tsv \\
                             --map scan_map.svh -o forte_top.scan_phase.txt [--reset-vec HEX]
    discover_meta.py compare --scandef A --ref-scandef B [--phase A.txt --ref-phase B.txt]

scandef: one chain cN per io_in[N] -> io_out[N], cells in scan order (FLOATING,
  as insert_dft writes them), each "( IN SI ) ( OUT Q|QN )".  OUT is the scan
  path's inversion between that cell and the next (the next cell's inversion
  from scan-in, XOR this one's), and for the last cell the inversion to the
  pin, which phase A measured.  An inverter after Q is written as QN: the bench
  treats both the same (map_qn).  An inversion between io_in and the first cell
  has no scandef form and is an error.

phase: a cell stores the RTL bit inverted (phase 1) when its physical Q at reset
  is the complement of its register's reset bit (scan_map.awk's table, via the
  map).  Cells whose register has no reset value, or whose Q was X at reset, are
  left out of the file: the bench then applies no correction (map_ph=0), and the
  summary counts them as not observed.

compare: the discovered scandef/phase against a reference (a synthesis scandef
  and phase file), as counts: positions with the same cell, phase agreements.

Everything printed is counts; instance names stay in the files.
"""
import argparse
import re
import sys
from collections import defaultdict
from pathlib import Path


def read_probes(path):
    probes = {}
    for line in Path(path).read_text().splitlines():
        if line.strip():
            i, p = line.split("\t", 1)
            probes[int(i)] = p
    return probes


def read_discover(path):
    chains, cells = {}, defaultdict(dict)
    for line in Path(path).read_text().splitlines():
        f = line.split("\t")
        if f[0] == "L":
            chains[int(f[1])] = (int(f[2]), f[3])
        elif f[0] == "C":
            cells[int(f[1])][int(f[2])] = (int(f[3]), f[4], f[5])
    return chains, cells


def scandef_chains(text):
    """{k: [(path, out_pin)]} -- the same tokenising scan_map.awk uses."""
    sec = re.search(r"(?ms)^\s*SCANCHAINS\s+\d+\s*;(.*?)^\s*END\s+SCANCHAINS", text)
    if not sec:
        sys.exit("discover_meta.py: no SCANCHAINS section")
    chains, k, mode, want, paren, pdir = {}, None, None, None, False, None
    for tok in re.sub(r"([();])", r" \1 ", sec.group(1)).split():
        if want == "name":
            k = int(tok[1:]) + 1
            chains[k] = []
            want = mode = None
            continue
        if want == "kw":
            mode, want = tok, None
            continue
        if tok == "-":
            want = "name"
        elif tok == "+":
            want = "kw"
        elif tok == ";":
            k = mode = None
        elif tok == "(":
            paren, pdir = True, None
        elif tok == ")":
            paren = False
        elif paren:
            if pdir is None:
                pdir = tok
            elif pdir == "OUT" and k is not None and chains[k] and mode in ("FLOATING", "ORDERED"):
                chains[k][-1] = (chains[k][-1][0], tok)
        elif k is not None and mode in ("FLOATING", "ORDERED"):
            chains[k].append((tok.replace("\\", ""), None))
    return chains


def cmd_scandef(a):
    probes = read_probes(a.probes)
    chains, cells = read_discover(a.discover)
    if len(chains) != 8:
        sys.exit(f"discover_meta.py: {len(chains)} chains in {a.discover}, expected 8")
    out = ["# forte_top.scandef -- DISCOVERED from the netlist by full_tb (scan_discover.svh,",
           "# discover_meta.py), not written by DFT insertion.  Cell order and the scan",
           "# path's inversions are what simulation showed; OUT QN marks an inversion",
           "# after the cell (a QN output or an inverter).",
           "VERSION 5.8 ;", "DESIGN forte_top ;", f"SCANCHAINS {len(chains)} ;"]
    n_cells = n_qn = 0
    for k in sorted(chains):
        length, pin_inv = chains[k]
        c = cells[k]
        missing = [j for j in range(1, length + 1) if j not in c]
        if missing:
            sys.exit(f"discover_meta.py: c{k-1}: {len(missing)} unresolved position(s)")
        if c[1][1] != "0":
            sys.exit(f"discover_meta.py: c{k-1}: the path from io_in[{k-1}] to the first cell inverts; "
                     "a scandef cannot describe that")
        out += [f"- c{k-1}", f"  + START PIN io_in[{k-1}]", "  + FLOATING"]
        for j in range(1, length + 1):
            idx, inv_in, _ = c[j]
            nxt = c[j + 1][1] if j < length else str(int(inv_in) ^ int(pin_inv))
            qn = int(inv_in) ^ int(nxt) if j < length else int(nxt)
            n_qn += qn
            n_cells += 1
            out.append(f"    {probes[idx]} ( IN SI ) ( OUT {'QN' if qn else 'Q'} )")
        out += [f"  + STOP PIN io_out[{k-1}] ;"]
    out += ["END SCANCHAINS", "END DESIGN", ""]
    Path(a.output).write_text("\n".join(out))
    print(f"discover_meta: scandef with {n_cells} cells on {len(chains)} chains, "
          f"{n_qn} inverting scan output(s)")


def cmd_phase(a):
    probes = read_probes(a.probes)
    _, cells = read_discover(a.discover)
    sm = Path(a.map).read_text()
    rst = {}
    for r, v in re.findall(r"reg_rst\[(\d+)\]\s*=\s*([^;]+);", sm):
        v = v.strip()
        if v == "'x":
            rst[int(r)] = None
        elif "RESET_VEC" in v:
            rst[int(r)] = int(a.reset_vec, 16)
        else:
            m = re.fullmatch(r"\d*'h([0-9a-fA-F_]+)", v)
            rst[int(r)] = int(m.group(1).replace("_", ""), 16) if m else None
    cell_re = re.compile(r"map_reg\[(\d+)\]\[(\d+)\]\s*=\s*(-?\d+);\s*map_bit\[\1\]\[\2\]\s*=\s*(\d+);")
    lines = ["# forte_top.scan_phase.txt -- DISCOVERED: physical Q at reset against the",
             "# register's RTL reset value (discover_meta.py).  Cells with no reset value",
             "# or an X at reset are not listed (not observed)."]
    n = inv = no_rst = x_rst = 0
    for k, j, r, b in cell_re.findall(sm):
        k, j, r, b = int(k), int(j), int(r), int(b)
        idx, _, q = cells[k][j]
        n += 1
        if rst.get(r) is None:
            no_rst += 1
            continue
        if q not in ("0", "1"):
            x_rst += 1
            continue
        ph = int(q) ^ ((rst[r] >> b) & 1)
        inv += ph
        lines.append(f"{probes[idx]} {ph}")
    Path(a.output).write_text("\n".join(lines) + "\n")
    print(f"discover_meta: phase for {n - no_rst - x_rst} of {n} cells ({inv} stored inverted); "
          f"not observed: {no_rst} with no reset value, {x_rst} X at reset")


def read_phase(path):
    ph = {}
    for line in Path(path).read_text().splitlines():
        line = line.split("#", 1)[0].strip()
        if line:
            p, v = line.split()
            ph[p.replace("\\", "")] = v
    return ph


def cmd_compare(a):
    mine = scandef_chains(Path(a.scandef).read_text())
    ref = scandef_chains(Path(a.ref_scandef).read_text())
    same = diff = 0
    for k in sorted(set(mine) | set(ref)):
        m, r = mine.get(k, []), ref.get(k, [])
        if len(m) != len(r):
            print(f"discover_meta: compare: c{k-1}: {len(m)} cells discovered, {len(r)} in the reference")
        for j in range(max(len(m), len(r))):
            if j < len(m) and j < len(r) and m[j][0] == r[j][0]:
                same += 1
            else:
                diff += 1
    print(f"discover_meta: compare scandef: {same} position(s) SAME cell, {diff} DIFFERENT")
    rc = 0 if diff == 0 else 1
    if a.phase and a.ref_phase:
        pm, pr = read_phase(a.phase), read_phase(a.ref_phase)
        agree = sum(1 for p, v in pm.items() if p in pr and pr[p] == v)
        disagree = sum(1 for p, v in pm.items() if p in pr and pr[p] != v)
        only_ref = sum(1 for p in pr if p not in pm)
        print(f"discover_meta: compare phase: {agree} SAME, {disagree} DIFFERENT, "
              f"{only_ref} in the reference only (not observed here)")
        rc |= disagree != 0
    return rc


ap = argparse.ArgumentParser()
sub = ap.add_subparsers(dest="cmd")
sub.required = True
p = sub.add_parser("scandef")
p.add_argument("--probes", required=True)
p.add_argument("--discover", required=True)
p.add_argument("-o", "--output", required=True)
p = sub.add_parser("phase")
p.add_argument("--probes", required=True)
p.add_argument("--discover", required=True)
p.add_argument("--map", required=True)
p.add_argument("--reset-vec", default="80000000")
p.add_argument("-o", "--output", required=True)
p = sub.add_parser("compare")
p.add_argument("--scandef", required=True)
p.add_argument("--ref-scandef", required=True)
p.add_argument("--phase")
p.add_argument("--ref-phase")
a = ap.parse_args()
sys.exit({"scandef": cmd_scandef, "phase": cmd_phase, "compare": cmd_compare}[a.cmd](a) or 0)
