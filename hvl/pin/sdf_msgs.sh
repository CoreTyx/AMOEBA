# hvl/pin/sdf_msgs.sh -- the rules for VCS's SDF annotation messages, shared by
# hvl/pin/pin.sh (the pin bench) and synth/scripts/full_tb/run.sh (the scan
# bench).  Sourced; defines one function:
#
#   sdf_classify <build.log> <sdf> <strict|niod>
#
# Returns 0 when the annotation in <build.log> is complete by these rules, and
# sets SDFM_UH, SDFM_IW, SDFM_NN (the accepted SDFCOM_UHICD, SDFCOM_IWSBA and,
# in niod mode, SDFCOM_NIOD counts).  Otherwise returns 1 with SDFM_ERR set,
# after printing the first offending messages to stderr.
#
# Accepted, each one checked against the SDF line it cites:
#   SDFCOM_UHICD  a wire from a cell pin inside the chip to one of forte_top's
#                 own output ports: VCS cannot annotate a wire that leaves the
#                 annotated scope (the driving cell's delay is still applied).
#   SDFCOM_IWSBA  an INTERCONNECT whose net passes through an assign: VCS still
#                 annotates it.
#   SDFCOM_NIOD   negative IOPATH delay -- only in niod mode (--ignore-neg-delay),
#                 which is never sign-off.
# Everything else fails: any other SDFCOM_* (an instance, pin, arc or check the
# SDF names that the netlist/models lack, so a delay or check is missing) and
# any other SDF* tag (SDFPE: a parse error, after which VCS aborts annotation),
# and an annotation summary that is missing, aborted, or not 0 errors with only
# the accepted warnings.

sdf_classify() {
  local log="$1" sdf="$2" mode="$3"
  SDFM_UH=0 SDFM_IW=0 SDFM_NN=0 SDFM_ERR=""
  local uh_lines="" uh_badl iw_lines iw_badl bad summ
  # SDF line number cited by each message with tag $1 ("<sdf>, <line>" follows the tag).
  _sdfm_lines() { grep -A1 "Warning-\[$1\]" "$log" | grep -oE ', [0-9]+[[:space:]]*$' | tr -dc '0-9\n' | grep . || true; }
  SDFM_UH="$(grep -c 'Warning-\[SDFCOM_UHICD\]' "$log" || true)"
  SDFM_IW="$(grep -c 'Warning-\[SDFCOM_IWSBA\]' "$log" || true)"
  if [ "$SDFM_IW" -gt 0 ]; then
    iw_lines="$(_sdfm_lines SDFCOM_IWSBA)"
    [ "$(grep -c . <<<"$iw_lines")" = "$SDFM_IW" ] \
      || { SDFM_ERR="$SDFM_IW SDFCOM_IWSBA message(s), but could not read the SDF line of each ($log)"; return 1; }
    iw_badl="$(awk 'NR == FNR { want[$1] = 1; next }
                    FNR in want { if ($0 !~ /^[[:space:]]*\(INTERCONNECT[[:space:]]/) print FNR; delete want[FNR] }
                    END { for (l in want) print l }' <(echo "$iw_lines") "$sdf" | sort -un | head -5)"
    [ -z "$iw_badl" ] \
      || { SDFM_ERR="SDFCOM_IWSBA on SDF line(s) $(echo $iw_badl) that are not an INTERCONNECT entry"; return 1; }
  fi
  if [ "$SDFM_UH" -gt 0 ]; then
    uh_lines="$(_sdfm_lines SDFCOM_UHICD)"
    [ "$(grep -c . <<<"$uh_lines")" = "$SDFM_UH" ] \
      || { SDFM_ERR="$SDFM_UH SDFCOM_UHICD message(s), but could not read the SDF line of each ($log)"; return 1; }
    # Each UHICD must be a wire into a forte_top output port.
    uh_badl="$(awk -v div="$(grep -m1 -oE '\(DIVIDER[[:space:]]+[^[:space:])]' "$sdf" | awk '{print $2}')" '
        NR == FNR { want[$1] = 1; next }
        FNR in want {
          ok = 0
          if (match($0, /^[[:space:]]*\(INTERCONNECT[[:space:]]+/)) {
            n = split(substr($0, RLENGTH + 1), t, /[[:space:]]+/)
            src = t[1]; dst = t[2]; sub(/^\\/, "", dst); port = dst; sub(/\[[0-9]+\]$/, "", port)
            if (div == "") div = "/"
            if (index(src, div) && !index(dst, div) && port ~ /^(io_out|req|wr|uart_tx|status|clk_out)$/) ok = 1
          }
          if (!ok) print FNR
        }' <(echo "$uh_lines") "$sdf" | head -5)"
    [ -z "$uh_badl" ] \
      || { SDFM_ERR="SDFCOM_UHICD on SDF line(s) $(echo $uh_badl) that are not a wire into a forte_top output port"; return 1; }
  fi
  local ok_tags='UHICD|IWSBA'
  if [ "$mode" = niod ]; then
    ok_tags='UHICD|IWSBA|NIOD'
    SDFM_NN="$(grep -c 'Warning-\[SDFCOM_NIOD\]' "$log" || true)"
  fi
  bad="$(grep -E '(Warning|Error)-\[SDF[A-Z0-9_]*\]' "$log" | grep -vE "Warning-\\[SDFCOM_($ok_tags)\\]" || true)"
  if [ -n "$bad" ]; then
    awk -v ok="SDFCOM_($ok_tags)" '/(Warning|Error)-\[SDF[A-Z0-9_]*\]/ { show = ($0 !~ ok); left = 5 }
         show && left-- > 0' "$log" | head -40 | sed 's/^/  | /' >&2
    SDFM_ERR="$(wc -l <<<"$bad") SDF message(s): $(grep -oE 'SDF[A-Z0-9_]*' <<<"$bad" | sort | uniq -c | awk '{printf "%s x%s ", $2, $1}')(first above; all in $log)"
    return 1
  fi
  local uh=$SDFM_UH iw=$SDFM_IW nn=$SDFM_NN
  summ="$(sed -n '/SDF annotation begin/,/SDF annotation \(completed\|aborted\)/p' "$log")"
  if [ -z "$summ" ] || grep -q 'SDF annotation aborted' <<<"$summ" || ! grep -q 'SDF annotation completed' <<<"$summ" \
     || ! grep -qE 'Total errors: +0$' <<<"$summ" || ! grep -qE "Total warnings: +(0|$uh|$((uh + iw))|$((uh + nn))|$((uh + iw + nn)))\$" <<<"$summ"; then
    echo "$summ" | tail -12 | sed 's/^/  | /' >&2
    SDFM_ERR="annotation of $sdf did not complete cleanly (above; $log)"
    return 1
  fi
  return 0
}
