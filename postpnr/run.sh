#!/bin/bash
# postpnr/run.sh -- post-PnR chip-level verification, on the VCS VM.
#
#   PNR_DIR=/path/to/drop postpnr/run.sh [options]
#
# The drop folder ($PNR_DIR) holds what PnR produced:
#   forte_top.v (or the one *.v / *.v.gz)    the post-PnR netlist (ports as forte_top)
#   forte_top.sdc (or the one *.sdc)         the SDC PnR signed off with
#   *.sdf[.gz]: one SDF with min:typ:max triples, or one per corner whose name
#               says which (*max*.sdf / *min*.sdf, also *ss*/*ff*, *slow*/*fast*)
#   pnr.env     optional: RTL_REF=<sha> (the commit the netlist came from; the
#               golden must be that commit's), and any vm_paths.sh override
#               (STDCELL_MODELS=(...), VCS_FLAGS=(...), ...)
#
# Options:
#   --only REGEX       images whose name matches (default: all with a golden)
#   --corners LIST     max,min (default), or one of them
#   --jobs N           simulations at once (default 1; each holds a VCS licence)
#   --golden DIR       default: the only postpnr/golden/<sha>, or RTL_REF's
#   --with-vcs-rtl     also run the golden RTL under VCS (4-state) on every
#                      image and compare it with the Verilator golden
#   --max-errors N     bench errors before a run stops (default 1)
#   --no-build         reuse the corner builds as they are
#
# What makes a row PASS -- all of:
#   func  the bench's verdict: the program finished with exit 0 and no pin,
#         protocol or X error (hvl/pin/pin_tb.sv)
#   tchk  no VCS 'Timing violation' (setup/hold/recovery/removal/width/period,
#         from the cell models' specify blocks with the SDF's limits), except
#         lines matched by postpnr/waivers.txt (empty unless you add to it)
#   win   no pad output-window error: every output settles and holds per the
#         SDC's set_output_delay (hvl/pin/pin_cycle_trace.sv)
#   trace the run's pins, cycle by cycle, its link transactions and its console
#         are exactly the golden RTL's (bin/pin_trace_cmp.py)
# and every corner's build must annotate its SDF with no SDFCOM_* message.
#
# Inputs launch IN_MAX after the core_clk edge in the max corner and IN_MIN in
# the min corner; outputs are sampled and window-checked as the SDC says
# (postpnr/sdc_delays.py prints exactly what was derived).
#
# INITREG=0|1|random (environment) starts every register at that value: for
# triage of X pessimism only, and SUMMARY says so on every row.
#
# Output: postpnr/results/<date>/SUMMARY (paste it back), and
# postpnr/results/<date>.tgz (logs, traces, consoles: send it if asked).
set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
P="$R/hvl/pin"

