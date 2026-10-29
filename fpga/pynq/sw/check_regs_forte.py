#!/usr/bin/env python3
"""Fail when sw/forte/regs.py and fpga/bringup/rtl/fbu_pkg.sv disagree.

Every REG_* offset and the ID/VERSION constants must match by name, and every
REG_* in the package must exist in Python (a register the firmware cannot name
is a register nobody tests)."""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PKG = os.path.join(HERE, "..", "..", "bringup", "rtl", "fbu_pkg.sv")
sys.path.insert(0, HERE)
from forte import regs  # noqa: E402


def sv_constants(path):
    text = open(path).read()
    found = {}
    for name, width, value in re.findall(
            r"localparam\s+logic\s*\[[^\]]*\]\s*(\w+)\s*=\s*(\d+)'h([0-9A-Fa-f_]+)", text):
        found[name] = int(value.replace("_", ""), 16)
    return found


def main():
    sv = sv_constants(PKG)
    bad = 0
    for name, value in sorted(sv.items()):
        if not (name.startswith("REG_") or name in ("FBU_ID", "FBU_VERSION")):
            continue
        py = getattr(regs, name, None)
        if py is None:
            print(f"missing in regs.py: {name} = 0x{value:X}")
            bad += 1
        elif py != value:
            print(f"mismatch: {name} is 0x{value:X} in fbu_pkg.sv, 0x{py:X} in regs.py")
            bad += 1
    for name in dir(regs):
        if name.startswith("REG_") and name not in sv:
            print(f"regs.py has {name}, fbu_pkg.sv does not")
            bad += 1
    checked = sum(1 for n in sv if n.startswith("REG_"))
    print(f"check_regs_forte: {checked} registers, {bad} problems")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
