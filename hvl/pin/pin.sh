#!/bin/bash
# hvl/pin/pin.sh -- build and run the pin-only forte_top bench (hvl/pin/pin_tb.sv).
#
#   SIM=verilator|vcs DUT=rtl|rtl_sva|gate  hvl/pin/pin.sh <command> ...
#
#   preflight                 check tools and (vcs) every path in vm_paths.sh
#   build                     compile into sim/pin/build/$SIM_$DUT
#   run <prog> [x.cmd] [+plusargs]
#                             run one program: a .c/.S/.s/.elf (built with
#                             bin/generate_memory_file.py) or a .lst.  Without a
#                             script: load, reset, run to tohost, expect exit 0.
#                             With one: $MEM (the image), $RUN and $REPO expand.
#   compare <runA> <runB>     pin traces must match (bin/pin_trace_cmp.py)
#
# DUT variants -- the first two are the RTL references, the third the netlist:
#   rtl      forte_top RTL with `SYNTHESIS: SRAM macros and pad cells exactly
#            as synthesized.  Drops the RTL's own `ifndef SYNTHESIS SVA.
#   rtl_sva  forte_top RTL without `SYNTHESIS: behavioural pads and arrays,
#            with the SVA in forte_link_core/phy and forte_chip.
#   gate     $NETLIST plus cell, SRAM and pad models (VCS only).  Zero-delay
#            unless $SDF is set in vm_paths.sh.
# Verilator is 2-state: it validates the bench and the flow, not X behaviour.
#
# Runs land in sim/pin/runs/$SIM_$DUT/<name>/: sim.log, pin_trace.log,
# uart.log, and RESULT (the PIN_TB_RESULT line, or FAIL if there was none).
# One simulation at a time per checkout: generate_memory_file.py writes a
# shared sim/bin/memory_8.lst, which this script copies away immediately.
set -euo pipefail

R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
P="$R/hvl/pin"
SIM="${SIM:-verilator}"
DUT="${DUT:-rtl}"
# WAVES=1 builds (waveform dumping) live in their own directory, so a normal
# rebuild -- the self-test, vm_run.sh -- cannot replace them unnoticed.
BUILD="$R/sim/pin/build/${SIM}_${DUT}${WAVES:+_waves}"
RUNS="$R/sim/pin/runs/${SIM}_${DUT}"

die() { echo "pin.sh: $*" >&2; exit 1; }

case "$SIM" in verilator|vcs) ;; *) die "SIM must be verilator or vcs, not '$SIM'";; esac
case "$DUT" in rtl|rtl_sva|gate) ;; *) die "DUT must be rtl, rtl_sva or gate, not '$DUT'";; esac
[ "$SIM/$DUT" = "verilator/gate" ] && die "gate-level needs a 4-state simulator: use SIM=vcs"

if [ "$SIM" = vcs ]; then
  # The VM's own paths: not tracked, not in the bundle (see vm_paths.example.sh).
  [ -f "$P/vm_paths.sh" ] || die "no $P/vm_paths.sh: cp $P/vm_paths.example.sh $P/vm_paths.sh and fill it in"
  # shellcheck source=vm_paths.example.sh
  PDK_FIRST=(); VCS_FLAGS=()
  source "$P/vm_paths.sh"
else
  NETLIST=""; SDF=""; STDCELL_MODELS=(); SRAM_MODELS=(); PAD_MODELS=(); PDK_FIRST=()
fi

# ---- source lists ------------------------------------------------------------
# Only directories that exist: a VM unpacked from vm_bundle.tgz has no
# third_party/cvw, and nothing the bench compiles includes from it.
INCS=()
# hdl itself: prim_fifo_async.sv (moved there from third_party/opentitan) does
# `include "prim_assert.sv".
for d in pkg hdl hdl/core hdl/core/ifu/bpred third_party/cvw/config/rv64gc; do
  [ -d "$R/$d" ] && INCS+=(+incdir+"$R/$d")
done
BENCH=("$P/pin_link_agent.sv" "$P/pin_uart_agent.sv" "$P/pin_tb.sv")
LINK_PKG="$R/hdl/forte_link_pkg.sv"

