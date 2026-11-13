
#!/usr/bin/env python3
import argparse
import csv
import json
from collections import defaultdict
import re
import sys
from pathlib import Path

FULL_TB_DIR = Path(__file__).resolve().parents[1]
SYNOUT_DIR = FULL_TB_DIR.parents[1] / "synout"
SCANDEF_PATH = SYNOUT_DIR / "forte_top.scandef"
SCAN_MAP_PATH = FULL_TB_DIR / "sim/scan_map.generated.svh"
OUT_PATH = FULL_TB_DIR / "sim/scan_hookups.generated.svh"
NETLIST_PATH = SYNOUT_DIR / "forte_top.gate.v"

ap = argparse.ArgumentParser()
ap.add_argument("--scandef", type=Path,default=SCANDEF_PATH)
ap.add_argument("--scan_map", type=Path,default=SCAN_MAP_PATH)
ap.add_argument("-o", "--output", type=Path,
                default=OUT_PATH)
ap.add_argument("--dut", default="dut")
ap.add_argument("--netlist", type=Path,
                default=NETLIST_PATH)
ap.add_argument("--stop-pin", choices=("X", "Q", "QN"),
                default="X")
ap.add_argument("--pc-bit0-zero", action="store_true",
                help="Deprecated compatibility option; ignored (no values are assumed)")
ap.add_argument("--top", default="forte_top")
ap.add_argument("--report", type=Path,
                help="Per-bit TSV report (default: output file with .report.tsv suffix)")
ap.add_argument("--strict", action="store_true",
                help="Fail if a mapped cell cannot be probed; unmapped bits are still reported")
args = ap.parse_args()
if args.pc_bit0_zero:
    print("NOTE: --pc-bit0-zero is ignored; unavailable bits remain Z.")

# ---- SystemVerilog identifiers and section formatting ------------------------
def sv_section(title, *comments):
    """Readable separators used in the generated hookups.svh."""
    return ["// " + "=" * 76, "// " + title,
            "// " + "=" * 76, *["// " + c for c in comments], ""]


def sv_ident(s):
    if re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", s):
        return s
    return "\\" + s + " "

def hier(path):
    return ".".join(sv_ident(p) for p in path.split("/"))


sm = args.scan_map.read_text()
sd = args.scandef.read_text()

# ---- Netlist parsing and hierarchical flop lookup ----------------------------
# Resolve each scandef path by walking the actual netlist module hierarchy.
# Instance names need only be unique *within their containing module*.
# This also supports partially flattened escaped identifiers containing '/'.
def parse_netlist(text):
    # Remove comments before splitting statements, including comments with ';'.
    text = re.sub(r"/\*.*?\*/|//[^\n]*", " ", text, flags=re.S)
    modules = {}
    module_re = re.compile(
        r"(?ms)^\s*module\s+(?:automatic\s+)?(\\\S+|[A-Za-z_$][\w$]*)(.*?)^\s*endmodule\b"
    )
    instance_re = re.compile(
        r"^([A-Za-z_$][\w$]*)\s+(\\\S+|[A-Za-z_$][\w$]*)\s*\("
    )
    for match in module_re.finditer(text):
        modname = match.group(1).lstrip("\\")
        body = match.group(2)
        instances = {}
        for record in body.split(";"):
            stmt = re.sub(r"/\*.*?\*/|//[^\n]*", " ", record, flags=re.S)
            stmt = re.sub(r"\s+", " ", stmt).strip()
            m = instance_re.match(stmt)
            if not m:
                continue
            cell_type, inst = m.groups()
            inst = inst.lstrip("\\")
            if inst in instances:
                raise ValueError(f"Duplicate instance {modname}/{inst}")
            outputs = {}
            for pin in ("Q", "QN"):
                # A connected output expression may itself contain parentheses.
                pm = re.search(r"\." + pin + r"\s*\(", stmt)
                outputs[pin] = False
                if pm:
                    depth, end = 1, pm.end()
                    while end < len(stmt) and depth:
                        depth += (stmt[end] == "(") - (stmt[end] == ")")
                        end += 1
                    if depth:
                        raise ValueError(f"Unbalanced {pin} connection on {modname}/{inst}")
                    outputs[pin] = bool(stmt[pm.end():end-1].strip())
            instances[inst] = (cell_type, outputs)
        modules[modname] = instances
    if args.top not in modules:
        raise ValueError(f"Cannot find module {args.top} in netlist")
    return modules