# ---- one simulation (run in parallel by xargs: run.sh __one <corner> <name>) ----
if [ "${1:-}" = __one ]; then
  corner="$2" n="$3"
  img="$GOLDEN/images"
  a=() cmd=""
  [ -f "$img/$n.cmd" ] && cmd="$img/$n.cmd"
  [ -f "$img/$n.args" ] && read -r -a a < "$img/$n.args"
  pa=()
  if [ "$corner" = rtl ]; then
    env_sdf=() dut=rtl
    read -r -a pa <<<"$PLUSARGS_RTL"
  else
    sdf_var="SDF_$corner"; env_sdf=(PIN_SDF="${!sdf_var}" PIN_SDF_CORNER="$corner") dut=gate
    pa_var="PLUSARGS_$corner"; read -r -a pa <<<"${!pa_var}"
  fi
  runs="$OUT/runs/$corner"
  echo "$(date '+%T') start  $corner $n" >&2
  env ${env_sdf[@]+"${env_sdf[@]}"} PIN_RUNS="$runs" SIM=vcs DUT=$dut "$P/pin.sh" run "$img/$n.lst" ${cmd:+"$cmd"} \
      +TIMEOUT=10000000 +UART_QUIET +MAX_ERRORS="$MAX_ERRORS" ${pa[@]+"${pa[@]}"} ${a[@]+"${a[@]}"} \
      > "$runs/$n.pin.log" 2>&1 || true
  d="$runs/$n"
  mkdir -p "$d"          # pin.sh may have died before making it
  res="$(cat "$d/RESULT" 2>/dev/null || echo 'PIN_TB_RESULT: FAIL no RESULT (see '"$runs/$n.pin.log"')')"
  # func: the bench's own verdict, before pin.sh folded the timing checks in
  if [[ "$res" == "PIN_TB_RESULT: PASS"* ]] || [[ "$res" == *"; bench: functionally ok"* ]]; then func=PASS; else func=FAIL; fi
  tchk=0 waived=0
  [ -f "$d/TCHK_COUNT" ] && { eval "$(cat "$d/TCHK_COUNT")"; tchk=$((tchk - waived)); }
  win="$(zcat -f "$d/sim.log" 2>/dev/null | grep -c '\[PIN_IO\] ERROR.*output window' || true)"
  if python3 "$R/bin/pin_trace_cmp.py" "$GOLDEN/traces/$n" "$d" > "$d/CMP" 2>&1; then trace=MATCH
  elif grep -q '^MISMATCH' "$d/CMP"; then trace=DIFF
  else trace=NONE; fi
  ok=PASS
  [ $func = PASS ] && [ "$tchk" = 0 ] && [ "$win" = 0 ] && [ $trace = MATCH ] || ok=FAIL
  why=""
  [ $func = PASS ] || why="${res#PIN_TB_RESULT: }"
  [ $trace = MATCH ] || why="${why:+$why; }$(head -1 "$d/CMP" | cut -c1-160)"
  [ -n "${INITREG:-}" ] && why="${why:+$why; }INITREG=$INITREG"
  [ -f "$d/sim.log" ] && gzip -f "$d/sim.log"
  rm -f "$d/memory.lst"
  printf '%-4s %-40s %-4s func=%s tchk=%s%s win=%s trace=%s%s\n' "$ok" "$n" "$corner" "$func" "$tchk" \
         "$([ "$waived" -gt 0 ] && echo "(+${waived}w)")" "$win" "$trace" "${why:+  $why}" | tee "$d/ROW"
  exit 0
fi

# ---- options ---------------------------------------------------------------------------
ONLY="" CORNERS="max,min" JOBS=1 GOLDEN="" VCS_RTL=0 MAX_ERRORS=1 BUILD=1
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="$2"; shift;;
    --corners) CORNERS="$2"; shift;;
    --jobs) JOBS="$2"; shift;;
    --golden) GOLDEN="$2"; shift;;
    --with-vcs-rtl) VCS_RTL=1;;
    --max-errors) MAX_ERRORS="$2"; shift;;
    --no-build) BUILD=0;;
    -h|--help) sed -n '2,/^set -uo/{/^set -uo/d;p}' "$0"; exit 0;;
    *) echo "run.sh: unknown option $1 (--help)" >&2; exit 2;;
  esac
  shift
done

STAMP="$(date '+%Y%m%d_%H%M%S')"
OUT="$R/postpnr/results/$STAMP"
mkdir -p "$OUT"
SUM="$OUT/SUMMARY"
: > "$SUM"
log() { echo "$*" | tee -a "$SUM"; }
pack() { tar -C "$R/postpnr/results" -czf "$R/postpnr/results/$STAMP.tgz" "$STAMP" 2>/dev/null
         echo "results: $SUM  and  $R/postpnr/results/$STAMP.tgz"; }
stop() { log "STOPPED: $*"; pack; exit 1; }
# heartbeat <pid> <log> <what>: a line a minute while <pid> runs (console only)
heartbeat() {
  local pid="$1" f="$2" what="$3" t0=$SECONDS last=$SECONDS
  while kill -0 "$pid" 2>/dev/null; do
    sleep 5
    if [ $((SECONDS - last)) -ge 60 ]; then
      last=$SECONDS
      echo "         ... $what: $(( (SECONDS - t0) / 60 )) min, $(wc -l < "$f" 2>/dev/null || echo 0) log lines: $(tail -1 "$f" 2>/dev/null | cut -c1-100)"
    fi
  done
}

