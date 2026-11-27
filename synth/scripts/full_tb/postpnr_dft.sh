#!/bin/bash
# Post-PnR DFT verification from hvl/pin/vm_paths.sh: the PnR netlist (NETLIST),
# its SDF (SDF) and the cell/SRAM/pad models.  No scandef or phase file needed.
#
#   synth/scripts/full_tb/postpnr_dft.sh [--vm-paths FILE] [--corners min,max]
#                                        [--ignore-neg-delay] [--quick] [--from N]
# vm_paths: --vm-paths, else $VM_PATHS, else vm_paths.sh beside the checkout
# (<repo>/../vm_paths.sh), else hvl/pin/vm_paths.sh.
#
# Stages (each one line in results/<stamp>/SUMMARY; later stages still run
# after a failure unless they depend on it):
#   1 preflight   paths, vcs, forte_top in the netlist, TIMINGCHECK in the SDF
#   2 discover    chain order, scan-path inversions and logical phase, found by
#                 simulating the netlist (zero-delay; run.sh --discover-only)
#   3 zero-delay  full_tb on the PnR netlist, every phase (A M B C D E P H F R I
#                 S), then BREAK_SE and BREAK_MAP, which must FAIL.  Separates a
#                 wrong discovery or logic problem from a timing problem.
#   4 timing      per corner: full_tb --timing, phase S first (hold, scan out,
#                 scan in, resume, compare: 40 cases), then regress.sh --timing
#                 (11 jobs).  Functional clock 10 MHz, scan 1 MHz (full_tb's
#                 timing defaults; FUNC_PERIOD_PS / SCAN_PERIOD_PS to change).
#   5 holds       per corner: the pin bench's DFT hold regression on the netlist
#                 with the SDF (hvl/pin/hold_regress.sh, SIM=vcs DUT=gate).
#   TOTAL         and results/<stamp>.tgz (summaries and logs).
# --quick: 3 runs phases A-C only and no controls, 4 runs phase S with one
#          workload, 5 runs basic_arith only.  To check the setup first.
# --from N: skip stages before N (2 always runs: it is cached).
# --ignore-neg-delay: SDFCOM_NIOD (negative IOPATH delay) counted, not failed.
#          Every line it affects says "not sign-off".
#
# SUMMARY and the console print counts, verdicts and RTL register names only:
# no cell names, model text or SDF values.  Paste SUMMARY back.
set -uo pipefail
D="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
R="$(cd "$D/../../.." && pwd)"
# vm_paths.sh: $VM_PATHS, else beside the checkout (../vm_paths.sh), else hvl/pin/.
VMP="${VM_PATHS:-}"
if [ -z "$VMP" ]; then
  VMP="$(cd "$R/.." && pwd)/vm_paths.sh"; [ -f "$VMP" ] || VMP="$R/hvl/pin/vm_paths.sh"
fi
CORNERS="min,max" NIOD=0 QUICK=0 FROM=1
while [ $# -gt 0 ]; do
  case "$1" in
    --vm-paths) VMP="$2"; shift ;;
    --corners) CORNERS="$2"; shift ;;
    --ignore-neg-delay) NIOD=1 ;;
    --quick) QUICK=1 ;;
    --from) FROM="$2"; shift ;;
    -h|--help) sed -n '2,/^set -uo/p' "$0" | sed '$d'; exit 0 ;;
    *) echo "postpnr_dft.sh: unknown option $1" >&2; exit 2 ;;
  esac
  shift
done
STAMP="$(date +%Y%m%d_%H%M%S)"
OUT="$D/results/$STAMP"
mkdir -p "$OUT"
SUM="$OUT/SUMMARY"
exec > >(tee "$OUT/console.log") 2>&1
log() { echo "$*" | tee -a "$SUM"; }
pass=0 fail=0
row() {   # row <PASS|FAIL> <text>
  [ "$1" = PASS ] && pass=$((pass + 1)) || fail=$((fail + 1))
  log "$(printf '%-5s %s' "$1" "$2")"
}
NOTE=""; [ $NIOD = 1 ] && NOTE=" (--ignore-neg-delay: not sign-off)"
RUNOPT=(--vm-paths "$VMP"); [ $NIOD = 1 ] && RUNOPT+=(--ignore-neg-delay)
IFS=, read -r -a CORNER_LIST <<<"$CORNERS"
log "postpnr_dft: $STAMP  vm_paths=$VMP  corners=${CORNERS}${NOTE}$([ $QUICK = 1 ] && echo '  QUICK')"
[ -f "$R/.git/HEAD" ] || [ -f "$R/.git" ] && log "revision: $(git -C "$R" rev-parse --short HEAD 2>/dev/null)$(git -C "$R" diff --quiet 2>/dev/null || echo ' (modified)')"
finish() {
  log "TOTAL: $pass pass, $fail fail${NOTE}"
  ( cd "$D/results" && tar -czf "$STAMP.tgz" "$STAMP" ) 2>/dev/null
  echo "results: $SUM  and  $D/results/$STAMP.tgz"
  [ "$fail" = 0 ]; exit $?
}
# A stage's own lines worth keeping: verdicts and counts, no paths.
keep() { grep -E "$1" "$2" 2>/dev/null | sed "s|$R/||g" | sed 's/^/      /' | tee -a "$SUM" >/dev/null; }

