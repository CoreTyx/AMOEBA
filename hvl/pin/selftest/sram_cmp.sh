#!/bin/bash
# hvl/pin/selftest/sram_cmp.sh -- compare every PDK SRAM model in vm_paths.sh's
# SRAM_MODELS with the behaviour the RTL assumes (sram_cmp_drv.sv).
#
#   SIM=vcs hvl/pin/selftest/sram_cmp.sh            uses vm_paths.sh
#   SIM=vcs SRAM_MODELS_LIST="a.v b.v" ...          or name the files directly
#
# Macro geometry (depth, port width) comes from hvl/pin/models/sram_behav.sv,
# whose PIN_RF_SP table mirrors the wrappers in hdl/core/generic/mem.  Prints
# one SRAM_CMP line per macro and SRAM_CMP_RESULT: PASS|FAIL.
set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
P="$R/hvl/pin"
SIM="${SIM:-vcs}"
OUT="$R/sim/pin/selftest/$SIM/sram_cmp"
mkdir -p "$OUT"

PDK_FIRST=(); SRAM_MODELS=()
if [ -n "${SRAM_MODELS_LIST:-}" ]; then read -r -a SRAM_MODELS <<<"$SRAM_MODELS_LIST"
elif [ -f "$P/vm_paths.sh" ]; then source "$P/vm_paths.sh"; fi
[ ${#SRAM_MODELS[@]} -gt 0 ] || { echo "SRAM_CMP_RESULT: SKIP (no SRAM_MODELS)"; exit 0; }

# Macros the models define, with their geometry from the stand-in table.
declare -A GEOM
while read -r name dep wid; do GEOM[$name]="$dep $wid"; done < <(
  sed -nE 's/^`PIN_RF_SP\(([a-z0-9_]+), *([0-9]+), *([0-9]+)\).*/\1 \2 \3/p' "$P/models/sram_behav.sv")
mapfile -t DEFINED < <(cat "${SRAM_MODELS[@]}" | grep -oE '^[[:space:]]*module[[:space:]]+rf_sp_[0-9]+_[0-9]+' | awk '{print $2}' | sort -u)
[ ${#DEFINED[@]} -gt 0 ] || { echo "SRAM_CMP_RESULT: FAIL (SRAM_MODELS define no rf_sp_* module)"; exit 1; }

TOP="$OUT/sram_cmp_tb.sv"
{
  echo '`timescale 1ns/1ps'
  echo 'module sram_cmp_tb;'
  echo '  logic clk = 0; always #5 clk = ~clk;'
  for m in "${DEFINED[@]}"; do
    [ -n "${GEOM[$m]:-}" ] || { echo "  // $m: not in the stand-in table, not compared"; continue; }
    read -r dep wid <<<"${GEOM[$m]}"
    aw=$(python3 -c "import math; print(max(1, math.ceil(math.log2($dep))))")
    cat <<EOT
  wire c_$m, w_$m; wire [$((aw-1)):0] a_$m; wire [$((wid-1)):0] d_$m, qm_$m, qr_$m;
  sram_cmp_drv #(.DEPTH($dep), .WIDTH($wid), .NAME("$m")) drv_$m (.clk, .cen(c_$m), .wen(w_$m), .a(a_$m), .d(d_$m), .q_model(qm_$m), .q_ref(qr_$m));
  $m model_$m (.CLK(clk), .CEN(c_$m), .WEN(w_$m), .A(a_$m), .D(d_$m), .Q(qm_$m));
  pin_rf_sp #(.DEPTH($dep), .WIDTH($wid)) ref_$m (.CLK(clk), .CEN(c_$m), .WEN(w_$m), .A(a_$m), .D(d_$m), .Q(qr_$m));
EOT
  done
  echo '  initial begin'
  echo '    int bad = 0;'
  echo '    #10;'
  printf '    wait (1'
  for m in "${DEFINED[@]}"; do [ -n "${GEOM[$m]:-}" ] && printf ' && drv_%s.done' "$m"; done
  echo ');'
  for m in "${DEFINED[@]}"; do [ -n "${GEOM[$m]:-}" ] && echo "    bad += drv_$m.diffs;"; done
  echo '    if (bad == 0) $display("SRAM_CMP_RESULT: PASS"); else $display("SRAM_CMP_RESULT: FAIL %0d differences", bad);'
  echo '    $finish;'
  echo '  end'
  echo 'endmodule'
} > "$TOP"

SRCS=(${PDK_FIRST[@]+"${PDK_FIRST[@]}"} "${SRAM_MODELS[@]}" "$P/models/sram_behav.sv" "$P/selftest/sram_cmp_drv.sv" "$TOP")
cd "$OUT"
if [ "$SIM" = verilator ]; then
  verilator --binary --timing --timescale 1ns/1ps -Wno-fatal -Wno-lint -Wno-style +define+PIN_RF_SP_GENERIC_ONLY \
    "${SRCS[@]}" --top-module sram_cmp_tb -o sram_cmp >build.log 2>&1 || { tail -20 build.log; echo "SRAM_CMP_RESULT: FAIL build"; exit 1; }
  ./obj_dir/sram_cmp | tee run.log | grep -E '^SRAM_CMP'
else
  [ -x simv ] || rm -rf simv.daidir csrc
  vcs -full64 -sverilog -licqueue -timescale=1ns/1ps +nospecify +notimingcheck +define+PIN_RF_SP_GENERIC_ONLY \
    "${SRCS[@]}" -top sram_cmp_tb -o simv >build.log 2>&1
  rc=$?; grep -q "need not be recompiled" build.log && [ -x simv ] && rc=0
  [ $rc = 0 ] && [ -x simv ] || { tail -20 build.log; echo "SRAM_CMP_RESULT: FAIL build"; exit 1; }
  ./simv | tee run.log | grep -E '^SRAM_CMP'
fi
grep -q '^SRAM_CMP_RESULT: PASS' run.log