def resolve_cell(path, modules):
    parts = path.split("/")
    module = args.top
    resolved = []
    while parts:
        instances = modules.get(module)
        if instances is None:
            raise ValueError(f"No module definition for {module} while resolving {path}")
        # Try the longest matching instance first. An escaped instance can
        # contain '/' characters from flattening, so consume multiple parts.
        choice = None
        for n in range(len(parts), 0, -1):
            candidate = "/".join(parts[:n])
            if candidate in instances:
                choice = (candidate, n)
                break
        if choice is None:
            # Some exported top netlists flatten away chip/ and use escaped
            # names beginning directly at soc_core_... .
            if not resolved and parts[0] == "chip":
                parts = parts[1:]
                continue
            raise ValueError(
                f"Cannot resolve scandef path {path}: no instance matching "
                f"{'/'.join(parts)} inside module {module}"
            )
        name, consumed = choice
        cell_type, pins = instances[name]
        resolved.append(name)
        parts = parts[consumed:]
        if parts:
            module = cell_type
        else:
            if not any(pins.values()):
                raise ValueError(f"Neither Q nor QN connected on {path}")
            ref = args.dut + "." + ".".join(sv_ident(x) for x in resolved)
            return ref, pins
    raise ValueError(f"Empty cell path: {path}")


modules = parse_netlist(args.netlist.read_text())

# ---- Scan-map records and scandef cross-checks -------------------------------
reg_names = {
    int(n): v
    for n, v in re.findall(
        r'reg_name\[(\d+)\]\s*=\s*"([^"]+)"', sm
    )
}
assert reg_names, "No reg_name[] entries"

cell_re = re.compile(
    r"map_reg\[(\d+)\]\[(\d+)\]\s*=\s*(-?\d+);\s*"
    r"map_bit\[\1\]\[\2\]\s*=\s*(\d+);\s*"
    r"map_qn\[\1\]\[\2\]\s*=\s*(\d+);\s*"
    r"map_ph\[\1\]\[\2\]\s*=\s*(\d+);\s*//\s*(\S+)"
)

records = {}
for m in cell_re.finditer(sm):
    k, j, r, b, qn, ph, path = m.groups()
    key = (int(k), int(j))
    assert key not in records, f"Duplicate map cell {key}"
    records[key] = (
        int(r), int(b), int(qn), int(ph), path
    )

assert records, "No scan map cells"

section = re.search(
    r"(?ms)^SCANCHAINS\s+\d+\s*;(.*?)^END SCANCHAINS",
    sd
)
assert section, "No SCANCHAINS section"

# Tokenised exactly as scan_map.awk reads it, so both see the same cells: any
# layout (one cell per line or several, "( OUT pin )" present or not, any pin
# names).  "- cN" opens a chain, "+ KEYWORD" sets the mode, and only names in
# FLOATING/ORDERED mode are cells.  "+ START ..."/"+ STOP ..." are endpoints
# (STOP is the scan-out gate in front of io_out[k], or PIN io_out[k]).
chains = {}
k = None
mode = want = None
paren = False
pdir = None
for tok in re.sub(r"([();])", r" \1 ", section.group(1)).split():
    if want == "name":
        cm = re.fullmatch(r"c(\d+)", tok)
        assert cm, f"Chain {tok!r} is not named cN"
        k = int(cm.group(1)) + 1
        assert k not in chains, f"Duplicate chain {tok}"
        chains[k] = []
        mode = want = None
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
            # Q or QN for the probe; any other scan-out pin is left to stop_pin.
            name, _ = chains[k][-1]
            chains[k][-1] = (name, tok if tok in ("Q", "QN") else None)
    elif k is not None and mode in ("FLOATING", "ORDERED"):
        chains[k].append((tok, None))

assert chains, "No chains found"

by_reg = defaultdict(dict)
unresolved = []
qn_mismatches = []

for k, entries in sorted(chains.items()):
    for j, (path, pin) in enumerate(entries, 1):
        assert (k, j) in records, (
            f"Missing map entry c{k-1}[{j}]"
        )

        r, b, qn, ph, mpath = records[k, j]

        assert path == mpath, (
            f"Cell mismatch c{k-1}[{j}]: "
            f"{path} != {mpath}"
        )
        assert r in reg_names

        if pin is not None:
            if qn != int(pin == "QN"):
                qn_mismatches.append(
                    (k, j, path, qn, pin)
                )
        else:
            # No OUT pin, or one other than Q/QN: the probe picks an output.
            if args.stop_pin != "X":
                pin = args.stop_pin

        if b in by_reg[r]:
            raise ValueError(
                f"Duplicate bit {reg_names[r]}[{b}]"
            )

        if pin is None:
            unresolved.append(
                (k, j, path, reg_names[r], b)
            )

        by_reg[r][b] = (k, j, path, pin, ph)

if len(records) != sum(len(x) for x in chains.values()):
    map_len = defaultdict(int)
    for kk, _ in records:
        map_len[kk] += 1
    for kk in sorted(set(map_len) | set(chains)):
        print(f"internal_hookups.py: c{kk-1}: {map_len[kk]} cells in the map, "
              f"{len(chains.get(kk, []))} read from the scandef", file=sys.stderr)
    raise SystemExit("internal_hookups.py: map and scandef cell counts differ")