# ---- 1 preflight -----------------------------------------------------------------------
if [ "$FROM" -le 1 ]; then
  pf="$OUT/preflight.log"
  (
    set -e
    [ -f "$VMP" ] || { echo "no vm_paths file: $VMP (cp hvl/pin/vm_paths.example.sh ../vm_paths.sh, beside the checkout; fill in NETLIST, SDF and the models)"; exit 1; }
    NETLIST="" SDF="" PDK_FIRST=() STDCELL_MODELS=() SRAM_MODELS=() PAD_MODELS=()
    source "$VMP"
    [ -n "$NETLIST" ] && [ -s "$NETLIST" ] || { echo "NETLIST not set or empty"; exit 1; }
    [ -n "$SDF" ] && [ -s "$SDF" ] || { echo "SDF not set or empty"; exit 1; }
    for v in STDCELL_MODELS SRAM_MODELS PAD_MODELS; do
      eval "n=\${#$v[@]}"; [ "$n" -gt 0 ] || { echo "$v is empty"; exit 1; }
      eval "for f in \"\${$v[@]}\"; do [ -e \"\$f\" ] || { echo \"$v: missing \$f\"; exit 1; }; done"
    done
    command -v vcs >/dev/null || { echo "vcs not on PATH"; exit 1; }
    # grep on a process substitution: with pipefail, zcat's SIGPIPE after an
    # early grep -q match would fail a pipe.
    grep -qE '^[[:space:]]*module[[:space:]]+forte_top([^[:alnum:]_]|$)' <(zcat -f "$NETLIST") || { echo "no module forte_top in NETLIST"; exit 1; }
    grep -qiE '\([[:space:]]*TIMINGCHECK' <(zcat -f "$SDF") || { echo "SDF has no TIMINGCHECK section"; exit 1; }
    rr=$(grep -cE '\([[:space:]]*RECREM([[:space:]]|$)' <(zcat -f "$SDF") || true)
    echo "netlist and SDF found; SDF: $rr RECREM entries"
  ) > "$pf" 2>&1
  if [ $? = 0 ]; then row PASS "1 preflight: $(tail -1 "$pf")"; else row FAIL "1 preflight: $(tail -1 "$pf")"; finish; fi
fi

# ---- 2 discover ------------------------------------------------------------------------
dl="$OUT/discover.log"
bash "$D/run.sh" "${RUNOPT[@]}" --discover-only > "$dl" 2>&1
if [ $? = 0 ]; then
  row PASS "2 discover: $(grep -m1 -oE 'DISCOVER: [0-9]+ cells on [0-9]+ chains: [0-9]+ resolved' "$dl")"
else
  row FAIL "2 discover: see discover.log"; keep 'DISCOVER|ERROR|run.sh:' "$dl"; finish
fi
keep '\| \[[0-9]+\] A: c[0-9]|DISCOVER: |discover_meta: |discover_cells: |compare' "$dl"

# ---- 3 zero-delay ----------------------------------------------------------------------
if [ "$FROM" -le 3 ]; then
  zl="$OUT/zero_delay.log"
  ph=(); [ $QUICK = 1 ] && ph=(+SCAN_PHASES=C)
  bash "$D/run.sh" "${RUNOPT[@]}" --regen "${ph[@]}" > "$zl" 2>&1
  rc=$?
  v=$(grep -m1 -E '^DFT TB (PASS|FAIL)' "$D/sim/sim.log" 2>/dev/null)
  [ $rc = 0 ] && row PASS "3 zero-delay full_tb${ph:+ (${ph[*]})}: $v" || row FAIL "3 zero-delay full_tb${ph:+ (${ph[*]})}: ${v:-no verdict, see zero_delay.log}"
  keep '^PHASE: ' "$D/sim/sim.log"
  cp "$D/sim/sim.log" "$OUT/zero_delay.sim.log" 2>/dev/null
  if [ $QUICK = 0 ]; then
    for ctl in BREAK_SE BREAK_MAP; do
      bash "$D/run.sh" "${RUNOPT[@]}" +define+$ctl +SCAN_PHASES=C > "$OUT/control_$ctl.log" 2>&1
      if [ $? != 0 ]; then row PASS "3 control +define+$ctl: fails, as it must"; else row FAIL "3 control +define+$ctl: PASSED, so the bench cannot see that fault"; fi
    done
  fi
