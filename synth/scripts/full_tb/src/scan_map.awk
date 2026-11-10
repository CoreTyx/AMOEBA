# scan_map.awk -- generate scan_map.svh and full-path scan_phase.txt.
# awk -v NETLIST=forte_top.gate.v -v TOP=forte_top \
#     -v PHASE_OUT=scan_phase.txt -f scan_map.awk forte_top.scandef > scan_map.svh
# Omit PHASE_OUT to generate only scan_map.svh and skip netlist extraction.
# PHASE_OUT is output availability metadata for internal_hookups.py --scan-phase.
# It is independent of the optional verified LOGICAL_PHASE input.
#
# QN usage identifies a scan-output inversion, NOT the RTL bit's polarity.
# Legacy PHASE files based on Q/QN pin availability are ignored.
# LOGICAL_PHASE optionally supplies independently verified physical-Q-to-RTL
# corrections: "<full scandef instance path> <0|1>", with # comments allowed.
# No leaf-name lookup. Missing entries use map_ph=0: no extra correction;
# this convention is not proof that physical Q equals the RTL register bit.
#
# For every chain cN (k = N+1 in the bench) and every cell j along it, j = 1
# next to scan-in: the register the cell belongs to, the bit of it the cell
# holds, and whether its scan output is QN.  The last cell is the STOP entry;
# its scan-out pin is not in the scandef, so it is written as 2 and the bench
# works it out from the inversion it measures on the pin.  Cells are taken in
# file order, START to STOP.
#
# A cell's register is its name without "chip/", "soc_core_", the bit index
# and the flop's own name (q_reg, cw_stored_reg, <signal>_reg):
#   chip/soc_core_ieu_dp_RD1EReg_cw_stored_reg_5_   -> ieu_dp_RD1EReg, bit 5
#   chip/soc_core_priv_csr_csrsr_STATUS_MPP_reg_1_  -> priv_csr_csrsr_STATUS_MPP, bit 1
# The register is then looked up in the table below, which mirrors the scan
# groups in dft_setup.tcl and says what the bench may do with it.

