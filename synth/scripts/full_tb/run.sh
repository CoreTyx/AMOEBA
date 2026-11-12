#!/bin/bash
# Build and run tb_scan.sv on the scanned forte_top gate netlist (pads included).
#   ./run.sh [paths file] [vcs args...] [runtime plusargs...]
#   ./run.sh clean                     remove generated simulation outputs
#   ./run.sh                           expect "DFT TB PASS"
#   ./run.sh --regen                   regenerate map/hookups, then build/run
#   ./run.sh +define+BREAK_SE           scan enable held off, expect FAIL
#   ./run.sh +define+BREAK_MAP          one inversion in the map moved, expect FAIL
#   ./run.sh +define+NO_HARDEN          skip phase H
#
# Source paths.sh beside this script, or an alternate file given first:
#   NETLIST          the gate netlist to simulate
#   STDCELL_MODELS   standard-cell Verilog models
#   SRAM_MODELS      SRAM macro Verilog models
#   PAD_MODELS       pad cell Verilog models
#   VCS_FLAGS        extra VCS flags, added after the defaults so they win
#   SCANDEF          the scandef written with NETLIST; default forte_top.scandef
#                    next to it. Needed only for --regen: scan_map.awk creates
#                    scan_map.generated.svh, which tells the bench which register bit each
#                    scan cell holds.
#   LOGICAL_PHASE    optional, --regen only: per-cell logical phase.  Default:
#                    ./scan_phase.txt if present, else forte_top.scan_phase.txt
#                    beside SCANDEF (written by dft_insert.tcl).
#   LINK_PKG, LINK_AGENT  the link package and pin agent for phase I; default
#                    the repo's hdl/forte_link_pkg.sv and hvl/pin/pin_link_agent.sv.
# Each *_MODELS may be a file, a glob, or a folder (all the .v and .sv in it), or
# several of those separated by spaces or as a bash array, X=(dir/*.v).  An
# array cannot be exported: set it directly in the sourced paths file.
#
# Compile order, as in hvl/pin/pin.sh: pad and SRAM models as ordinary sources
# ahead of the netlist, so any `define, `timescale or primitive they carry is
# there when they elaborate; then standard cells last with -v, so only the
# cells the netlist uses are elaborated.


# Private netlist/model paths come from the environment or the supplied file.

# Verilog simulation models.  Each is compiled with -v (library: only the
# modules the design references are elaborated).
# TODO: removed in git version, add back in VM

# This runner requires the real SRAM/pad models; it does not build an RTL
# reference. Use hvl/pin/pin.sh separately for functional RTL/gate comparisons.

if ! declare -p VCS_FLAGS &>/dev/null; then
    VCS_FLAGS=(+define+ARM_UD_MODEL -debug_acc+all -kdb -j4)
fi

set -euo pipefail

die() { echo "run.sh: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
SIM_DIR="$SCRIPT_DIR/sim"
if [[ "${1:-}" == clean ]]; then
    # Netlist-derived metadata is reused until --regen is requested.
    if [[ -d "$SIM_DIR" ]]; then
        find "$SIM_DIR" -mindepth 1 -maxdepth 1 \
            ! -name scan_map.generated.svh \
            ! -name scan_hookups.generated.svh \
            ! -name scan_hookups.generated.report.tsv \
            -exec rm -rf -- {} +
    fi
    # Also clean outputs left in the script directory by older runs.
    rm -rf -- "$SCRIPT_DIR/csrc" "$SCRIPT_DIR/simv_scan.daidir" \
        "$SCRIPT_DIR/simv_scan" "$SCRIPT_DIR/ucli.key" \
        "$SCRIPT_DIR/verdi_config_file"
    rm -f -- "$SCRIPT_DIR/run.log" "$SCRIPT_DIR/compile.log" \
        "$SCRIPT_DIR/sim.log" "$SCRIPT_DIR/scan_map.svh" "$SCRIPT_DIR/novas.*"
    echo "run.sh: cleaned simulation outputs; preserved generated map/hookups and phase metadata"
    exit 0
fi

mkdir -p "$SIM_DIR"
for source_file in "$SRC_DIR/tb_scan.sv" "$SRC_DIR/scan_random.svh" "$SRC_DIR/scan_exec.svh"; do
    [ -s "$source_file" ] || die "missing source: $source_file; use the complete full_tb/src directory"
done

# Everything printed from here on (these messages, VCS's output, the results)
# also goes to sim/run.log.  sim.log keeps the full simulation
# output, compile.log the full compile.
exec > >(tee "$SIM_DIR/run.log") 2>&1

PATHS_FILE="$SCRIPT_DIR/paths.sh"
if [ $# -gt 0 ] && [[ "$1" != [-+]* ]]; then
    PATHS_FILE="$1"
    shift
fi
[ -f "$PATHS_FILE" ] || die "no paths file: $PATHS_FILE; create paths.sh beside run.sh or supply a file first"
echo "run.sh: sourcing $PATHS_FILE"
# shellcheck disable=SC1090
source "$(realpath "$PATHS_FILE")"
[ -z "${SDF:-}" ] || die "full_tb runs zero-delay only; use hvl/pin for SDF simulation"

# Phase I talks to the chip through the same link agent as the pin bench, on
# the current io_in/io_out protocol.  Both come from the repo unless overridden.
REPO_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
LINK_PKG=${LINK_PKG:-$REPO_DIR/hdl/forte_link_pkg.sv}
LINK_AGENT=${LINK_AGENT:-$REPO_DIR/hvl/pin/pin_link_agent.sv}
for f in "$LINK_PKG" "$LINK_AGENT"; do
    [ -s "$f" ] || die "missing link source: $f; copy hdl/forte_link_pkg.sv and hvl/pin/pin_link_agent.sv from the repo, or set LINK_PKG/LINK_AGENT"
done
LINK_PKG=$(realpath "$LINK_PKG"); LINK_AGENT=$(realpath "$LINK_AGENT")

# Compiler options and simulator plusargs have different destinations. A bare
# +NAME or +NAME=value is a runtime argument; known VCS +options stay at build.
COMPILE_ARGS=(); RUN_ARGS=()
runtime_only=0
REGENERATE=0
for arg in "$@"; do
    if [[ "$arg" == -- ]]; then
        runtime_only=1
    elif (( runtime_only )); then
        RUN_ARGS+=("$arg")
    elif [[ "$arg" == --regen ]]; then
        REGENERATE=1
    else
        case "$arg" in
            +define+*|+incdir+*|+libext+*|+nospecify|+notimingcheck|+vcs+*|+v2k)
                COMPILE_ARGS+=("$arg") ;;
            +*) RUN_ARGS+=("$arg") ;;
            *) COMPILE_ARGS+=("$arg") ;;
        esac
    fi
