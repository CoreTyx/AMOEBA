# hvl/pin/vm_paths.sh -- site paths for VCS runs.  FILL THESE IN ON THE VM.
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

# Verilog simulation models.  Each is compiled with -v (library: only the
# modules the design references are elaborated).
STDCELL_MODELS=()                        # standard-cell library .v
SRAM_MODELS=()                           # rf_sp_<D>_<W> macro models (PDK)
PAD_MODELS=()                            # io_in / io_out / io_tri

# Used for the RTL reference too: forte_top under `SYNTHESIS instantiates the
# SRAM macros and pad cells, so the RTL build needs SRAM_MODELS and PAD_MODELS.
# Leave both empty to fall back to hvl/pin/models/*_behav.sv (NOT sign-off).
