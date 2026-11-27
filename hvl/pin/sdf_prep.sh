#!/bin/bash
# hvl/pin/sdf_prep.sh -- the SDF a timing build should annotate, prepared once.
#
#   hvl/pin/sdf_prep.sh <sdf[.gz]> <outdir> [model file]...
#
# Prints the path of the SDF to annotate on stdout (the original when it needs
# nothing); what it did goes to stderr as counts only (no SDF text).
#   - .gz: unpacked into <outdir>.
#   - It must have a TIMINGCHECK section: delays alone cannot show a hold check
#     ran.
#   - RECREM (recovery/removal of an async reset) is written as SETUPHOLD when
#     the SDF has RECREM entries and no given model file has a $recrem check.
#     Cell models that check the reset as $setuphold(posedge CK, negedge R) have
#     nothing a RECREM can annotate, and VCS drops it WITHOUT a message: the
#     model's placeholder limits are checked instead (on the VM: 24 false
#     violations at reset release, then X).  RECREM (reset) (clock) (rec) (rem)
#     is exactly the check $setuphold(clock, reset, setup, hold) makes, so only
#     the keyword changes: pins, edges and values are untouched, and the copy has
#     the same line numbers (sdf_msgs.sh cites SDF lines).  SDF_RECREM=keep or
#     SDF_RECREM=rewrite overrides the decision.
# The copy is cached in <outdir> by the source's path, size and mtime.
set -euo pipefail
die() { echo "sdf_prep.sh: $*" >&2; exit 1; }
[ $# -ge 2 ] || die "usage: sdf_prep.sh <sdf[.gz]> <outdir> [model file]..."
src="$1" out="$2"; shift 2
[ -s "$src" ] || die "no such SDF, or empty: $src"
mkdir -p "$out"; out="$(cd "$out" && pwd)"
src="$(cd "$(dirname "$src")" && pwd)/$(basename "$src")"
key="$(stat -L -c '%n %s %Y' "$src") ${SDF_RECREM:-auto}"
tag="$(printf '%s' "$src" | sha256sum | cut -c1-12)"
base="$(basename "${src%.gz}")"; base="${base%.sdf}"

if [ -f "$out/$tag.key" ] && [ "$(cat "$out/$tag.key")" = "$key" ] && [ -s "$out/$tag.path" ] \
   && [ -s "$(cat "$out/$tag.path")" ]; then
  echo "sdf_prep: $(basename "$src"): unchanged, using the prepared copy" >&2
  cat "$out/$tag.path"; exit 0
fi

plain="$src"
if [[ "$src" == *.gz ]]; then
  plain="$out/${tag}_$base.sdf"
  gunzip -c "$src" > "$plain.tmp" && mv -f "$plain.tmp" "$plain"
  echo "sdf_prep: unpacked $(basename "$src")" >&2
fi
grep -qiE '\([[:space:]]*TIMINGCHECK([[:space:](]|$)' "$plain" \
  || die "$(basename "$src") has no TIMINGCHECK section: export timing checks, not only delays"

RECREM_RE='\([[:space:]]*RECREM([[:space:]]|$)'
n_rr="$(grep -cE "$RECREM_RE" "$plain" || true)"
n_mod=0
for m in "$@"; do
  [ -f "$m" ] || continue
  if grep -q '\$recrem' "$m"; then n_mod=$((n_mod + 1)); fi
done
decision="${SDF_RECREM:-auto}"
if [ "$decision" = auto ]; then
  if [ "$n_rr" -gt 0 ] && [ "$n_mod" = 0 ]; then decision=rewrite; else decision=keep; fi
fi
case "$decision" in keep|rewrite) ;; *) die "SDF_RECREM must be keep or rewrite, not '$decision'";; esac
final="$plain"
if [ "$decision" = rewrite ] && [ "$n_rr" -gt 0 ]; then
  final="$out/${tag}_$base.recrem.sdf"
  sed -E "s/$RECREM_RE/(SETUPHOLD\1/g" "$plain" > "$final.tmp"
  [ "$(wc -l < "$plain")" = "$(wc -l < "$final.tmp")" ] || die "RECREM rewrite changed the line count"
  ! grep -qE "$RECREM_RE" "$final.tmp" || die "RECREM rewrite left RECREM entries"
  mv -f "$final.tmp" "$final"
  echo "sdf_prep: $n_rr RECREM written as SETUPHOLD (no model file of $# has a \$recrem check)" >&2
else
  echo "sdf_prep: $n_rr RECREM kept ($n_mod of $# model file(s) have a \$recrem check)" >&2
fi
echo "$final" > "$out/$tag.path"; echo "$key" > "$out/$tag.key"
echo "$final"