log "==== postpnr/run.sh $(date '+%F %T')  host=$(hostname)"
[ -n "${PNR_DIR:-}" ] || stop "set PNR_DIR to the post-PnR drop folder (netlist, SDF, SDC)"
[ -d "$PNR_DIR" ] || stop "PNR_DIR=$PNR_DIR is not a directory"
PNR_DIR="$(cd "$PNR_DIR" && pwd)"
log "drop:    $PNR_DIR"

# The bundle's own check (postpnr/pack.sh): every file as packed.
if [ -f "$R/postpnr/BUNDLE.sha256" ]; then
  ( cd "$R" && sha256sum -c --quiet postpnr/BUNDLE.sha256 ) > "$OUT/bundle_check.log" 2>&1 \
    || { head -20 "$OUT/bundle_check.log" >> "$SUM"; stop "files differ from the bundle (above): unpack it again"; }
  log "bundle:  $(head -1 "$R/postpnr/BUNDLE" 2>/dev/null) -- all $(wc -l < "$R/postpnr/BUNDLE.sha256") files verified"
fi

# ---- the drop folder ----------------------------------------------------------------------
one_file() {   # one_file <desc> <glob>...: the first glob with matches must have exactly one;
               # it is gunzipped into $OUT/drop if need be
  local desc="$1" f g; shift
  local hits=()
  shopt -s nullglob
  for g in "$@"; do
    for f in "$PNR_DIR"/$g; do [ -f "$f" ] && hits+=("$f"); done
    [ ${#hits[@]} -gt 0 ] && break
  done
  shopt -u nullglob
  [ ${#hits[@]} -eq 1 ] || { echo "ERR:$desc: ${#hits[@]} candidates (${hits[*]:-none}) for $*" ; return; }
  f="${hits[0]}"
  if [[ "$f" == *.gz ]]; then
    mkdir -p "$OUT/drop"; gunzip -c "$f" > "$OUT/drop/$(basename "${f%.gz}")"; f="$OUT/drop/$(basename "${f%.gz}")"
  fi
  echo "$f"
}
NETLIST="$(one_file netlist forte_top.v forte_top.v.gz '*.v' '*.v.gz')"
SDC="$(one_file sdc forte_top.sdc '*.sdc')"
[[ "$NETLIST" == ERR:* ]] && stop "${NETLIST#ERR:}"
[[ "$SDC" == ERR:* ]] && stop "${SDC#ERR:}"
SDF_max="" SDF_min=""
shopt -s nullglob nocaseglob
sdfs=("$PNR_DIR"/*.sdf "$PNR_DIR"/*.sdf.gz)
shopt -u nocaseglob
if [ ${#sdfs[@]} -eq 1 ]; then
  SDF_max="$(one_file sdf "$(basename "${sdfs[0]}")")"; SDF_min="$SDF_max"; SDF_MODE="one SDF, min:typ:max triples"
elif [ ${#sdfs[@]} -eq 2 ]; then
  for f in "${sdfs[@]}"; do
    b="$(basename "$f" | tr 'A-Z' 'a-z')"
    if [[ "$b" =~ (max|ss|slow|wc|worst) ]]; then SDF_max="$(one_file sdf "$(basename "$f")")"
    elif [[ "$b" =~ (min|ff|fast|bc|best) ]]; then SDF_min="$(one_file sdf "$(basename "$f")")"; fi
  done
  [ -n "$SDF_max" ] && [ -n "$SDF_min" ] || stop "two SDFs, but cannot tell max from min by name: ${sdfs[*]}"
  SDF_MODE="one SDF per corner"
else
  stop "need one SDF (min:typ:max) or two (max and min) in $PNR_DIR, found ${#sdfs[@]}"
fi
shopt -u nullglob
export SDF_max SDF_min

RTL_REF=""
EXTRA=""
if [ -f "$PNR_DIR/pnr.env" ]; then
  EXTRA="$PNR_DIR/pnr.env"
  RTL_REF="$(bash -c 'source "$1" >/dev/null 2>&1; echo "${RTL_REF:-}"' _ "$EXTRA")"
fi
for f in $(printf '%s\n' "$NETLIST" "$SDF_max" "$SDF_min" "$SDC" ${EXTRA:+"$EXTRA"} | awk '!seen[$0]++'); do
  log "  $(sha256sum "$f" | cut -c1-16)  $(du -h "$f" | cut -f1)  $f"
done
log "sdf:     $SDF_MODE"

# ---- the golden ------------------------------------------------------------------------
if [ -z "$GOLDEN" ]; then
  if [ -n "$RTL_REF" ]; then
    mapfile -t gs < <(ls -d "$R"/postpnr/golden/"${RTL_REF:0:12}"* 2>/dev/null)
  else
    mapfile -t gs < <(ls -d "$R"/postpnr/golden/*/ 2>/dev/null)
  fi
  [ ${#gs[@]} -eq 1 ] || stop "found ${#gs[@]} goldens in postpnr/golden${RTL_REF:+ for RTL_REF=$RTL_REF}: pass --golden"
  GOLDEN="${gs[0]%/}"
fi
GOLDEN="$(cd "$GOLDEN" && pwd)"
[ -f "$GOLDEN/GOLDEN" ] && [ -f "$GOLDEN/images/MANIFEST" ] && [ -d "$GOLDEN/rtl/hdl" ] \
  || stop "$GOLDEN is not a complete golden (postpnr/prepare.sh writes one)"
gsha="$(awk '/^rtl_sha:/{print $2}' "$GOLDEN/GOLDEN")"
log "golden:  $GOLDEN (RTL $gsha)"
if [ -n "$RTL_REF" ]; then
  [[ "$gsha" == "$RTL_REF"* ]] || stop "pnr.env says RTL_REF=$RTL_REF but the golden is RTL $gsha"
else
  log "WARNING: no RTL_REF in pnr.env -- cannot prove the netlist came from golden RTL $gsha"
fi
export GOLDEN OUT MAX_ERRORS

# ---- the SDC ------------------------------------------------------------------------------
python3 "$R/postpnr/sdc_delays.py" "$SDC" > "$OUT/sdc.txt" 2>&1 || { cat "$OUT/sdc.txt" >> "$SUM"; stop "the SDC cannot drive the bench (above)"; }
python3 "$R/postpnr/sdc_delays.py" "$SDC" --sh > "$OUT/sdc.env"
cat "$OUT/sdc.txt" >> "$SUM"; cat "$OUT/sdc.txt"
# shellcheck disable=SC1091
source "$OUT/sdc.env"
export PLUSARGS_max="$PLUSARGS_MAX" PLUSARGS_min="$PLUSARGS_MIN"
# The VCS RTL cross-check runs at the bench defaults, like the golden.
export PLUSARGS_RTL=""

# ---- builds ----------------------------------------------------------------------------------
export PIN_NETLIST="$NETLIST" PIN_RTL_ROOT="$GOLDEN/rtl"
[ -n "$EXTRA" ] && export PIN_PATHS_EXTRA="$EXTRA"
if [ -s "$R/postpnr/waivers.txt" ] && grep -qvE '^[[:space:]]*(#|$)' "$R/postpnr/waivers.txt"; then
  export PIN_WAIVERS="$R/postpnr/waivers.txt"
  log "WAIVERS: $(grep -cvE '^[[:space:]]*(#|$)' "$PIN_WAIVERS") pattern(s) in postpnr/waivers.txt -- waived violations are still listed"
fi
[ -n "${INITREG:-}" ] && log "WARNING: INITREG=$INITREG -- registers start at a value, not X: NOT a sign-off run"
IFS=, read -r -a CORN <<<"$CORNERS"
for c in "${CORN[@]}"; do case "$c" in max|min) ;; *) stop "--corners: $c is not max or min";; esac; done
SIM=vcs DUT=gate PIN_SDF="$SDF_max" "$P/pin.sh" preflight > "$OUT/preflight.log" 2>&1 \
  || { cat "$OUT/preflight.log" >> "$SUM"; stop "preflight"; }
for c in "${CORN[@]}"; do
  v="SDF_$c"
  if [ $BUILD = 1 ]; then
    log "build:   gate, SDF $c corner ($(basename "${!v}"))"
    SIM=vcs DUT=gate PIN_SDF="${!v}" PIN_SDF_CORNER="$c" "$P/pin.sh" build > "$OUT/build_$c.log" 2>&1 &
    bpid=$!
    heartbeat $bpid "$OUT/build_$c.log" "building $c corner ($OUT/build_$c.log)"
    wait $bpid \
      || { tail -45 "$OUT/build_$c.log" >> "$SUM"; stop "gate build, $c corner (SDFCOM messages fail it: above, and $OUT/build_$c.log)"; }
  fi
  grep -E '^build: SDF' "$OUT/build_$c.log" 2>/dev/null | sed 's/^/         /' | tee -a "$SUM"
done
if [ $VCS_RTL = 1 ]; then
  log "build:   golden RTL under VCS"
  SIM=vcs DUT=rtl "$P/pin.sh" build > "$OUT/build_rtl.log" 2>&1 &
  bpid=$!
  heartbeat $bpid "$OUT/build_rtl.log" "building VCS RTL ($OUT/build_rtl.log)"
  wait $bpid || { tail -30 "$OUT/build_rtl.log" >> "$SUM"; stop "VCS RTL build"; }
fi

# ---- runs -----------------------------------------------------------------------------------
: > "$OUT/jobs"
while read -r name duts; do
  [[ " $duts " == *" gate "* ]] || continue
  [ -z "$ONLY" ] || [[ "$name" =~ $ONLY ]] || continue
  [ -d "$GOLDEN/traces/$name" ] || { log "SKIP $name: no golden trace"; continue; }
  for c in "${CORN[@]}"; do echo "$c $name" >> "$OUT/jobs"; done
  [ $VCS_RTL = 1 ] && echo "rtl $name" >> "$OUT/jobs"
done < "$GOLDEN/images/MANIFEST"
for c in "${CORN[@]}" rtl; do mkdir -p "$OUT/runs/$c"; done
log "runs:    $(wc -l < "$OUT/jobs") ($(cut -d' ' -f2 "$OUT/jobs" | sort -u | wc -l) images x ${CORN[*]}$([ $VCS_RTL = 1 ] && echo ' + vcs rtl')), $JOBS at a time"
log "         a 'start' line when each simulation begins, its row when it ends; per-run logs in $OUT/runs/<corner>/<name>.pin.log"
log ""
xargs -a "$OUT/jobs" -P "$JOBS" -L1 "$0" __one | tee "$OUT/rows.unsorted"

# ---- summary -----------------------------------------------------------------------------------
log ""
log "==== results (sorted)"
sort -k2,2 -k3,3 "$OUT/rows.unsorted" >> "$SUM"
total=$(wc -l < "$OUT/rows.unsorted")
pass=$(grep -c '^PASS' "$OUT/rows.unsorted" || true)
for c in "${CORN[@]}" rtl; do
  n=$(awk -v c="$c" '$3==c' "$OUT/rows.unsorted" | wc -l); [ "$n" = 0 ] && continue
  p=$(awk -v c="$c" '$3==c && $1=="PASS"' "$OUT/rows.unsorted" | wc -l)
  tv=$(awk -v c="$c" '$3==c' "$OUT/rows.unsorted" | grep -o 'tchk=[0-9]*' | awk -F= '{t+=$2} END{print t+0}')
  log "corner $c: $p/$n pass, $tv timing violation(s) in total"
done
ins="$(for f in "$OUT"/runs/{max,min}/*/sim.log.gz; do [ -f "$f" ] && zcat "$f" | grep -m1 'clk_out insertion' | sed "s|^|$(basename "$(dirname "$(dirname "$f")")") |"; done 2>/dev/null | sort -u | head -4)"
[ -n "$ins" ] && log "$ins"
log "TOTAL: $pass/$total pass$([ -n "${INITREG:-}" ] && echo "  (INITREG=$INITREG: not sign-off)")"
pack
[ "$pass" = "$total" ] && [ "$total" -gt 0 ]
