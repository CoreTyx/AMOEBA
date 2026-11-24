#!/bin/bash
# postpnr/run.sh -- post-PnR chip-level verification, on the VCS VM.
#
#   postpnr/run.sh [options]
#
# The netlist and SDF come from vm_paths.sh when it sets NETLIST=... and
# SDF=... (one SDF with min:typ:max triples, .gz allowed), and SDC=... there is
# optional.  Otherwise they come from the drop folder, PNR_DIR=... (the
# environment, else vm_paths.sh):
#   forte_top.v (or the one *.v / *.v.gz)    the post-PnR netlist (ports as forte_top)
#   forte_top.sdc (or the one *.sdc)         the SDC PnR signed off with
#   *.sdf[.gz]: one SDF with min:typ:max triples, or one per corner whose name
#               says which (*max*.sdf / *min*.sdf, also *ss*/*ff*, *slow*/*fast*)
#   pnr.env     optional: RTL_REF=<sha> (the commit the netlist came from; the
#               golden must be that commit's), and any vm_paths.sh override
#               (STDCELL_MODELS=(...), VCS_FLAGS=(...), ...)
# With no SDC anywhere, --clk-mhz is required, and the I/O timing is derived
# from the clock: inputs launched 25% (max corner) / 10% (min corner) of a
# period after the core_clk edge, outputs sampled at 75% (so they must settle
# within the first 75% of the cycle), and no pad output-window check.  SUMMARY
# says so.  That is a "does it run at this clock" test, not an I/O sign-off.
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
#   --clk-mhz MHZ      run core_clk at MHZ instead of the SDC's period (needed
#                      when there is no SDC): the target-frequency test.  The SDC's I/O delays are board
#                      delays and stay as they are; everything derived from the
#                      period follows MHZ (postpnr/sdc_delays.py --period).
#                      The period is rounded to a whole even number of ps.
#                      SUMMARY and the TOTAL line name the clock either way.
#   --cycle-slack N    netlist rows: the link trace must match the golden's
#                      record for record (type, address, data, order) and each
#                      record's cycle may differ by at most N; the console must
#                      still match; the per-cycle pin trace is not compared.
#                      For clock-domain crossings that resolve an edge earlier
#                      or later than in RTL.  Default 0: cycle-exact.  The row
#                      shows the largest shift, trace=MATCH(+-S)
#   --no-cycles        netlist rows: the link trace must match the golden's in
#                      type, address, data and order, at any cycle; the console
#                      must still match; the per-cycle pin trace is not compared.
#                      NOT a sign-off run
#   --reorder N        netlist rows: as --cycle-slack N, but transactions to
#                      different addresses may also swap places (I- and D-cache
#                      fills reaching the bus in a different order after a
#                      timing shift).  Every transaction must still appear with
#                      the same content; same-address records, writes, tohost
#                      and interrupts keep their order.  Row: trace=MATCH(+-S)
#   --no-cycles, --cycle-slack and --reorder: at most one
#   --recrem-as-setuphold
#                      simulate a copy of the SDF with each RECREM written as
#                      SETUPHOLD (same pins, edges and values), for cell models
#                      that check an async reset with $setuphold(posedge CK,
#                      negedge R) and have no $recrem: VCS drops a RECREM it
#                      has no $recrem for without a message, and the model's
#                      placeholder limits are checked instead
#   --ignore-neg-delay SDFCOM_NIOD (VCS: negative IOPATH delay) does not fail
#                      the build; the build line and SUMMARY count them, and
#                      TOTAL says the run is not sign-off
#   --vm-paths FILE    the model paths (vm_paths.sh format) to use; default:
#                      $VM_PATHS, else vm_paths.sh beside this checkout
#                      (../vm_paths.sh), else hvl/pin/vm_paths.sh
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
#         are exactly the golden RTL's (bin/pin_trace_cmp.py); with --cycle-slack
#         N, the link transactions within N cycles and no per-cycle pin check
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
      > "$runs/$n.pin.log" 2>&1 </dev/null || true
  d="$runs/$n"
  mkdir -p "$d"          # pin.sh may have died before making it
  res="$(cat "$d/RESULT" 2>/dev/null || echo 'PIN_TB_RESULT: FAIL no RESULT (see '"$runs/$n.pin.log"')')"
  # func: the bench's own verdict, before pin.sh folded the timing checks in
  if [[ "$res" == "PIN_TB_RESULT: PASS"* ]] || [[ "$res" == *"; bench: functionally ok"* ]]; then func=PASS; else func=FAIL; fi
  tchk=0 waived=0
  [ -f "$d/TCHK_COUNT" ] && { eval "$(cat "$d/TCHK_COUNT")"; tchk=$((tchk - waived)); }
  win="$(zcat -f "$d/sim.log" 2>/dev/null | grep -c '\[PIN_IO\] ERROR.*output window' || true)"
  # --cycle-slack applies to the netlist only: VCS RTL must match the golden exactly.
  cs=(); [ "$corner" != rtl ] && [ "${CYCLE_SLACK:-0}" -gt 0 ] && cs=(--cycle-slack="$CYCLE_SLACK")
  [ "$corner" != rtl ] && [ "${REORDER:-0}" -gt 0 ] && cs=(--reorder="$REORDER")
  [ "$corner" != rtl ] && [ "${NO_CYCLES:-0}" = 1 ] && cs=(--no-cycles)
  if python3 "$R/bin/pin_trace_cmp.py" "$GOLDEN/traces/$n" "$d" ${cs[@]+"${cs[@]}"} > "$d/CMP" 2>&1; then trace=MATCH
  elif grep -q '^MISMATCH' "$d/CMP"; then trace=DIFF
  else trace=NONE; fi
  tshow=$trace
  if [ $trace = MATCH ] && [ "${cs[0]:-}" != --no-cycles ] && [ ${#cs[@]} -gt 0 ]; then
    tshow="MATCH(+-$(grep -oE 'cycle shift \+-[0-9]+' "$d/CMP" | grep -oE '[0-9]+$' || echo '?'))"
  fi
  ok=PASS
  [ $func = PASS ] && [ "$tchk" = 0 ] && [ "$win" = 0 ] && [ $trace = MATCH ] || ok=FAIL
  why=""
  [ $func = PASS ] || why="${res#PIN_TB_RESULT: }"
  [ $trace = MATCH ] || why="${why:+$why; }$(head -1 "$d/CMP" | cut -c1-160)"
  [ -n "${INITREG:-}" ] && why="${why:+$why; }INITREG=$INITREG"
  [ -f "$d/sim.log" ] && gzip -f "$d/sim.log"
  rm -f "$d/memory.lst"
  printf '%-4s %-40s %-4s func=%s tchk=%s%s win=%s trace=%s%s\n' "$ok" "$n" "$corner" "$func" "$tchk" \
         "$([ "$waived" -gt 0 ] && echo "(+${waived}w)")" "$win" "$tshow" "${why:+  $why}" | tee "$d/ROW"
  exit 0
fi

# ---- options ---------------------------------------------------------------------------
ONLY="" CORNERS="max,min" JOBS=1 GOLDEN="" VCS_RTL=0 MAX_ERRORS=1 BUILD=1 VMP="${VM_PATHS:-}" CLK_MHZ="" IGN_NIOD=0 RECREM_SH=0 CYCLE_SLACK=0 NO_CYCLES=0 REORDER=0
while [ $# -gt 0 ]; do
  case "$1" in
    --only) ONLY="$2"; shift;;
    --corners) CORNERS="$2"; shift;;
    --jobs) JOBS="$2"; shift;;
    --golden) GOLDEN="$2"; shift;;
    --with-vcs-rtl) VCS_RTL=1;;
    --max-errors) MAX_ERRORS="$2"; shift;;
    --no-build) BUILD=0;;
    --clk-mhz) CLK_MHZ="$2"; shift;;
    --vm-paths) VMP="$2"; shift;;
    --ignore-neg-delay) IGN_NIOD=1;;
    --recrem-as-setuphold) RECREM_SH=1;;
    --cycle-slack) CYCLE_SLACK="$2"; shift;;
    --no-cycles) NO_CYCLES=1;;
    --reorder) REORDER="$2"; shift;;
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

