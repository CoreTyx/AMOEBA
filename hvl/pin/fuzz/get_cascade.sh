#!/bin/bash
# hvl/pin/fuzz/get_cascade.sh -- fetch Cascade (GPL-3.0, ETH Zurich) at a pinned
# commit into third_party/cascade (gitignored: a test tool, not part of the
# design), with its Python dependencies in third_party/cascade/.venv.
set -euo pipefail
R="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
C="$R/third_party/cascade"
COMMIT=c3de482
[ -d "$C/.git" ] || git clone -q https://github.com/cascade-artifacts-designs/cascade-meta "$C"
git -C "$C" checkout -q "$COMMIT"
[ -x "$C/.venv/bin/python" ] || python3 -m venv "$C/.venv"
"$C/.venv/bin/pip" install -q filelock numpy tqdm matplotlib
echo "cascade at $(git -C "$C" log -1 --format='%h %ad' --date=short) in $C"