done

# The entries of variable $1, one per line: an array's elements (X=(a/*.v)),
# or a string split on spaces and glob-expanded (X="a/*.v b.v").  $X alone
# would give only an array's first element.
entries() {
    local re='^declare -[[:alpha:]]*a'
    if [[ "$(declare -p "$1" 2>/dev/null)" =~ $re ]]; then
        local -n arr=$1
        printf '%s\n' ${arr[@]+"${arr[@]}"}
    else
        # shellcheck disable=SC2086
        printf '%s\n' ${!1:-}
    fi
}

# Absolute paths of the .v files variable $1 names.  Resolved against the
# caller's directory, so this runs before the cd below.
model_files() {
    local e list
    list=$(entries "$1")
    [ -n "$list" ] || die "$1 is not set: configure it in paths.sh"
    while IFS= read -r e; do
        if [ -d "$e" ]; then
            local f files
            files=($(shopt -s nullglob; printf '%s\n' "$e"/*.v "$e"/*.sv))
            [ ${#files[@]} -gt 0 ] || die "$1: no .v or .sv files in $e"
            for f in "${files[@]}"; do realpath "$f"; done
        elif [ -f "$e" ]; then
            realpath "$e"
        else
            die "$1: no such file or folder: $e"
        fi
    done <<< "$list"
}

# Command substitution, not <(...), so a die in model_files stops the script
pads=$(model_files PAD_MODELS);      mapfile -t PADS  <<< "$pads"
srams=$(model_files SRAM_MODELS);    mapfile -t SRAMS <<< "$srams"
cells=$(model_files STDCELL_MODELS); mapfile -t CELLS <<< "$cells"
FLAGS=()
flags=$(set -f; entries VCS_FLAGS)
[ -z "$flags" ] || mapfile -t FLAGS <<< "$flags"

[ -n "${NETLIST:-}" ] || die "NETLIST is not set: configure it in paths.sh"
[ -f "$NETLIST" ] || die "NETLIST: no such file: $NETLIST"
NETLIST=$(realpath "$NETLIST")
SCAN_MAP="$SIM_DIR/scan_map.generated.svh"
SCAN_HOOKUP_FILE="$SIM_DIR/scan_hookups.generated.svh"
SCAN_REPORT="$SIM_DIR/scan_hookups.generated.report.tsv"
if (( REGENERATE )); then
    SCANDEF=${SCANDEF:-$(dirname "$NETLIST")/forte_top.scandef}
    [ -f "$SCANDEF" ] || die "no scandef at $SCANDEF: set SCANDEF to the one written with NETLIST"
    SCANDEF=$(realpath "$SCANDEF")

    # Verified logical phase is an input, never generated or overwritten here.
    if [[ -n "${LOGICAL_PHASE:-}" ]]; then
        [ -f "$LOGICAL_PHASE" ] || die "no logical-polarity metadata at $LOGICAL_PHASE"
        LOGICAL_PHASE=$(realpath "$LOGICAL_PHASE")
    elif [[ -f "$SCRIPT_DIR/scan_phase.txt" ]]; then
        LOGICAL_PHASE="$SCRIPT_DIR/scan_phase.txt"
    elif [[ -f "$(dirname "$SCANDEF")/forte_top.scan_phase.txt" ]]; then
        LOGICAL_PHASE="$(dirname "$SCANDEF")/forte_top.scan_phase.txt"
    else
        LOGICAL_PHASE=""
    fi
    echo "run.sh: logical phase from ${LOGICAL_PHASE:-<none>: every cell taken as stored in true polarity>}"
    # Publish only after all requested generation steps succeed.
    awk -v LOGICAL_PHASE="$LOGICAL_PHASE" -v TOP=forte_top \
        -f "$SRC_DIR/scan_map.awk" "$SCANDEF" > "$SCAN_MAP.tmp" \
        || die "failed to generate scan map"
    if [[ "${SCAN_HOOKUPS:-1}" == 1 ]]; then
        python3 "$SRC_DIR/internal_hookups.py" \
            --scandef "$SCANDEF" --scan_map "$SCAN_MAP.tmp" \
            --netlist "$NETLIST" --dut dut \
            -o "$SCAN_HOOKUP_FILE.tmp" --report "$SCAN_REPORT.tmp" \
            || die "failed to generate internal hookups"
    fi
    mv "$SCAN_MAP.tmp" "$SCAN_MAP"
    if [[ "${SCAN_HOOKUPS:-1}" == 1 ]]; then
        mv "$SCAN_HOOKUP_FILE.tmp" "$SCAN_HOOKUP_FILE"
        mv "$SCAN_REPORT.tmp" "$SCAN_REPORT"
    else
        # An older hookup file must not be paired with the newly generated map.
        rm -f -- "$SCAN_HOOKUP_FILE" "$SCAN_REPORT"
    fi
    echo "run.sh: regenerated scan map and enabled hookups from $SCANDEF"
else
    [ -s "$SCAN_MAP" ] || die "no cached scan map at $SCAN_MAP; run ./run.sh --regen once"
    # A map older than what it was made from belongs to another netlist.
    stale_src=${SCANDEF:-$(dirname "$NETLIST")/forte_top.scandef}
    for f in "$NETLIST" "$stale_src" "${LOGICAL_PHASE:-}" "$SRC_DIR/scan_map.awk"; do
        [[ -n "$f" && -f "$f" && "$f" -nt "$SCAN_MAP" ]] \
            && die "cached scan map is older than $f; run ./run.sh --regen"
    done
    if [[ "${SCAN_HOOKUPS:-1}" == 1 ]]; then
        [ -s "$SCAN_HOOKUP_FILE" ] || die "no cached hookups at $SCAN_HOOKUP_FILE; run ./run.sh --regen"
    fi
    echo "run.sh: reusing generated map/hookups; use --regen after netlist, scandef, or phase changes"
fi
if [[ "${SCAN_HOOKUPS:-1}" != 1 ]]; then
  COMPILE_ARGS+=(+define+SCAN_NO_HOOKUPS)
fi

cd "$SIM_DIR"

# Each file once (the variables may name the same folder).  A file that is also
# in STDCELL_MODELS stays a -v library: compiling a whole cell library as
# sources is slow, and fails on any cell defined twice.
declare -A seen=()
LIBS=()
for f in "${CELLS[@]}"; do
    [ -n "${seen[$f]-}" ] || { seen[$f]=1; LIBS+=(-v "$f"); }
done
SRCS=()
for f in "${PADS[@]}" "${SRAMS[@]}"; do
    [ -n "${seen[$f]-}" ] || { seen[$f]=1; SRCS+=("$f"); }
done
echo "run.sh: netlist $NETLIST"
echo "run.sh: ${#SRCS[@]} pad/SRAM model file(s), $(( ${#LIBS[@]} / 2 )) cell library file(s)"

# The bench drives forte_top's pads: the netlist must hold the whole chip
grep -qE '^[[:space:]]*module[[:space:]]+forte_top([^[:alnum:]_]|$)' "$NETLIST" \
    || die "no forte_top module in $NETLIST (it needs the pad ring, not just forte_chip)"

if ! command -v vcs >/dev/null; then
    if type module &>/dev/null; then module load Synopsys_x86-64; fi
    command -v vcs >/dev/null || die "vcs not found; load the simulator environment first"
fi

# Zero-delay functional simulation: no specify-block delays or timing checks
vcs -full64 -sverilog -timescale=1ns/1ps -l compile.log \
    +nospecify +notimingcheck ${FLAGS[@]+"${FLAGS[@]}"} \
    "${COMPILE_ARGS[@]}" \
    "+incdir+$SIM_DIR" "+incdir+$SRC_DIR" \
    "${SRCS[@]}" "$LINK_PKG" "$LINK_AGENT" "$SRC_DIR/tb_scan.sv" "$NETLIST" "${LIBS[@]}" \
    -Mdir=csrc -top tb_scan -o simv_scan

rm -f sim.log
./simv_scan -l sim.log "${RUN_ARGS[@]}" | grep -E '^\[|^(GROUP|REG|PC|PHASE):|DFT TB|^=+'
grep -qE '^DFT TB PASS($| \(partial coverage:)' sim.log \
    || die "simulation did not produce a passing verdict; see $SIM_DIR/sim.log"
