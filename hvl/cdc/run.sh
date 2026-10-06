#!/bin/bash
# The two-clock CDC run docs/impl_plan_link_clocking.md s9a requires: forte_chip
# with core_clk and link_clk from independent generators at a non-integer ratio,
# running an ordinary ISA programme, gated on exact flit balance.
#
#   ./run.sh [program.c]              one run at the default 1:1.3701
#   SWEEP=1 ./run.sh [program.c]      sweep several ratios
#
# Built with `verilator --binary --timing` because the clocks are generated in
# SystemVerilog -- the main flow's Verilator harness drives clk from C++ and
# cannot produce a second one.  See hvl/cdc/forte_cdc_tb.sv.
set -euo pipefail
R="$(cd "$(dirname "$0")/../.." && pwd)"
PROG="${1:-$R/testcode/isa_level_testing/tc_link_abort.c}"
# Absolute, because the memory image is generated from inside $R/sim.
case "$PROG" in /*) ;; *) PROG="$(cd "$(dirname "$PROG")" && pwd)/$(basename "$PROG")";; esac
OUT="${OUT:-$(mktemp -d)}"
mkdir -p "$OUT"

# Build the memory image for THIS programme, the same way sim/Makefile's
# run_verilator_top_tb_no_spike does.  Generated rather than picked up: sim/bin/
# holds whatever the last regression left there, so reusing it would silently run
# a different programme than the one named on the command line.
( cd "$R/sim" && python3 "$R/bin/generate_memory_file.py" -8 "$PROG" >/dev/null )
MEMLST="$R/sim/bin/memory_8.lst"
[ -f "$MEMLST" ] || { echo "run.sh: no memory image at $MEMLST"; exit 1; }
echo "=== programme: $PROG ==="

CORE_SV="$R/hdl/core/cvw.sv"
mapfile -t CORE_SRCS < <(find "$R/hdl/core" -name '*.sv' -o -name '*.v' | grep -v '/cvw\.sv$' | sort)
mapfile -t SRAM_SRCS < <(find "$R/sram/output" -name '*.v' 2>/dev/null | sort)

cd "$OUT"
echo "=== building in $OUT ==="
verilator --binary -j "$(nproc)" --timing --timescale 1ns/1ps \
  -Wno-fatal \
  +define+ECE411_VERILATOR +define+ECE411_NO_FLOAT +define+ECE411_NO_SPIKE_DPI \
  +incdir+"$R/pkg" +incdir+"$R/hdl/core" +incdir+"$R/hdl/core/ifu/bpred" \
  +incdir+"$R/third_party/cvw/config/rv64gc" +incdir+"$R/third_party/opentitan" \
  +incdir+"$R/hvl/common" \
  "$R/pkg/types.sv" "$R/pkg/forte_link_pkg.sv" "$CORE_SV" "${CORE_SRCS[@]}" \
  ${SRAM_SRCS[0]+"${SRAM_SRCS[@]}"} \
  "$R/hdl/forte_chip.sv" "$R/hdl/forte_link_core.sv" "$R/hdl/forte_link_phy.sv" \
  "$R/hdl/forte_rst_sync.sv" "$R/hdl/forte_soc.sv" "$R/hdl/forte_uncore.sv" \
  "$R/third_party/opentitan/prim_flop_2sync.sv" \
  "$R/third_party/opentitan/prim_fifo_async.sv" \
  "$R/hvl/common/mem_itf.sv" "$R/hvl/common/masked_memory.sv" \
  "$R/hvl/common/forte_link_model.sv" "$R/hvl/cdc/forte_cdc_tb.sv" \
  --top-module forte_cdc_tb -o cdctb

run_one() {  # $1 = link half-period in ns
  echo "--- link_half=$1 ---"
  ./obj_dir/cdctb +MEMLST_ECE411="$MEMLST" +TIMEOUT_ECE411=4000000 \
                  +LINK_HALF="$1" ${CDC_EXTRA:-} 2>&1 | grep -E "^\[CDC\]|^\[FLIT\]|FORTE_CDC|%Error|Fatal"
}

if [ "${SWEEP:-0}" = "1" ]; then
  # Ratios either side of 1, none of them rational multiples of the core clock.
  for h in 3.6495 4.1234 5.0000 5.7311 6.9876 7.3000; do run_one "$h"; done
else
  run_one "${LINK_HALF:-3.6495}"
fi
