#!/bin/bash
# Build and run tb_scan.sv on the scanned forte_top gate netlist (pads included).
#   ./run.sh [paths file] [options] [vcs args...] [runtime plusargs...]
#   ./run.sh clean                     remove generated simulation outputs
#   ./run.sh                           full suite, load+capture, baseline sentinels
#   ./run.sh --regen                   regenerate map/hookups, then build/run
#   ./run.sh --timing                  annotate the SDF; timing checks on
#   ./run.sh +define+BREAK_SE           scan enable held off, expect FAIL
#   ./run.sh +define+BREAK_MAP          one inversion in the map moved, expect FAIL
#   ./run.sh +define+NO_HARDEN          skip phase H
#
# Options:
#   --vm-paths FILE    the paths file (below); same as giving it first
#   --regen            regenerate the scan map and hookups (and, with no
#                      scandef, discover the chains first: --discover)
#   --discover         find the chain order, scan-path inversions and logical
#                      phase from the netlist itself (src/scan_discover.svh),
#                      even when a scandef is given: that scandef and phase file
#                      are then only compared with what was found (counts)
#   --discover-only    discover (as --regen would) and stop
#   --timing           SDF timing simulation of the netlist the SDF belongs to
#   --corner min|typ|max   SDF triplet entry (default: SDF_CORNER, else min);
#                      each corner builds in sim/timing_<corner>/
#   --ignore-neg-delay SDFCOM_NIOD (negative IOPATH delay) is counted, not
#                      failed: NOT a sign-off run (timing_summary.log says so)
#
# The paths file: an explicit one, else $VM_PATHS, else vm_paths.sh beside the
# checkout (<repo>/../vm_paths.sh), else hvl/pin/vm_paths.sh (the pin bench's VM file: NETLIST, SDF, SDF_CORNER, PDK_FIRST, PAD_MODELS,
# SRAM_MODELS, STDCELL_MODELS, VCS_FLAGS), else paths.sh beside this script.
#   NETLIST          the gate netlist to simulate.  With --timing it is the
#                    netlist the SDF was written for, unless PNR_NETLIST is set
#   SDF, SDF_CORNER  --timing: the SDF (.gz allowed) and min|typ|max
#   PNR_NETLIST, PNR_SCANDEF, PNR_LOGICAL_PHASE, PNR_DIR
#                    --timing: a separate post-route set (older paths.sh files)
#   PDK_FIRST, PAD_MODELS, SRAM_MODELS   compiled as sources, in that order
#   STDCELL_MODELS   standard-cell Verilog models (-v libraries)
#   VCS_FLAGS        extra VCS flags, added after the defaults so they win
#   SCANDEF          the scandef written with NETLIST; default forte_top.scandef
#                    beside it.  With none, --regen discovers the chains.
#   LOGICAL_PHASE    per-cell logical phase; default ./scan_phase.txt, else
#                    forte_top.scan_phase.txt beside SCANDEF (dft_insert.tcl
#                    writes it).  Discovery writes its own.
#   LINK_PKG, LINK_AGENT  the link package and pin agent for phase I; default
#                    the repo's hdl/forte_link_pkg.sv and hvl/pin/pin_link_agent.sv.
# Each *_MODELS may be a file, a glob, or a folder (all the .v and .sv in it), or
# several of those separated by spaces or as a bash array, X=(dir/*.v).  An
# array cannot be exported: set it directly in the sourced paths file.
#
# Compile order, as in hvl/pin/pin.sh: PDK_FIRST, pad and SRAM models as
# ordinary sources ahead of the netlist, so any `define, `timescale or
# primitive they carry is there when they elaborate; then standard cells last
# with -v, so only the cells the netlist uses are elaborated.
#
# SDF builds follow hvl/pin/pin.sh exactly (one set of rules for both benches):
# -negdelay +neg_tchk +define+NTC +define+RECREM, +define+ARM_UD_* dropped from
# VCS_FLAGS (unit-delay models have no specify block), the SDF prepared by
# hvl/pin/sdf_prep.sh (.gz, RECREM as SETUPHOLD when no model has $recrem), and
# the annotation judged by hvl/pin/sdf_msgs.sh.
#
# This runner requires the real SRAM/pad models; it does not build an RTL
# reference. Use hvl/pin/pin.sh separately for functional RTL/gate comparisons.