# ---- register table -----------------------------------------------------------
# One row per register dft_setup.tcl selects: the end of its name (an ERE,
# anchored at a "_" or "/" and at the end), group, kind and reset value.  The
# first row that matches wins.  Kinds (tb_scan.sv's kind_e):
#   PC         the fetch PC.  Reset value RESET_VEC.
#   DATA       holds any value while the pipeline is stalled.
#   ECC        a SECDED codeword (flopenrc_cw): holds a valid codeword, repairs
#              a 1-bit error, holds a 2-bit one; both set MSECFAULT.
#   CTRL       control: a random value can flush or unstall the pipeline, so
#              it is only reset and held at its reset value.
#   TMR        a privmode copy (reg_sub 0-2 mode a-c, 3-5 check a-c).
#   MPP        mstatus.MPP: 2'b10 sets MSECFAULT[1].
#   MSECFAULT  the sticky security fault CSR the hardening checks read.
#   STICKY     FTStatusSticky.
# Reset: hex, "x" for a register with no reset, "pc" for RESET_VEC.
function row(re, grp, kind, rst) {
    nrow++
    t_re[nrow] = "(^|[_/])(" re ")$"; t_src[nrow] = re
    t_grp[nrow] = grp; t_kind[nrow] = kind; t_rst[nrow] = rst
}
BEGIN {
    nreg = 0
    net_load()
    if (PHASE != "")
        print "scan_map.awk: ignoring legacy PHASE (QN-only does not establish logical polarity)" > "/dev/stderr"
    if (LOGICAL_PHASE != "") {
        while ((phase_rc = (getline ln < LOGICAL_PHASE)) > 0) {
            sub(/#.*/, "", ln)
            sub(/^[[:space:]]+/, "", ln)
            sub(/[[:space:]]+$/, "", ln)
            if (ln == "") continue
            nf = split(ln, f, /[[:space:]]+/)
            if (nf != 2 || f[2] !~ /^[01]$/) {
                print "scan_map.awk: invalid LOGICAL_PHASE entry: " ln > "/dev/stderr"
                bad = 1
                continue
            }
            gsub(/\\/, "", f[1])
            if ((f[1] in ph) && ph[f[1]] != f[2]) {
                print "scan_map.awk: conflicting LOGICAL_PHASE entries for " f[1] > "/dev/stderr"
                bad = 1
            } else ph[f[1]] = f[2] + 0
        }
        if (phase_rc < 0) {
            print "scan_map.awk: cannot read LOGICAL_PHASE: " LOGICAL_PHASE > "/dev/stderr"
            bad = 1
        }
        close(LOGICAL_PHASE)
    }
    row("dftlock_.*|dftlock|unlocked",       "G_NONE",     "K_LOCK",      "0")
    row("pcreg",                             "G_PC",       "K_PC",        "pc")
    # ECC-protected datapath registers
    row("RD1EReg",                           "G_PIPELINE", "K_ECC",       "0")
    row("RD2EReg",                           "G_PIPELINE", "K_ECC",       "0")
    row("ImmExtEReg",                        "G_PIPELINE", "K_ECC",       "0")
    row("SrcAMReg",                          "G_PIPELINE", "K_ECC",       "0")
    row("IEUResultMReg",                     "G_PIPELINE", "K_ECC",       "0")
    row("WriteDataMReg",                     "G_PIPELINE", "K_ECC",       "0")
    row("IFResultWReg",                      "G_PIPELINE", "K_ECC",       "0")
    # control: flush, fault, trap and FSM inputs
    row("controlregD",                       "G_PIPELINE", "K_CTRL",      "0")
    row("controlregE",                       "G_PIPELINE", "K_CTRL",      "0")
    row("controlregM",                       "G_PIPELINE", "K_CTRL",      "0")
    row("controlregW",                       "G_PIPELINE", "K_CTRL",      "0")
    row("faultregD",                         "G_PIPELINE", "K_CTRL",      "0")
    row("faultregE",                         "G_PIPELINE", "K_CTRL",      "0")
    row("faultregM",                         "G_PIPELINE", "K_CTRL",      "0")
    row("PCSrcMReg",                         "G_PIPELINE", "K_CTRL",      "0")
    row("InstrMisalignedReg",                "G_PIPELINE", "K_CTRL",      "0")
    row("divfaultreg",                       "G_PIPELINE", "K_CTRL",      "0")
    row("wfiWReg",                           "G_PIPELINE", "K_CTRL",      "0")
    row("SpillDReg",                         "G_PIPELINE", "K_CTRL",      "0")
    row("SpillEReg",                         "G_PIPELINE", "K_CTRL",      "0")
    row("SpillMReg",                         "G_PIPELINE", "K_CTRL",      "0")
    row("CompressedDReg",                    "G_PIPELINE", "K_CTRL",      "0")
    row("CompressedEReg",                    "G_PIPELINE", "K_CTRL",      "0")
    row("CompressedMReg",                    "G_PIPELINE", "K_CTRL",      "0")
    # data
    row("AlignedInstrRawDFlop",              "G_PIPELINE", "K_DATA",      "13")   # resets to nop
    row("ReadDataMWReg",                     "G_PIPELINE", "K_DATA",      "x")    # flopen: no reset
    row("PCDReg",                            "G_PIPELINE", "K_DATA",      "0")
    row("InstrEReg",                         "G_PIPELINE", "K_DATA",      "0")
    row("InstrMReg",                         "G_PIPELINE", "K_DATA",      "0")
    row("InstrRawEReg",                      "G_PIPELINE", "K_DATA",      "0")
    row("InstrRawMReg",                      "G_PIPELINE", "K_DATA",      "0")
    row("PCEReg",                            "G_PIPELINE", "K_DATA",      "0")
    row("PCMReg",                            "G_PIPELINE", "K_DATA",      "0")
    row("Rs1EReg",                           "G_PIPELINE", "K_DATA",      "0")
    row("Rs2EReg",                           "G_PIPELINE", "K_DATA",      "0")
    row("RdEReg",                            "G_PIPELINE", "K_DATA",      "0")
    row("RdMReg",                            "G_PIPELINE", "K_DATA",      "0")
    row("RdWReg",                            "G_PIPELINE", "K_DATA",      "0")
    row("AddressMReg",                       "G_PIPELINE", "K_DATA",      "0")
    row("W64MReg",                           "G_PIPELINE", "K_DATA",      "0")
    row("MDUResultWReg",                     "G_PIPELINE", "K_DATA",      "0")
    row("PP1Reg",                            "G_PIPELINE", "K_DATA",      "0")
    row("PP2Reg",                            "G_PIPELINE", "K_DATA",      "0")
    row("CSRValWReg",                        "G_PIPELINE", "K_DATA",      "0")
    # hardened CSRs
    row("privmodereg_a",                     "G_HCSR",     "K_TMR",       "3")
    row("privmodereg_b",                     "G_HCSR",     "K_TMR",       "3")
    row("privmodereg_c",                     "G_HCSR",     "K_TMR",       "3")
    row("privchkreg_a",                      "G_HCSR",     "K_TMR",       "3")
    row("privchkreg_b",                      "G_HCSR",     "K_TMR",       "3")
    row("privchkreg_c",                      "G_HCSR",     "K_TMR",       "3")
    row("STATUS_MPP",                        "G_HCSR",     "K_MPP",       "0")
    row("MSECFAULT_REGW",                    "G_HCSR",     "K_MSECFAULT", "0")
    row("FTStatusSticky",                    "G_HCSR",     "K_STICKY",    "0")
    row("RANDINSTRFREQreg",                  "G_HCSR",     "K_DATA",      "0")
}

# The register a cell name belongs to, and (in cbit) the bit it holds.
function reg_key(name,    s) {
    s = name
    gsub(/\\/, "", s)
    sub(/^chip\//, "", s)
    cbit = 0
    if (match(s, /(\[[0-9]+\]|_[0-9]+_?)$/)) {
        cbit = substr(s, RSTART, RLENGTH)
        gsub(/[^0-9]/, "", cbit)
        cbit += 0
        s = substr(s, 1, RSTART - 1)
    }
    if (!sub(/[_\/](q|cw_stored)_reg$/, "", s)) sub(/_reg$/, "", s)
    sub(/[_\/]store$/, "", s)
    sub(/^soc[_\/]core[_\/]/, "", s)
    return s
}

function reg_index(key,    i) {
    if (key in reg_of) return reg_of[key]
    reg_of[key] = nreg
    rname[nreg] = key
    rrow[nreg] = 0
    for (i = 1; i <= nrow; i++)
        if (key ~ t_re[i]) { rrow[nreg] = i; used[i]++; break }
    return nreg++
}

function add_cell(name, qn,    key, path) {
    n++
    key = reg_key(name)
    cell[k, n] = name
    inv[k, n] = qn
    creg[k, n] = reg_index(key)
    cbitv[k, n] = cbit
    # Full path only: repeated leaf names in distinct modules are valid.
    path = name
    gsub(/\\/, "", path)
    cph[k, n] = 0
    if (LOGICAL_PHASE == "") return
    if (!(path in ph)) { n_ph_missing++; return }
    ph_used[path] = 1
    cph[k, n] = ph[path]
    if (ph[path] == 1) ph_regs[key]++
}

function end_chain() {
    if (k > 0) len[k] = n
    k = 0; n = 0; mode = ""
}

/^[[:space:]]*SCANCHAINS[[:space:]]/ { in_sc = 1; next }
/^[[:space:]]*END[[:space:]]+SCANCHAINS/ { end_chain(); in_sc = 0; next }

in_sc {
    line = $0
    gsub(/[();]/, " & ", line)
    nt = split(line, t, /[[:space:]]+/)
    for (i = 1; i <= nt; i++) {
        tok = t[i]
        if (tok == "") continue
        if (want == "name") {
            if (tok !~ /^c[0-9]+$/) { print "scan_map.awk: chain '" tok "' is not named cN" > "/dev/stderr"; bad = 1 }
            k = substr(tok, 2) + 1; n = 0; chains++
            want = ""; continue
        }
        if (want == "kw") { mode = tok; want = ""; stop_seen = 0; continue }
        if (tok == "-") { end_chain(); want = "name"; continue }
        if (tok == "+") { want = "kw"; continue }
        if (tok == ";") { end_chain(); continue }
        if (tok == "(") { paren = 1; pdir = ""; continue }
        if (tok == ")") { paren = 0; continue }
        if (paren) {
            if (pdir == "") pdir = tok
            else if (pdir == "OUT" && n > 0) inv[k, n] = (tok ~ /N$/) ? 1 : 0
            continue
        }
        if (mode == "FLOATING" || mode == "ORDERED") add_cell(tok, 0)
        else if (mode == "STOP" && !stop_seen) {
            stop_seen = 1
            if (tok != "PIN") add_cell(tok, 2)
        }
    }
}

END {
    if (!chains) { print "scan_map.awk: no scan chains found" > "/dev/stderr"; exit 1 }
    for (path in ph)
        if (!(path in ph_used)) {
            print "scan_map.awk: LOGICAL_PHASE path not found in scandef: " path > "/dev/stderr"
            bad = 1
        }
    if (bad) exit 1
    net_write_phase()
    printf "// scan_map.svh -- generated by run.sh from %s; do not edit.\n", FILENAME
    print  "// Registers r = 0..n_regs-1 (scan_map.awk's table gives group, kind, reset)."
    print  "// Chain cN is k = N+1; cell j = 1 is next to scan-in.  map_reg/map_bit: the"
    print  "// register and bit the cell holds.  map_qn: 1 = scan output from QN, 2 = not"
    print  "// in the scandef (the last cell; the bench derives it from the pin)."
    print  "// map_ph: explicit physical-Q-to-RTL correction; never inferred from QN usage."
    print  "// Without an explicit entry map_ph=0 means no extra logical correction."
    print  "function automatic void scan_map_init();"
    printf "  n_regs = %d;\n", nreg
    for (r = 0; r < nreg; r++) {
        i = rrow[r]
        grp  = i ? t_grp[i]  : "G_NONE"
        kind = i ? t_kind[i] : "K_UNKNOWN"
        rst  = i ? t_rst[i]  : "x"
        sub_ = 0
        if (kind == "K_TMR") {
            sub_ = (rname[r] ~ /privchkreg/ ? 3 : 0) + index("abc", substr(rname[r], length(rname[r]))) - 1
        }
        if (rst == "pc")     rv = "256'(`RESET_VEC)"
        else if (rst == "x") rv = "'x"
        else                 rv = "256'h" rst
        printf "  reg_name[%d] = \"%s\"; reg_group[%d] = %s; reg_kind[%d] = %s; reg_rst[%d] = %s; reg_sub[%d] = %d;\n", \
               r, rname[r], r, grp, r, kind, r, rv, r, sub_
    }
    for (kk = 1; kk <= 64; kk++) {
        if (!(kk in len)) continue
        printf "  map_len[%d] = %d;\n", kk, len[kk]
        for (j = 1; j <= len[kk]; j++)
            printf "  map_reg[%d][%d] = %d; map_bit[%d][%d] = %d; map_qn[%d][%d] = %d; map_ph[%d][%d] = %d;  // %s\n", \
                   kk, j, creg[kk, j], kk, j, cbitv[kk, j], kk, j, inv[kk, j], kk, j, cph[kk, j], cell[kk, j]
    }
    # Logical correction provenance; independent of scan-output Q/QN inversion.
    if (LOGICAL_PHASE == "")
        print "  map_notes.push_back(\"map_ph=0: no explicit logical polarity corrections supplied; physical Q convention, not verified RTL equivalence\");"
    if (PHASE != "")
        print "  map_notes.push_back(\"legacy QN-only PHASE inference ignored; scan-output inversions still use map_qn\");"
    for (key in ph_regs)
        printf "  map_notes.push_back(\"%s: %d explicit logical polarity correction(s) from LOGICAL_PHASE\");\n", key, ph_regs[key]
    if (n_ph_missing)
        printf "  map_notes.push_back(\"%d scan cell(s) without explicit LOGICAL_PHASE entries: no extra logical correction\");\n", n_ph_missing
    # Rows that matched no register: a register dft_setup.tcl selects that is not
    # on the chains, or a name that changed.  The bench prints these.
    for (i = 1; i <= nrow; i++)
        if (!used[i] && t_kind[i] != "K_LOCK")
            printf "  map_notes.push_back(\"no cell on the chains matches scan_map.awk's row %s\");\n", t_src[i]
    print  "endfunction"
}

# ---- Netlist hierarchy and Q/QN availability ---------------------------------
# Synthesized named-port instances, including preserved hierarchy and escaped
# flattened identifiers. Generate constructs must already be elaborated.
function net_load(    saved_rs, record, status) {
    if (PHASE_OUT == "") return
    if (NETLIST == "") {
        net_fail("PHASE_OUT requires NETLIST")
        return
    }
    if (TOP == "") TOP = "forte_top"
    if (PHASE_OUT == NETLIST || PHASE_OUT == LOGICAL_PHASE || PHASE_OUT == PHASE) {
        net_fail("PHASE_OUT must differ from input files")
        return
    }
    saved_rs = RS
    RS = ";"
    while ((status = (getline record < NETLIST)) > 0) net_parse_record(record)
    close(NETLIST)
    RS = saved_rs
    if (status < 0) net_fail("cannot read netlist " NETLIST)
    if (net_block_comment) net_fail("unterminated netlist block comment")
    if (!(TOP in net_modules)) net_fail("cannot find top module " TOP)
    if (!bad) net_walk(TOP, "")
}

# Delay writing the second output until both input parsers have succeeded.
function net_write_phase(    i) {
    if (PHASE_OUT == "") return
    printf "%s", "" > PHASE_OUT
    for (i = 1; i <= net_output_count; i++)
        printf "%s %d\n", net_output_path[i], net_output_qn_only[i] > PHASE_OUT
    close(PHASE_OUT)
}

function net_fail(message) {
    print "scan_map.awk: netlist: " message > "/dev/stderr"
    bad = 1
}

# Tokenize records so comments and escaped names do not become instance names.
# Comment state persists across semicolon-separated records.
function net_tokenize(s, out,    i, c, d, start, count) {
    split("", out)
    count = 0
    for (i = 1; i <= length(s); ) {
        c = substr(s, i, 1); d = substr(s, i, 2)
        if (net_line_comment) {
            if (c == "\n") net_line_comment = 0
            i++; continue
        }
        if (net_block_comment) {
            if (d == "*/") { net_block_comment = 0; i += 2 }
            else i++
            continue
        }
        if (d == "//") { net_line_comment = 1; i += 2; continue }
        if (d == "/*") { net_block_comment = 1; i += 2; continue }
        if (c ~ /[[:space:]]/) { i++; continue }
        start = i
        if (c == "\\") {
            while (i <= length(s) && substr(s, i, 1) !~ /[[:space:]]/) i++
        } else if (c == "\"") {
            i++
            while (i <= length(s)) {
                c = substr(s, i, 1)
                if (c == "\\") { i += 2; continue }
                i++
                if (c == "\"") break
            }
        } else if (c ~ /[A-Za-z0-9_$]/) {
            while (i <= length(s) && substr(s, i, 1) ~ /[A-Za-z0-9_$]/) i++
        } else i++
        out[++count] = substr(s, start, i - start)
    }
    return count
}

function net_unescape(name) { sub(/^\\/, "", name); return name }

function net_identifier(name) { return name ~ /^([A-Za-z_$][A-Za-z0-9_$]*|\\[^[:space:]]+)$/ }

# Return the matching ')' token. Nested connection expressions are allowed.
function net_closing(open, count,    i, depth) {
    depth = 0
    for (i = open; i <= count; i++) {
        if (net_t[i] == "(") depth++
        if (net_t[i] == ")" && --depth == 0) return i
    }
    net_fail("unbalanced parentheses in module " net_current)
    return 0
}

function net_record_instance(type, name, first, last,    i, end, pin, idx) {
    name = net_unescape(name)
    if ((net_current SUBSEP name) in net_names) {
        net_fail("duplicate instance " net_current "/" name); return
    }
    net_names[net_current, name] = 1
    idx = ++net_children[net_current]
    net_child_type[net_current, idx] = net_unescape(type)
    net_child_name[net_current, idx] = name
    for (i = first; i <= last; i++) {
        if (net_t[i] != "." || net_t[i+2] != "(") continue
        pin = net_t[i+1]
        end = net_closing(i+2, last)
        if (!end) return
        if (pin == "SI") net_scan[net_current, idx] = 1
        if (pin == "Q") net_q[net_current, idx] = (end > i+3)
        if (pin == "QN") net_qn[net_current, idx] = (end > i+3)
        i = end
    }
}

function net_parse_record(s,    count, i, type, end, name) {
    count = net_tokenize(s, net_t)
    # endmodule has no semicolon and may precede the next module header.
    for (i = 1; i <= count; i++) {
        if (net_t[i] == "endmodule") net_current = ""
        if (net_t[i] == "module") {
            i++
            if (net_t[i] == "automatic" || net_t[i] == "static") i++
            net_current = net_unescape(net_t[i])
            if (net_current in net_modules) net_fail("duplicate module " net_current)
            net_modules[net_current] = 1
            return
        }
        if (net_t[i] == "generate" || net_t[i] == "endgenerate")
            net_fail("elaborate generate constructs before extracting hierarchy")
    }
    if (net_current == "" || !count) return
    i = 1
    # Optional synthesis attributes before a cell declaration.
    while (net_t[i] == "(" && net_t[i+1] == "*") {
        i += 2
        while (i <= count && !(net_t[i] == "*" && net_t[i+1] == ")")) i++
        i += 2
    }
    type = net_t[i++]
    if (!net_identifier(type)) return
    if (type ~ /^(input|output|inout|wire|tri|logic|reg|assign|parameter|localparam|integer|time|real|genvar|supply0|supply1|defparam|endmodule)$/) return
    if (net_t[i] == "#" && net_t[i+1] == "(") {
        end = net_closing(i+1, count)
        if (!end) return
        i = end + 1
    }
    while (i <= count) {
        name = net_t[i++]
        if (!net_identifier(name) || net_t[i] != "(") break
        end = net_closing(i, count)
        if (!end) break
        net_record_instance(type, name, i+1, end-1)
        i = end + 1
        if (net_t[i] != ",") break
        i++
    }
}

function net_walk(module, prefix,    i, type, path) {
    if (net_active[module]) { net_fail("recursive module hierarchy at " prefix); return }
    net_active[module] = 1
    for (i = 1; i <= net_children[module]; i++) {
        type = net_child_type[module, i]
        path = prefix net_child_name[module, i]
        if (net_scan[module, i] && (net_q[module, i] || net_qn[module, i])) {
            if (path in net_emitted) { net_fail("ambiguous full path " path); continue }
            net_emitted[path] = 1
            net_output_path[++net_output_count] = path
            net_output_qn_only[net_output_count] = (net_qn[module, i] && !net_q[module, i]) ? 1 : 0
        } else if (type in net_modules) net_walk(type, path "/")
    }
    delete net_active[module]
}
