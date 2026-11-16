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
#   build-dir / runs-dir      print where build / run would go, and stop
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
# Runs land in sim/pin/runs/$SIM_$DUT[_<corner>]/<name>/: sim.log, pin_trace.log,
# pin_cycle.log.gz, uart.log, and RESULT (the PIN_TB_RESULT line, or FAIL if
# there was none).
#
# Environment (all optional; postpnr/run.sh and postpnr/prepare.sh set them):
#   PIN_NETLIST, PIN_SDF, PIN_SDF_CORNER   override vm_paths.sh's NETLIST, SDF,
#                                          SDF_CORNER (the post-PnR drop folder)
#   PIN_VM_PATHS      the vm_paths.sh to source instead of hvl/pin/vm_paths.sh
#                     (postpnr/run.sh sets it to the one it found)
#   PIN_PATHS_EXTRA   a file sourced after vm_paths.sh (postpnr's pnr.env)
#   PIN_RTL_ROOT      take hdl/ and pkg/ from this tree instead of this checkout
#                     (the golden RTL at a pinned commit, with this bench)
#   PIN_BUILD, PIN_RUNS   build and run directories instead of sim/pin/...
#   PIN_WAIVERS       file of regexes: matching 'Timing violation' lines are
#                     reported but do not fail the run (none by default)
#   INITREG=0|1|random    VCS only: start every register and memory at that
#                     value (+vcs+initreg).  For triage of X-pessimism ONLY --
#                     a sign-off run starts from X; RESULT says when it did not.
#
# A gate build with an SDF is a TIMING simulation, and fails hard on:
#   - any VCS SDFCOM_* message at compile time (an SDF entry not annotated --
#     a missing instance, pin or arc means some delay or check is not modelled),
#     or any other SDF* message (SDFPE: a parse error, which ABORTS annotation),
#   - an annotation VCS does not report completed with 0 errors and 0 warnings,
# and every run of it fails on any 'Timing violation' (setup, hold, recovery,
# removal, width, period) not matched by PIN_WAIVERS, even if the bench passed.
# One simulation at a time per checkout: generate_memory_file.py writes a
# shared sim/bin/memory_8.lst, which this script copies away immediately.
set -euo pipefail

R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
P="$R/hvl/pin"
SIM="${SIM:-verilator}"
DUT="${DUT:-rtl}"
RTL="${PIN_RTL_ROOT:-$R}"
INITREG="${INITREG:-}"

die() { echo "pin.sh: $*" >&2; exit 1; }

case "$SIM" in verilator|vcs) ;; *) die "SIM must be verilator or vcs, not '$SIM'";; esac
case "$DUT" in rtl|rtl_sva|gate) ;; *) die "DUT must be rtl, rtl_sva or gate, not '$DUT'";; esac
[ "$SIM/$DUT" = "verilator/gate" ] && die "gate-level needs a 4-state simulator: use SIM=vcs"

case "$INITREG" in ""|0|1|random) ;; *) die "INITREG must be 0, 1 or random, not '$INITREG'";; esac
[ -n "$INITREG" ] && [ "$SIM" != vcs ] && die "INITREG is VCS only (Verilator is 2-state and starts at 0)"

if [ "$SIM" = vcs ]; then
  # The VM's own paths: not tracked, not in the bundle (see vm_paths.example.sh).
  VM_PATHS="${PIN_VM_PATHS:-$P/vm_paths.sh}"
  [ -f "$VM_PATHS" ] || die "no $VM_PATHS: cp $P/vm_paths.example.sh $P/vm_paths.sh and fill it in"
  # shellcheck source=vm_paths.example.sh
  PDK_FIRST=(); VCS_FLAGS=(); IGNORE_CELLS=()
  source "$VM_PATHS"
  if [ -n "${PIN_PATHS_EXTRA:-}" ]; then
    [ -f "$PIN_PATHS_EXTRA" ] || die "PIN_PATHS_EXTRA: no such file: $PIN_PATHS_EXTRA"
    # shellcheck disable=SC1090
    source "$PIN_PATHS_EXTRA"
  fi
  NETLIST="${NETLIST:-}"; SDF="${SDF:-}"     # a vm_paths.sh may leave them out
  # The drop folder wins over whatever vm_paths.sh hard-codes.
  [ -n "${PIN_NETLIST:-}" ]    && NETLIST="$PIN_NETLIST"
  [ -n "${PIN_SDF+x}" ]        && SDF="$PIN_SDF"
  [ -n "${PIN_SDF_CORNER:-}" ] && SDF_CORNER="$PIN_SDF_CORNER"
  SDF_CORNER="${SDF_CORNER:-max}"
  case "$SDF_CORNER" in min|typ|max) ;; *) die "SDF_CORNER must be min, typ or max, not '$SDF_CORNER'";; esac
