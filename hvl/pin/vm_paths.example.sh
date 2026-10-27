# hvl/pin/vm_paths.example.sh -- template for hvl/pin/vm_paths.sh, the VM's
# own netlist and library paths.  On the VM:
#     cp hvl/pin/vm_paths.example.sh hvl/pin/vm_paths.sh     # then fill it in
# vm_paths.sh is not tracked and never in vm_bundle.tgz, so unpacking a new
# bundle cannot overwrite it.
#
# VCS itself must already be on PATH (e.g. 'module load vcs' or the site's
# Synopsys setup script) in the shell that runs vm_run.sh; check 'which vcs'.
#
# Sourced by hvl/pin/pin.sh for --sim vcs.  Every path is checked before
# anything is compiled (pin.sh preflight), so a wrong one fails in seconds with
# its name, not after an hour of elaboration.  Bash arrays, so globs work:
#   SRAM_MODELS=(/path/to/sram/*/*.v)

# Synthesized (or placed-and-routed) netlist of forte_top.  synth/ writes
# synth/outputs/forte_top.gate.v when run with DESIGN_TOP=forte_top.
NETLIST="${NETLIST:-}"

# SDF for the same netlist.  Empty = zero-delay functional gate simulation
# (post-synthesis).  Set it for post-PnR timing simulation.
SDF="${SDF:-}"
SDF_CORNER="${SDF_CORNER:-max}"          # min | typ | max

# Verilog simulation models.  Compile order (pin.sh): PDK_FIRST, PAD_MODELS,
# SRAM_MODELS -- as ordinary sources, in the order listed, BEFORE the design --
# then the design and bench, then STDCELL_MODELS with -v (library: only the
# cells the netlist uses are elaborated).  build.log starts with the command.
PDK_FIRST=()                             # PDK primitives/headers the pad or SRAM models build on
PAD_MODELS=()                            # io_in / io_out / io_tri (and what they instantiate)
SRAM_MODELS=()                           # rf_sp_/sram_sp_<D>_<W> macro models (PDK)
STDCELL_MODELS=()                        # standard-cell library .v

# Used for the RTL reference too: forte_top under `SYNTHESIS instantiates the
# SRAM macros and pad cells, so the RTL build needs SRAM_MODELS and PAD_MODELS.
# Leave both empty to fall back to hvl/pin/models/*_behav.sv (NOT sign-off).

# SRAM macro control pins for selftest/sram_cmp.sh.  Empty = what the RTL
# wrappers tie (.RETN(1'b1), .EMA('0)); set it to try other values.
SRAM_TIES="${SRAM_TIES:-}"

# Extra VCS flags for every VCS build (pin.sh, the self-test, sram_cmp), added
# after the defaults so they win.  Put site flags here rather than editing the
# scripts: bundle files are checksummed, and a new bundle replaces them.  e.g.
#   VCS_FLAGS=(+define+ARM_UD_MODEL -debug_acc+all -kdb -j4)
VCS_FLAGS=()