set -euo pipefail

die() { echo "run.sh: $*" >&2; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC_DIR="$SCRIPT_DIR/src"
SIM_ROOT="$SCRIPT_DIR/sim"
SIM_DIR="$SIM_ROOT"
REPO_DIR="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [[ "${1:-}" == clean ]]; then
    # Netlist-derived metadata is reused until --regen is requested.
    for clean_dir in "$SIM_ROOT"/timing* "$SIM_ROOT"; do
      if [[ -d "$clean_dir" ]]; then
        find "$clean_dir" -mindepth 1 -maxdepth 1 \
            ! -name 'timing*' ! -name meta \
            ! -name scan_map.generated.svh \
            ! -name scan_hookups.generated.svh \
            ! -name scan_hookups.generated.report.tsv \
            ! -name scan_metadata.inputs \
            -exec rm -rf -- {} +
      fi
    done
    # Also clean outputs left in the script directory by older runs.
    rm -rf -- "$SCRIPT_DIR/csrc" "$SCRIPT_DIR/simv_scan.daidir" \
        "$SCRIPT_DIR/simv_scan" "$SCRIPT_DIR/ucli.key" \
        "$SCRIPT_DIR/verdi_config_file"
    rm -f -- "$SCRIPT_DIR/run.log" "$SCRIPT_DIR/compile.log" \
        "$SCRIPT_DIR/sim.log" "$SCRIPT_DIR/scan_map.svh" "$SCRIPT_DIR/novas.*"
    echo "run.sh: cleaned simulation outputs; preserved generated map/hookups, discovery and phase metadata"
    exit 0
fi

mkdir -p "$SIM_ROOT"
for source_file in "$SRC_DIR/tb_scan.sv" "$SRC_DIR/scan_random.svh" "$SRC_DIR/scan_exec.svh" "$SRC_DIR/scan_resume.svh" "$SRC_DIR/scan_hold_checks.svh" "$SRC_DIR/scan_output_z.svh" "$SRC_DIR/scan_discover.svh"; do
    [ -s "$source_file" ] || die "missing source: $source_file; use the complete full_tb/src directory"
done

PATHS_FILE=""
if [ $# -gt 0 ] && [[ "$1" != [-+]* ]]; then
    PATHS_FILE="$1"
    shift
fi

# Compiler options and simulator plusargs have different destinations. A bare
# +NAME or +NAME=value is a runtime argument; known VCS +options stay at build.
COMPILE_ARGS=(); RUN_ARGS=()
runtime_only=0
REGENERATE=0
TIMING=0
DISCOVER=0
DISCOVER_ONLY=0
IGNORE_NIOD=0
CORNER=""
want=""
for arg in "$@"; do
    if [[ -n "$want" ]]; then
        printf -v "$want" '%s' "$arg"; want=""; continue
    fi
    if [[ "$arg" == -- ]]; then
        runtime_only=1
    elif (( runtime_only )); then
        RUN_ARGS+=("$arg")
    else
        case "$arg" in
            --regen) REGENERATE=1 ;;
            --timing) TIMING=1 ;;
            --discover) DISCOVER=1; REGENERATE=1 ;;
            --discover-only) DISCOVER_ONLY=1; REGENERATE=1 ;;
            --ignore-neg-delay) IGNORE_NIOD=1 ;;
            --corner) want=CORNER ;;
            --corner=*) CORNER=${arg#--corner=} ;;
            --vm-paths) want=PATHS_FILE ;;
            --vm-paths=*) PATHS_FILE=${arg#--vm-paths=} ;;
            +define+*|+incdir+*|+libext+*|+nospecify|+notimingcheck|+vcs+*|+v2k)
                COMPILE_ARGS+=("$arg") ;;
            +*) RUN_ARGS+=("$arg") ;;
            *) COMPILE_ARGS+=("$arg") ;;
        esac
    fi
