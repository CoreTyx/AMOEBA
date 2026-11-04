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
FPGA_TESTS="$R/fpga/bringup/tests"
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

# tc_fault_control checks that FI_CONTROL is 0 after reset, which the prologue undoes.
ALWAYS_ON_IMAGES=()
for f in "$R"/testcode/isa_level_testing/tc_*.c "$R"/testcode/isa_level_testing/tcf_*.c "$R"/testcode/baremetal_ecc/tc_*.c; do
  [ "$(basename "$f")" = tc_fault_control.c ] || ALWAYS_ON_IMAGES+=("$f")
done
# Known frozen-RTL failures (plan s12.1): these must keep failing the same way.
ALWAYS_ON_KNOWN_HANGS=("tc_pmp_deny/0x5F-g10s4l7")   # F1: I$ ECC repair written to the flush target's set
ALWAYS_ON_KNOBS=(
  "g30s1|+FPGA_GAP_PCT=30 +FPGA_SEED=1"
  "g60s3|+FPGA_GAP_PCT=60 +FPGA_SEED=3"
  "g10s4l7|+FPGA_GAP_PCT=10 +FPGA_SEED=4 +FPGA_RD_LAT=7"
)

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

upto_tohost() { awk '{print} $1=="T"{exit}' "$1" > "$2"; }
# The bench stops at tohost before the console's last newline arrives.
same_console() { diff -q <(sed -e '$a\' "$1") <(sed -e '$a\' "$2") > /dev/null; }

# Runs that stop at tohost cut the console wherever the UART is; compare
# what both have.
same_console_prefix() {
  local n
  n=$(( $(stat -c%s "$1") < $(stat -c%s "$2") ? $(stat -c%s "$1") : $(stat -c%s "$2") ))
  cmp -s -n "$n" "$1" "$2"
}

# fe_fault_burst.c (fe_fault_pin.c for a patterned pin).  Pin high on both
# sides: the gateware must reproduce the bench's console and trace.  Then the
# gateware alone: a 512-period burst per round, started by a PL trigger on the
# round's "FI GO", and the pin held low.
fault_tests() {
  local base="$OUT/fe_fault_burst" d cmp ok=1
  rm -rf "$base"
  bench_run "$base/bench" "$FPGA_TESTS/fe_fault_burst.c" "$FPGA_TESTS/fe_fault_pin_bench.cmd"
  d="$base/pin_high"
  mkdir -p "$d"
  expand_script "$FPGA_TESTS/fe_fault_pin_bench.cmd" "$base/bench/memory.lst" "$d/script.cmd"
  fbu_run "$d" +CMD="$d/script.cmd"
  upto_tohost "$base/bench/pin_trace.log" "$base/a.log"
  upto_tohost "$d/pin_trace.log" "$base/b.log"
  cmp=$(python3 "$R/bin/pin_trace_cmp.py" "$base/a.log" "$base/b.log" 2>&1 | head -1 || true)
  [[ "$cmp" == MATCH* ]] || ok=0
  same_console "$base/bench/uart.log" "$d/uart.log" || ok=0
  [ "$(verdict_of "$base/bench/run.log")" = PASS ] && [ "$(verdict_of "$d/run.log")" = PASS ] || ok=0
  report $ok "fe_fault_burst/pin_high" "$cmp, uart.log $(same_console "$base/bench/uart.log" "$d/uart.log" && echo identical || echo DIFFERS)"
  for t in fe_fault_burst fe_fault_off; do
    ok=1
    d="$base/$t"
    mkdir -p "$d"
    expand_script "$FPGA_TESTS/$t.cmd" "$base/bench/memory.lst" "$d/script.cmd"
    fbu_run "$d" +CMD="$d/script.cmd"
    [ "$(verdict_of "$d/run.log")" = PASS ] || ok=0
    report $ok "fe_fault_burst/$t" "$(verdict_of "$d/run.log"); $(grep -c 'FI unit .*: PASS' "$d/run.log") rounds PASS"
  done
}

# fe_fault_cal.c: the console handshake on both sides with the pin low, then
# the gateware's 512-phase calibration sweeps, from the reset offset and from
# a planted one.
calibration_tests() {
  local base="$OUT/fe_fault_cal" d ok=1
  rm -rf "$base"
  bench_run "$base/bench" "$FPGA_TESTS/fe_fault_cal.c" "$FPGA_TESTS/fe_fault_cal_bench.cmd"
  d="$base/handshake"
  mkdir -p "$d"
  expand_script "$FPGA_TESTS/fe_fault_cal_bench.cmd" "$base/bench/memory.lst" "$d/script.cmd"
  fbu_run "$d" +CMD="$d/script.cmd"
  same_console "$base/bench/uart.log" "$d/uart.log" || ok=0
  [ "$(verdict_of "$base/bench/run.log")" = PASS ] && [ "$(verdict_of "$d/run.log")" = PASS ] || ok=0
  report $ok "fe_fault_cal/handshake" "bench=$(verdict_of "$base/bench/run.log") fbu=$(verdict_of "$d/run.log"), uart.log $(same_console "$base/bench/uart.log" "$d/uart.log" && echo identical || echo DIFFERS)"
  for t in fe_fault_cal fe_fault_cal_planted; do
    ok=1
    d="$base/$t"
    mkdir -p "$d"
    expand_script "$FPGA_TESTS/$t.cmd" "$base/bench/memory.lst" "$d/script.cmd"
    fbu_run "$d" +CMD="$d/script.cmd"
    [ "$(verdict_of "$d/run.log")" = PASS ] || ok=0
    report $ok "fe_fault_cal/$t" "$(verdict_of "$d/run.log"); $(grep -o 'delta [-0-9]*, FI_PHASE_OFS [0-9]* -> [0-9]*' "$d/run.log" | paste -sd ';')"
  done
}

# fe_cache_ded.c (CTRL-21): the console handshake on both sides with the pin
# low, then the gateware's one-cycle pulses at the cache phases.
cache_ded_tests() {
  local base="$OUT/fe_cache_ded" d ok=1
  rm -rf "$base"
  bench_run "$base/bench" "$FPGA_TESTS/fe_cache_ded.c" "$FPGA_TESTS/fe_cache_ded_bench.cmd"
  d="$base/handshake"
  mkdir -p "$d"
  expand_script "$FPGA_TESTS/fe_cache_ded_bench.cmd" "$base/bench/memory.lst" "$d/script.cmd"
  fbu_run "$d" +CMD="$d/script.cmd"
  same_console "$base/bench/uart.log" "$d/uart.log" || ok=0
  [ "$(verdict_of "$base/bench/run.log")" = PASS ] && [ "$(verdict_of "$d/run.log")" = PASS ] || ok=0
  report $ok "fe_cache_ded/handshake" "bench=$(verdict_of "$base/bench/run.log") fbu=$(verdict_of "$d/run.log"), uart.log $(same_console "$base/bench/uart.log" "$d/uart.log" && echo identical || echo DIFFERS)"
  ok=1
  d="$base/fe_cache_ded"
  mkdir -p "$d"
  expand_script "$FPGA_TESTS/fe_cache_ded.cmd" "$base/bench/memory.lst" "$d/script.cmd"
  fbu_run "$d" +CMD="$d/script.cmd"
  [ "$(verdict_of "$d/run.log")" = PASS ] || ok=0
  report $ok "fe_cache_ded/fe_cache_ded" "$(verdict_of "$d/run.log"); $(grep -o 'DED T[0-9] [A-Z]* traps [0-9]*' "$d/uart.log" | paste -sd ';')"
}

# fe_fault_site.c (CTRL-22): the console handshake on both sides with the pin
# low, then one site at a time with the whole unit armed.
site_tests() {
  local base="$OUT/fe_fault_site" d ok=1
  rm -rf "$base"
  bench_run "$base/bench" "$FPGA_TESTS/fe_fault_site.c" "$FPGA_TESTS/fe_fault_site_bench.cmd"
  d="$base/handshake"
  mkdir -p "$d"
  expand_script "$FPGA_TESTS/fe_fault_site_bench.cmd" "$base/bench/memory.lst" "$d/script.cmd"
  fbu_run "$d" +CMD="$d/script.cmd"
  same_console "$base/bench/uart.log" "$d/uart.log" || ok=0
  [ "$(verdict_of "$base/bench/run.log")" = PASS ] && [ "$(verdict_of "$d/run.log")" = PASS ] || ok=0
  report $ok "fe_fault_site/handshake" "bench=$(verdict_of "$base/bench/run.log") fbu=$(verdict_of "$d/run.log"), uart.log $(same_console "$base/bench/uart.log" "$d/uart.log" && echo identical || echo DIFFERS)"
  ok=1
  d="$base/fe_fault_site"
  mkdir -p "$d"
  expand_script "$FPGA_TESTS/fe_fault_site.cmd" "$base/bench/memory.lst" "$d/script.cmd"
  fbu_run "$d" +CMD="$d/script.cmd"
  [ "$(verdict_of "$d/run.log")" = PASS ] || ok=0
  report $ok "fe_fault_site/fe_fault_site" "$(verdict_of "$d/run.log"); $(grep -c 'target_site unit' "$d/run.log") sites"
}

# CTRL-20: fault_inject high from before release, FI_CONTROL armed by the
# fi_arm_lst.py prologue.  RF ECC (0x5F) and pipeline ECC (0x6F) take turns:
# armed together under a high pin, the pipeline flip's EccStallE drops the
# read that carries the RF flip, so RF ECC goes unexercised (s5.4.2).  The
# gateware must reproduce the bench's trace, and the console must be the
# unarmed run's.
always_on_tests() {
  local image base off d arm k name args cmp ok
  for image in "${ALWAYS_ON_IMAGES[@]}"; do
    base="$(basename "${image%.*}")"
    off="$OUT/fi_always/$base/off"
    rm -rf "$OUT/fi_always/$base"
    bench_run "$off" "$image" ""
    for arm in 0x5F 0x6F; do
      for k in "${ALWAYS_ON_KNOBS[@]}"; do
        IFS='|' read -r name args <<<"$k"
        ok=1
        d="$OUT/fi_always/$base/$arm-$name"
        mkdir -p "$d"
        python3 "$FPGA_TESTS/fi_arm_lst.py" "$off/memory.lst" "$d/armed.lst" $arm > "$d/patch.log" 2>&1 || ok=0
        # shellcheck disable=SC2086
        bench_run "$d/bench" "$d/armed.lst" "$FPGA_TESTS/fe_fi_always_bench.cmd" $args
        expand_script "$FPGA_TESTS/fe_fi_always.cmd" "$d/armed.lst" "$d/script.cmd"
        # shellcheck disable=SC2086
        fbu_run "$d/fbu" +CMD="$d/script.cmd" $args
        if [[ " ${ALWAYS_ON_KNOWN_HANGS[*]} " == *" $base/$arm-$name "* ]]; then
          grep -q 'no tohost write' "$d/bench/run.log" && grep -q 'no tohost write' "$d/fbu/run.log" || ok=0
          report $ok "fi_always/$base/$arm-$name" "known RTL hang (plan s12.1 F1) on both sides"
          continue
        fi
        strip_error_text "$d/bench/pin_trace.log" "$d/a.log"
        strip_error_text "$d/fbu/pin_trace.log" "$d/b.log"
        cmp=$(python3 "$R/bin/pin_trace_cmp.py" "$d/a.log" "$d/b.log" 2>&1 | head -1 || true)
        [[ "$cmp" == MATCH* ]] || ok=0
        [ "$(verdict_of "$d/bench/run.log")" = PASS ] && [ "$(verdict_of "$d/fbu/run.log")" = PASS ] || ok=0
        same_console_prefix "$off/uart.log" "$d/fbu/uart.log" || ok=0
        report $ok "fi_always/$base/$arm-$name" "bench=$(verdict_of "$d/bench/run.log") fbu=$(verdict_of "$d/fbu/run.log") $cmp; counters$(grep -o 'counters:.*' "$d/fbu/run.log" | cut -d: -f2)"
      done
    done
  done
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
  fault_tests
  calibration_tests
  cache_ded_tests
  site_tests
  always_on_tests
fi

echo "fbu_vs_pin: $pass passed, $fail failed  (runs in $OUT)"
if [ $fail != 0 ]; then
  printf '  %s\n' "${failed[@]}"
  exit 1
fi
