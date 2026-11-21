#!/usr/bin/env bash
# Native RTL hold/resume regression. No netlist or private libraries required.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
cd "$ROOT"
export SIM=verilator DUT=rtl JOBS=${JOBS:-1} CCACHE_DISABLE=${CCACHE_DISABLE:-1}
OUT="$ROOT/sim/pin/hold_regress/$(date +%Y%m%d_%H%M%S)_$$"
mkdir -p "$OUT"
exec > >(tee "$OUT/regress.log") 2>&1
echo "Results: $OUT"
git rev-parse HEAD > "$OUT/revision"
git diff --binary > "$OUT/changes.patch"
verilator --version > "$OUT/tool.txt"
git ls-files -z hdl pkg hvl/pin | xargs -0 sha256sum > "$OUT/sources.sha256"
sha256sum hvl/pin/hold_regress.sh hvl/pin/tests/hold_state.c hvl/pin/tests/irq_hold.cmd >> "$OUT/sources.sha256"
PIN=hvl/pin/pin.sh
"$PIN" build > "$OUT/build.log" 2>&1
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
failed=0
for program in testcode/baremetal/basic_arith.c testcode/baremetal/sorting_algo.c hvl/pin/tests/hold_state.c; do
    name=$(basename "${program%.*}")
    for profile in fast gapped; do
        args=(+FPGA_GAP_PCT=0 +FPGA_RD_LAT=0 +DFT_HOLD_SE=0)
        if [[ $profile == gapped ]]; then
            args=(+FPGA_GAP_PCT=25 +FPGA_RD_LAT=7 +DFT_HOLD_SE=1)
        fi
        base="sim/pin/runs/verilator_rtl/${name}_hold_${profile}_base"
        held="sim/pin/runs/verilator_rtl/${name}_hold_${profile}_held"
        status=PASS
        TAG="hold_${profile}_base" "$PIN" run "$program" "$BASE_CMD" "${args[@]}" > "$OUT/${name}_${profile}_base.log" 2>&1 || status=FAIL
        TAG="hold_${profile}_held" "$PIN" run "$program" "$CMD" "${args[@]}" > "$OUT/${name}_${profile}_held.log" 2>&1 || status=FAIL
        [[ $(grep -c '^\[PIN_TB\] dft_hold ' "$held/sim.log" || true) == "${#gaps[@]}" ]] || status=FAIL
        "$PIN" compare --no-cycles "$base" "$held" > "$OUT/${name}_${profile}_compare.log" 2>&1 || status=FAIL
        cp "$base/sim.log" "$OUT/${name}_${profile}_base_sim.log"
        cp "$held/sim.log" "$OUT/${name}_${profile}_held_sim.log"
        cp "$base/pin_trace.log" "$OUT/${name}_${profile}_base_trace.log"
        cp "$held/pin_trace.log" "$OUT/${name}_${profile}_held_trace.log"
        echo "$status $name $profile: ${#gaps[@]} holds, program exit, ordered pin trace" | tee -a "$OUT/SUMMARY"
        [[ $status == PASS ]] || failed=1
    done
done
status=PASS
base=sim/pin/runs/verilator_rtl/irq_hold_irq_base
held=sim/pin/runs/verilator_rtl/irq_hold_irq_held
TAG=hold_irq_base "$PIN" run hvl/pin/tests/irq.c hvl/pin/tests/irq.cmd > "$OUT/irq_base.log" 2>&1 || status=FAIL
TAG=hold_irq_held "$PIN" run hvl/pin/tests/irq.c hvl/pin/tests/irq_hold.cmd > "$OUT/irq_held.log" 2>&1 || status=FAIL
[[ $(grep -c '^\[PIN_TB\] dft_hold ' "$held/sim.log" || true) == 4 ]] || status=FAIL
"$PIN" compare --no-cycles "$base" "$held" > "$OUT/irq_compare.log" 2>&1 || status=FAIL
cmp "$base/uart.log" "$held/uart.log" > "$OUT/irq_uart_compare.log" 2>&1 || status=FAIL
for kind in base held; do
    run="$base"; [[ $kind != held ]] || run="$held"
    for file in sim.log pin_trace.log uart.log; do cp "$run/$file" "$OUT/irq_${kind}_${file}"; done
done
echo "$status irq: 4 holds, level IRQ service, ordered pin trace and UART bytes" | tee -a "$OUT/SUMMARY"
[[ $status == PASS ]] || failed=1
echo "Logs: $OUT"
exit "$failed"
