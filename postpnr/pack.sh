#!/bin/bash
# postpnr/pack.sh -- one file for the VM: the bench, the scripts and a golden.
#
#   postpnr/pack.sh [<sha12>|<golden dir>]     default: the only postpnr/golden/*
#
# Writes postpnr/postpnr_bundle_<sha12>.tgz.  On the VM (no git, no toolchain):
#   mkdir -p <dir> && tar -xzf postpnr_bundle_<sha12>.tgz -C <dir>
#   cp <dir>/hvl/pin/vm_paths.example.sh <dir>/hvl/pin/vm_paths.sh   # once: the PDK models
#   PNR_DIR=/path/to/drop <dir>/postpnr/run.sh
# A later bundle unpacks over the same <dir>: vm_paths.sh is never in it, and
# results/ is left alone.
#
# The bundle carries postpnr/BUNDLE (what and when) and postpnr/BUNDLE.sha256;
# run.sh refuses to run if any file differs from what was packed.
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$R"
die() { echo "pack.sh: $*" >&2; exit 1; }

if [ $# -ge 1 ] && [ -d "$1" ]; then G="$(cd "$1" && pwd)"
elif [ $# -ge 1 ]; then G="$R/postpnr/golden/$1"
else
  mapfile -t gs < <(ls -d "$R"/postpnr/golden/*/ 2>/dev/null)
  [ ${#gs[@]} -eq 1 ] || die "${#gs[@]} goldens in postpnr/golden: name one"
  G="${gs[0]%/}"
fi
[ -f "$G/GOLDEN" ] || die "$G has no GOLDEN: run postpnr/prepare.sh"
S12="$(basename "$G")"
GREL="postpnr/golden/$S12"

STAGE="$R/postpnr/work/pack.stage"
rm -rf "$STAGE"; mkdir -p "$STAGE/postpnr/golden"
tar -cf - --exclude='hvl/pin/vm_paths.sh' --exclude='*.swp' --exclude='__pycache__' \
    hvl/pin bin/pin_trace_cmp.py bin/vcd_first_x.py \
    postpnr/README.md postpnr/run.sh postpnr/sdc_delays.py postpnr/sdf_out_wires.py postpnr/waivers.txt postpnr/selfcheck.sh \
  | tar -xf - -C "$STAGE"
# The golden itself, wherever it lives, lands at postpnr/golden/<sha12>.
tar -C "$G" -cf - GOLDEN rtl images traces | { mkdir -p "$STAGE/$GREL"; tar -xf - -C "$STAGE/$GREL"; }

{
  echo "postpnr bundle, golden RTL $(awk '/^rtl_sha:/{print $2}' "$G/GOLDEN")"
  echo "packed:  $(date '+%F %T') on $(hostname)"
  echo "bench:   $(git rev-parse --short HEAD) on $(git rev-parse --abbrev-ref HEAD)$(git status --porcelain -- hvl/pin bin postpnr | grep -v '^?? postpnr/\(golden\|work\|results\)' | grep -q . && echo ' + uncommitted changes')"
  echo "images:  $(wc -l < "$G/images/MANIFEST")"
} > "$STAGE/postpnr/BUNDLE"
( cd "$STAGE" && find . -type f ! -name BUNDLE.sha256 | sed 's|^\./||' | sort | xargs -d '\n' sha256sum ) \
  > "$STAGE/postpnr/BUNDLE.sha256"

OUTF="$R/postpnr/postpnr_bundle_$S12.tgz"
tar -C "$STAGE" -czf "$OUTF" .
rm -rf "$STAGE"
echo "wrote $OUTF ($(du -h "$OUTF" | cut -f1), $(tar -tzf "$OUTF" | grep -cv '/$') files)"
cat "$G/GOLDEN" | sed 's/^/  /'
