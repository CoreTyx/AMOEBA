#!/bin/bash
# hvl/pin/vm_run.sh -- the whole post-synthesis check, one command, on the VM.
#
#   1. on a machine with the repo: hvl/pin/vm_pack.sh  ->  sim/pin/vm_bundle.tgz
#   2. on the VM: tar -xzf vm_bundle.tgz -C <dir>; once, cp hvl/pin/vm_paths.example.sh
#      hvl/pin/vm_paths.sh and fill it in; load VCS (which vcs)
#   3. hvl/pin/vm_run.sh [stage ...]          default: all stages, in order
#
# Stages (each stops the run if it fails, except `regress`, which records
# per-image results and carries on):
#   preflight   tools, paths, netlist ports, macro models     (seconds)
#   selftest    harness self-test under VCS, incl. X checks   (minutes)
#   build       pin_tb for rtl and gate                       (minutes)
#   regress     every image in MANIFEST on rtl, then gate, then a cycle-exact
#               trace comparison                              (long)
#   xstress     4-state stress on XLIST (default: the directed tests and the
#               baremetal tier), rtl and gate: the bus is driven X whenever
#               nobody owns it and every input is X while rst_n is low.  Must
#               pass; a failure is an X the chip lets in, or a reset that does
#               not dominate.
#   xmem        as xstress, plus unwritten memory reads back X.  INFORMATIONAL:
#               a store into a line filled from never-written memory merges
#               into X bytes, and the D$'s line-wide ECC then encodes X, which
#               silicon (consistent garbage) never sees.  Read its failures as
#               leads, not verdicts.
# ONLY=<regex> restricts regress to matching image names; SKIP_RTL=1 reuses the
# rtl runs of a previous invocation.
#
# Output: sim/pin/vm_results/SUMMARY (paste this back) and
# sim/pin/vm_results.tgz (logs, traces, consoles -- send this if asked).
set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
P="$R/hvl/pin"
IMG="$R/sim/pin/images"
OUT="$R/sim/pin/vm_results"
STAGES=("$@"); [ ${#STAGES[@]} -gt 0 ] || STAGES=(preflight selftest build regress xstress)
XLIST="${XLIST:-^(smoke|uart_echo|irq|bm_.*)$}"
XARGS=(+FPGA_IO_IDLE=x +FPGA_X_IN_RESET)
mkdir -p "$OUT"
SUM="$OUT/SUMMARY"
[ -f "$SUM" ] || : > "$SUM"
log() { echo "$*" | tee -a "$SUM"; }
stop() { log "STOPPED: $*"; pack; exit 1; }
pack() { tar -C "$R/sim/pin" -czf "$R/sim/pin/vm_results.tgz" vm_results runs 2>/dev/null; echo "results: $SUM, $R/sim/pin/vm_results.tgz"; }

log "==== vm_run $(date '+%F %T')  host=$(hostname)  stages=${STAGES[*]}"
# No git on the VM: the bundle says what it is (hvl/pin/vm_pack.sh).
if [ -f "$R/VM_BUNDLE" ]; then sed 's/^/bundle /' "$R/VM_BUNDLE" | while read -r l; do log "$l"; done
else log "bundle: none (no VM_BUNDLE: files were not unpacked from vm_bundle.tgz)"; fi

for st in "${STAGES[@]}"; do
  case "$st" in
  preflight)
    # Every file must be exactly what was packed: a partial or mixed copy is
    # the commonest way for a VM run to test something nobody meant to test.
    if [ -f "$R/VM_FILES.sha256" ]; then
      command -v sha256sum >/dev/null || stop "sha256sum not found: cannot verify the bundle"
      ( cd "$R" && sha256sum -c --quiet VM_FILES.sha256 ) >"$OUT/bundle_check.log" 2>&1 \
        || { grep -v '^sha256sum: WARNING' "$OUT/bundle_check.log" | head -20 | sed 's/^/       /' >>"$SUM"
             stop "files differ from the bundle (above); unpack vm_bundle.tgz again"; }
      log "bundle: all $(wc -l < "$R/VM_FILES.sha256") files match"
    else
      log "bundle: WARNING no VM_FILES.sha256, files not verified"
    fi
    [ -f "$IMG/MANIFEST" ] || stop "no $IMG/MANIFEST: unpack vm_bundle.tgz from hvl/pin/vm_pack.sh"
    for d in rtl gate; do
      SIM=vcs DUT=$d "$P/pin.sh" preflight >"$OUT/preflight_$d.log" 2>&1 || { cat "$OUT/preflight_$d.log" >>"$SUM"; stop "preflight $d"; }
    done
    log "preflight: OK ($(wc -l < "$IMG/MANIFEST") images)";;
  selftest)
    SIM=vcs "$P/selftest/run.sh" >"$OUT/selftest.log" 2>&1
    rc=$?; grep -E '^\s+(PASS|FAIL|SKIP|\|)|summary' "$OUT/selftest.log" >>"$SUM"
    [ $rc = 0 ] || stop "selftest (see selftest.log)"
    log "selftest: OK";;
  build)
    for d in rtl gate; do
      SIM=vcs DUT=$d "$P/pin.sh" build >"$OUT/build_$d.log" 2>&1 || { tail -30 "$OUT/build_$d.log" >>"$SUM"; stop "build $d"; }
      log "build $d: OK ($(grep -ciE 'warning' "$R/sim/pin/build/vcs_$d/build.log") warnings)"
    done;;
  regress)
    pass=0; fail=0
    while read -r name duts; do
      [ -n "$name" ] || continue
      [[ -z "${ONLY:-}" || "$name" =~ ${ONLY} ]] || continue
      args=("$IMG/$name.lst"); [ -f "$IMG/$name.cmd" ] && args+=("$IMG/$name.cmd")
      t0=$(date +%s)
      r_rtl="skip"; r_gate="skip"; r_cmp="-"
      if [ -z "${SKIP_RTL:-}" ] && [[ " $duts " == *" rtl "* ]]; then
        SIM=vcs DUT=rtl "$P/pin.sh" run "${args[@]}" +TIMEOUT=10000000 +UART_QUIET >/dev/null 2>&1 && r_rtl=PASS || r_rtl=FAIL
      fi
      if [[ " $duts " == *" gate "* ]]; then
        SIM=vcs DUT=gate "$P/pin.sh" run "${args[@]}" +TIMEOUT=10000000 +UART_QUIET >/dev/null 2>&1 && r_gate=PASS || r_gate=FAIL
        if python3 "$R/bin/pin_trace_cmp.py" "$R/sim/pin/runs/vcs_rtl/$name" "$R/sim/pin/runs/vcs_gate/$name" >"$OUT/cmp_$name.log" 2>&1
        then r_cmp=MATCH; else r_cmp=DIFF; fi
      fi
      verdict=PASS; [[ "$r_rtl" == FAIL || "$r_gate" == FAIL || "$r_cmp" == DIFF ]] && verdict=FAIL
      [ $verdict = PASS ] && pass=$((pass+1)) || fail=$((fail+1))
      line="$(printf '%-4s %-36s rtl=%-4s gate=%-4s trace=%-5s %5ss' $verdict "$name" $r_rtl $r_gate $r_cmp $(( $(date +%s) - t0 )))"
      log "$line"
      if [ $verdict = FAIL ]; then
        for d in rtl gate; do
          f="$R/sim/pin/runs/vcs_$d/$name/sim.log"
          [ -f "$f" ] && grep -m3 -E 'ERROR|PIN_TB_RESULT|Error|Fatal' "$f" | sed "s/^/       $d: /" >>"$SUM"
        done
        [ "$r_cmp" = DIFF ] && sed 's/^/       /' "$OUT/cmp_$name.log" | head -8 >>"$SUM"
      fi
    done < "$IMG/MANIFEST"
    log "regress: $pass passed, $fail failed";;
  xstress|xmem)
    pass=0; fail=0
    xa=("${XARGS[@]}"); [ "$st" = xmem ] && xa+=(+FPGA_MEM=x)
    while read -r name _; do
      [[ -n "$name" && "$name" =~ $XLIST ]] || continue
      args=("$IMG/$name.lst"); [ -f "$IMG/$name.cmd" ] && args+=("$IMG/$name.cmd")
      for d in rtl gate; do
        if SIM=vcs DUT=$d TAG="$st" "$P/pin.sh" run "${args[@]}" "${xa[@]}" +TIMEOUT=10000000 +UART_QUIET >/dev/null 2>&1
        then r=PASS; pass=$((pass+1)); else r=FAIL; fail=$((fail+1)); fi
        log "$(printf '%-4s %-7s %-4s %s' $r "$st" $d "$name")"
        [ $r = PASS ] || grep -m3 -E 'ERROR|PIN_TB_RESULT' "$R/sim/pin/runs/vcs_$d/${name}_$st/sim.log" | sed 's/^/       /' >>"$SUM"
      done
    done < "$IMG/MANIFEST"
    log "$st: $pass passed, $fail failed";;
  *) stop "unknown stage '$st'";;
  esac
done
pack