# ---- Generated per-register buses --------------------------------------------
out = [
    "// Generated debug buses; include inside tb_scan.",
    "// *_raw_internal is physical Q: .Q or ~.QN; NO logical polarity correction.",
    "// *_internal estimates the RTL value as physical Q XOR map_ph.",
    "// *_pin_internal probes the scandef-selected Q or QN output.",
    "// If Q is unconnected, raw Q is derived as ~QN (and vice versa).",
    "// An unconnected Q pin is never probed when connected QN is available.",
    "// Unavailable bits have available=0 and remain Z in raw/pin/estimated buses.",
    "// No logical constants are assumed; the testbench displays unavailable bits as '-'.",
    "// No map entry does not prove that synthesis optimized a bit away.",
    ""
]

used_names = set()
reg_syms = {}
report_rows = []
unavailable = []
mapped_failures = []
width_hints = {int(r): int(w) for r, w in re.findall(
    r"reg_width\[(\d+)\]\s*=\s*(\d+)\s*;", sm)}

for r in sorted(reg_names):
    name = reg_names[r]
    stem = re.sub(r"[^a-zA-Z0-9_]", "_", name)
    if name == "ifu_pcreg":
        stem = "pc"
    if stem[0].isdigit():
        stem = "_" + stem
    sym = stem + "_internal"
    rawname = stem + "_raw_internal"
    pinname = stem + "_pin_internal"
    if sym in used_names:
        raise ValueError(f"Duplicate identifier: {sym}")
    used_names.add(sym)
    bits = by_reg[r]
    width = max(max(bits, default=-1) + 1, width_hints.get(r, 0),
                64 if name == "ifu_pcreg" else 1)
    reg_syms[r] = (sym, rawname, pinname, width)

    out += sv_section(f"Register {name}: {len(bits)} mapped bits, width {width}")
    out += [
        "// Bus declarations",
        f"wire [{width-1}:0] {sym};",
        f"wire [{width-1}:0] {rawname};",
        f"wire [{width-1}:0] {pinname};",
        f"wire [{width-1}:0] {rawname}_available;",
        ""
    ]
    # Collect each bus separately, then emit all its bits in one block.
    assignments = {dest: [] for dest in (rawname, sym, pinname, rawname + "_available")}
    for b in range(width):
        if b not in bits:
            reason = "no_scan_map_entry; constant/merged/optimized status is unproven"
            assignments[rawname].append(f"assign {rawname}[{b}] = 1'bz; // unavailable physical Q")
            assignments[pinname].append(f"assign {pinname}[{b}] = 1'bz; // unavailable scan pin")
            assignments[sym].append(f"assign {sym}[{b}] = 1'bz; // unavailable logical estimate")
            assignments[rawname + "_available"].append(f"assign {rawname}_available[{b}] = 1'b0;")
            report_rows.append((name, b, "<unmapped>", "", "", "", "unavailable", reason))
            unavailable.append((name, b, "<unmapped>", reason))
            continue

        k, j, path, pin, ph = bits[b]
        # Resolve full hierarchy; do not require globally unique leaf names.
        try:
            ref, available = resolve_cell(path, modules)
        except ValueError as exc:
            reason = str(exc)
            for dest in (rawname, pinname, sym):
                assignments[dest].append(f"assign {dest}[{b}] = 1'bz; // unavailable; see report")
            assignments[rawname + "_available"].append(f"assign {rawname}_available[{b}] = 1'b0;")
            report_rows.append((name, b, path, "", "", ph, "unresolved", reason))
            unavailable.append((name, b, path, reason))
            mapped_failures.append((name, b, path, reason))
            continue
        assignments[rawname + "_available"].append(f"assign {rawname}_available[{b}] = 1'b1;")
        # Reconstruct physical Q from connected netlist outputs. Logical
        # polarity correction is supplied separately by scan_map.svh map_ph.
        raw_expr = f"{ref}.Q" if available["Q"] else f"~{ref}.QN"
        report_rows.append((name, b, path, ref, raw_expr, ph, "available", ""))
        assignments[rawname].append(f"assign {rawname}[{b}] = {raw_expr}; // c{k-1}[{j}]")
        assignments[sym].append(f"assign {sym}[{b}] = {rawname}[{b}]" + (" ^ 1'b1;" if ph else ";"))

        # The scandef identifies a preferred scan-out pin; a cell without one
        # uses Q when present, else QN.
        selected = pin if pin is not None else ("Q" if available["Q"] else "QN")
        other = "QN" if selected == "Q" else "Q"
        pin_expr = (f"{ref}.{selected}" if available[selected]
                    else f"~{ref}.{other}")
        assignments[pinname].append(f"assign {pinname}[{b}] = {pin_expr};")
    for dest, description in (
        (rawname, "Physical Q: .Q or ~.QN; no logical polarity correction."),
        (sym, "Logical estimate: physical Q XOR map_ph; unavailable bits stay Z."),
        (pinname, "Scan output pin: scandef Q/QN selection; no OUT pin uses an available output."),
        (rawname + "_available", "Availability mask: 1 = physical Q can be probed; 0 = unavailable."),
    ):
        out += [f"// ---- {dest} ----", "// " + description, *assignments[dest], ""]