else
  NETLIST=""; SDF=""; STDCELL_MODELS=(); SRAM_MODELS=(); PAD_MODELS=(); PDK_FIRST=(); IGNORE_CELLS=()
fi
[ "$DUT" = gate ] || SDF=""        # SDF belongs to the netlist only
TIMED=""; [ "$DUT" = gate ] && [ -n "$SDF" ] && TIMED="_sdf${SDF_CORNER}"
# ARM's +define+ARM_UD_MODEL (and its ARM_UD_* companions) selects the models'
# unit-delay branch, which has no specify block: with an SDF every IOPATH and
# timing check of those models goes unannotated.  An SDF build drops them.
UD_DROPPED=()
if [ -n "$TIMED" ] && [ ${#VCS_FLAGS[@]} -gt 0 ]; then
  keep=()
  for f in "${VCS_FLAGS[@]}"; do
    if [[ "$f" =~ ^\+define\+ARM_UD_ ]]; then UD_DROPPED+=("$f"); else keep+=("$f"); fi
  done
  VCS_FLAGS=(${keep[@]+"${keep[@]}"})
fi

# One build per configuration: WAVES=1 (waveform dumping), each SDF corner
# (annotated at compile time) and INITREG live in their own directories, so a
# normal rebuild -- the self-test, vm_run.sh -- cannot replace them unnoticed.
BUILD="${PIN_BUILD:-$R/sim/pin/build/${SIM}_${DUT}${TIMED}${INITREG:+_init$INITREG}${WAVES:+_waves}}"
RUNS="${PIN_RUNS:-$R/sim/pin/runs/${SIM}_${DUT}${TIMED}${INITREG:+_init$INITREG}}"

# ---- source lists ------------------------------------------------------------
# Only directories that exist: a VM unpacked from vm_bundle.tgz has no
# third_party/cvw, and nothing the bench compiles includes from it.
INCS=()
# hdl itself: prim_fifo_async.sv (moved there from third_party/opentitan) does
# `include "prim_assert.sv".
for d in pkg hdl hdl/core hdl/core/ifu/bpred third_party/cvw/config/rv64gc; do
  [ -d "$RTL/$d" ] && INCS+=(+incdir+"$RTL/$d")
done
BENCH=("$P/pin_link_agent.sv" "$P/pin_uart_agent.sv" "$P/pin_cycle_trace.sv" "$P/pin_tb.sv")
LINK_PKG="$RTL/hdl/forte_link_pkg.sv"

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
  mapfile -t core  < <(find "$RTL/hdl/core" \( -name '*.sv' -o -name '*.v' \) ! -name cvw.sv | sort)
  mapfile -t forte < <(find "$RTL/hdl" -maxdepth 1 -name 'forte_*.sv' ! -name forte_link_pkg.sv | sort)
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
  SRCS+=("$RTL/pkg/types.sv" "$LINK_PKG" "$RTL/hdl/core/cvw.sv" "${core[@]}" "${forte[@]}"
         "$RTL/hdl/prim_flop_2sync.sv" "$RTL/hdl/prim_fifo_async.sv"
         "${BENCH[@]}")
}

# IGNORE_CELLS (vm_paths.sh): cell-name globs, e.g. ('FILLCAP*' 'DCAP*'), for
# physical-only cells (fill, decap, tap, endcap) the libraries have no Verilog
# for.  VCS cannot skip an instance, so each matching cell the netlist uses
# gets an empty module in $BUILD/ignored_cells.v -- which also keeps any SDF
# entry for those instances annotatable.  A cell whose instances connect any
# port other than a power/ground pin is refused: it has logic, it needs a model.
IGNORED_V=""
[ ${#IGNORE_CELLS[@]} -gt 0 ] && IGNORED_V="$BUILD/ignored_cells.v"
PG_PORTS='^(VDD|VSS|VCC|GND|VPW|VNW|VPP|VBB|VDDPE|VDDCE|VSSE|VNWELL|VPWELL|VDD[A-Z0-9_]*|VSS[A-Z0-9_]*)$'

ignored_cells() {   # write $IGNORED_V; print one 'build: ignored ...' line per cell
  local re="" g e cell n ports p bad=0 out=()
  for g in "${IGNORE_CELLS[@]}"; do
    e="$(sed -e 's/[][\.^$+(){}|]/\\&/g' -e 's/\*/.*/g' -e 's/?/./g' <<<"$g")"
    re="${re:+$re|}$e"
  done
  re="^($re)\$"
  # One pass over the netlist: each matching cell, its instance count and the
  # port names its instances connect (an instance may span lines up to ';').
  mapfile -t out < <(awk -v re="$re" '
    function emit(   s, q) {
      s = buf
      while (match(s, /\.[A-Za-z_][A-Za-z0-9_]*[ \t]*\(/)) {
        q = substr(s, RSTART + 1, RLENGTH - 1); sub(/[ \t]*\($/, "", q)
        if (!((cell, q) in seen)) { seen[cell, q] = 1; ports[cell] = ports[cell] " " q }
        s = substr(s, RSTART + RLENGTH)
      }
      inst = 0
    }
    inst { buf = buf " " $0; if (index($0, ";")) emit(); next }
    $1 ~ re && $1 != "module" { cell = $1; cnt[cell]++; buf = $0; inst = 1; if (index($0, ";")) emit(); next }
    END { for (c in cnt) print c, cnt[c] ports[c] }' "$NETLIST" | sort)
  [ ${#out[@]} -gt 0 ] || die "IGNORE_CELLS (${IGNORE_CELLS[*]}): the netlist instantiates no such cell"
  mkdir -p "$(dirname "$IGNORED_V")"
  { echo "// generated by hvl/pin/pin.sh from IGNORE_CELLS (${IGNORE_CELLS[*]}): physical-only cells, no logic"
    for l in "${out[@]}"; do
      read -r cell n ports <<<"$l"
      for p in $ports; do
        [[ "$p" =~ $PG_PORTS ]] || { echo "pin.sh: IGNORE_CELLS: $cell connects port $p -- not a power/ground pin, so it is not physical-only: give it a model" >&2; bad=1; }
      done
      if [ -n "$ports" ]; then
        echo "module $cell($(tr ' ' '\n' <<<"$ports" | sed '/^$/d' | paste -sd, -)); input $(tr ' ' '\n' <<<"$ports" | sed '/^$/d' | paste -sd, -); endmodule"
      else
        echo "module $cell(); endmodule"
      fi
    done; } > "$IGNORED_V"
  [ $bad = 0 ] || die "IGNORE_CELLS matches cells with logic (above)"
  for l in "${out[@]}"; do read -r cell n ports <<<"$l"; echo "build: ignored $cell x$n (empty module${ports:+, ports:$ports})"; done
}

gate_sources() {
  pdk_first
  SRCS=("${PDK[@]}" "$LINK_PKG" ${IGNORED_V:+"$IGNORED_V"} "$NETLIST" "${BENCH[@]}")
  DEFS=(+define+PIN_TB_GATE)
  LIBS=()
  for f in "${STDCELL_MODELS[@]}"; do LIBS+=(-v "$f"); done
}

# ---- preflight -----------------------------------------------------------------
preflight() {
  local bad=0
  need() { command -v "$1" >/dev/null || { echo "  MISSING tool: $1"; bad=1; }; }
  isfile() { [ -f "$2" ] || { echo "  MISSING $1: '$2'"; bad=1; }; }
  echo "preflight: SIM=$SIM DUT=$DUT${VM_PATHS:+  paths: $VM_PATHS}"
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
    # (models/sram_behav.sv defines its macros through `PIN_RF_SP(name, ...).)
    # </dev/null: with every model list empty, cat would otherwise wait on the terminal.
    local defs; defs="$(cat /dev/null ${PDK_FIRST[@]+"${PDK_FIRST[@]}"} ${SRAM_MODELS[@]+"${SRAM_MODELS[@]}"} ${PAD_MODELS[@]+"${PAD_MODELS[@]}"} 2>/dev/null </dev/null \
      | grep -oE '^[[:space:]]*(module[[:space:]]+|`PIN_RF_SP\()[A-Za-z0-9_]+' | sed -E 's/.*(module[[:space:]]+|\()//' | sort -u || true)"
    for m in $(grep -oE '^[[:space:]]*((rf|sram)_sp_[0-9]+_[0-9]+|sram_dp_[0-9]+_[0-9]+|io_in|io_out|io_tri)[[:space:]]' "$NETLIST" | sort -u); do
      grep -qx "$m" <<<"$defs" || { echo "  netlist instantiates $m but no model defines it"; bad=1; }
    done
    # The ports the bench connects.
    for p in core_clk rst_n io_in io_out req clk_out wr ready rvalid irq uart_tx uart_rx test_mode scan_en fault_inject status; do
      grep -qw "$p" <<<"$hdr" || { echo "  forte_top in NETLIST has no port $p"; bad=1; }
    done
  fi
  if [ "$SIM" = vcs ] && [ "$DUT" = gate ] && [ ${#STDCELL_MODELS[@]} -gt 1 ]; then
    # -v libraries: VCS takes each cell from the FIRST file that defines it.
    # Several variants of one library (e.g. with and without negative-check
    # support) listed together means the later ones are never used.
    grep -HoE '^[[:space:]]*module[[:space:]]+[A-Za-z_][A-Za-z0-9_]*' "${STDCELL_MODELS[@]}" 2>/dev/null </dev/null \
      | awk -F: '{ n = split($NF, w, /[ \t]+/); m = w[n]; f = $1
                   if (m in owner) { if (owner[m] != f) { shadow[f]++; dup++ } } else { owner[m] = f; mine[f]++ } }
                 END { if (dup) {
                         print "  WARNING " dup " cell definition(s) appear in more than one STDCELL_MODELS file; VCS uses the first file listed:"
                         for (f in mine) if (f in shadow) print "            " f ": its " shadow[f] " duplicate cell(s) are never used"
                         for (f in shadow) if (!(f in mine)) print "            " f ": never used (every cell it defines comes from an earlier file)"
                         print "          Keep one variant of each library: the one whose cells carry the timing checks the SDF has." } }' || true
  fi
  [ $bad = 0 ] && echo "preflight: OK" || die "preflight failed"
}

# ---- build ---------------------------------------------------------------------------
# One hash over every file the build compiles (sources, models, netlist).
# Recorded at build, compared at run: a bundle unpacked since the build keeps
# the PACKING machine's timestamps, so comparing mtimes would miss it.
src_hash() {
  if [ "$DUT" = gate ]; then gate_sources; else rtl_sources; fi
  local f files=()
  for f in "${SRCS[@]}" "${LIBS[@]}"; do [ -f "$f" ] && files+=("$f"); done
  # Included headers are not in SRCS: take every header the include paths hold.
  while IFS= read -r f; do files+=("$f"); done < <(find "$RTL/pkg" "$RTL/hdl" -maxdepth 1 \( -name '*.vh' -o -name '*.svh' -o -name 'prim_assert.sv' \) 2>/dev/null)
  # The SDF, corner and INITREG are compiled in too.
  { sha256sum "${files[@]}" 2>/dev/null | awk '{print $1}'
    # An SDF can be gigabytes: identify it by path, size and mtime, not content.
    [ -n "$SDF" ] && { stat -L -c '%n %s %Y' "$SDF"; echo "corner=$SDF_CORNER"; }
    echo "initreg=$INITREG"; echo "ignore=${IGNORE_CELLS[*]}"; } | sha256sum | awk '{print $1}'
}

build() {
  preflight
  mkdir -p "$BUILD"
  [ "$DUT" = gate ] && [ -n "$IGNORED_V" ] && ignored_cells
  [ ${#UD_DROPPED[@]} -gt 0 ] && echo "build: dropped ${UD_DROPPED[*]} from VCS_FLAGS: unit-delay models have no specify block for the SDF"
  if [ "$DUT" = gate ]; then gate_sources; else rtl_sources; fi
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
    [ -n "${WAVES:-}" ] && xp+=(-debug_access+all -kdb +define+PIN_WAVES)
    local timing=(+nospecify +notimingcheck)
    if [ "$DUT" = gate ] && [ -n "$SDF" ]; then
      # Timing checks ON (no +notimingcheck/+nospecify), negative limits
      # honoured, and every SDF message printed rather than summarised.
      # NTC and RECREM are the cell-model conventions (Artisan/TSMC, NanGate)
      # that switch on the delayed-signal nets negative limits need and the
      # recovery/removal checks: without them a library may compile its
      # timing checks out or ignore negative setup/hold values.
      # -negdelay: post-PnR SDF has negative IOPATH/INTERCONNECT delays (slew
      # effects); without it VCS replaces them with 0 (SDFCOM_NDI).
      timing=(-sdf "$SDF_CORNER:pin_tb.dut:$SDF" +neg_tchk -negdelay +sdfverbose +define+NTC +define+RECREM)
    fi
    [ -n "$INITREG" ] && timing+=(+vcs+initreg+random)
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
  if [ "$SIM" = vcs ] && [ -n "$SDF" ]; then sdf_gate; fi
  src_hash > "$BUILD/srchash"
  echo "build: OK"
}

# The SDF must annotate completely.  Fails the build on:
#   - any VCS SDF message: SDFCOM_* (an SDF instance, port, arc or check it
#     could not find or apply -- delays or checks silently missing) and every
#     other SDF* tag, e.g. SDFPE (a parse error, after which VCS ABORTS the
#     annotation and the build would otherwise run with no delays at all);
#   - an annotation that did not end in "SDF annotation completed" with
#     "Total errors: 0" and "Total warnings: 0", or that VCS reports aborted.
sdf_gate() {
  local bad summ now
  now="$(src_hash)"
  # VCS skips an unchanged design ("need not be recompiled") and prints no
  # annotation at all: accept that only if this exact configuration (sources,
  # netlist, SDF path/size/mtime, corner) annotated cleanly before.
  if grep -q "design hasn't changed and need not be recompiled" "$BUILD/build.log"; then
    if [ "$(cat "$BUILD/sdf_ok" 2>/dev/null)" = "$now" ]; then
      echo "build: SDF $SDF ($SDF_CORNER) unchanged since it annotated completely"
      return 0
    fi
    sdf_fail "VCS did not recompile, and this configuration has no record of a clean annotation"
  fi
  # SDFCOM_UHICD on a wire from a cell pin to one of forte_top's own output
  # ports: VCS cannot annotate a wire that leaves the annotated scope.  Accepted
  # only when every one is exactly that -- each message's SDF line is checked --
  # because postpnr/run.sh measures those wires (postpnr/sdf_out_wires.py) and
  # tightens the output-window check by the largest.  Any other SDF message fails.
  local uh_n uh_lines uh_badl
  uh_n="$(grep -c 'Warning-\[SDFCOM_UHICD\]' "$BUILD/build.log" || true)"
  if [ "$uh_n" -gt 0 ]; then
    uh_lines="$(grep -A1 'Warning-\[SDFCOM_UHICD\]' "$BUILD/build.log" | grep -oE ', [0-9]+[[:space:]]*$' | tr -dc '0-9\n')"
    [ "$(grep -c . <<<"$uh_lines")" = "$uh_n" ] \
      || sdf_fail "$uh_n SDFCOM_UHICD message(s), but could not read the SDF line of each ($BUILD/build.log)"
    uh_badl="$(awk -v div="$(grep -m1 -oE '\(DIVIDER[[:space:]]+[^[:space:])]' "$SDF" | awk '{print $2}')" '
        NR == FNR { want[$1] = 1; next }
        FNR in want {
          ok = 0
          if (match($0, /^[[:space:]]*\(INTERCONNECT[[:space:]]+/)) {
            n = split(substr($0, RLENGTH + 1), t, /[[:space:]]+/)
            src = t[1]; dst = t[2]; sub(/^\\/, "", dst); port = dst; sub(/\[[0-9]+\]$/, "", port)
            if (div == "") div = "/"
            if (index(src, div) && !index(dst, div) && port ~ /^(io_out|req|wr|uart_tx|status|clk_out)$/) ok = 1
          }
          if (!ok) print FNR
        }' <(echo "$uh_lines") "$SDF" | head -5)"
    [ -z "$uh_badl" ] \
      || sdf_fail "SDFCOM_UHICD on SDF line(s) $(echo $uh_badl) that are not a wire into a forte_top output port"
  fi
  bad="$(grep -E '(Warning|Error)-\[SDF[A-Z0-9_]*\]' "$BUILD/build.log" | grep -v 'Warning-\[SDFCOM_UHICD\]' || true)"
  if [ -n "$bad" ]; then
    awk '/(Warning|Error)-\[SDF[A-Z0-9_]*\]/ { show = ($0 !~ /SDFCOM_UHICD/); left = 5 }
         show && left-- > 0' "$BUILD/build.log" | head -40 | sed 's/^/  | /' >&2
    sdf_fail "$(wc -l <<<"$bad") SDF message(s): $(grep -oE 'SDF[A-Z0-9_]*' <<<"$bad" | sort | uniq -c | awk '{printf "%s x%s ", $2, $1}')(first above; all in $BUILD/build.log)"
  fi
  summ="$(sed -n '/SDF annotation begin/,/SDF annotation \(completed\|aborted\)/p' "$BUILD/build.log")"
  if [ -z "$summ" ] || grep -q 'SDF annotation aborted' <<<"$summ" || ! grep -q 'SDF annotation completed' <<<"$summ" \
     || ! grep -qE 'Total errors: +0$' <<<"$summ" || ! grep -qE "Total warnings: +(0|$uh_n)\$" <<<"$summ"; then
    echo "$summ" | tail -12 | sed 's/^/  | /' >&2
    sdf_fail "annotation of $SDF did not complete cleanly (above; $BUILD/build.log)"
  fi
  echo "$now" > "$BUILD/sdf_ok"
  if [ "$uh_n" -gt 0 ]; then
    echo "build: SDF $SDF ($SDF_CORNER) annotated completely: 0 errors; $uh_n SDFCOM_UHICD, each a wire into a forte_top output port (run.sh compensates), no other SDF* message"
  else
    echo "build: SDF $SDF ($SDF_CORNER) annotated completely: 0 errors, 0 warnings, no SDF* messages"
  fi
}

# A failed annotation leaves no runnable build, and makes VCS recompile next
# time instead of calling the design unchanged.
sdf_fail() {
  rm -f "$BUILD/srchash" "$BUILD/sdf_ok" "$BUILD/simv.daidir/.vcs.timestamp"
  die "SDF annotation: $*"
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
  # The bench and RTL are compiled into the executable: if any source differs
  # from what it was built from (a new bundle unpacked, an edit), the run would
  # test the OLD code.
  if [ "$(cat "$BUILD/srchash" 2>/dev/null)" != "$(src_hash)" ]; then
    die "sources differ from what $exe was built from -- rebuild: ${WAVES:+WAVES=1 }SIM=$SIM DUT=$DUT $0 build"
  fi
  # +PIN_VCD only works in a WAVES=1 build; without one it would be ignored.
  local a vcd=0
  local fsdb=0
  for a in "$@"; do [ "$a" = +PIN_VCD ] && vcd=1; [ "$a" = +PIN_FSDB ] && fsdb=1; done
  if [ $((vcd + fsdb)) -gt 0 ] && [ "$SIM" = vcs ] && ! grep -q PIN_WAVES "$BUILD/build.cmd" 2>/dev/null; then
    die "+PIN_VCD/+PIN_FSDB need a waveform build: WAVES=1 SIM=$SIM DUT=$DUT $0 build, then run with WAVES=1 too"
  fi
  [ $fsdb = 1 ] && [ "$SIM" != vcs ] && die "+PIN_FSDB is VCS only (use +PIN_VCD under Verilator)"
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
  [ -n "$INITREG" ] && args+=(+vcs+initreg+"$INITREG")
  ( cd "$run" && "$exe" "${args[@]}" +FPGA_TRACE="$run/pin_trace.log" +UART_LOG="$run/uart.log" \
      +PIN_CYCLE_TRACE="$run/pin_cycle.log" "$@" ) \
    > "$run/sim.log" 2>&1 || true
  [ -f "$run/pin_cycle.log" ] && gzip -f "$run/pin_cycle.log"
  [ $vcd = 1 ] && { [ -s "$run/pin.vcd" ] && echo "waveform: $run/pin.vcd" || echo "pin.sh: WARNING +PIN_VCD given but no $run/pin.vcd was written" >&2; }
  [ $fsdb = 1 ] && { [ -s "$run/wave.fsdb" ] && echo "waveform: $run/wave.fsdb  (verdi -ssf $run/wave.fsdb)" || echo "pin.sh: WARNING +PIN_FSDB given but no $run/wave.fsdb was written" >&2; }
  # No verdict line: a $fatal in the DESIGN (its own assertions) ends the run
  # before the bench can print one.  Name it rather than calling it a crash.
  local res; res="$(grep -m1 '^PIN_TB_RESULT:' "$run/sim.log" || true)"
  if [ -z "$res" ]; then
    local fat; fat="$(grep -m1 -A1 -E '^Fatal:|%Fatal|Error:.*Assertion' "$run/sim.log" | tr '\n' ' ' | cut -c1-220)"
    if [ -n "$fat" ]; then res="PIN_TB_RESULT: FAIL design \$fatal: $fat"
    else res="PIN_TB_RESULT: FAIL no verdict (crash or killed; see $run/sim.log)"; fi
  fi
  # Timing checks: a violation is a failure however the bench ended.
  local nv nw=0 viol
  nv="$(grep -c 'Timing violation' "$run/sim.log" || true)"
  if [ "$nv" -gt 0 ]; then
    viol="$(grep -A2 'Timing violation' "$run/sim.log" | grep -v '^--$')"
    if [ -n "${PIN_WAIVERS:-}" ] && [ -s "$PIN_WAIVERS" ]; then
      local pats; pats="$(grep -vE '^[[:space:]]*(#|$)' "$PIN_WAIVERS" || true)"
      if [ -n "$pats" ]; then
        nw="$(grep 'Timing violation' "$run/sim.log" | grep -cEf <(echo "$pats") || true)"
        grep 'Timing violation' "$run/sim.log" | grep -Ef <(echo "$pats") > "$run/TCHK_WAIVED" || true
      fi
    fi
    echo "$viol" | head -60 > "$run/TCHK"
    if [ $((nv - nw)) -gt 0 ]; then
      local wv=""; [ "$nw" -gt 0 ] && wv=" ($nw waived)"
      # Never the word PASS in a FAIL line: callers grep for it.
      local bench="${res#PIN_TB_RESULT: }"; [[ "$bench" == PASS* ]] && bench="functionally ok"
      res="PIN_TB_RESULT: FAIL $((nv - nw)) timing violation(s)$wv; bench: $bench"
    fi
  fi
  echo "tchk=$nv waived=$nw" > "$run/TCHK_COUNT"
  [ -n "$INITREG" ] && res="$res [INITREG=$INITREG: not sign-off]"
  echo "$res" | tee "$run/RESULT"
  grep -E '^\[PIN_TB\] cycles=|ERROR' "$run/sim.log" | head -20 || true
  [[ "$res" == "PIN_TB_RESULT: PASS"* ]]
}

case "${1:-}" in
  preflight) preflight;;
  build)     build;;
  run)       shift; run "$@";;
  compare)   shift; python3 "$R/bin/pin_trace_cmp.py" "$@";;
  build-dir) echo "$BUILD";;
  runs-dir)  echo "$RUNS";;
  *)         sed -n '2,/^set -euo pipefail/{/^set -euo/d;p}' "$0"; exit 1;;
esac
