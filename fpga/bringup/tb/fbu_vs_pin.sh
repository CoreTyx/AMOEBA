#!/usr/bin/env bash
# fbu_vs_pin.sh -- the P1 gate (docs/impl_plan_fpga_rtl_freeze.md s8.1):
# fbu_link_slave must reproduce the pin bench's link trace cycle for cycle.
#
#   fpga/bringup/tb/fbu_vs_pin.sh [image ...]     (default: the set below)
#
# For each image and each knob set: run hvl/pin/pin.sh on it (the bench, as
# is), then tb_fbu_vs_pin on the bench's own memory.lst with the same plusargs,
# and compare the two pin_trace.log files with bin/pin_trace_cmp.py.  E records
# are compared by cycle only (the bench prints prose, the gateware an error
# code).  Both verdicts must agree too.
#
# Mutation runs (+FPGA_MUTATE) corrupt the run on purpose; they pass when both
# sides fail the same way on the same cycle.  A natural-mode run (+NODET, slow
# backend) checks content and order only, since its timing legitimately moves.
#
# Needs: make -C fpga/pynq build-fbu, and the pin bench (hvl/pin/pin.sh build).
# One simulation at a time: the bench shares sim/bin/memory_8.lst.
set -euo pipefail
R="$(git -C "$(dirname "$0")" rev-parse --show-toplevel)"
TB="$R/fpga/pynq/build/tb_fbu_vs_pin/Vtb_fbu_vs_pin"
OUT="${OUT:-$R/sim/fbu_vs_pin}"
BENCH_RUNS="$R/sim/pin/runs/verilator_rtl"
[ -x "$TB" ] || { echo "no $TB: make -C fpga/pynq build-fbu"; exit 2; }

