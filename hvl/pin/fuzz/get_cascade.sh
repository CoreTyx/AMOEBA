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
# Cascade needs Python >= 3.10 (match statements).  PYTHON picks the
# interpreter; otherwise the first python3 on PATH that is new enough (on EWS
# the Synopsys PATH puts a 3.6 first: module load python3, or
# PYTHON=/software/python-3.12.10/bin/python3).
if [ ! -x "$C/.venv/bin/python" ]; then
  PY="${PYTHON:-}"
  if [ -z "$PY" ]; then
    for p in $(which -a python3 python3.14 python3.13 python3.12 python3.11 python3.10 2>/dev/null); do
      "$p" -c 'import sys; sys.exit(sys.version_info < (3, 10))' 2>/dev/null && { PY="$p"; break; }
    done
  fi
  [ -n "$PY" ] && "$PY" -c 'import sys; sys.exit(sys.version_info < (3, 10))' \
    || { echo "get_cascade.sh: Cascade needs Python >= 3.10; set PYTHON=/path/to/python3.1x" >&2; exit 1; }
  "$PY" -m venv "$C/.venv"
fi
"$C/.venv/bin/pip" install -q filelock numpy tqdm matplotlib
echo "cascade at $(git -C "$C" log -1 --format='%h %ad' --date=short) in $C"
