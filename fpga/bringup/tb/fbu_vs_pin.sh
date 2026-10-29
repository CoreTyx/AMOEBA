#!/usr/bin/env bash
# fbu_vs_pin.sh -- the bring-up gateware against the pin bench
# (docs/impl_plan_fpga_rtl_freeze.md s8.1).
#
#   fpga/bringup/tb/fbu_vs_pin.sh [image ...]     (default: the full set)
#
# Link runs: each image at each knob set, on the bench (hvl/pin/pin.sh) and on
# tb_fbu_vs_pin with the bench's own memory.lst; the pin traces must match
# cycle for cycle.  E records compare by cycle (the bench prints prose, the
# gateware an error code).
#
# Script runs: the bench's command scripts.  Console-triggered commands land
# a few cycles apart on the two sides (different uart_tx sampling points), so
# these compare content and order, plus an identical uart.log.
#
# Self-tests: the bench's link mutations must fail identically on both sides
# (compared on what the bench's sim.log keeps, since the bench loses
# pin_trace.log when a Verilator run fails); planted script and boot-gate
# faults must fail.
#
# One simulation at a time: the bench shares sim/bin/memory_8.lst.
set -euo pipefail
R="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
TB="${TB:-$R/fpga/pynq/build/tb_fbu_vs_pin/Vtb_fbu_vs_pin}"
OUT="${OUT:-$R/sim/fbu_vs_pin}"
BENCH_RUNS="$R/sim/pin/runs/verilator_rtl"
TESTS="$R/hvl/pin/tests"
[ -x "$TB" ] || { echo "no $TB: make -C fpga/pynq build-fbu"; exit 2; }

