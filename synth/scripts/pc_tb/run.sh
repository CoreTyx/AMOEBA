#!/bin/bash
# Build and run tb_scan.sv on the scanned forte_top gate netlist (pads included).
#   ./run.sh [env file] [vcs args...]
#   ./run.sh env.s                     expect "DFT TB PASS"
#   ./run.sh env.s +define+BREAK_SE    self-test: scan enable held off, expect FAIL
#   ./run.sh env.s +define+BREAK_MAP   self-test: one inversion in the map moved, expect FAIL
#
# Paths come from the env file if one is given first (sourced here), else from
# the environment (exported):
#   NETLIST          the gate netlist to simulate
#   STDCELL_MODELS   standard-cell Verilog models
#   SRAM_MODELS      SRAM macro Verilog models
#   PAD_MODELS       pad cell Verilog models
#   VCS_FLAGS        extra VCS flags, added after the defaults so they win
#   SCANDEF          optional: the scandef written with NETLIST; default
#                    forte_top.scandef next to it.  Turned into scan_map.svh
#                    (scan_map.awk), which the bench needs for its PC phases.
# Each *_MODELS may be a file, a glob, or a folder (all the .v and .sv in it), or
# several of those separated by spaces or as a bash array, X=(dir/*.v).  An
# array cannot be exported: set it in the env file and pass that file first.
#
# Compile order, as in hvl/pin/pin.sh: pad and SRAM models as ordinary sources
# ahead of the netlist, so any `define, `timescale or primitive they carry is
# there when they elaborate; then standard cells last with -v, so only the
# cells the netlist uses are elaborated.


export NETLIST=/groups/ece427-group4/dft_testing/synth/synout/forte_top.gate.v

# SDF for the same netlist.  Empty = zero-delay functional gate simulation
# (post-synthesis).  Set it for post-PnR timing simulation.
export SDF="${SDF:-}"
export SDF_CORNER="${SDF_CORNER:-max}"          # min | typ | max

# Verilog simulation models.  Each is compiled with -v (library: only the
# modules the design references are elaborated).
# TODO: removed in git version, add back in VM


# Used for the RTL reference too: forte_top under `SYNTHESIS instantiates the
# SRAM macros and pad cells, so the RTL build needs SRAM_MODELS and PAD_MODELS.
# Leave both empty to fall back to hvl/pin/models/*_behav.sv (NOT sign-off).

export VCS_FLAGS=(+define+ARM_UD_MODEL -debug_acc+all -kdb -j4 -fgp)



set -euo pipefail

die() { echo "run.sh: $*" >&2; exit 1; }

if [ $# -gt 0 ] && [[ "$1" != [-+]* ]]; then
    [ -f "$1" ] || die "no such env file: $1"
    echo "run.sh: sourcing $1"
    # shellcheck disable=SC1090
    source "$(realpath "$1")"
    shift
fi

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
    [ -n "$list" ] || die "$1 is not set: give the env file first (./run.sh env.s), or export it"
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

[ -n "${NETLIST:-}" ] || die "NETLIST is not set: give the env file first (./run.sh env.s), or export it"
[ -f "$NETLIST" ] || die "NETLIST: no such file: $NETLIST"
NETLIST=$(realpath "$NETLIST")
SCANDEF=${SCANDEF:-$(dirname "$NETLIST")/forte_top.scandef}
[ ! -f "$SCANDEF" ] || SCANDEF=$(realpath "$SCANDEF")
cd "$(dirname "$0")"

# Scan map from the scandef: which PC bit each scan cell holds
MAP=()
rm -f scan_map.svh
if [ -f "$SCANDEF" ]; then
    awk -f scan_map.awk "$SCANDEF" > scan_map.svh || die "cannot read the scan chains in $SCANDEF"
    MAP=(+define+SCAN_MAP)
    echo "run.sh: scan map from $SCANDEF"
else
    echo "run.sh: no scandef at $SCANDEF: the bench skips its PC phases (set SCANDEF)"
fi

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

# Zero-delay functional simulation: no specify-block delays or timing checks
vcs -full64 -sverilog -timescale=1ns/1ps -l compile.log \
    +nospecify +notimingcheck ${FLAGS[@]+"${FLAGS[@]}"} \
    ${MAP[@]+"${MAP[@]}"} "$@" \
    "${SRCS[@]}" tb_scan.sv "$NETLIST" "${LIBS[@]}" \
    -top tb_scan -o simv_scan

./simv_scan -l sim.log | grep -E '^\[|^PC:|DFT TB'
