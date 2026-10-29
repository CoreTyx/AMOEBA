#!/usr/bin/env bash
# check_frozen.sh -- the FPGA emulation must not touch the frozen RTL, and its
# stand-ins must not drift from the pin bench's models.
#
#   fpga/scripts/check_frozen.sh            (FREEZE_REF overrides the base)
#
# 1. hdl/, pkg/ and sram/ are identical to FREEZE_REF, committed or not.
# 2. emu_pads.sv's modules are pad_behav.sv's, line for line.
# 3. emu_srams.sv defines the same macros, depths and port widths as
#    sram_behav.sv, and every macro the RTL instantiates is among them.
# 4. Every SRAM wrapper ties RETN to 1'b1 (the stand-in cannot show X).
# 5. split/forte_top_split.sv, once it exists, differs from forte_top.sv only
#    in the link_clk port and its connection.
set -euo pipefail
R="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
cd "$R"
FREEZE_REF="${FREEZE_REF:-8babc55}"
EMU=fpga/pynq/rtl/emu
MODELS=hvl/pin/models
fail=0
bad() { echo "FAIL: $*"; fail=1; }

# 1 -- frozen trees
if ! git diff --quiet "$FREEZE_REF" -- hdl pkg sram; then
  bad "hdl/ pkg/ sram/ differ from $FREEZE_REF:"; git diff --stat "$FREEZE_REF" -- hdl pkg sram
fi
untracked=$(git ls-files --others --exclude-standard -- hdl pkg sram)
[ -z "$untracked" ] || bad "untracked files under the frozen trees: $untracked"

# 2 -- pad bodies
pads() { sed -n '/^module io_/,/^endmodule/p' "$1"; }
diff <(pads $MODELS/pad_behav.sv) <(pads $EMU/emu_pads.sv) >/dev/null \
  || bad "emu_pads.sv modules differ from pad_behav.sv"

# 3 -- macro table
table() { grep -oE '^`[A-Z_]+\((rf|sram)_sp_[0-9]+_[0-9]+, *[0-9]+, *[0-9]+\)' "$1" | sed -E 's/^`[A-Z_]+\(//; s/[ )]//g' | sort; }
diff <(table $MODELS/sram_behav.sv) <(table $EMU/emu_srams.sv) >/dev/null \
  || bad "emu_srams.sv macro table differs from sram_behav.sv"
have=$(table $EMU/emu_srams.sv | cut -d, -f1)
for m in $(grep -rhoE '\b(rf|sram)_sp_[0-9]+_[0-9]+\b' hdl | sort -u); do
  grep -qx "$m" <<<"$have" || bad "RTL instantiates $m, emu_srams.sv does not define it"
done

# 4 -- RETN tied high in every wrapper that instantiates a macro
for f in $(grep -rlE '\b(rf|sram)_sp_[0-9]+_[0-9]+\b' hdl/core/generic/mem); do
  grep -q "\.RETN(1'b1)" "$f" || bad "$f does not tie RETN to 1'b1"
done

# 5 -- split-clock pad ring copy
S=fpga/pynq/rtl/split/forte_top_split.sv
if [ -f "$S" ]; then
  d=$(diff <(sed 's/forte_top_split/forte_top/' "$S") hdl/forte_top.sv | grep -E '^[<>]' | grep -v 'link_clk' || true)
  [ -z "$d" ] || { bad "forte_top_split.sv differs from forte_top.sv beyond link_clk:"; echo "$d"; }
fi

[ $fail = 0 ] && echo "check_frozen OK (base $FREEZE_REF)"
exit $fail