IMAGES=("$@")
FULL=0
if [ ${#IMAGES[@]} -eq 0 ]; then
  FULL=1
  IMAGES=("$TESTS/smoke.c")
  for f in "$R"/testcode/isa_level_testing/tc_*.c "$R"/testcode/isa_level_testing/tcf_*.c; do
    IMAGES+=("$f")
  done
fi

KNOBS=(
  "d|+FPGA_SEED=1"
  "g30s1|+FPGA_GAP_PCT=30 +FPGA_SEED=1"
  "g30s2l2|+FPGA_GAP_PCT=30 +FPGA_SEED=2 +FPGA_RD_LAT=2"
  "g60s3|+FPGA_GAP_PCT=60 +FPGA_SEED=3"
  "g10s4l7|+FPGA_GAP_PCT=10 +FPGA_SEED=4 +FPGA_RD_LAT=7"
)

pass=0
fail=0
failed=()

verdict_of() { grep -o 'PIN_TB_RESULT: [A-Z]*' "$1" 2>/dev/null | head -1 | awk '{print $2}'; }
strip_error_text() { awk '$1=="E"{print "E", $2; next} {print}' "$1" > "$2"; }

report() {   # ok(0/1) name detail
  if [ "$1" = 1 ]; then
    pass=$((pass + 1))
    printf 'ok   %-38s %s\n' "$2" "$3"
  else
    fail=$((fail + 1))
    failed+=("$2")
    printf 'FAIL %-38s %s\n' "$2" "$3"
  fi
}

bench_run() {   # dir image [script] -- plusargs
  local dir="$1" image="$2" script="$3" base
  shift 3
  base="$(basename "${image%.*}")"
  mkdir -p "$dir"
  # shellcheck disable=SC2086
  "$R/hvl/pin/pin.sh" run "$image" ${script:+"$script"} "$@" > "$dir/run.log" 2>&1 || true
  cp "$BENCH_RUNS/$base"/{pin_trace.log,memory.lst,sim.log,uart.log} "$dir/" 2>/dev/null || true
}

fbu_run() {   # dir -- plusargs
  local dir="$1"
  shift
  mkdir -p "$dir"
  ( cd "$dir" && timeout 3600 "$TB" "$@" > run.log 2>&1 ) || true
}

signature_bench() {
  local rdwr errs ex
  rdwr=$(grep -o 'link_rd=[0-9]* link_wr=[0-9]*' "$1" | head -1)
  errs=$(grep -o '\[FPGA-LINK\] ERROR @[^ ]* cyc [0-9]*' "$1" | awk '{print $NF}' | tr '\n' ' ')
  ex=$(grep -o 'exit code [0-9]*, expected' "$1" | head -1 | awk '{print $3}' | tr -d ,)
  grep -q 'timeout:' "$1" && ex=timeout
  echo "$rdwr errs=[${errs% }] exit=${ex:-none}"
}

signature_fbu() {
  local rdwr errs ex
  rdwr="link_rd=$(grep -c '^L [0-9]* R' "$1/pin_trace.log" || true) link_wr=$(grep -c '^L [0-9]* W' "$1/pin_trace.log" || true)"
  errs=$(awk '$1=="E"{print $2}' "$1/pin_trace.log" | tr '\n' ' ')
  ex=$(grep -o 'exit code [0-9]*, expected' "$1/run.log" | head -1 | awk '{print $3}' | tr -d ,)
  grep -q 'timeout:' "$1/run.log" && ex=timeout
  echo "$rdwr errs=[${errs% }] exit=${ex:-none}"
}

link_test() {   # image name plusargs
  local image="$1" name="$2" args="$3" base d bv fv ok=1 cmp
  base="$(basename "${image%.*}")"
  d="$OUT/$base/$name"
  rm -rf "$d"
  # shellcheck disable=SC2086
  bench_run "$d/bench" "$image" "" $args
  # shellcheck disable=SC2086
  fbu_run "$d/fbu" +MEMLST="$d/bench/memory.lst" $args
  strip_error_text "$d/bench/pin_trace.log" "$d/a.log"
  strip_error_text "$d/fbu/pin_trace.log" "$d/b.log"
  cmp=$(python3 "$R/bin/pin_trace_cmp.py" "$d/a.log" "$d/b.log" 2>&1 | head -1 || true)
  bv=$(verdict_of "$d/bench/run.log")
  fv=$(verdict_of "$d/fbu/run.log")
  [[ "$cmp" == MATCH* ]] || ok=0
  [ "$bv" = PASS ] && [ "$fv" = PASS ] || ok=0
  report $ok "$base/$name" "bench=$bv fbu=$fv $cmp"
}

mutation_test() {   # name plusargs
  local name="$1" args="$2" d bv fv sa sb ok=1
  d="$OUT/smoke/$name"
  rm -rf "$d"
  # shellcheck disable=SC2086
  bench_run "$d/bench" "$TESTS/smoke.c" "" $args
  # shellcheck disable=SC2086
  fbu_run "$d/fbu" +MEMLST="$d/bench/memory.lst" $args
  sa=$(signature_bench "$d/bench/sim.log")
  sb=$(signature_fbu "$d/fbu")
  bv=$(verdict_of "$d/bench/run.log")
  fv=$(verdict_of "$d/fbu/run.log")
  [ "$sa" = "$sb" ] || ok=0
  [ "$bv" = FAIL ] && [ "$fv" = FAIL ] || ok=0
  report $ok "smoke/$name" "bench=$bv fbu=$fv bench[$sa] fbu[$sb]"
}

natural_test() {
  local d="$OUT/smoke/natural" args="+FPGA_GAP_PCT=20 +FPGA_SEED=9" cmp ok=1
  rm -rf "$d"
  # shellcheck disable=SC2086
  bench_run "$d/bench" "$TESTS/smoke.c" "" $args
  # shellcheck disable=SC2086
  fbu_run "$d/fbu" +MEMLST="$d/bench/memory.lst" $args +NODET +MEM_LAT=23
  cmp=$(python3 "$R/bin/pin_trace_cmp.py" "$d/bench/pin_trace.log" "$d/fbu/pin_trace.log" --no-cycles 2>&1 | head -1 || true)
  [[ "$cmp" == MATCH* ]] || ok=0
  [ "$(verdict_of "$d/fbu/run.log")" = PASS ] || ok=0
  report $ok "smoke/natural" "$cmp"
}

expand_script() {   # script memory.lst out [sed-expression]
  if [ -n "${4:-}" ]; then
    sed -e "s|\$REPO|$R|g" -e "s|\$MEM|$2|g" -e "$4" "$1" > "$3"
  else
    sed -e "s|\$REPO|$R|g" -e "s|\$MEM|$2|g" "$1" > "$3"
  fi
}

script_test() {   # test [gateware script, default the bench's own]
  local t="$1" fbu_script="${2:-$TESTS/$1.cmd}" d bv fv cmp ok=1
  d="$OUT/$t/script${2:+_$(basename "${2%.cmd}")}"
  rm -rf "$d"
  bench_run "$d/bench" "$TESTS/$t.c" "$TESTS/$t.cmd"
  mkdir -p "$d/fbu"
  expand_script "$fbu_script" "$d/bench/memory.lst" "$d/fbu/script.cmd"
  fbu_run "$d/fbu" +CMD="$d/fbu/script.cmd"
  # The PS polls, so a console-triggered irq lands some cycles after the
  # bench's and may fall on the other side of a line fill: transactions and
  # irq changes are compared as two sequences.
  strip_error_text "$d/bench/pin_trace.log" "$d/a.log"
  grep -v '^I ' "$d/a.log" > "$d/a_link.log" || true
  grep -v '^I ' "$d/fbu/pin_trace.log" > "$d/b_link.log" || true
  grep '^I ' "$d/a.log" > "$d/a_irq.log" || true
  grep '^I ' "$d/fbu/pin_trace.log" > "$d/b_irq.log" || true
  cmp=$(python3 "$R/bin/pin_trace_cmp.py" "$d/a_link.log" "$d/b_link.log" --no-cycles 2>&1 | head -1 || true)
  local irq_cmp
  irq_cmp=$(python3 "$R/bin/pin_trace_cmp.py" "$d/a_irq.log" "$d/b_irq.log" --no-cycles 2>&1 | head -1 || true)
  [[ "$irq_cmp" == MATCH* ]] || ok=0
  cmp="link $cmp; irq $irq_cmp"
  bv=$(verdict_of "$d/bench/run.log")
  fv=$(verdict_of "$d/fbu/run.log")
  [[ "$cmp" == "link MATCH"* ]] || ok=0
  cmp -s "$d/bench/uart.log" "$d/fbu/uart.log" || ok=0
  [ "$bv" = PASS ] && [ "$fv" = PASS ] || ok=0
  report $ok "$t/$(basename "$d")" "bench=$bv fbu=$fv $cmp, uart.log $(cmp -s "$d/bench/uart.log" "$d/fbu/uart.log" && echo identical || echo DIFFERS)"
}

planted_script_fault() {   # test name sed-expression expected-text
  local t="$1" name="$2" edit="$3" expect="$4" d ok=1
  d="$OUT/$t/$name"
  rm -rf "$d"
  mkdir -p "$d"
  expand_script "$TESTS/$t.cmd" "$OUT/$t/script/bench/memory.lst" "$d/script.cmd" "$edit"
  fbu_run "$d" +CMD="$d/script.cmd"
  [ "$(verdict_of "$d/run.log")" = FAIL ] || ok=0
  grep -q "$expect" "$d/run.log" || ok=0
  report $ok "$t/$name" "$(grep -m1 -E 'ERROR|RESULT: FAIL' "$d/run.log" | cut -c1-80)"
}

self_test() {   # name plusargs expected-line
  local name="$1" args="$2" expect="$3" d ok=1
  d="$OUT/smoke/$name"
  rm -rf "$d"
  # shellcheck disable=SC2086
  fbu_run "$d" +MEMLST="$OUT/smoke/d/bench/memory.lst" +FPGA_SEED=1 $args
  [ "$(verdict_of "$d/run.log")" = PASS ] || ok=0
  grep -q "$expect" "$d/run.log" || ok=0
  report $ok "smoke/$name" "$(verdict_of "$d/run.log"); $(grep -m1 -o "$expect.*" "$d/run.log" | cut -c1-60)"
}

boot_gate_tests() {
  local d="$OUT/smoke/boot_gate" cmp ok=1
  rm -rf "$d"
  fbu_run "$d/pass" +MEMLST="$OUT/smoke/d/bench/memory.lst" +FPGA_SEED=1 +BOOT_GATE
  cmp=$(python3 "$R/bin/pin_trace_cmp.py" "$OUT/smoke/d/bench/pin_trace.log" "$d/pass/pin_trace.log" 2>&1 | head -1 || true)
  [[ "$cmp" == MATCH* ]] || ok=0
  grep -q 'gate passes=1 fails=0 gave_up=0' "$d/pass/run.log" || ok=0
  report $ok "smoke/boot_gate_pass" "$cmp; $(grep -o 'gate passes=.*' "$d/pass/run.log")"
  ok=1
  fbu_run "$d/selftest" +MEMLST="$OUT/smoke/d/bench/memory.lst" +BOOT_GATE +BOOT_GATE_SELFTEST +BOOT_GATE_RETRIES=2 +TIMEOUT=20000
  grep -q 'gate passes=0 fails=3 gave_up=1' "$d/selftest/run.log" || ok=0
  [ "$(verdict_of "$d/selftest/run.log")" = FAIL ] || ok=0
  report $ok "smoke/boot_gate_selftest" "$(grep -o 'gate passes=.*' "$d/selftest/run.log")"
}

for image in "${IMAGES[@]}"; do
  for k in "${KNOBS[@]}"; do
    IFS='|' read -r name args <<<"$k"
    link_test "$image" "$name" "$args"
  done
done

if [ $FULL = 1 ]; then
  mutation_test m1 "+FPGA_MUTATE=1 +TIMEOUT=200000"
  mutation_test m2 "+FPGA_MUTATE=2"
  mutation_test m3 "+FPGA_MUTATE=3 +FPGA_WDOG=200"
  mutation_test early_stop "+FPGA_GAP_PCT=60 +FPGA_SEED=3 +FPGA_WDOG=20"
  natural_test
  link_test "$TESTS/smoke.c" wstrb "+FPGA_SEED=1 +WSTRB_TEST"
  link_test "$TESTS/smoke.c" fi_gen "+FPGA_SEED=1 +FI_TEST"
  for st in 1 3 5; do
    link_test "$TESTS/smoke.c" "reset_in_state$st" "+FPGA_SEED=1 +TRIG_RESET_STATE=$st"
  done
  for st in 2 6; do
    self_test "reset_in_state$st" "+TRIG_RESET_STATE=$st" "reset trigger fired once"
  done
  for t in irq uart_echo uart_lsr; do
    script_test "$t"
  done
  script_test irq "$R/fpga/bringup/tests/irq_trig.cmd"
  planted_script_fault uart_lsr clean_byte 's/^uart_send_ferr 55/uart_send U/' 'exit code 1, expected 0'
  planted_script_fault uart_echo wrong_div 's/^uart_div 1/uart_div 2/' 'framing error'
  planted_script_fault irq no_irq 's/^irq 0 1/irq 0 0/' 'never printed "IRQ3"'
  boot_gate_tests
fi

echo "fbu_vs_pin: $pass passed, $fail failed  (runs in $OUT)"
if [ $fail != 0 ]; then
  printf '  %s\n' "${failed[@]}"
  exit 1
fi
