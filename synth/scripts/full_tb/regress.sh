#!/bin/bash
# Sequential full_tb regression. Optional --unload-reset compares readout modes.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SIM_DIR="$SCRIPT_DIR/sim"
RESULTS="$SCRIPT_DIR/regressions/$(date +%Y%m%d_%H%M%S)_$$"
mode=standard
if (($# == 1)) && [[ "$1" == --unload-reset ]]; then
    mode=unload_reset
elif (($# != 0)); then
    echo "Usage: $0 [--unload-reset] (reads paths.sh beside run.sh)" >&2
    exit 1
fi
[[ -f "$SCRIPT_DIR/paths.sh" ]] || { echo "Create $SCRIPT_DIR/paths.sh first" >&2; exit 1; }
mkdir -p "$RESULTS" "$SIM_DIR"
printf 'test\tresult\texit_code\tseconds\tverdict\n' > "$RESULTS/summary.tsv"
passed=0
failed=0
partial=0

# Preserve logs from the invocation preceding this regression.
for file in run.log compile.log sim.log; do
    if [[ -f "$SIM_DIR/$file" ]]; then
        mkdir -p "$RESULTS/preexisting"
        cp "$SIM_DIR/$file" "$RESULTS/preexisting/"
    fi
done

run_case() {
    local name="$1"
    shift
    local dest="$RESULTS/$name" rc status verdict file started=$SECONDS
    mkdir -p "$dest"
    printf 'cd %q\n' "$PWD" > "$dest/command.sh"
    printf 'bash %q ' "$SCRIPT_DIR/run.sh" >> "$dest/command.sh"
    printf '%q ' "$@" >> "$dest/command.sh"
    printf '\n' >> "$dest/command.sh"
    # A compile/setup failure must not inherit the previous simulation verdict.
    rm -f "$SIM_DIR/run.log" "$SIM_DIR/compile.log" "$SIM_DIR/sim.log"
    echo "Running $name ..."
    if bash "$SCRIPT_DIR/run.sh" "$@" > "$dest/console.log" 2>&1; then
        rc=0
    else
        rc=$?
    fi
    for file in run.log compile.log sim.log; do
        [[ ! -f "$SIM_DIR/$file" ]] || cp "$SIM_DIR/$file" "$dest/"
    done
    verdict="No simulation verdict; inspect console.log and compile.log"
    if [[ -f "$dest/sim.log" ]]; then
        verdict=$(grep -E '^DFT TB (PASS|FAIL)' "$dest/sim.log" | tail -1 || true)
        verdict=${verdict:-No simulation verdict; inspect console.log and compile.log}
        grep -E '^PHASE:|H: [0-9]+ checks' "$dest/sim.log" > "$dest/phases.txt" || true
    fi
    if ((rc != 0)) || [[ "$verdict" != "DFT TB PASS"* ]]; then
        status=FAIL
        failed=$((failed + 1))
    elif [[ "$verdict" == *"partial coverage"* ]]; then
        status=PARTIAL
        partial=$((partial + 1))
    else
        status=PASS
        passed=$((passed + 1))
    fi
    printf '%s\t%s\t%d\t%d\t%s\n' "$name" "$status" "$rc" "$((SECONDS-started))" "$verdict" >> "$RESULTS/summary.tsv"
    printf '  %-7s %s\n' "$status" "$verdict"
}

echo "Results: $RESULTS"
echo "Mode: $mode"
if [[ "$mode" == unload_reset ]]; then
    run_case 01_baseline_control +SCAN_PHASES=E '+SCAN_CASE=E reset value' +SCAN_OP=both
    run_case 02_baseline_reset   +SCAN_PHASES=E '+SCAN_CASE=E reset value' +SCAN_OP=both +SCAN_UNLOAD_RESET
    run_case 03_pp2_control      +SCAN_PHASES=P '+SCAN_CASE=PP2Reg all 1' +SCAN_OP=both
    run_case 04_pp2_reset        +SCAN_PHASES=P '+SCAN_CASE=PP2Reg all 1' +SCAN_OP=both +SCAN_UNLOAD_RESET
    run_case 05_csrval_control   +SCAN_PHASES=P '+SCAN_CASE=CSRValWReg all 1' +SCAN_OP=both
    run_case 06_csrval_reset     +SCAN_PHASES=P '+SCAN_CASE=CSRValWReg all 1' +SCAN_OP=both +SCAN_UNLOAD_RESET
    run_case 07_randinstr_control +SCAN_PHASES=P '+SCAN_CASE=RANDINSTRFREQreg all 1' +SCAN_OP=both
    run_case 08_randinstr_reset   +SCAN_PHASES=P '+SCAN_CASE=RANDINSTRFREQreg all 1' +SCAN_OP=both +SCAN_UNLOAD_RESET
    # Nonzero captured fault flags must survive the reset-protected readout.
    run_case 09_hardening_reset  +SCAN_PHASES=H +SCAN_OP=both +SCAN_SENTINEL +SCAN_UNLOAD_RESET
else
    # Protect nonscan logic during destructive readout. Capture expectations
    # are unchanged; longer retention experiments are outside this regression.
    run_case 01_baseline_repeat +SCAN_PHASES=E '+SCAN_CASE=E reset value' +SCAN_OP=both +SCAN_REPEAT=5 +SCAN_UNLOAD_RESET
    run_case 02_pc_load         +SCAN_PHASES=E +SCAN_OP=load +SCAN_UNLOAD_RESET
    run_case 03_baseline_capture +SCAN_PHASES=D +SCAN_OP=both +SCAN_UNLOAD_RESET
    run_case 04_pc_capture      +SCAN_PHASES=E +SCAN_OP=both +SCAN_UNLOAD_RESET
    run_case 05_registers       +SCAN_PHASES=P +SCAN_OP=both +SCAN_UNLOAD_RESET
    # H injects faults through scan and checks their effects after capture.
    run_case 06_fault_injection +SCAN_PHASES=H +SCAN_OP=both +SCAN_SENTINEL +SCAN_UNLOAD_RESET
    run_case 07_reset_recovery  +SCAN_PHASES=F +SCAN_OP=both +SCAN_UNLOAD_RESET
    run_case 08_full_suite      +SCAN_OP=both +SCAN_UNLOAD_RESET
fi

echo
cat "$RESULTS/summary.tsv"
printf '\nPASS=%d FAIL=%d PARTIAL=%d\nResults: %s\n' "$passed" "$failed" "$partial" "$RESULTS"
if ((failed > 0)); then exit 1; fi
if ((partial > 0)); then exit 2; fi
exit 0