# ---- the model paths (vm_paths.sh) --------------------------------------------------------
if [ -z "$VMP" ]; then
  for f in "$R/../vm_paths.sh" "$P/vm_paths.sh"; do [ -f "$f" ] && { VMP="$f"; break; }; done
fi
[ -n "$VMP" ] && [ -f "$VMP" ] \
  || stop "no vm_paths.sh${VMP:+ at $VMP}: put one beside this checkout ($(cd "$R/.." && pwd)/vm_paths.sh), or pass --vm-paths"
VMP="$(cd "$(dirname "$VMP")" && pwd)/$(basename "$VMP")"
export PIN_VM_PATHS="$VMP"

# ---- where the netlist, SDF and SDC come from ------------------------------------------------
# vm_paths.sh's NETLIST= and SDF= (and SDC=, optional) win; else the drop folder.
mapfile -t vv < <(bash -c 'set +u; NETLIST=; SDF=; SDC=; PNR_DIR=; source "$1" >/dev/null 2>&1 </dev/null
                           printf "%s\n%s\n%s\n%s\n" "$NETLIST" "$SDF" "$SDC" "$PNR_DIR"' _ "$VMP")
V_NETLIST="${vv[0]:-}" V_SDF="${vv[1]:-}" V_SDC="${vv[2]:-}"
PNR_FROM="environment"
if [ -z "${PNR_DIR:-}" ]; then PNR_DIR="${vv[3]:-}"; PNR_FROM="$VMP"; fi
if [ -n "$V_NETLIST" ] || [ -n "$V_SDF" ]; then
  [ -n "$V_NETLIST" ] && [ -n "$V_SDF" ] \
    || stop "$VMP sets $([ -n "$V_NETLIST" ] && echo NETLIST || echo SDF) but not $([ -n "$V_NETLIST" ] && echo SDF || echo NETLIST): set both, or neither to use the drop folder"
  SRC=vm_paths
  log "design:  NETLIST and SDF from $VMP"
else
  SRC=drop
  [ -n "$PNR_DIR" ] || stop "no netlist: set NETLIST=... and SDF=... in $VMP, or PNR_DIR to the post-PnR drop folder (environment or $VMP)"
fi
if [ -n "$PNR_DIR" ]; then
  [ -d "$PNR_DIR" ] || stop "PNR_DIR=$PNR_DIR (from $PNR_FROM) is not a directory"
  PNR_DIR="$(cd "$PNR_DIR" && pwd)"
  log "drop:    $PNR_DIR  (PNR_DIR from $PNR_FROM)$([ $SRC = vm_paths ] && echo ": SDC and pnr.env only")"
fi
log "paths:   $VMP"
# Source it here too (in a subshell, so it cannot touch this script's variables)
# and list every entry of every array, exactly as pin.sh will use them
# ("${ARRAY[@]}"); pin.sh preflight then checks every file.
bash -c 'set +u; STDCELL_MODELS=(); SRAM_MODELS=(); PAD_MODELS=(); PDK_FIRST=(); VCS_FLAGS=(); IGNORE_CELLS=()
  source "$1" >/dev/null || exit 1
  for a in STDCELL_MODELS SRAM_MODELS PAD_MODELS PDK_FIRST VCS_FLAGS IGNORE_CELLS; do
    declare -n x=$a
    printf "         %-15s %s\n" "$a" "${#x[@]} entr$([ ${#x[@]} = 1 ] && echo y || echo ies)"
    for e in "${x[@]}"; do printf "           %s\n" "$e"; done
  done' _ "$VMP" | tee -a "$SUM" || stop "sourcing $VMP failed"

# The bundle's own check (postpnr/pack.sh): every file as packed.
if [ -f "$R/postpnr/BUNDLE.sha256" ]; then
  ( cd "$R" && sha256sum -c --quiet postpnr/BUNDLE.sha256 ) > "$OUT/bundle_check.log" 2>&1 \
    || { head -20 "$OUT/bundle_check.log" >> "$SUM"; stop "files differ from the bundle (above): unpack it again"; }
  log "bundle:  $(head -1 "$R/postpnr/BUNDLE" 2>/dev/null) -- all $(wc -l < "$R/postpnr/BUNDLE.sha256") files verified"
fi

# ---- the design files ------------------------------------------------------------------------
unz() {   # unz <file>: the file, gunzipped into $OUT/drop if need be
  local f="$1"
  [ -f "$f" ] || { echo "ERR:$f: no such file"; return; }
  if [[ "$f" == *.gz ]]; then
    mkdir -p "$OUT/drop"; gunzip -c "$f" > "$OUT/drop/$(basename "${f%.gz}")"; f="$OUT/drop/$(basename "${f%.gz}")"
  fi
  echo "$(cd "$(dirname "$f")" && pwd)/$(basename "$f")"
}
one_file() {   # one_file <desc> <glob>...: the first glob with matches in $PNR_DIR must have exactly one
  local desc="$1" f g; shift
  local hits=()
  shopt -s nullglob
  for g in "$@"; do
    for f in "$PNR_DIR"/$g; do [ -f "$f" ] && hits+=("$f"); done
    [ ${#hits[@]} -gt 0 ] && break
  done
  shopt -u nullglob
  [ ${#hits[@]} -eq 1 ] || { echo "ERR:$desc: ${#hits[@]} candidates (${hits[*]:-none}) in $PNR_DIR for $*" ; return; }
  unz "${hits[0]}"
}
SDF_max="" SDF_min="" SDF_max_src=""
if [ $SRC = vm_paths ]; then
  NETLIST="$(unz "$V_NETLIST")"
  SDF_max="$(unz "$V_SDF")"; SDF_min="$SDF_max"; SDF_MODE="one SDF from vm_paths.sh, min:typ:max triples"
  [[ "$NETLIST" == ERR:* ]] && stop "NETLIST in $VMP: ${NETLIST#ERR:}"
  [[ "$SDF_max" == ERR:* ]] && stop "SDF in $VMP: ${SDF_max#ERR:}"
else
  NETLIST="$(one_file netlist forte_top.v forte_top.v.gz '*.v' '*.v.gz')"
  [[ "$NETLIST" == ERR:* ]] && stop "${NETLIST#ERR:}"
  shopt -s nullglob nocaseglob
  sdfs=("$PNR_DIR"/*.sdf "$PNR_DIR"/*.sdf.gz)
  shopt -u nocaseglob nullglob
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
fi
# --recrem-as-setuphold: RECREM (reset) (clock) (recovery) (removal) is the
# check $setuphold(clock, reset, setup, hold) makes, so the keyword is rewritten
# in a line-for-line copy: pins, edges and values untouched, and SDF line numbers
# unchanged (pin.sh's SDF-message checks cite them).  Cached in postpnr/work/sdf/
# by the source's path, size and mtime, so an unchanged SDF is not recompiled.
RECREM_RE='\([[:space:]]*RECREM([[:space:]]|$)'
recrem_sdf() {   # recrem_sdf <sdf>: the copy's path, or ERR:<why>
  local src="$1" d="$R/postpnr/work/sdf" key dst
  key="$(stat -L -c '%n %s %Y' "$src")"
  dst="$d/$(printf '%s' "$src" | sha256sum | cut -c1-12)_$(basename "${src%.sdf}").recrem.sdf"
  mkdir -p "$d"
  if [ ! -f "$dst" ] || [ "$(cat "$dst.key" 2>/dev/null)" != "$key" ]; then
    sed -E "s/$RECREM_RE/(SETUPHOLD\1/g" "$src" > "$dst.tmp" || { echo "ERR:rewriting $src failed"; return; }
    [ "$(wc -l < "$src")" = "$(wc -l < "$dst.tmp")" ] || { echo "ERR:$dst.tmp: line count differs from $src"; return; }
    ! grep -qE "$RECREM_RE" "$dst.tmp" || { echo "ERR:$dst.tmp still has RECREM"; return; }
    mv -f "$dst.tmp" "$dst"; echo "$key" > "$dst.key"
  fi
  echo "$dst"
}
if [ $RECREM_SH = 1 ]; then
  for c in max min; do
    v="SDF_$c"; src="${!v}"
    n="$(grep -cE "$RECREM_RE" "$src" || true)"
    if [ "$n" = 0 ]; then log "sdf:     --recrem-as-setuphold: $(basename "$src") has no RECREM, used as it is"; continue; fi
    if [ $c = min ] && [ "$src" = "$SDF_max_src" ]; then SDF_min="$SDF_max"; continue; fi
    out="$(recrem_sdf "$src")"; [[ "$out" == ERR:* ]] && stop "--recrem-as-setuphold: ${out#ERR:}"
    log "sdf:     --recrem-as-setuphold: $n RECREM -> SETUPHOLD ($c corner), simulating $out"
    printf -v "$v" '%s' "$out"; [ $c = max ] && SDF_max_src="$src"
  done
fi
export SDF_max SDF_min
# The SDC: vm_paths.sh's SDC=, else the drop folder's one *.sdc, else none.
SDC=""
if [ -n "$V_SDC" ]; then
  SDC="$(unz "$V_SDC")"; [[ "$SDC" == ERR:* ]] && stop "SDC in $VMP: ${SDC#ERR:}"
elif [ -n "$PNR_DIR" ] && compgen -G "$PNR_DIR/*.sdc" >/dev/null; then
  SDC="$(one_file sdc forte_top.sdc '*.sdc')"; [[ "$SDC" == ERR:* ]] && stop "${SDC#ERR:}"
fi

RTL_REF=""
EXTRA=""
if [ -n "$PNR_DIR" ] && [ -f "$PNR_DIR/pnr.env" ]; then
  EXTRA="$PNR_DIR/pnr.env"
  RTL_REF="$(bash -c 'source "$1" >/dev/null 2>&1; echo "${RTL_REF:-}"' _ "$EXTRA")"
fi
for f in $(printf '%s\n' "$NETLIST" "$SDF_max" "$SDF_min" ${SDC:+"$SDC"} ${EXTRA:+"$EXTRA"} | awk '!seen[$0]++'); do
  log "  $(sha256sum "$f" | cut -c1-16)  $(du -h "$f" | cut -f1)  $f"
done
log "sdf:     $SDF_MODE"
[ -n "$SDC" ] || log "sdc:     NONE -- I/O timing derived from --clk-mhz (see below); not an I/O timing sign-off"

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
  log "WARNING: no RTL_REF (drop/pnr.env) -- cannot prove the netlist came from golden RTL $gsha"
fi
export GOLDEN OUT MAX_ERRORS CYCLE_SLACK NO_CYCLES REORDER

# ---- the SDC ------------------------------------------------------------------------------
# --clk-mhz: the period in ns, a whole even number of ps so the bench's
# half-period is exact in its 1 ps time precision.
PERIOD=()
if [ -n "$CLK_MHZ" ]; then
  awk -v f="$CLK_MHZ" 'BEGIN { exit !(f + 0 > 0 && f ~ /^[0-9]*\.?[0-9]+$/) }' \
    || stop "--clk-mhz $CLK_MHZ: give a positive number of MHz"
  PERIOD=(--period "$(awk -v f="$CLK_MHZ" 'BEGIN { printf "%.3f", 2 * int(500000 / f + 0.5) / 1000 }')")
fi
if [ -z "$SDC" ]; then
  # No SDC: derive the bench's I/O timing from the clock alone (header).  The
  # generated SDC goes through the same sdc_delays.py and its checks; the pad
  # output-window plusargs are dropped below (no set_output_delay to check).
  [ -n "$CLK_MHZ" ] || stop "no SDC (SDC= in $VMP, or one *.sdc in the drop folder): give --clk-mhz MHZ"
  SDC="$OUT/generated.sdc"
  awk -v p="${PERIOD[1]}" 'BEGIN {
    printf "# generated by postpnr/run.sh: no SDC was given; I/O timing from --clk-mhz\n"
    printf "create_clock -name core_clk -period %s [get_ports core_clk]\n", p
    printf "set_input_delay -max %.3f -clock core_clk [get_ports {io_in[*] ready rvalid}]\n", 0.25 * p
    printf "set_input_delay -min %.3f -clock core_clk [get_ports {io_in[*] ready rvalid}]\n", 0.10 * p
    printf "set_false_path -from [get_ports {rst_n irq[*] uart_rx test_mode scan_en fault_inject}]\n"
    printf "set_output_delay -max %.3f -clock core_clk [get_ports {io_out[*] req wr uart_tx status}]\n", 0.25 * p
    printf "set_output_delay -min 0 -clock core_clk [get_ports {io_out[*] req wr uart_tx status}]\n" }' > "$SDC"
  NO_SDC=1
  PERIOD=()
fi
python3 "$R/postpnr/sdc_delays.py" "$SDC" ${PERIOD[@]+"${PERIOD[@]}"} > "$OUT/sdc.txt" 2>&1 \
  || { cat "$OUT/sdc.txt" >> "$SUM"; cat "$OUT/sdc.txt"; stop "the SDC${CLK_MHZ:+ at --clk-mhz $CLK_MHZ} cannot drive the bench (above)"; }
python3 "$R/postpnr/sdc_delays.py" "$SDC" ${PERIOD[@]+"${PERIOD[@]}"} --sh > "$OUT/sdc.env"
cat "$OUT/sdc.txt" >> "$SUM"; cat "$OUT/sdc.txt"
# shellcheck disable=SC1091
source "$OUT/sdc.env"
CLK_NOTE="clock $(awk -v p="$CLK_PS" 'BEGIN { printf "%g ns = %g MHz", p / 1000, 1e6 / p }')"
if [ -n "${NO_SDC:-}" ]; then
  CLK_NOTE="$CLK_NOTE (--clk-mhz $CLK_MHZ, NO SDC: inputs at 25%/10% of the period, outputs sampled at 75%, no output-window check)"
elif [ "$CLK_PS" != "$SDC_CLK_PS" ]; then
  CLK_NOTE="$CLK_NOTE (--clk-mhz $CLK_MHZ; the SDC's is $(awk -v p="$SDC_CLK_PS" 'BEGIN { printf "%g ns", p / 1000 }'))"
else
  CLK_NOTE="$CLK_NOTE (the SDC's)"
fi
log "clock:   ${CLK_NOTE#clock }"
# Wires from the pad drivers to forte_top's output ports: VCS cannot annotate
# them (SDFCOM_UHICD, accepted by pin.sh only for exactly these), so outputs
# change up to that much earlier in simulation than on silicon.  The max corner
# (setup side) therefore checks each output group's window that much earlier:
# a pass then holds with the wire included.  The min corner needs nothing: an
# output that changes earlier only makes its hold-side check stricter.
WIRES_N=0
if [ -n "${NO_SDC:-}" ]; then
  # No set_output_delay to check: no pad window, so no window compensation.
  # The sample points stay (outputs must have settled by 75% of the period).
  PLUSARGS_MAX="$(sed -E 's/ ?\+OUT_M(AX|IN)_[A-Z]+_PS=-?[0-9]+//g' <<<"$PLUSARGS_MAX")"
  PLUSARGS_MIN="$(sed -E 's/ ?\+OUT_M(AX|IN)_[A-Z]+_PS=-?[0-9]+//g' <<<"$PLUSARGS_MIN")"
else
  python3 "$R/postpnr/sdf_out_wires.py" "$SDF_max" > "$OUT/wires.env" || stop "postpnr/sdf_out_wires.py $SDF_max failed"
  # shellcheck disable=SC1091
  source "$OUT/wires.env"
fi
if [ "$WIRES_N" -gt 0 ]; then
  for g in LINK SLOW; do
    w="WIRES_${g}_PS"; o="OUT_MAX_${g}_PS"
    [ -n "${!o}" ] && [ "${!w}" -gt 0 ] || continue
    PLUSARGS_MAX="$(sed "s/+OUT_MAX_${g}_PS=[0-9]*/+OUT_MAX_${g}_PS=$(( ${!o} + ${!w} ))/" <<<"$PLUSARGS_MAX")"
  done
  log "  pad wires      $WIRES_N INTERCONNECT(s) into forte_top output ports, not annotatable in VCS (SDFCOM_UHICD); largest:"
  log "                 io_out/req/wr $(awk -v p="$WIRES_LINK_PS" 'BEGIN{printf "%.3f", p/1000}') ns, uart_tx/status $(awk -v p="$WIRES_SLOW_PS" 'BEGIN{printf "%.3f", p/1000}') ns, clk_out $(awk -v p="$WIRES_CLK_PS" 'BEGIN{printf "%.3f", p/1000}') ns"
  log "                 -> max corner: outputs must settle that much earlier than the SDC says ($(grep -oE '\+OUT_MAX_[A-Z]+_PS=[0-9]+' <<<"$PLUSARGS_MAX" | tr '\n' ' '))"
fi
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
[[ "$CYCLE_SLACK" =~ ^[0-9]+$ ]] || stop "--cycle-slack needs a whole number of cycles, not '$CYCLE_SLACK'"
[ "$CYCLE_SLACK" -gt 0 ] && log "trace:   --cycle-slack $CYCLE_SLACK: netlist link transactions must match the golden in content and order, each within $CYCLE_SLACK cycles; console exact; per-cycle pin trace NOT compared"
[[ "$REORDER" =~ ^[0-9]+$ ]] || stop "--reorder needs a whole number of cycles, not '$REORDER'"
[ $((NO_CYCLES + (CYCLE_SLACK > 0) + (REORDER > 0))) -gt 1 ] && stop "--no-cycles, --cycle-slack, --reorder: pick one"
[ "$REORDER" -gt 0 ] && log "trace:   --reorder $REORDER: netlist link transactions must match the golden in content, each within $REORDER cycles; different addresses may swap; same-address records and writes keep their order; console exact; per-cycle pin trace NOT compared"
[ $NO_CYCLES = 1 ] && log "WARNING: --no-cycles -- netlist link transactions must match the golden in content and order at any cycle; console exact; per-cycle pin trace NOT compared: NOT a sign-off run"
[ $IGN_NIOD = 1 ] && log "WARNING: --ignore-neg-delay -- SDFCOM_NIOD (negative IOPATH delay) does not fail the build: NOT a sign-off run"
IFS=, read -r -a CORN <<<"$CORNERS"
for c in "${CORN[@]}"; do case "$c" in max|min) ;; *) stop "--corners: $c is not max or min";; esac; done
log "preflight: tools, model paths, netlist ports and cells ($OUT/preflight.log)"
SIM=vcs DUT=gate PIN_SDF="$SDF_max" "$P/pin.sh" preflight > "$OUT/preflight.log" 2>&1 </dev/null \
  || { cat "$OUT/preflight.log" >> "$SUM"; cat "$OUT/preflight.log"; stop "preflight"; }
grep -E '^(preflight: OK|  )' "$OUT/preflight.log" | sed 's/^/         /' | tee -a "$SUM"
for c in "${CORN[@]}"; do
  v="SDF_$c"
  if [ $BUILD = 1 ]; then
    log "build:   gate, SDF $c corner ($(basename "${!v}"))"
    SIM=vcs DUT=gate PIN_SDF="${!v}" PIN_SDF_CORNER="$c" PIN_SDF_IGNORE_NIOD=$IGN_NIOD "$P/pin.sh" build > "$OUT/build_$c.log" 2>&1 </dev/null &
    bpid=$!
    heartbeat $bpid "$OUT/build_$c.log" "building $c corner ($OUT/build_$c.log)"
    wait $bpid \
      || { tail -45 "$OUT/build_$c.log" | tee -a "$SUM"
           why="$(grep -E '^pin\.sh: ' "$OUT/build_$c.log" | tail -1)"
           stop "gate build, $c corner: ${why:-see above} ($OUT/build_$c.log)"; }
  fi
  grep -E '^build: (SDF|ignored|dropped|--ignore-neg-delay)' "$OUT/build_$c.log" 2>/dev/null | sed 's/^/         /' | tee -a "$SUM"
done
if [ $VCS_RTL = 1 ]; then
  log "build:   golden RTL under VCS"
  SIM=vcs DUT=rtl "$P/pin.sh" build > "$OUT/build_rtl.log" 2>&1 </dev/null &
  bpid=$!
  heartbeat $bpid "$OUT/build_rtl.log" "building VCS RTL ($OUT/build_rtl.log)"
  wait $bpid || { tail -30 "$OUT/build_rtl.log" | tee -a "$SUM"; stop "VCS RTL build"; }
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
xargs -r -a "$OUT/jobs" -P "$JOBS" -L1 "$0" __one | tee "$OUT/rows.unsorted"

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
log "TOTAL: $pass/$total pass  $CLK_NOTE$([ -n "${INITREG:-}" ] && echo "  (INITREG=$INITREG: not sign-off)")$([ $IGN_NIOD = 1 ] && echo "  (--ignore-neg-delay: not sign-off)")$([ "$CYCLE_SLACK" -gt 0 ] && echo "  (--cycle-slack $CYCLE_SLACK)")$([ "$REORDER" -gt 0 ] && echo "  (--reorder $REORDER)")$([ $NO_CYCLES = 1 ] && echo "  (--no-cycles: not sign-off)")"
pack
[ "$pass" = "$total" ] && [ "$total" -gt 0 ]
