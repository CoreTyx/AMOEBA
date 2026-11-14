#!/bin/bash
# postpnr/selfcheck.sh -- the assumptions the post-PnR comparison rests on, checked
# on the RTL (Verilator, local or CI):
#
#   1. timing-independence: the per-cycle pin trace, the link trace and the
#      console do not change with the clock period, the input launch delay or
#      the output sample points (so one golden serves any SDC and both corners)
#   2. the two RTL references agree: DUT=rtl (pads and SRAM macros as
#      synthesized) and DUT=rtl_sva (behavioural, with the RTL's SVA)
#   3. the comparator catches a difference: one output bit flipped in a copy
#      of a trace must be a MISMATCH at that cycle
#
#   postpnr/selfcheck.sh [test ...]       default: smoke uart_echo irq
set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P="$R/hvl/pin"
OUT="$R/postpnr/work/selfcheck"
rm -rf "$OUT"; mkdir -p "$OUT"
TESTS=("$@"); [ ${#TESTS[@]} -gt 0 ] || TESTS=(smoke uart_echo irq)
fail=0
ok()  { printf '  PASS %s\n' "$*"; }
bad() { printf '  FAIL %s\n' "$*"; fail=1; }

# Far from the defaults (10 ns, 2 ns launch, clk_out + 5 ns, negedge UART):
# a 7 ns clock, inputs late in the half-cycle, every sample core_clk-referenced.
ALT=(+CLK_PS=7000 +FPGA_TCO_PS=3200 +FPGA_SAMPLE_REF=core +FPGA_SAMPLE_PS=4900
     +UART_SAMPLE_PS=6100 +PIN_TRACE_SAMPLE_PS=6500)

for dut in rtl rtl_sva; do
  SIM=verilator DUT=$dut PIN_BUILD="$R/sim/pin/build/verilator_$dut" "$P/pin.sh" build > "$OUT/build_$dut.log" 2>&1 \
    || { tail -20 "$OUT/build_$dut.log"; echo "selfcheck: $dut build failed"; exit 2; }
done

run() {   # run <dut> <tag> <test> [plusargs...]: the run directory
  local dut="$1" tag="$2" t="$3"; shift 3
  local cmd=""; [ -f "$P/tests/$t.cmd" ] && cmd="$P/tests/$t.cmd"
  PIN_RUNS="$OUT/$dut-$tag" SIM=verilator DUT=$dut "$P/pin.sh" run "$P/tests/$t.c" ${cmd:+"$cmd"} +UART_QUIET "$@" \
    > "$OUT/$dut-$tag-$t.log" 2>&1
  echo "$OUT/$dut-$tag/$t"
}

echo "== selfcheck: ${TESTS[*]}"
for t in "${TESTS[@]}"; do
  a="$(run rtl dflt "$t")"; grep -q 'PIN_TB_RESULT: PASS' "$a/RESULT" 2>/dev/null || { bad "$t: rtl run failed: $(cat "$a/RESULT" 2>/dev/null)"; continue; }
  b="$(run rtl alt "$t" "${ALT[@]}")"
  grep -q 'PIN_TB_RESULT: PASS' "$b/RESULT" 2>/dev/null || bad "$t: rtl run at other timing failed: $(cat "$b/RESULT" 2>/dev/null)"
  if r="$(python3 "$R/bin/pin_trace_cmp.py" "$a" "$b")"; then ok "$t: timing-independent ($r)"; else bad "$t: trace depends on timing:"; echo "$r" | sed 's/^/       /'; fi
  c="$(run rtl_sva dflt "$t")"
  if r="$(python3 "$R/bin/pin_trace_cmp.py" "$a" "$c")"; then ok "$t: rtl = rtl_sva"; else bad "$t: rtl and rtl_sva differ:"; echo "$r" | sed 's/^/       /'; fi
done

# 3: the comparator, against a deliberately broken copy of the first trace.
t="${TESTS[0]}"; a="$OUT/rtl-dflt/$t"; m="$OUT/mutant/$t"
rm -rf "$m"; mkdir -p "$m"; cp "$a"/{pin_trace.log,uart.log} "$m/"
line="$(zcat "$a/pin_cycle.log.gz" | grep -n '^C ' | sed -n '50p' | cut -d: -f1)"
zcat "$a/pin_cycle.log.gz" | awk -v L="$line" 'NR==L{$NF = ($NF=="0") ? "1" : "0"} {print}' | gzip > "$m/pin_cycle.log.gz"
cyc="$(zcat "$m/pin_cycle.log.gz" | sed -n "${line}p" | awk '{print $2}')"
r="$(python3 "$R/bin/pin_trace_cmp.py" "$a" "$m")"
if [ $? -ne 0 ] && grep -q "status" <<<"$r" && grep -q "C $cyc " <<<"$r"; then ok "comparator catches a flipped status bit at cycle $cyc"
else bad "comparator missed a flipped bit at cycle $cyc:"; echo "$r" | sed 's/^/       /'; fi

[ $fail = 0 ] && echo "selfcheck: PASS" || echo "selfcheck: FAIL (logs in $OUT)"
exit $fail
