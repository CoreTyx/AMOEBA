#!/usr/bin/env bash
# DFT hold/resume regression on the pin bench: programs with holds in the
# middle must finish with the same link traffic as without them.
#
#   JOBS=2 hvl/pin/hold_regress.sh                     RTL, Verilator (no netlist)
#   SIM=vcs DUT=gate hvl/pin/hold_regress.sh           the netlist in vm_paths.sh,
#                                                      with its SDF if it sets one
# Environment:
#   SIM, DUT          as pin.sh (default verilator, rtl)
#   HOLD_CORNERS      gate with an SDF: the corners to run, e.g. "min max"
#                     (default min: hold checks)
#   HOLD_IGNORE_NIOD=1  SDF builds: SDFCOM_NIOD counted, not failed (not sign-off)
#   HOLD_PROGRAMS     the programs (default basic_arith, sorting_algo, hold_state)
#   HOLD_IRQ=0        skip the interrupt case
#   PIN_VM_PATHS      as pin.sh
# Each held run is compared (--no-cycles) with an unheld run of the SAME build,
# so a gate run needs no RTL golden.  With an SDF, pin.sh fails a run on any
# timing-check violation, and the build on any SDF message sdf_msgs.sh does not
# accept.  SUMMARY lines carry no cell, model or SDF text.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
export SIM=${SIM:-verilator} DUT=${DUT:-rtl} JOBS=${JOBS:-1} CCACHE_DISABLE=${CCACHE_DISABLE:-1}
OUT="$ROOT/sim/pin/hold_regress/$(date +%Y%m%d_%H%M%S)_$$_${SIM}_${DUT}"
mkdir -p "$OUT"
exec > >(tee "$OUT/regress.log") 2>&1
echo "Results: $OUT"
if git -C "$ROOT" rev-parse HEAD > "$OUT/revision" 2>/dev/null; then
  git -C "$ROOT" diff --binary > "$OUT/changes.patch" || true
  git -C "$ROOT" ls-files -z hdl pkg hvl/pin | xargs -0 sha256sum > "$OUT/sources.sha256" || true
else
  echo "(not a git checkout)" > "$OUT/revision"
fi
if [[ $SIM == verilator ]]; then verilator --version > "$OUT/tool.txt"; else vcs -ID > "$OUT/tool.txt" 2>&1 || true; fi
sha256sum hvl/pin/hold_regress.sh hvl/pin/tests/hold_state.c hvl/pin/tests/irq_hold.cmd >> "$OUT/sources.sha256"
PIN=hvl/pin/pin.sh

