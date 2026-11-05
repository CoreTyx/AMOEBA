#!/usr/bin/env bash
# fi_always.sh -- the design under continuous fault injection, from its pins.
#
#   hvl/pin/fi_always.sh            the vectors, then the whole matrix
#   hvl/pin/fi_always.sh vectors    the vectors only
#
# Every ISA-level and baremetal_ecc program, armed by bin/fi_arm_lst.py with
# fault_inject held high, at three link settings: it must pass, with the console
# of its unarmed run.  RF ECC (0x5F) and pipeline ECC (0x6F) take turns: armed
# together, the pipeline flip's EccStallE drops the read carrying the RF flip.
# tc_fault_control is left out: it checks FI_CONTROL is 0 after reset.
#
# Failures here depend on exact timing, which a different compiler moves, so
# tests/vectors/ keeps built images that once failed:
#   tc_pmp_deny_arm5f.lst  tc_pmp_deny armed 0x5F, at g10s4l7.  An I$ ECC repair
#                          flushed in its write cycle landed in the flush
#                          target's set; a later fetch hit it and ran another
#                          function's code, and the test trapped forever.
# Timing also moves with the RTL, so a vector can stop reaching its coincidence
# without failing: hvl/cache/icache_ecc_flush_tb.sv is that bug's direct test.
#
# One simulation at a time: the bench shares sim/bin/memory_8.lst.
set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RUNS="$R/sim/pin/runs/verilator_rtl"
OUT="$R/sim/pin/fi_always"
SCRIPT="$R/hvl/pin/tests/fi_always.cmd"

KNOBS=(
  "g30s1|+FPGA_GAP_PCT=30 +FPGA_SEED=1"
  "g60s3|+FPGA_GAP_PCT=60 +FPGA_SEED=3"
  "g10s4l7|+FPGA_GAP_PCT=10 +FPGA_SEED=4 +FPGA_RD_LAT=7"
)

pass=0
failed=()

report() {   # ok(0/1) name detail
  if [ "$1" = 1 ]; then
    pass=$((pass + 1))
    printf 'ok   %-44s %s\n' "$2" "$3"
  else
    failed+=("$2")
    printf 'FAIL %-44s %s\n' "$2" "$3"
  fi
}

verdict_of() { grep -o 'PIN_TB_RESULT: .*' "$1" | head -1 | cut -d' ' -f2-; }

# A run cut at tohost cuts the console wherever the UART is; compare what both have.
same_console_prefix() {
  local a b
  a=$(stat -c%s "$1")
  b=$(stat -c%s "$2")
  cmp -s -n "$((a < b ? a : b))" "$1" "$2"
}

armed_run() {   # dir image -- plusargs; leaves run.log and uart.log in dir
  local d="$1" image="$2"
  shift 2
  mkdir -p "$d"
  "$R/hvl/pin/pin.sh" run "$image" "$SCRIPT" "$@" > "$d/run.log" 2>&1
  cp "$RUNS/$(basename "${image%.*}")/uart.log" "$d/" 2>/dev/null
}

vector_tests() {
  local d="$OUT/vectors/tc_pmp_deny_arm5f" v
  rm -rf "$d"
  armed_run "$d" "$R/hvl/pin/tests/vectors/tc_pmp_deny_arm5f.lst" +FPGA_GAP_PCT=10 +FPGA_SEED=4 +FPGA_RD_LAT=7
  v=$(verdict_of "$d/run.log")
  [ "$v" = PASS ] && report 1 vectors/tc_pmp_deny_arm5f "$v" || report 0 vectors/tc_pmp_deny_arm5f "${v:-no verdict}"
}

matrix_tests() {
  local image base off d arm k name args v ok
  for image in "$R"/testcode/isa_level_testing/tc_*.c "$R"/testcode/isa_level_testing/tcf_*.c "$R"/testcode/baremetal_ecc/tc_*.c; do
    base="$(basename "${image%.*}")"
    [ "$base" = tc_fault_control ] && continue
    off="$OUT/$base/off"
    rm -rf "$OUT/$base"
    mkdir -p "$off"
    "$R/hvl/pin/pin.sh" run "$image" > "$off/run.log" 2>&1
    cp "$RUNS/$base"/{memory.lst,uart.log} "$off/" 2>/dev/null
    v=$(verdict_of "$off/run.log")
    if [ "$v" != PASS ]; then
      report 0 "$base/off" "${v:-no verdict}"
      continue
    fi
    for arm in 0x5F 0x6F; do
      for k in "${KNOBS[@]}"; do
        IFS='|' read -r name args <<<"$k"
        d="$OUT/$base/$arm-$name"
        mkdir -p "$d"
        python3 "$R/bin/fi_arm_lst.py" "$off/memory.lst" "$d/armed.lst" "$arm"
        # shellcheck disable=SC2086
        armed_run "$d" "$d/armed.lst" $args
        v=$(verdict_of "$d/run.log")
        ok=1
        [ "$v" = PASS ] || ok=0
        same_console_prefix "$off/uart.log" "$d/uart.log" || { ok=0; v="$v, console differs"; }
        report $ok "$base/$arm-$name" "${v:-no verdict}"
      done
    done
  done
}

mkdir -p "$OUT"
SIM=verilator DUT=rtl "$R/hvl/pin/pin.sh" build > "$OUT/build.log" 2>&1 \
  || { tail -20 "$OUT/build.log"; exit 2; }

vector_tests
[ "${1:-}" = vectors ] || matrix_tests

echo "fi_always: $pass passed, ${#failed[@]} failed"
if [ ${#failed[@]} != 0 ]; then
  printf '  %s\n' "${failed[@]}"
  exit 1
fi
