#!/usr/bin/env python3
"""add_test_cell.py <in.lib> <out.lib>: give the FreePDK45 scan flops (SDFF*) the
test_cell groups DFT Compiler needs to use them as scan cells.  EWS stand-in only."""
import re, sys
src, dst = sys.argv[1], sys.argv[2]
text = open(src).read()
out = []; pos = 0; n = 0
for m in re.finditer(r'\n(\s*)cell\s*\(\s*(SDFF(R|S|RS)?_X\d)\s*\)\s*\{', text):
    name, kind = m.group(2), m.group(3) or ""
    # find the cell's ff block to copy clear/preset
    start = m.end()
    ffm = re.search(r'ff\s*\(\s*"IQ"\s*,\s*"IQN"\s*\)\s*\{(.*?)\}', text[start:], re.S)
    body = ffm.group(1)
    clear = re.search(r'clear\s*:\s*"([^"]*)"', body); preset = re.search(r'preset\s*:\s*"([^"]*)"', body)
    pins = ["D", "CK"] + (["RN"] if "R" in kind else []) + (["SN"] if "S" in kind else [])
    tc = "\n\ttest_cell () {\n"
    for p in pins: tc += f"\t\tpin ({p}) {{ direction : input; }}\n"
    tc += "\t\tpin (SI) { direction : input; signal_type : test_scan_in; }\n"
    tc += "\t\tpin (SE) { direction : input; signal_type : test_scan_enable; }\n"
    tc += '\t\tff ("IQ", "IQN") { next_state : "D"; clocked_on : "CK";'
    if clear: tc += f' clear : "{clear.group(1)}";'
    if preset: tc += f' preset : "{preset.group(1)}";'
    m2 = re.search(r'clear_preset_var1\s*:\s*(\w+)', body)
    if m2: tc += f' clear_preset_var1 : {m2.group(1)};'
    m3 = re.search(r'clear_preset_var2\s*:\s*(\w+)', body)
    if m3: tc += f' clear_preset_var2 : {m3.group(1)};'
    tc += " }\n"
    tc += '\t\tpin (Q) { direction : output; function : "IQ"; signal_type : test_scan_out; }\n'
    tc += '\t\tpin (QN) { direction : output; function : "IQN"; signal_type : test_scan_out_inverted; }\n'
    tc += "\t}\n"
    out.append(text[pos:start]); out.append(tc); pos = start; n += 1
out.append(text[pos:])
open(dst, "w").write("".join(out))
print("test_cell added to", n, "cells")