# The gate build's SDF, if any: prepared once (sdf_prep.sh), one build per corner.
CORNERS=("")
if [[ $DUT == gate ]]; then
  VMP="${PIN_VM_PATHS:-$ROOT/hvl/pin/vm_paths.sh}"
  [[ -f $VMP ]] || { echo "no $VMP"; exit 1; }
  sdf_src=$(PDK_FIRST=(); STDCELL_MODELS=(); SDF=""; source "$VMP" >/dev/null 2>&1; echo "${PIN_SDF:-$SDF}")
  if [[ -n $sdf_src ]]; then
    read -r -a CORNERS <<<"${HOLD_CORNERS:-min}"
    models=$(PDK_FIRST=(); STDCELL_MODELS=(); SRAM_MODELS=(); PAD_MODELS=(); source "$VMP" >/dev/null 2>&1
             for m in "${STDCELL_MODELS[@]}" "${SRAM_MODELS[@]}" "${PAD_MODELS[@]}"; do
               if [[ -d $m ]]; then ls "$m"/*.v "$m"/*.sv 2>/dev/null; else echo "$m"; fi; done)
    mapfile -t MODEL_FILES <<<"$models"
    PIN_SDF=$(bash hvl/pin/sdf_prep.sh "$sdf_src" "$ROOT/sim/pin/sdf" "${MODEL_FILES[@]}")
    export PIN_SDF
    [[ ${HOLD_IGNORE_NIOD:-0} == 1 ]] && export PIN_SDF_IGNORE_NIOD=1 && echo "NOTE: SDFCOM_NIOD ignored: not a sign-off run" | tee -a "$OUT/SUMMARY"
  else
    echo "NOTE: gate netlist without an SDF: zero-delay" | tee -a "$OUT/SUMMARY"
  fi
fi

CMD="$OUT/holds.cmd"
cat > "$CMD" <<'EOF'
load_lst $MEM
reset 16
EOF
# Entry offsets include back-to-back sessions, cold-cache startup and execution.
gaps=(0 1 2 3 7 31 127 509 1021 4093 8191 16381 50000 100003 250001 7)
lengths=(1 2 3 17 200 1000 1 50 5000 3 31 200 127 4096 1 31)
for i in "${!gaps[@]}"; do
    printf 'run %s\ndft_hold %s\n' "${gaps[i]}" "${lengths[i]}" >> "$CMD"
done
cat >> "$CMD" <<'EOF'
run_until_tohost 8000000
expect_tohost 0
run 10000
finish
EOF
BASE_CMD="$OUT/reference.cmd"
cat > "$BASE_CMD" <<'EOF'
load_lst $MEM
reset 16
run_until_tohost 8000000
expect_tohost 0
# Drain the exit fence's remaining writebacks after tohost becomes visible.
run 10000
finish
EOF
read -r -a PROGRAMS <<<"${HOLD_PROGRAMS:-testcode/baremetal/basic_arith.c testcode/baremetal/sorting_algo.c hvl/pin/tests/hold_state.c}"
# Without a RISC-V compiler (the VCS VMs), run the prebuilt images in
# hvl/pin/hold_images/ (same name, .lst; rebuild them on EWS with
# bin/generate_memory_file.py -8 when a program changes).
HAVE_CC=0
for cc in riscv64-unknown-elf-gcc riscv64-elf-gcc riscv64-linux-gnu-gcc; do command -v $cc >/dev/null && HAVE_CC=1; done
image() {   # image <program>: the program, or its prebuilt .lst
  local n; n=$(basename "${1%.*}")
  if [[ $HAVE_CC == 0 || ${HOLD_PREBUILT:-0} == 1 ]] && [[ -f hvl/pin/hold_images/$n.lst ]]; then echo "hvl/pin/hold_images/$n.lst"; else echo "$1"; fi
}
[[ $HAVE_CC == 1 && ${HOLD_PREBUILT:-0} != 1 ]] || echo "NOTE: prebuilt images from hvl/pin/hold_images/" | tee -a "$OUT/SUMMARY"
failed=0
for corner in "${CORNERS[@]}"; do
  if [[ -n $corner ]]; then
    export PIN_SDF_CORNER=$corner
    label="sdf $corner"
  else
    unset PIN_SDF_CORNER; label="${SIM}/${DUT}"
  fi
  sfx=${corner:+_$corner}
  "$PIN" build > "$OUT/build$sfx.log" 2>&1 || { echo "FAIL build ($label): see $OUT/build$sfx.log" | tee -a "$OUT/SUMMARY"; failed=1; continue; }
  grep -E '^build: (SDF|--ignore|dropped)' "$OUT/build$sfx.log" | sed "s|$ROOT/||g; s|SDF /[^ ]*|SDF|" || true
  RUNS=$("$PIN" runs-dir)
  for program in "${PROGRAMS[@]}"; do
    name=$(basename "${program%.*}")
    for profile in fast gapped; do
        args=(+FPGA_GAP_PCT=0 +FPGA_RD_LAT=0 +DFT_HOLD_SE=0)
        if [[ $profile == gapped ]]; then
            # scan_en high through the hold shifts every scan chain.  On RTL the
            # chains are one-flop placeholders, so that only exercises the
            # hold logic; on a scan-inserted netlist it shifts the real PC and
            # pipeline registers with nothing reloaded, which corrupts the
            # program by design.  Gate runs hold with scan_en low; shifting
            # with a reload is full_tb phase S.
            se=1; [[ $DUT == gate ]] && se=0
            args=(+FPGA_GAP_PCT=25 +FPGA_RD_LAT=7 +DFT_HOLD_SE=$se)
        fi
        base="$RUNS/${name}_hold_${profile}_base"
        held="$RUNS/${name}_hold_${profile}_held"
        status=PASS
        TAG="hold_${profile}_base" "$PIN" run "$(image "$program")" "$BASE_CMD" "${args[@]}" > "$OUT/${name}_${profile}${sfx}_base.log" 2>&1 || status=FAIL
        TAG="hold_${profile}_held" "$PIN" run "$(image "$program")" "$CMD" "${args[@]}" > "$OUT/${name}_${profile}${sfx}_held.log" 2>&1 || status=FAIL
        holds=$(zcat -f "$held/sim.log" 2>/dev/null | grep -c '^\[PIN_TB\] dft_hold ' || true)
        tchk=$(zcat -f "$base/sim.log" "$held/sim.log" 2>/dev/null | grep -c 'Timing violation' || true)
        [[ $holds == "${#gaps[@]}" ]] || status=FAIL
        [[ $tchk == 0 ]] || status=FAIL
        "$PIN" compare --no-cycles "$base" "$held" > "$OUT/${name}_${profile}${sfx}_compare.log" 2>&1 || status=FAIL
        for f in sim.log pin_trace.log; do
          [[ -f $base/$f ]] && cp "$base/$f" "$OUT/${name}_${profile}${sfx}_base_$f"
          [[ -f $held/$f ]] && cp "$held/$f" "$OUT/${name}_${profile}${sfx}_held_$f"
        done
        echo "$status $label $name $profile: $holds/${#gaps[@]} holds, timing violations $tchk, program exit and ordered link trace vs unheld" | tee -a "$OUT/SUMMARY"
        [[ $status == PASS ]] || failed=1
    done
  done
  if [[ ${HOLD_IRQ:-1} == 1 ]]; then
    status=PASS
    base="$RUNS/irq_hold_irq_base"
    held="$RUNS/irq_hold_irq_held"
    TAG=hold_irq_base "$PIN" run "$(image hvl/pin/tests/irq.c)" hvl/pin/tests/irq.cmd > "$OUT/irq${sfx}_base.log" 2>&1 || status=FAIL
    TAG=hold_irq_held "$PIN" run "$(image hvl/pin/tests/irq.c)" hvl/pin/tests/irq_hold.cmd > "$OUT/irq${sfx}_held.log" 2>&1 || status=FAIL
    holds=$(zcat -f "$held/sim.log" 2>/dev/null | grep -c '^\[PIN_TB\] dft_hold ' || true)
    tchk=$(zcat -f "$base/sim.log" "$held/sim.log" 2>/dev/null | grep -c 'Timing violation' || true)
    [[ $holds == 4 ]] || status=FAIL
    [[ $tchk == 0 ]] || status=FAIL
    "$PIN" compare --no-cycles "$base" "$held" > "$OUT/irq${sfx}_compare.log" 2>&1 || status=FAIL
    cmp "$base/uart.log" "$held/uart.log" > "$OUT/irq${sfx}_uart_compare.log" 2>&1 || status=FAIL
    echo "$status $label irq: $holds/4 holds, timing violations $tchk, level IRQ service, ordered link trace and UART bytes vs unheld" | tee -a "$OUT/SUMMARY"
    [[ $status == PASS ]] || failed=1
  fi
done
echo "Logs: $OUT"
exit "$failed"
