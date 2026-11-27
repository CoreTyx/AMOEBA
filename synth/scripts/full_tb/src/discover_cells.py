#!/usr/bin/env python3
"""Probes for scan-chain discovery: every flop in the netlist, by its physical Q.

    discover_cells.py --netlist N.v [--top forte_top] [--dut dut]
                      [--exclude-model F]... -o probes.svh --index probes.tsv

Used when the netlist comes without a scandef (a post-PnR .v): tb_scan.sv built
with +define+SCAN_DISCOVER watches these probes while it shifts a single 1 down
each chain, and so learns which flop is at each chain position (see
scan_discover.svh).

A probe is a leaf instance (its cell type is not a module of the netlist) with
a connected Q or QN pin -- the same pin convention internal_hookups.py uses for
scan cells.  Its physical Q is .Q, or ~.QN when only QN is connected.  Cell
types defined by an --exclude-model file (the SRAM macro and pad models) are
never probes: an SRAM's Q is a data bus, not a flop.

probes.svh: DISC_N and the packed vector disc_q (bit i = probe i).
probes.tsv: "<i>\t<instance path>" with the path from the top, '/'-separated as
            in a scandef (chip/<flattened name>).  Instance and cell names stay in
            these generated files (sim/meta/, never committed); stdout prints counts.
"""
import argparse
import re
import sys
from pathlib import Path

ap = argparse.ArgumentParser()
ap.add_argument("--netlist", type=Path, required=True)
ap.add_argument("--top", default="forte_top")
ap.add_argument("--dut", default="dut")
ap.add_argument("--exclude-model", type=Path, action="append", default=[])
ap.add_argument("-o", "--output", type=Path, required=True)
ap.add_argument("--index", type=Path, required=True)
args = ap.parse_args()


def sv_ident(s):
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", s):
        return s
    return "\\" + s + " "


def parse_netlist(text):
    """modules[name] = list of (cell_type, instance, {"Q": bool, "QN": bool}).

    The same statement reader as internal_hookups.py: comments removed, one
    statement per ';', "type name (" opens an instance."""
    text = re.sub(r"/\*.*?\*/|//[^\n]*", " ", text, flags=re.S)
    modules = {}
    module_re = re.compile(
        r"(?ms)^\s*module\s+(?:automatic\s+)?(\\\S+|[A-Za-z_$][\w$]*)(.*?)^\s*endmodule\b")
    instance_re = re.compile(r"^([A-Za-z_$][\w$]*|\\\S+)\s+(\\\S+|[A-Za-z_$][\w$]*)\s*\(")
    keywords = {"module", "input", "output", "inout", "wire", "reg", "assign", "supply0",
                "supply1", "tri", "wand", "wor", "parameter", "localparam", "defparam"}
    for match in module_re.finditer(text):
        modname = match.group(1).lstrip("\\")
        insts = []
        for record in match.group(2).split(";"):
            stmt = re.sub(r"\s+", " ", record).strip()
            m = instance_re.match(stmt)
            if not m or m.group(1) in keywords:
                continue
            cell_type, inst = m.group(1).lstrip("\\"), m.group(2).lstrip("\\")
            pins = {}
            for pin in ("Q", "QN"):
                pm = re.search(r"\." + pin + r"\s*\(", stmt)
                pins[pin] = False
                if pm:
                    depth, end = 1, pm.end()
                    while end < len(stmt) and depth:
                        depth += (stmt[end] == "(") - (stmt[end] == ")")
                        end += 1
                    pins[pin] = bool(stmt[pm.end():end - 1].strip())
            insts.append((cell_type, inst, pins))
        modules[modname] = insts
    return modules


excluded = set()
for f in args.exclude_model:
    if f.is_file():
        excluded.update(m.lstrip("\\") for m in re.findall(
            r"(?m)^\s*module\s+(\\\S+|[A-Za-z_$][\w$]*)", f.read_text(errors="replace")))

modules = parse_netlist(args.netlist.read_text(errors="replace"))
if args.top not in modules:
    sys.exit(f"discover_cells.py: no module {args.top} in the netlist")

probes = []          # (path, sv expression)
n_leaf = n_excluded = 0


def walk(mod, path, ref, depth=0):
    global n_leaf, n_excluded
    if depth > 64:
        sys.exit("discover_cells.py: hierarchy deeper than 64 (recursive module?)")
    for cell_type, inst, pins in modules[mod]:
        p = path + [inst]
        r = ref + "." + sv_ident(inst)
        if cell_type in modules:
            walk(cell_type, p, r, depth + 1)
            continue
        n_leaf += 1
        if cell_type in excluded:
            n_excluded += 1
            continue
        if pins["Q"]:
            probes.append(("/".join(p), f"{r}.Q", r, pins))
        elif pins["QN"]:
            probes.append(("/".join(p), f"~{r}.QN", r, pins))


walk(args.top, [], args.dut)
if not probes:
    sys.exit("discover_cells.py: no instance with a connected Q or QN: cannot discover the chains")

lines = ["// discover_probes.generated.svh -- discover_cells.py; do not edit.",
         f"localparam int DISC_N = {len(probes)};",
         "wire [DISC_N-1:0] disc_q;"]
lines += [f"assign disc_q[{i}] = {e};" for i, (_, e, _, _) in enumerate(probes)]
# disc_force(i) / disc_release(i): drive probe i's physical Q (Q = disc_fv,
# QN = ~disc_fv on the pins it connects), to see which flop the next chain cell
# really takes its data from when two flops hold identical values.
lines += ["logic disc_fv = 1'b0;", "task automatic disc_force(input int i);", "  case (i)"]
for i, (_, _, r, pins) in enumerate(probes):
    f = []
    if pins["Q"]:
        f.append(f"force {r}.Q = disc_fv;")
    if pins["QN"]:
        f.append(f"force {r}.QN = ~disc_fv;")
    lines.append(f"    {i}: begin {' '.join(f)} end")
lines += ["  endcase", "endtask", "task automatic disc_release(input int i);", "  case (i)"]
for i, (_, _, r, pins) in enumerate(probes):
    f = []
    if pins["Q"]:
        f.append(f"release {r}.Q;")
    if pins["QN"]:
        f.append(f"release {r}.QN;")
    lines.append(f"    {i}: begin {' '.join(f)} end")
lines += ["  endcase", "endtask"]
args.output.write_text("\n".join(lines) + "\n")
args.index.write_text("".join(f"{i}\t{p}\n" for i, (p, _, _, _) in enumerate(probes)))
print(f"discover_cells: {len(probes)} flop probes of {n_leaf} leaf cells "
      f"({n_excluded} SRAM/pad macro instances excluded)")