done
[[ -z "$want" ]] || die "${want,,} needs a value"

if [[ -z "$PATHS_FILE" ]]; then
    # vm_paths.sh beside the checkout (../vm_paths.sh) survives unpacking a
    # new copy of the repo over the old one.
    for f in "${VM_PATHS:-}" "$REPO_DIR/../vm_paths.sh" "$REPO_DIR/hvl/pin/vm_paths.sh" "$SCRIPT_DIR/paths.sh"; do
        [[ -n "$f" && -f "$f" ]] && { PATHS_FILE="$f"; break; }
    done
fi
[[ -n "$PATHS_FILE" && -f "$PATHS_FILE" ]] \
    || die "no paths file: cp hvl/pin/vm_paths.example.sh ../vm_paths.sh (beside the checkout) and fill it in, or give one with --vm-paths"
PATHS_FILE=$(realpath "$PATHS_FILE")
PDK_FIRST=()
# shellcheck disable=SC1090
source "$PATHS_FILE"

# Phase I talks to the chip through the same link agent as the pin bench, on
# the current io_in/io_out protocol.  Both come from the repo unless overridden.
LINK_PKG=${LINK_PKG:-$REPO_DIR/hdl/forte_link_pkg.sv}
LINK_AGENT=${LINK_AGENT:-$REPO_DIR/hvl/pin/pin_link_agent.sv}
for f in "$LINK_PKG" "$LINK_AGENT"; do
    [ -s "$f" ] || die "missing link source: $f; copy hdl/forte_link_pkg.sv and hvl/pin/pin_link_agent.sv from the repo, or set LINK_PKG/LINK_AGENT"
done
LINK_PKG=$(realpath "$LINK_PKG"); LINK_AGENT=$(realpath "$LINK_AGENT")

scan_op_given=0
for arg in "${RUN_ARGS[@]}"; do
    [[ "$arg" != +SCAN_OP=* ]] || scan_op_given=1
done
if (( ! scan_op_given )); then
    RUN_ARGS+=(+SCAN_OP=both)
fi

if (( TIMING )); then
    CORNER=${CORNER:-${SDF_CORNER:-min}}
    case "$CORNER" in min|typ|max) ;; *) die "the SDF corner must be min, typ or max, not '$CORNER'" ;; esac
    SIM_DIR="$SIM_ROOT/timing_$CORNER"
elif [[ -n "$CORNER" ]]; then
    die "--corner needs --timing"
