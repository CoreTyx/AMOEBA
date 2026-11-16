#!/bin/bash
# postpnr/variants.sh -- which STDCELL_MODELS file should come first?
#
#   postpnr/variants.sh [--vm-paths FILE] [--corner max|min] [--static-only]
#
# VCS takes each cell from the first -v file that defines it, so with several
# variants of one library in STDCELL_MODELS the order decides which model --
# and which specify block -- every cell gets.  This script:
#
#   1. static: for each STDCELL_MODELS entry, the number of modules, and of
#      modules whose specify block has each timing check; and how many of each
#      check the SDF asks for.  COUNTS ONLY: no cell names, no model contents.
#   2. per entry i: postpnr/run.sh --only '^smoke$' --corners <corner> with
#      STDCELL_MODELS reordered as (entry i, then the others in their order),
#      and the count of every SDF* message type in that build, plus the count
#      of every other VCS Error type, and the verdict.
#
# Entries are named by their index in STDCELL_MODELS (run.sh lists them in
# that order).  Pick, per threshold-voltage flavour, the entry with no
# SDFCOM_CFTC/IANE/TANE: only SDFCOM_UHICD (pad wires) should remain.
#
# PNR_DIR as for run.sh (environment, else PNR_DIR=... in vm_paths.sh).
# Each build replaces sim/pin/build/vcs_gate_sdf<corner>; the next run.sh
# rebuilds it from the real vm_paths.sh.  Builds run one after another.
set -uo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VMP="${VM_PATHS:-}" CORNER=max STATIC_ONLY=0
while [ $# -gt 0 ]; do
  case "$1" in
    --vm-paths) VMP="$2"; shift;;
    --corner) CORNER="$2"; shift;;
    --static-only) STATIC_ONLY=1;;
    -h|--help) sed -n '2,/^set -uo/{/^set -uo/d;p}' "$0"; exit 0;;
    *) echo "variants.sh: unknown option $1 (--help)" >&2; exit 2;;
  esac
  shift
done
case "$CORNER" in max|min) ;; *) echo "variants.sh: --corner max or min" >&2; exit 2;; esac
if [ -z "$VMP" ]; then
  for f in "$R/../vm_paths.sh" "$R/hvl/pin/vm_paths.sh"; do [ -f "$f" ] && { VMP="$f"; break; }; done
fi
[ -n "$VMP" ] && [ -f "$VMP" ] || { echo "variants.sh: no vm_paths.sh (--vm-paths)" >&2; exit 2; }
VMP="$(cd "$(dirname "$VMP")" && pwd)/$(basename "$VMP")"

mapfile -t LIBS < <(bash -c 'set +u; STDCELL_MODELS=(); source "$1" >/dev/null 2>&1 </dev/null
                             printf "%s\n" "${STDCELL_MODELS[@]}"' _ "$VMP")
N=${#LIBS[@]}
[ "$N" -ge 1 ] || { echo "variants.sh: STDCELL_MODELS is empty in $VMP" >&2; exit 2; }
if [ -z "${PNR_DIR:-}" ]; then
  PNR_DIR="$(bash -c 'set +u; PNR_DIR=; source "$1" >/dev/null 2>&1 </dev/null; printf %s "$PNR_DIR"' _ "$VMP")"
fi
echo "==== postpnr/variants.sh $(date '+%F %T')  paths: $VMP  corner: $CORNER"
echo "STDCELL_MODELS: $N entr$([ "$N" = 1 ] && echo y || echo ies) (numbered as listed)"

# ---- 1. static counts ------------------------------------------------------
CHECKS="setup hold setuphold recovery removal recrem period width skew nochange"
MACROS="NTC RECREM"     # pin.sh defines both for SDF builds: modules that test them
echo
echo "static: modules; modules with each timing check (in any \`ifdef branch); modules testing each macro"
printf '  %-4s %8s %8s' "#" modules specify; for c in $CHECKS; do printf ' %9s' "\$$c"; done
for m in $MACROS; do printf ' %8s' "\`$m"; done; echo
for i in "${!LIBS[@]}"; do
  f="${LIBS[$i]}"
  if [ ! -r "$f" ]; then printf '  [%d]  not readable\n' "$i"; continue; fi
  { case "$f" in *.gz) gzip -dc "$f";; *) cat "$f";; esac; } </dev/null | awk -v checks="$CHECKS" -v macros="$MACROS" -v idx="$i" '
    BEGIN { n = split(checks, C, " "); nm = split(macros, M, " ") }
    { sub(/\/\/.*/, "") }
    $0 ~ /^[[:space:]]*(module|macromodule)[[:space:]]/ { mods++; for (k in seen) delete seen[k] }
    $0 ~ /(^|[^A-Za-z0-9_$])specify([^A-Za-z0-9_]|$)/  { if (!("specify" in seen)) { seen["specify"] = 1; cnt["specify"]++ } }
    { for (k = 1; k <= n; k++) {
        c = C[k]
        if ($0 ~ ("\\$" c "[[:space:]]*\\(") && !(c in seen)) { seen[c] = 1; cnt[c]++ } }
      for (k = 1; k <= nm; k++) {
        c = "`" M[k]
        if ($0 ~ ("`(ifdef|ifndef|elsif)[[:space:]]+" M[k] "([^A-Za-z0-9_]|$)") && !(c in seen)) { seen[c] = 1; cnt[c]++ } } }
    END { printf "  [%d] %8d %8d", idx, mods, cnt["specify"]
          for (k = 1; k <= n; k++) printf " %9d", cnt[C[k]]
          for (k = 1; k <= nm; k++) printf " %8d", cnt["`" M[k]]
          printf "\n" }'