# Compile order.  PDK model files go FIRST, as ordinary sources, in the order
# vm_paths.sh lists them: PDK_FIRST (primitives, headers and anything the pad
# or SRAM models build on), then PAD_MODELS, then SRAM_MODELS.  A file given
# with -v is only searched for modules the design leaves unresolved, so any
# `define, `timescale or primitive the wrappers depend on would be missing
# when they are elaborated.  Standard cells stay -v, at the end: a cell
# library is thousands of modules, and only the ones the netlist uses are wanted.
pdk_first() {
  PDK=()
  for f in ${PDK_FIRST[@]+"${PDK_FIRST[@]}"} "${PAD_MODELS[@]}" "${SRAM_MODELS[@]}"; do PDK+=("$f"); done
}

rtl_sources() {
  local core forte
  mapfile -t core  < <(find "$R/hdl/core" \( -name '*.sv' -o -name '*.v' \) ! -name cvw.sv | sort)
  mapfile -t forte < <(find "$R/hdl" -maxdepth 1 -name 'forte_*.sv' ! -name forte_link_pkg.sv | sort)
  DEFS=(+define+PIN_TB_RTL +define+ECE411_NO_FLOAT +define+ECE411_LINUX)
  LIBS=()
  SRCS=()
  if [ "$DUT" = rtl ]; then
    DEFS+=(+define+SYNTHESIS)
    # Real PDK models when vm_paths.sh names them, else the local stand-ins.
    PDK=()
    [ ${#PDK_FIRST[@]} -gt 0 ] && PDK+=(${PDK_FIRST[@]+"${PDK_FIRST[@]}"})
    if [ ${#PAD_MODELS[@]} -gt 0 ];  then PDK+=("${PAD_MODELS[@]}");  else PDK+=("$P/models/pad_behav.sv");  fi
    if [ ${#SRAM_MODELS[@]} -gt 0 ]; then PDK+=("${SRAM_MODELS[@]}"); else PDK+=("$P/models/sram_behav.sv"); fi
    SRCS=("${PDK[@]}")
  fi
  SRCS+=("$R/pkg/types.sv" "$LINK_PKG" "$R/hdl/core/cvw.sv" "${core[@]}" "${forte[@]}"
         "$R/hdl/prim_flop_2sync.sv" "$R/hdl/prim_fifo_async.sv"
         "${BENCH[@]}")
}

gate_sources() {
  pdk_first
  SRCS=("${PDK[@]}" "$LINK_PKG" "$NETLIST" "${BENCH[@]}")
  DEFS=(+define+PIN_TB_GATE)
  LIBS=()
  for f in "${STDCELL_MODELS[@]}"; do LIBS+=(-v "$f"); done
}

# ---- preflight -----------------------------------------------------------------
preflight() {
  local bad=0
  need() { command -v "$1" >/dev/null || { echo "  MISSING tool: $1"; bad=1; }; }
  isfile() { [ -f "$2" ] || { echo "  MISSING $1: '$2'"; bad=1; }; }
  echo "preflight: SIM=$SIM DUT=$DUT"
  need python3
  if [ "$SIM" = verilator ]; then need verilator; verilator --version
  else
    need vcs; vcs -ID 2>/dev/null | head -3 || true
    if [ "$DUT" = gate ]; then
      isfile NETLIST "$NETLIST"
      [ ${#STDCELL_MODELS[@]} -gt 0 ] || { echo "  STDCELL_MODELS is empty"; bad=1; }
      [ ${#SRAM_MODELS[@]}    -gt 0 ] || { echo "  SRAM_MODELS is empty"; bad=1; }
      [ ${#PAD_MODELS[@]}     -gt 0 ] || { echo "  PAD_MODELS is empty"; bad=1; }
      [ -z "$SDF" ] || isfile SDF "$SDF"
    fi
    for f in ${PDK_FIRST[@]+"${PDK_FIRST[@]}"} "${STDCELL_MODELS[@]}" "${SRAM_MODELS[@]}" "${PAD_MODELS[@]}"; do isfile model "$f"; done
  fi
  if [ "$DUT" = gate ] && [ -f "$NETLIST" ]; then
    # POSIX classes only: gawk reads \b as backspace and awk has no \s, so the
    # GNU shorthands silently match nothing on some machines.
    local hdr; hdr="$(sed -nE '/^[[:space:]]*module[[:space:]]+forte_top([^[:alnum:]_]|$)/,/;/p' "$NETLIST")"
    [ -n "$hdr" ] || { echo "  NETLIST has no 'module forte_top'"; bad=1; }
    # Every SRAM macro and pad cell the netlist instantiates must be defined by a model.
    local defs; defs="$(cat ${PDK_FIRST[@]+"${PDK_FIRST[@]}"} "${SRAM_MODELS[@]}" "${PAD_MODELS[@]}" 2>/dev/null | grep -oE '^[[:space:]]*module[[:space:]]+[A-Za-z0-9_]+' | awk '{print $2}' | sort -u)"
    for m in $(grep -oE '^[[:space:]]*(rf_sp_[0-9]+_[0-9]+|sram_dp_[0-9]+_[0-9]+|io_in|io_out|io_tri)[[:space:]]' "$NETLIST" | sort -u); do
      grep -qx "$m" <<<"$defs" || { echo "  netlist instantiates $m but no model defines it"; bad=1; }
    done
    # The ports the bench connects.
    for p in core_clk rst_n io dir req clk_out wr ready rvalid irq uart_tx uart_rx test_mode scan_en fault_inject status; do
      grep -qw "$p" <<<"$hdr" || { echo "  forte_top in NETLIST has no port $p"; bad=1; }
    done
  fi
  [ $bad = 0 ] && echo "preflight: OK" || die "preflight failed"
}

# ---- build ---------------------------------------------------------------------------
build() {
  preflight
  if [ "$DUT" = gate ]; then gate_sources; else rtl_sources; fi
  mkdir -p "$BUILD"
  cd "$BUILD"
  echo "build: $BUILD"
  if [ "$SIM" = verilator ]; then
    verilator --binary -j "$(nproc)" --timing --timescale 1ns/1ps -Wno-fatal -Wno-lint -Wno-style \
      +define+ECE411_VERILATOR "${INCS[@]}" "${DEFS[@]}" "${SRCS[@]}" \
      --top-module pin_tb -o pin_tb 2>&1 | tee build.log
    [ -x obj_dir/pin_tb ] || die "verilator build failed, see $BUILD/build.log"
  else
    local xp=()
    [ "$DUT" = gate ] || xp=(-xprop="$P/xprop.config" -xprop=flowctrl)
    # WAVES=1: waveform dumping (+PIN_VCD at run time), at some speed cost.
    [ -n "${WAVES:-}" ] && xp+=(-debug_access+all +define+PIN_WAVES)
    local timing=(+nospecify +notimingcheck)
    if [ "$DUT" = gate ] && [ -n "$SDF" ]; then
      timing=(-sdf "$SDF_CORNER:pin_tb.dut:$SDF" +neg_tchk)
    fi
    # All of VCS's output into build.log (and the terminal), not -l: licence,
    # environment and command-line errors only ever reach the terminal.
    # simv is kept between builds: VCS compiles incrementally and, when nothing
    # changed, leaves it as it is ("The design hasn't changed and need not be
    # recompiled").  The verdict is VCS's exit status, not simv existing, so an
    # old simv cannot stand in for a failed compile.
    # simv.daidir without simv (an interrupted build, or an older pin.sh that
    # deleted simv) makes VCS report "unchanged" and produce nothing: clear it.
    [ -x simv ] || rm -rf simv.daidir csrc
    # The exact command first, so the compile order is always on record.
    { echo "# compile command (pin.sh, DUT=$DUT):"
      printf '%q ' vcs -full64 -sverilog -licqueue -lca -suppress=LCA_FEATURES_ENABLED -timescale=1ns/1ps \
        -assert svaext +lint=TFIPC-L "${xp[@]}" "${timing[@]}" ${VCS_FLAGS[@]+"${VCS_FLAGS[@]}"} "${INCS[@]}" "${DEFS[@]}" "${SRCS[@]}" "${LIBS[@]}" -top pin_tb -o simv
      echo; echo; } > build.cmd
    cat build.cmd
    # VCS's own exit status, captured inside the pipe (PIPESTATUS does not
    # survive the `|| true`).
    { vcs -full64 -sverilog -licqueue -lca -suppress=LCA_FEATURES_ENABLED -timescale=1ns/1ps \
        -assert svaext +lint=TFIPC-L "${xp[@]}" "${timing[@]}" ${VCS_FLAGS[@]+"${VCS_FLAGS[@]}"} \
        "${INCS[@]}" "${DEFS[@]}" "${SRCS[@]}" "${LIBS[@]}" \
        -top pin_tb -o simv 2>&1; echo $? > build.rc; } | cat build.cmd - | tee build.log || true
    local rc; rc="$(cat build.rc 2>/dev/null || echo 1)"
    # "Unchanged, not recompiled" is a success whatever status VCS gives it.
    grep -q "design hasn't changed and need not be recompiled" build.log && [ -x simv ] && rc=0
    if [ "$rc" != 0 ] || [ ! -x simv ]; then
      tail -40 build.log | sed 's/^/  | /' >&2
      die "vcs build failed (exit $rc), see $BUILD/build.log"
    fi
  fi
  echo "build: OK"
}

# ---- run -------------------------------------------------------------------------------
run() {
  local what="${1:?run needs a program (.c/.S/.s/.elf/.lst)}"; shift
  local script=""
  if [ $# -gt 0 ] && [[ "$1" == *.cmd ]]; then script="$1"; shift; fi
  abs() { echo "$(cd "$(dirname "$1")" && pwd)/$(basename "$1")"; }
  [ -f "$what" ] || die "no such file: $what"; what="$(abs "$what")"
  [ -z "$script" ] || { [ -f "$script" ] || die "no such file: $script"; script="$(abs "$script")"; }
  local name; name="$(basename "${what%.*}")${TAG:+_$TAG}"
  local run="$RUNS/$name"
  local exe; [ "$SIM" = verilator ] && exe="$BUILD/obj_dir/pin_tb" || exe="$BUILD/simv"
  [ -x "$exe" ] || die "not built: $exe (run: ${WAVES:+WAVES=1 }SIM=$SIM DUT=$DUT $0 build)"
  # +PIN_VCD only works in a WAVES=1 build; without one it would be ignored.
  local a vcd=0
  for a in "$@"; do [ "$a" = +PIN_VCD ] && vcd=1; done
  if [ $vcd = 1 ] && [ "$SIM" = vcs ] && ! grep -q PIN_WAVES "$BUILD/build.cmd" 2>/dev/null; then
    die "+PIN_VCD needs a waveform build: WAVES=1 SIM=$SIM DUT=$DUT $0 build, then run with WAVES=1 too"
  fi
  rm -rf "$run"; mkdir -p "$run"
  case "$what" in
    *.lst) cp "$what" "$run/memory.lst";;
    *.c|*.s|*.S|*.elf)
      ( cd "$R/sim" && python3 "$R/bin/generate_memory_file.py" -8 "$what" >"$run/memgen.log" 2>&1 ) \
        || die "generate_memory_file.py failed, see $run/memgen.log"
      cp "$R/sim/bin/memory_8.lst" "$run/memory.lst";;
    *) die "don't know how to run '$what'";;
  esac
  local args=(+MEMLST="$run/memory.lst")
  if [ -n "$script" ]; then
    sed -e "s|\$REPO|$R|g" -e "s|\$RUN|$run|g" -e "s|\$MEM|$run/memory.lst|g" "$script" > "$run/script.cmd"
    args=(+CMD="$run/script.cmd")
  fi
  echo "run: $name${script:+ ($(basename "$script"))} -> $run"
  ( cd "$run" && "$exe" "${args[@]}" +FPGA_TRACE="$run/pin_trace.log" +UART_LOG="$run/uart.log" "$@" ) \
    > "$run/sim.log" 2>&1 || true
  [ $vcd = 1 ] && { [ -s "$run/pin.vcd" ] && echo "waveform: $run/pin.vcd" || echo "pin.sh: WARNING +PIN_VCD given but no $run/pin.vcd was written" >&2; }
  local res; res="$(grep -m1 '^PIN_TB_RESULT:' "$run/sim.log" || echo 'PIN_TB_RESULT: FAIL no verdict (crash or killed)')"
  echo "$res" | tee "$run/RESULT"
  grep -E '^\[PIN_TB\] cycles=|ERROR' "$run/sim.log" | head -20 || true
  [[ "$res" == *PASS* ]]
}

case "${1:-}" in
  preflight) preflight;;
  build)     build;;
  run)       shift; run "$@";;
  compare)   shift; python3 "$R/bin/pin_trace_cmp.py" "$@";;
  *)         sed -n '2,24p' "$0"; exit 1;;
esac
