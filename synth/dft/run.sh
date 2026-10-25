#!/usr/bin/env bash
# Separate experimental run. Does not invoke the parent's destructive clean target.
set -euo pipefail
dft_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
export REPO_ROOT=$(cd -- "$dft_dir/../.." && pwd)
export DFT_MODE=${1:-inventory}
export DFT_TIER=${DFT_TIER:-1}
case "$DFT_MODE" in inventory|baseline|scan) ;; *) echo 'Use inventory, baseline or scan' >&2; exit 2;; esac
case "$DFT_TIER" in 1|2|3|4) ;; *) echo 'DFT_TIER must be 1..4' >&2; exit 2;; esac
command -v dc_shell >/dev/null || { echo 'dc_shell is unavailable; load the Synopsys environment.' >&2; exit 1; }
if [[ -z ${STD_CELL_LIB:-} ]]; then
    : "${FREEPDK45:?Set STD_CELL_LIB and STD_CELL_ALIB for the actual library, or FREEPDK45 for the parent flow defaults}"
    export STD_CELL_LIB="$FREEPDK45/stdcells.db"
fi
export STD_CELL_LIB
export STD_CELL_ALIB=${STD_CELL_ALIB:-${FREEPDK45:-$dft_dir/runs}/alib}
export DESIGN_TOP=forte_top
# Current project source lists are space-separated. Refuse ambiguous paths.
[[ $REPO_ROOT != *' '* ]] || { echo 'Repository paths containing spaces are unsupported.' >&2; exit 1; }
export PKG_SRCS="$REPO_ROOT/pkg/types.sv $REPO_ROOT/hdl/forte_link_pkg.sv"
export HDL_SRCS
HDL_SRCS=$(python3 - <<'PY'
import os
from pathlib import Path
r = Path(os.environ['REPO_ROOT'])
core = r/'hdl/core'
paths = [core/'cvw.sv']
paths += sorted(p for p in core.rglob('*.sv') if p.name != 'cvw.sv')
# Root hdl/ already contains the copied OpenTitan primitives. Do not also
# analyze third_party versions, which would duplicate module definitions.
paths += sorted(p for p in (r/'hdl').glob('*.sv') if p.name != 'forte_link_pkg.sv')
print(' '.join(str(p) for p in paths))
PY
)
if [[ ! ${SRAM_LIB+x} ]]; then
    SRAM_LIB=$(python3 - <<'PY'
import os
from pathlib import Path
print(' '.join(str(p) for p in sorted((Path(os.environ['REPO_ROOT'])/'sram/output').rglob('*.db'))))
PY
)
fi
export SRAM_LIB
export ECE411_CLOCK_PERIOD_PS=${ECE411_CLOCK_PERIOD_PS:-$(python3 "$REPO_ROOT/bin/get_options.py" clock)}
export ECE411_MIN_POWER=${ECE411_MIN_POWER:-$(python3 "$REPO_ROOT/bin/get_options.py" min_power)}
export ECE411_COMPILE_CMD=${ECE411_COMPILE_CMD:-$(python3 "$REPO_ROOT/bin/get_options.py" synth_cmd)}
export ECE411_COMPILE_CMD_INC=${ECE411_COMPILE_CMD_INC:-$(python3 "$REPO_ROOT/bin/get_options.py" synth_cmd_inc)}
export ECE411_COMPILE_ITER=${ECE411_COMPILE_ITER:-$(python3 "$REPO_ROOT/bin/get_options.py" synth_inc_iter)}
export ECE411_DC_CORES=${ECE411_DC_CORES:-4}
export SNPSLMD_QUEUE=${SNPSLMD_QUEUE:-true}
run_dir=${DFT_RUN_DIR:-$dft_dir/runs/${DFT_MODE}_tier${DFT_TIER}_$(date +%Y%m%d_%H%M%S)_$$}
[[ ! -e $run_dir ]] || { echo "Refusing to overwrite $run_dir" >&2; exit 1; }
mkdir -p -- "$run_dir/reports" "$run_dir/outputs"
cd -- "$run_dir"
{
    git -C "$REPO_ROOT" rev-parse HEAD
    git -C "$REPO_ROOT" status --short
    printf 'mode=%s tier=%s\nSTD_CELL_LIB=%s\nSRAM_LIB=%s\nperiod_ps=%s\ncompile=%s\n' \
        "$DFT_MODE" "$DFT_TIER" "$STD_CELL_LIB" "$SRAM_LIB" "$ECE411_CLOCK_PERIOD_PS" "$ECE411_COMPILE_CMD"
} > reports/run_manifest.txt
dc_shell -f "$dft_dir/synthesis_dft.tcl" 2>&1 | tee reports/synthesis.log
# dc_shell may log Tcl errors without a nonzero process status.
if grep -Eq '^Error:|^Fatal:' reports/synthesis.log; then
    echo 'DC reported errors; inspect reports/synthesis.log.' >&2
    exit 1
fi