# ---- Generated name-indexed arrays -------------------------------------------
# Associative arrays keyed by the same names as scan_map.svh reg_name[].
# The original internal_by_name is retained as an alias to estimated values.
out += sv_section("Name-indexed register arrays",
                  "Keys match scan_map.svh reg_name[].",
                  "Values are LIVE. Snapshot before scan unload.",
                  "Value arrays are padded to MAX_W with Z; masks are padded with 0.")
# Define array order and meaning once for both declarations and assignments.
array_sections = (
    ("internal_raw_by_name",
     "Physical Q (.Q or ~.QN), without map_ph correction; unavailable bits are Z."),
    ("internal_est_by_name",
     "Logical estimate (physical Q XOR map_ph); unavailable bits remain Z."),
    ("internal_available_by_name",
     "Availability mask: 1 = physical output can be probed; 0 = unavailable."),
    ("internal_by_name",
     "Compatibility alias of internal_est_by_name; not an independent observation."),
)
for dest, description in array_sections:
    out += ["// " + description, f"val_t {dest}[string];", ""]
out += ["always_comb begin"]
array_assignments = {dest: [] for dest, _ in array_sections}
for r in sorted(reg_names):
    name = reg_names[r]
    sym, rawname, pinname, width = reg_syms[r]
    prefix = f"{{{{(MAX_W-{width}){{1'bz}}}}, "
    array_assignments["internal_raw_by_name"].append(f'  internal_raw_by_name["{name}"] = {prefix}{rawname}}};')
    array_assignments["internal_est_by_name"].append(f'  internal_est_by_name["{name}"] = {prefix}{sym}}};')
    array_assignments["internal_available_by_name"].append(f'  internal_available_by_name["{name}"] = val_t\'({rawname}_available);')
    array_assignments["internal_by_name"].append(f'  internal_by_name["{name}"] = internal_est_by_name["{name}"];')
for dest, description in array_sections:
    out += [f"  // ---- {dest} ----", "  // " + description,
            *array_assignments[dest], ""]
out += ["end", ""]

# ---- Generated diagnostic messages and report file ---------------------------
out += sv_section("Static hookup limitations",
                  "Unavailable hookup sources; distinct from runtime X/Z on connected pins.")
out += ["initial begin"]
for name, b, path, reason in unavailable:
    # Pass text as a %s argument so netlist names containing '%' remain literal.
    message = f"INTERNAL UNAVAILABLE: {name}[{b}] instance={path} reason={reason}"
    out.append(f'  $display("%s", {json.dumps(message)});')
out += ["end", ""]

report_path = args.report or args.output.with_suffix(".report.tsv")
with report_path.open("w", newline="", encoding="utf-8") as report:
    writer = csv.writer(report, delimiter="\t")
    writer.writerow(("register", "bit", "scandef_instance", "resolved_instance",
                     "physical_Q_expression", "map_ph", "status", "reason"))
    writer.writerows(report_rows)
for name, b, path, reason in unavailable:
    print(f"UNAVAILABLE: {name}[{b}] instance={path}: {reason}")
if args.strict and mapped_failures:
    raise SystemExit(f"{len(mapped_failures)} mapped hookups unresolved; see {report_path}")

args.output.write_text("\n".join(out) + "\n")
print(f"Per-bit report: {report_path}; unresolved mapped bits: {len(mapped_failures)}")

print(
    f"Wrote {args.output}: "
    f"{len(by_reg)} register buses, "
    f"{len(records)} cells"
)

print(
    f"Cells without a scandef OUT pin: {len(unresolved)} "
    f"(netlist output selection attempted; see per-bit report for availability)"
)
for k, j, path, name, b in unresolved:
    print(
        f"  c{k-1}[{j}] {name}[{b}]: "
        f"no scandef output preference for {path}; see per-bit report"
    )

print(
    f"QN disagreements: {len(qn_mismatches)}"
)
for k, j, path, flag, pin in qn_mismatches:
    print(
        f"  c{k-1}[{j}] {path}: "
        f"map_qn={flag}, scandef={pin}"
    )