IMAGES=("$@")
if [ ${#IMAGES[@]} -eq 0 ]; then
  IMAGES=("$R/hvl/pin/tests/smoke.c")
  for f in "$R"/testcode/isa_level_testing/tc_*.c "$R"/testcode/isa_level_testing/tcf_*.c; do IMAGES+=("$f"); done
fi

# name | plusargs (shared by both sides) | kind: exact, mutate or order
VARIANTS=(
  "d|+FPGA_SEED=1|exact"
  "g30s1|+FPGA_GAP_PCT=30 +FPGA_SEED=1|exact"
  "g30s2l2|+FPGA_GAP_PCT=30 +FPGA_SEED=2 +FPGA_RD_LAT=2|exact"
  "g60s3|+FPGA_GAP_PCT=60 +FPGA_SEED=3|exact"
  "g10s4l7|+FPGA_GAP_PCT=10 +FPGA_SEED=4 +FPGA_RD_LAT=7|exact"
)
MUTATIONS=(
  "m1|+FPGA_MUTATE=1 +TIMEOUT=200000|mutate"
  "m2|+FPGA_MUTATE=2|mutate"
  "m3|+FPGA_MUTATE=3 +FPGA_WDOG=200|mutate"
)

# A mutation run fails on purpose, and the bench under Verilator loses its
# pin_trace.log when it does ($fatal aborts before the file is flushed).  So
# both sides are reduced to what the bench's sim.log keeps: transactions
# finished, the cycles of the link errors, and the exit code or the timeout.
sig_bench() {
  local rdwr errs ex
  rdwr=$(grep -o 'link_rd=[0-9]* link_wr=[0-9]*' "$1" | head -1)
  errs=$(grep -o '\[FPGA-LINK\] ERROR @[^ ]* cyc [0-9]*' "$1" | awk '{print $NF}' | tr '\n' ' ')
  ex=$(grep -o 'exit code [0-9]*, expected' "$1" | head -1 | awk '{print $3}' | tr -d ,)
  grep -q 'timeout:' "$1" && ex=timeout
  echo "$rdwr errs=[${errs% }] exit=${ex:-none}"
}
sig_fbu() {
  local rdwr errs ex
  rdwr=$(grep -o 'link_rd=[0-9]* link_wr=[0-9]*' "$1/run.log" | head -1)
  errs=$(awk '$1=="E"{print $2}' "$1/pin_trace.log" | tr '\n' ' ')
  ex=$(grep -o 'exit code [0-9]*, expected' "$1/run.log" | head -1 | awk '{print $3}' | tr -d ,)
  grep -q 'timeout:' "$1/run.log" && ex=timeout
  echo "$rdwr errs=[${errs% }] exit=${ex:-none}"
}

# E lines reduced to their cycle.
norm() { awk '$1=="E"{print "E", $2; next} {print}' "$1" > "$2"; }
verdict() { grep -o 'PIN_TB_RESULT: [A-Z]*' "$1" | head -1 | awk '{print $2}'; }

pass=0; fail=0; failed=()
run_one() {   # image, name, plusargs, kind
  local img="$1" name="$2" args="$3" kind="$4" base d b f bv fv
  base="$(basename "${img%.*}")"
  d="$OUT/$base/$name"; b="$d/bench"; f="$d/fbu"
  rm -rf "$d"; mkdir -p "$b" "$f"
  # shellcheck disable=SC2086
  "$R/hvl/pin/pin.sh" run "$img" $args > "$b/run.log" 2>&1 || true
  cp "$BENCH_RUNS/$base"/{pin_trace.log,memory.lst,RESULT,sim.log} "$b/" 2>/dev/null || true
  local tbargs="$args"
  [ "$kind" = order ] && tbargs="$args +NODET +MEM_LAT=23"
  # shellcheck disable=SC2086
  ( cd "$f" && timeout 3600 "$TB" +MEMLST="$b/memory.lst" +TRACE=pin_trace.log $tbargs > run.log 2>&1 ) || true
  bv=$(verdict "$b/run.log"); fv=$(verdict "$f/run.log")
  norm "$b/pin_trace.log" "$d/a.log"; norm "$f/pin_trace.log" "$d/b.log"
  local cmpargs=(); [ "$kind" = order ] && cmpargs=(--no-cycles)
  if [ "$kind" = mutate ]; then
    local sa sb; sa=$(sig_bench "$b/sim.log"); sb=$(sig_fbu "$f")
    if [ "$sa" = "$sb" ]; then echo "MATCH: $sa" > "$d/cmp.log"; else printf 'MISMATCH: bench %s / fbu %s\n' "$sa" "$sb" > "$d/cmp.log"; fi
  else
    python3 "$R/bin/pin_trace_cmp.py" "$d/a.log" "$d/b.log" "${cmpargs[@]}" > "$d/cmp.log" 2>&1 || true
  fi
  local ok=1
  grep -q '^MATCH' "$d/cmp.log" || ok=0
  [ "$bv" = "$fv" ] || ok=0
  case "$kind" in mutate) [ "$bv" = FAIL ] || ok=0;; *) [ "$bv" = PASS ] || ok=0;; esac
  if [ $ok = 1 ]; then pass=$((pass + 1)); s=ok; else fail=$((fail + 1)); s=FAIL; failed+=("$base/$name"); fi
  printf '%-4s %-26s %-8s bench=%-4s fbu=%-4s %s\n' "$s" "$base" "$name" "$bv" "$fv" "$(head -1 "$d/cmp.log")"
}

for img in "${IMAGES[@]}"; do
  for v in "${VARIANTS[@]}"; do IFS='|' read -r n a k <<<"$v"; run_one "$img" "$n" "$a" "$k"; done
done
# Self-tests and the natural-mode check, on the smallest image.
for v in "${MUTATIONS[@]}" "nat|+FPGA_GAP_PCT=20 +FPGA_SEED=9|order"; do
  IFS='|' read -r n a k <<<"$v"; run_one "$R/hvl/pin/tests/smoke.c" "$n" "$a" "$k"
done

echo "fbu_vs_pin: $pass passed, $fail failed  (runs in $OUT)"
[ $fail = 0 ] || { printf '  %s\n' "${failed[@]}"; exit 1; }