fi

# ---- 4 timing --------------------------------------------------------------------------
if [ "$FROM" -le 4 ]; then
  for c in "${CORNER_LIST[@]}"; do
    tl="$OUT/timing_${c}_S.log"
    sopt=(+SCAN_PHASES=S); [ $QUICK = 1 ] && sopt+=(+SCAN_RESUME_ITERS=1)
    bash "$D/run.sh" "${RUNOPT[@]}" --timing --corner "$c" --regen "${sopt[@]}" > "$tl" 2>&1
    rc=$?
    sd="$D/sim/timing_$c"
    v=$(grep -m1 -E '^DFT TB (PASS|FAIL)' "$sd/sim.log" 2>/dev/null)
    tv=$(grep -m1 -E '^TIMING VIOLATIONS' "$sd/timing_summary.log" 2>/dev/null)
    [ $rc = 0 ] && row PASS "4 timing $c, phase S: ${v}; ${tv}${NOTE}" || row FAIL "4 timing $c, phase S: ${v:-no verdict}; ${tv:-no timing summary, see $(basename "$tl")}${NOTE}"
    keep '^(PHASE: S|S (CHECKS|RESUME|COVERAGE))|^  by |^ANNOTATION|^PROBLEM' "$sd/sim.log"
    keep '^  by |^ANNOTATION|^PROBLEM' "$sd/timing_summary.log"
    cp "$sd/timing_summary.log" "$OUT/timing_${c}_S.timing_summary.log" 2>/dev/null
    if [ $QUICK = 0 ]; then
      rg="$OUT/timing_${c}_regress.log"
      ropt=(--timing --corner "$c" --vm-paths "$VMP"); [ $NIOD = 1 ] && ropt+=(--ignore-neg-delay)
      bash "$D/regress.sh" "${ropt[@]}" > "$rg" 2>&1
      rc=$?
      res=$(grep -m1 -oE '^PASS=[0-9]+ FAIL=[0-9]+ PARTIAL=[0-9]+' "$rg")
      [ $rc = 0 ] && row PASS "4 timing $c, regress.sh (11 jobs): $res${NOTE}" || row FAIL "4 timing $c, regress.sh (11 jobs): ${res:-see $(basename "$rg")}${NOTE}"
      d=$(grep -m1 -oE 'Results: .*' "$rg" | cut -d' ' -f2)
      [ -n "$d" ] && [ -f "$d/summary.tsv" ] && awk -F'\t' 'NR>1 {printf "      %-7s %s: %s\n", $2, $1, $5}' "$d/summary.tsv" | tee -a "$SUM" >/dev/null
      [ -n "$d" ] && for f in "$d"/*/timing_summary.log; do
        [ -f "$f" ] && n=$(grep -m1 -oE 'TIMING VIOLATIONS: [0-9]+' "$f") && [ "${n##* }" != 0 ] && echo "      $(basename "$(dirname "$f")"): $n" | tee -a "$SUM" >/dev/null
      done
    fi
  done
fi

# ---- 5 holds ---------------------------------------------------------------------------
if [ "$FROM" -le 5 ]; then
  hl="$OUT/holds.log"
  env SIM=vcs DUT=gate PIN_VM_PATHS="$VMP" HOLD_CORNERS="${CORNER_LIST[*]}" HOLD_IGNORE_NIOD=$NIOD \
      $([ $QUICK = 1 ] && echo HOLD_PROGRAMS=testcode/baremetal/basic_arith.c HOLD_IRQ=0) \
      bash "$R/hvl/pin/hold_regress.sh" > "$hl" 2>&1
  rc=$?
  hd=$(grep -m1 -oE '^Results: .*' "$hl" | cut -d' ' -f2)
  np=$(grep -c '^PASS' "$hd/SUMMARY" 2>/dev/null); nf=$(grep -c '^FAIL' "$hd/SUMMARY" 2>/dev/null)
  [ $rc = 0 ] && row PASS "5 pin-bench holds on the netlist with SDF: $np pass, $nf fail${NOTE}" \
              || row FAIL "5 pin-bench holds on the netlist with SDF: ${np:-0} pass, ${nf:-?} fail (holds.log)${NOTE}"
  [ -f "$hd/SUMMARY" ] && sed 's/^/      /' "$hd/SUMMARY" | tee -a "$SUM" >/dev/null
fi
finish
