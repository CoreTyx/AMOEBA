#!/bin/bash
# hvl/pin/selftest/run.sh -- everything that must hold before the pin bench's
# verdict on a netlist is believed.  SIM=verilator (default) or SIM=vcs.
#
#   1. pin_selftest_tb, legal traffic           -> PASS
#   2. pin_selftest_tb, +VIOLATE=1..13          -> each violation detected
#      (6, 11, 12 are X/Z checks: skipped, and reported as skipped, under Verilator)
#   3. pin_tb on the RTL with the directed tests -> PASS
#   4. pin_tb on the RTL with +FPGA_MUTATE=1..3  -> FAIL (a corrupted fetch, a
#      wrong exit code, a dropped word: the bench must notice each)
#   5. rtl vs rtl_sva pin traces                 -> cycle-exact match
#
# Prints one line per check and a summary; exit status 0 only if all hold.
set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
P="$R/hvl/pin"
SIM="${SIM:-verilator}"
OUT="$R/sim/pin/selftest/$SIM"
IMG="$R/sim/pin/images"
mkdir -p "$OUT"
pass=0; fail=0; skip=0
ok()   { echo "  PASS  $*"; pass=$((pass+1)); }
bad()  { echo "  FAIL  $*"; fail=$((fail+1)); }
skp()  { echo "  SKIP  $*"; skip=$((skip+1)); }

# ---- build the self-test bench ----------------------------------------------
if ! command -v "$SIM" >/dev/null; then
  echo "$SIM: not found on PATH.  Load the simulator first (e.g. 'module load vcs', or your"
  echo "site's Synopsys setup script), check with 'which $SIM', then rerun."
  exit 1
fi
echo "== build pin_selftest_tb ($SIM)"
SRCS=("$R/hdl/forte_link_pkg.sv" "$P/pin_link_agent.sv" "$P/pin_uart_agent.sv" "$P/selftest/pin_selftest_tb.sv")
if [ "$SIM" = verilator ]; then
  ( cd "$OUT" && verilator --binary --timing --timescale 1ns/1ps -Wno-fatal -Wno-lint -Wno-style \
      "${SRCS[@]}" --top-module pin_selftest_tb -o selftest >build.log 2>&1 )
  EXE="$OUT/obj_dir/selftest"
else
  # Everything VCS says goes to build.log.  Not -l: VCS writes licence,
  # environment and command-line errors to the terminal only, so a -l log of a
  # failed run can end at the banner with no reason given.
  rm -f "$OUT/simv"
  ( cd "$OUT" && vcs -full64 -sverilog -licqueue -timescale=1ns/1ps "${SRCS[@]}" \
      -top pin_selftest_tb -o simv ) >"$OUT/build.log" 2>&1
  EXE="$OUT/simv"
fi
if [ ! -x "$EXE" ]; then
  echo "build failed: $OUT/build.log -- last 40 lines:"
  tail -40 "$OUT/build.log" | sed 's/^/  | /'
  exit 1
fi

st() {  # $1 = label, rest = plusargs
  local label="$1"; shift
  local log="$OUT/$label.log"
  ( cd "$OUT" && "$EXE" "$@" ) >"$log" 2>&1
  local res; res="$(grep -m1 '^SELFTEST_RESULT:' "$log" || echo 'SELFTEST_RESULT: FAIL no verdict')"
  case "$res" in
    *"PASS (violation"*skipped*) skp "$label: needs 4-state";;
    *PASS*) ok "$label";;
    *)      bad "$label: ${res#SELFTEST_RESULT: } ($log)";;
  esac
}

echo "== harness self-test"
st legal
for v in $(seq 1 13); do st "violate_$v" +VIOLATE="$v"; done

# ---- the bench on the RTL ------------------------------------------------------------
# Directed tests need DUT builds; VCS on the VM uses the real SRAM/pad models
# when vm_paths.sh names them.
for dut in rtl rtl_sva; do
  echo "== build pin_tb ($SIM/$dut)"
  SIM=$SIM DUT=$dut "$P/pin.sh" build >"$OUT/build_$dut.log" 2>&1 || { bad "build $dut ($OUT/build_$dut.log)"; continue; }
  echo "== directed ($SIM/$dut)"
  for t in smoke uart_echo irq; do
    # Prebuilt images (hvl/pin/images.sh) where there is no RISC-V toolchain.
    if [ -f "$IMG/$t.lst" ]; then args=("$IMG/$t.lst")
    else args=("$P/tests/$t.c"); fi
    [ -f "$P/tests/$t.cmd" ] && args+=("$P/tests/$t.cmd")
    if SIM=$SIM DUT=$dut TAG=st "$P/pin.sh" run "${args[@]}" +TIMEOUT=2000000 >"$OUT/${dut}_$t.log" 2>&1
    then ok "$dut $t"; else bad "$dut $t ($OUT/${dut}_$t.log)"; fi
  done
done

echo "== mutations (must FAIL)"
for m in 1 2 3; do
  smoke="$P/tests/smoke.c"; [ -f "$IMG/smoke.lst" ] && smoke="$IMG/smoke.lst"
  if SIM=$SIM DUT=rtl TAG="mut$m" "$P/pin.sh" run "$smoke" +FPGA_MUTATE=$m +TIMEOUT=100000 >"$OUT/mut$m.log" 2>&1
  then bad "mutation $m went unnoticed ($OUT/mut$m.log)"
  else ok "mutation $m caught: $(grep -m1 -E 'ERROR|PIN_TB_RESULT' "$OUT/mut$m.log" | cut -c1-90)"; fi
done

echo "== rtl vs rtl_sva traces"
for t in smoke uart_echo irq; do
  a="$R/sim/pin/runs/${SIM}_rtl/${t}_st"; b="$R/sim/pin/runs/${SIM}_rtl_sva/${t}_st"
  if python3 "$R/bin/pin_trace_cmp.py" "$a" "$b" >"$OUT/cmp_$t.log" 2>&1; then ok "trace $t: $(cat "$OUT/cmp_$t.log")"
  else bad "trace $t: $(head -1 "$OUT/cmp_$t.log")"; fi
done

echo "== summary: $pass passed, $fail failed, $skip skipped"
[ $fail -eq 0 ]