fi
mkdir -p "$SIM_DIR"
# Keep post-route build products, metadata and logs separate from synthesis.
exec > >(tee "$SIM_DIR/run.log") 2>&1
echo "run.sh: sourced $PATHS_FILE; outputs in $SIM_DIR"

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
# caller's directory, so this runs before the cd below.  $2=optional: an unset
# variable is no files rather than an error.
model_files() {
    local e list
    list=$(entries "$1")
    if [ -z "$list" ]; then
        [[ "${2:-}" == optional ]] && return 0
        die "$1 is not set: configure it in $PATHS_FILE"
    fi
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
pdk=$(model_files PDK_FIRST optional); PDKS=(); [ -z "$pdk" ] || mapfile -t PDKS <<< "$pdk"
pads=$(model_files PAD_MODELS);      mapfile -t PADS  <<< "$pads"
srams=$(model_files SRAM_MODELS);    mapfile -t SRAMS <<< "$srams"
cells=$(model_files STDCELL_MODELS); mapfile -t CELLS <<< "$cells"
if ! declare -p VCS_FLAGS &>/dev/null; then
    VCS_FLAGS=(+define+ARM_UD_MODEL -debug_acc+all -kdb -j4)
fi
FLAGS=()
flags=$(set -f; entries VCS_FLAGS)
[ -z "$flags" ] || mapfile -t FLAGS <<< "$flags"

# A gzipped netlist is unpacked once into sim/meta/ (VCS and the parsers need text).
unzip_netlist() {
    local f="$1" d="$SIM_ROOT/meta/netlist" out
    [[ "$f" == *.gz ]] || { echo "$f"; return; }
    mkdir -p "$d"
    out="$d/$(printf '%s' "$f" | sha256sum | cut -c1-12)_$(basename "${f%.gz}")"
    if [[ ! -s "$out" || "$f" -nt "$out" ]]; then gunzip -c "$f" > "$out.tmp" && mv -f "$out.tmp" "$out"; fi
    echo "$out"
}

TIMING_ARGS=(+nospecify +notimingcheck)
SDF_NOTE=""
EXPLICIT_SCANDEF="" EXPLICIT_PHASE=""
if (( TIMING )); then
    if [[ -n "${PNR_NETLIST:-}" ]]; then
        NETLIST=$PNR_NETLIST
        echo "run.sh: --timing netlist: PNR_NETLIST"
        PNR_DIR=${PNR_DIR:-/groups/ece427-group4/experiment2/pnr/pnrout}
        EXPLICIT_SCANDEF=${PNR_SCANDEF:-$PNR_DIR/forte_top.scandef}
        EXPLICIT_PHASE=${PNR_LOGICAL_PHASE:-$PNR_DIR/forte_top.scan_phase.txt}
        [ -s "$EXPLICIT_SCANDEF" ] || EXPLICIT_SCANDEF=""
        [ -s "$EXPLICIT_PHASE" ] || EXPLICIT_PHASE=""
    else
        [[ -n "${NETLIST:-}" ]] || die "--timing needs NETLIST (the netlist the SDF was written for) in $PATHS_FILE"
        echo "run.sh: --timing netlist: NETLIST from $PATHS_FILE, the one the SDF belongs to"
        EXPLICIT_SCANDEF=${PNR_SCANDEF:-${SCANDEF:-}}
        EXPLICIT_PHASE=${PNR_LOGICAL_PHASE:-${LOGICAL_PHASE:-}}
    fi
    [[ -n "${SDF:-}" ]] && [ -s "$SDF" ] || die "--timing needs a nonempty SDF in $PATHS_FILE"
    for arg in "${FLAGS[@]}" "${COMPILE_ARGS[@]}" "${RUN_ARGS[@]}"; do
        case "$arg" in
            +nospecify*|+notimingcheck*|+notimingchecks*|+no_notifier*|+no_tchk_msg*|+ntb_disable_timing*|+delay_mode_zero*|+delay_mode_unit*|+timingchecksoff*)
                die "--timing conflicts with timing suppression option: $arg" ;;
        esac
        [[ ! "$arg" =~ ^\+define\+(.+\+)?FUNCTIONAL(\+|=|$) ]] \
            || die "--timing conflicts with FUNCTIONAL library models"
    done
    # ARM's +define+ARM_UD_MODEL (and companions) selects the models' unit-delay
    # branch, which has no specify block: the SDF would annotate nothing there.
    keep=() dropped=()
    for f in "${FLAGS[@]}"; do
        if [[ "$f" =~ ^\+define\+ARM_UD_ ]]; then dropped+=("$f"); else keep+=("$f"); fi
    done
    FLAGS=(${keep[@]+"${keep[@]}"})
    [ ${#dropped[@]} -eq 0 ] || echo "run.sh: dropped ${dropped[*]} from VCS_FLAGS: unit-delay models have no specify block for the SDF"
    SDF_SRC=$(realpath "$SDF")
    SDF=$(bash "$REPO_DIR/hvl/pin/sdf_prep.sh" "$SDF_SRC" "$SIM_DIR/sdf" "${CELLS[@]}" "${PADS[@]}" "${SRAMS[@]}") \
        || die "SDF preparation failed (hvl/pin/sdf_prep.sh)"
    TIMING_ARGS=(-sdf "$CORNER:tb_scan.dut:$SDF" +neg_tchk -negdelay +sdfverbose
                 +define+NTC +define+RECREM +define+SCAN_TIMING)
    echo "run.sh: post-P&R timing simulation, corner=$CORNER scope=tb_scan.dut"
    (( IGNORE_NIOD )) && SDF_NOTE="--ignore-neg-delay: SDFCOM_NIOD counted, not failed -- NOT a sign-off run"
else
    echo "run.sh: zero-delay simulation (SDF is used only with --timing)"
    EXPLICIT_SCANDEF=${SCANDEF:-}
    EXPLICIT_PHASE=${LOGICAL_PHASE:-}
fi

[ -n "${NETLIST:-}" ] || die "NETLIST is not set: configure it in $PATHS_FILE"
[ -f "$NETLIST" ] || die "NETLIST: no such file: $NETLIST"
NETLIST=$(unzip_netlist "$(realpath "$NETLIST")")
# The bench drives forte_top's pads: the netlist must hold the whole chip
grep -qE '^[[:space:]]*module[[:space:]]+forte_top([^[:alnum:]_]|$)' "$NETLIST" \
    || die "no forte_top module in $NETLIST (it needs the pad ring, not just forte_chip)"
# A scandef written with the netlist, when there is one beside it.
if [[ -z "$EXPLICIT_SCANDEF" && -f "$(dirname "$NETLIST")/forte_top.scandef" ]]; then
    EXPLICIT_SCANDEF="$(dirname "$NETLIST")/forte_top.scandef"
fi
if [[ -n "$EXPLICIT_SCANDEF" && -z "$EXPLICIT_PHASE" ]]; then
    if [[ -f "$SCRIPT_DIR/scan_phase.txt" ]]; then EXPLICIT_PHASE="$SCRIPT_DIR/scan_phase.txt"
    elif [[ -f "$(dirname "$EXPLICIT_SCANDEF")/forte_top.scan_phase.txt" ]]; then
        EXPLICIT_PHASE="$(dirname "$EXPLICIT_SCANDEF")/forte_top.scan_phase.txt"
    fi
fi
[[ -z "$EXPLICIT_SCANDEF" ]] || EXPLICIT_SCANDEF=$(realpath "$EXPLICIT_SCANDEF")
[[ -z "$EXPLICIT_PHASE" ]] || EXPLICIT_PHASE=$(realpath "$EXPLICIT_PHASE")

if ! command -v vcs >/dev/null; then
    if type module &>/dev/null; then module load Synopsys_x86-64; fi
    command -v vcs >/dev/null || die "vcs not found; load the simulator environment first"
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
for f in "${PDKS[@]}" "${PADS[@]}" "${SRAMS[@]}"; do
    [ -n "${seen[$f]-}" ] || { seen[$f]=1; SRCS+=("$f"); }
done
# IGNORE_CELLS (vm_paths.sh): physical-only cells (fill, decap, tap) get empty
# modules, made by hvl/pin/pin.sh so both benches treat them alike.
if declare -p IGNORE_CELLS &>/dev/null && [ ${#IGNORE_CELLS[@]} -gt 0 ]; then
    ign=$(SIM=vcs DUT=gate PIN_VM_PATHS="$PATHS_FILE" PIN_NETLIST="$NETLIST" PIN_SDF="" \
          PIN_BUILD="$SIM_ROOT/meta/ignored" bash "$REPO_DIR/hvl/pin/pin.sh" ignored-cells) \
        || die "IGNORE_CELLS: hvl/pin/pin.sh ignored-cells failed"
    [ -z "$ign" ] || SRCS+=("$ign")
fi

# vcs_build <dir> <extra args...>: tb_scan on $NETLIST into <dir>/simv_scan.
vcs_build() {
    local dir="$1"; shift
    ( cd "$dir" && vcs -full64 -sverilog -timescale=1ns/1ps -l compile.log \
        "$@" ${FLAGS[@]+"${FLAGS[@]}"} \
        "${COMPILE_ARGS[@]}" \
        "+incdir+$dir" "+incdir+$SRC_DIR" \
        "${SRCS[@]}" "$LINK_PKG" "$LINK_AGENT" "$SRC_DIR/tb_scan.sv" "$NETLIST" "${LIBS[@]}" \
        -Mdir=csrc -top tb_scan -o simv_scan )
}

# ---- discovery: the chains from the netlist itself (no scandef) ----------------------
# Zero-delay, in sim/meta/<netlist key>/, shared by every corner of that netlist.
discover() {
    local key meta
    key=$(stat -L -c '%n %s %Y' "$NETLIST" | sha256sum | cut -c1-16)
    meta="$SIM_ROOT/meta/$key"
    mkdir -p "$meta"
    local srcs_key
    srcs_key=$(cat "$SRC_DIR/scan_discover.svh" "$SRC_DIR/discover_cells.py" "$SRC_DIR/discover_meta.py" "$SRC_DIR/scan_map.awk" | sha256sum | cut -c1-16)
    if [[ -s "$meta/forte_top.scandef" && -f "$meta/forte_top.scan_phase.txt" && "$(cat "$meta/done" 2>/dev/null)" == "$srcs_key" ]]; then
        echo "run.sh: discovery: reusing $meta (same netlist)"
        grep -E '^\[[0-9]+\] (A: |DISCOVER: )|^DISCOVER (PASS|FAIL)' "$meta/discover.log" | sed 's/^/  | /' || true
        cat "$meta/discover_meta.out" 2>/dev/null || true
    else
        rm -f "$meta/done"
        echo "run.sh: discovery: finding the chains in the netlist (zero-delay build in $meta)"
        local excl=() f
        for f in "${SRAMS[@]}" "${PADS[@]}" "${PDKS[@]}"; do excl+=(--exclude-model "$f"); done
        python3 "$SRC_DIR/discover_cells.py" --netlist "$NETLIST" --top forte_top --dut dut \
            "${excl[@]}" -o "$meta/discover_probes.generated.svh" --index "$meta/probes.tsv" \
            | tee "$meta/discover_meta.out" || die "discovery: discover_cells.py failed"
        printf '%s\n' "// stub map for the discovery build; do not edit." \
            "function automatic void scan_map_init();" "  n_regs = 0;" "endfunction" \
            > "$meta/scan_map.generated.svh"
        local saved=("${COMPILE_ARGS[@]}")
        COMPILE_ARGS=()
        vcs_build "$meta" +nospecify +notimingcheck +define+SCAN_DISCOVER +define+SCAN_NO_HOOKUPS \
            > "$meta/build.out" 2>&1 || { tail -20 "$meta/compile.log" >&2; die "discovery: VCS build failed, see $meta/compile.log"; }
        COMPILE_ARGS=("${saved[@]}")
        ( cd "$meta" && ./simv_scan -l discover.log > /dev/null 2>&1 ) || true
        grep -E '^\[[0-9]+\] (A: |DISCOVER: )|^DISCOVER (PASS|FAIL)|ERROR #' "$meta/discover.log" | sed 's/^/  | /' || true
        grep -q '^DISCOVER PASS' "$meta/discover.log" || die "discovery failed: see $meta/discover.log"
        python3 "$SRC_DIR/discover_meta.py" scandef --probes "$meta/probes.tsv" \
            --discover "$meta/discover.tsv" -o "$meta/forte_top.scandef" | tee -a "$meta/discover_meta.out" \
            || die "discovery: no scandef"
        awk -v TOP=forte_top -f "$SRC_DIR/scan_map.awk" "$meta/forte_top.scandef" > "$meta/map_nophase.svh" \
            || die "discovery: scan_map.awk rejected the discovered scandef"
        python3 "$SRC_DIR/discover_meta.py" phase --probes "$meta/probes.tsv" --discover "$meta/discover.tsv" \
            --map "$meta/map_nophase.svh" -o "$meta/forte_top.scan_phase.txt" | tee -a "$meta/discover_meta.out" \
            || die "discovery: no phase file"
        echo "$srcs_key" > "$meta/done"
    fi
    if [[ -n "$EXPLICIT_SCANDEF" ]]; then
        echo "run.sh: discovery: compared with $EXPLICIT_SCANDEF${EXPLICIT_PHASE:+ and its phase file}"
        python3 "$SRC_DIR/discover_meta.py" compare --scandef "$meta/forte_top.scandef" \
            --ref-scandef "$EXPLICIT_SCANDEF" \
            ${EXPLICIT_PHASE:+--phase "$meta/forte_top.scan_phase.txt" --ref-phase "$EXPLICIT_PHASE"} \
            || echo "run.sh: discovery: DIFFERENT from the given scandef/phase (counts above); using what was discovered"
    fi
    SCANDEF="$meta/forte_top.scandef"
    LOGICAL_PHASE="$meta/forte_top.scan_phase.txt"
}

SCANDEF="" LOGICAL_PHASE=""
if (( DISCOVER || DISCOVER_ONLY )) || { (( REGENERATE )) && [[ -z "$EXPLICIT_SCANDEF" ]]; }; then
    discover
    (( DISCOVER_ONLY )) && { echo "run.sh: discovery done: $SCANDEF"; exit 0; }
else
    SCANDEF=$EXPLICIT_SCANDEF
    LOGICAL_PHASE=$EXPLICIT_PHASE
    if [[ -z "$SCANDEF" ]]; then
        # Not regenerating and no scandef: the cached map says what it came from.
        prev=$(sed -n 2p "$SIM_DIR/scan_metadata.inputs" 2>/dev/null || true)
        [[ -n "$prev" && -f "$prev" ]] || die "no scandef for $NETLIST and no discovered one cached: run ./run.sh$( (( TIMING )) && echo " --timing --corner $CORNER") --regen"
        SCANDEF=$prev
        LOGICAL_PHASE=$(sed -n 3p "$SIM_DIR/scan_metadata.inputs")
    fi
fi

SCAN_MAP="$SIM_DIR/scan_map.generated.svh"
SCAN_HOOKUP_FILE="$SIM_DIR/scan_hookups.generated.svh"
SCAN_REPORT="$SIM_DIR/scan_hookups.generated.report.tsv"
METADATA_INPUTS=$(printf '%s\n' "$NETLIST" "${SCANDEF:-}" "${LOGICAL_PHASE:-}")
if (( REGENERATE )); then
    [ -f "$SCANDEF" ] || die "no scandef at $SCANDEF"
    echo "run.sh: logical phase from ${LOGICAL_PHASE:-<none>: every cell taken as stored in true polarity}"
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
    printf '%s\n' "$METADATA_INPUTS" > "$SIM_DIR/scan_metadata.inputs"
    echo "run.sh: regenerated scan map and enabled hookups from $SCANDEF"
else
    [[ -f "$SIM_DIR/scan_metadata.inputs" && "$(cat "$SIM_DIR/scan_metadata.inputs")" == "$METADATA_INPUTS" ]] \
        || die "scan metadata inputs changed or cache is missing; run ./run.sh$( (( TIMING )) && echo " --timing --corner $CORNER") --regen"
    [ -s "$SCAN_MAP" ] || die "no cached scan map at $SCAN_MAP; run ./run.sh --regen once"
    # A map older than what it was made from belongs to another netlist.
    for f in "$NETLIST" "$SCANDEF" "${LOGICAL_PHASE:-}" "$SRC_DIR/scan_map.awk"; do
        [[ -n "$f" && -f "$f" && "$f" -nt "$SCAN_MAP" ]] \
            && die "cached scan map is older than $f; run ./run.sh --regen"
    done
    if [[ "${SCAN_HOOKUPS:-1}" == 1 ]]; then
        [ -s "$SCAN_HOOKUP_FILE" ] || die "no cached hookups at $SCAN_HOOKUP_FILE; run ./run.sh --regen"
        [[ "$SRC_DIR/internal_hookups.py" -nt "$SCAN_HOOKUP_FILE" ]] \
            && die "cached hookups are older than src/internal_hookups.py; run ./run.sh --regen"
    fi
    echo "run.sh: reusing generated map/hookups; use --regen after netlist, scandef, or phase changes"
fi
if [[ "${SCAN_HOOKUPS:-1}" != 1 ]]; then
  COMPILE_ARGS+=(+define+SCAN_NO_HOOKUPS)
fi

echo "run.sh: netlist $NETLIST"
echo "run.sh: ${#SRCS[@]} PDK/pad/SRAM model file(s), $(( ${#LIBS[@]} / 2 )) cell library file(s)"

cd "$SIM_DIR"
rm -f timing_summary.log
# Timing mode retains specify blocks, timing checks and notifier behavior.
vcs_build "$SIM_DIR" "${TIMING_ARGS[@]}" || die "VCS build failed, see $SIM_DIR/compile.log"

ANN=() ANN_FAIL=""
if (( TIMING )); then
    # shellcheck source=../../../hvl/pin/sdf_msgs.sh
    source "$REPO_DIR/hvl/pin/sdf_msgs.sh"
    mode=strict; (( IGNORE_NIOD )) && mode=niod
    # VCS skips an unchanged design and then prints no annotation: judge the
    # log of the compile that built it (kept as compile.full.log).
    ann_log="$SIM_DIR/compile.log"
    if grep -q "design hasn't changed and need not be recompiled" "$ann_log"; then
        ann_log="$SIM_DIR/compile.full.log"
        [ -s "$ann_log" ] || die "VCS did not recompile and there is no log of the build it reused; delete $SIM_DIR/simv_scan.daidir and rerun"
        echo "run.sh: design unchanged; judging the SDF annotation of the build it reused"
    else
        cp "$SIM_DIR/compile.log" "$SIM_DIR/compile.full.log"
    fi
    if sdf_classify "$ann_log" "$SDF" "$mode"; then
        ANN+=("complete: 0 errors; $SDFM_UH SDFCOM_UHICD (wires into forte_top output ports), $SDFM_IW SDFCOM_IWSBA (INTERCONNECT through an assign, still annotated)")
        (( SDFM_NN > 0 )) && ANN+=("$SDFM_NN SDFCOM_NIOD (negative IOPATH) IGNORED -- not a sign-off run")
    else
        ANN_FAIL=$SDFM_ERR
    fi
    [[ -z "$SDF_NOTE" ]] || ANN+=("$SDF_NOTE")
    prep_note=""; [[ "$SDF" == "$SDF_SRC" ]] || prep_note=", simulated a prepared copy (hvl/pin/sdf_prep.sh)"
    ANN+=("SDF corner $CORNER$prep_note")
fi

rm -f sim.log
sim_status=0
if [[ -z "$ANN_FAIL" ]]; then
    # Timing-check messages (model file, pins, limits) stay in sim.log;
    # timing_summary.log counts them.
    ./simv_scan -l sim.log "${RUN_ARGS[@]}" | grep -E '^\[|^(GROUP|REG|PC|PHASE):|^S (CHECKS|CHECK COVERAGE|COVERAGE|RESUME):|^OUTPUT Z SUMMARY:|DFT TB|^=+' || sim_status=$?
fi
if (( TIMING )); then
    args=()
    for l in "${ANN[@]}"; do args+=(--annotation "$l"); done
    [[ -z "$ANN_FAIL" ]] || args+=(--annotation-fail "$ANN_FAIL")
    python3 "$SRC_DIR/timing_report.py" sim.log "${args[@]}" > timing_summary.log \
        || { cat timing_summary.log; die "timing/annotation check failed; see $SIM_DIR/timing_summary.log"; }
    cat timing_summary.log
fi
(( sim_status == 0 )) || die "simulation failed (status $sim_status); see $SIM_DIR/sim.log"
grep -qE '^DFT TB PASS($| \(partial coverage:)' sim.log \
    || die "simulation did not produce a passing verdict; see $SIM_DIR/sim.log"