done
SDF=""
if [ -n "${PNR_DIR:-}" ] && [ -d "$PNR_DIR" ]; then
  s=("$PNR_DIR"/*.sdf "$PNR_DIR"/*.sdf.gz); for f in "${s[@]}"; do [ -f "$f" ] && { SDF="$f"; break; }; done
fi
if [ -n "$SDF" ]; then
  echo "SDF ($(basename "$SDF")): timing-check entries by kind"
  { case "$SDF" in *.gz) gzip -dc "$SDF";; *) cat "$SDF";; esac; } </dev/null \
    | grep -oE '\((SETUP|HOLD|SETUPHOLD|RECOVERY|REMOVAL|RECREM|PERIOD|WIDTH|SKEW|NOCHANGE)[[:space:]]' \
    | tr -d '( \t' | sort | uniq -c | awk '{ printf "  %-10s %d\n", $2, $1 }'
else
  echo "SDF: none found (PNR_DIR=${PNR_DIR:-unset})"
fi
[ $STATIC_ONLY = 1 ] && exit 0

# ---- 2. one build per entry first -------------------------------------------
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
for i in "${!LIBS[@]}"; do
  order=("${LIBS[$i]}"); for j in "${!LIBS[@]}"; do [ "$j" = "$i" ] || order+=("${LIBS[$j]}"); done
  v="$TMP/vm_paths_$i.sh"
  { echo "source $(printf '%q' "$VMP")"
    printf 'STDCELL_MODELS=('; printf ' %q' "${order[@]}"; echo ' )'; } > "$v"
  echo
  echo "---- [$i] first  ($(date '+%T'))"
  log="$TMP/run_$i.log"
  "$R/postpnr/run.sh" --vm-paths "$v" --only '^smoke$' --corners "$CORNER" > "$log" 2>&1 </dev/null
  rc=$?
  out="$(sed -n 's/^results: \(.*\)\/SUMMARY .*/\1/p' "$log" | tail -1)"
  b="$out/build_$CORNER.log"
  if [ -f "$b" ]; then
    m="$(grep -oE '(Warning|Error)-\[SDF[A-Z0-9_]*\]' "$b" | sort | uniq -c | awk '{ printf "%s %s  ", $2, $1 }')"
    e="$(grep -oE 'Error-\[[A-Z0-9_]+\]' "$b" | grep -v 'Error-\[SDF' | sort | uniq -c | awk '{ printf "%s %s  ", $2, $1 }')"
    echo "  SDF messages:   ${m:-none}"
    [ -n "$e" ] && echo "  other errors:   $e"
    grep -qE '^build: SDF .* annotated completely' "$b" && echo "  SDF gate:       PASS" || echo "  SDF gate:       FAIL"
  else
    echo "  no build log (run.sh stopped before the build)"
  fi
  echo "  run.sh:         exit $rc; $(grep -E '^(STOPPED|TOTAL)' "$log" | tail -1 | cut -c1-120)"
  echo "  results:        ${out:-?}"
done
