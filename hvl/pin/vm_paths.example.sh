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
# postpnr/run.sh: when NETLIST and SDF are both set here, it simulates exactly
# these (one SDF with min:typ:max triples; .gz allowed; SDF_CORNER is ignored,
# run.sh builds the corners it is asked for), and SDC is optional:
# SDC=/path/forte_top.sdc
# Without an SDC (here or in a drop folder) run.sh needs --clk-mhz and derives
# the I/O timing from the clock.  When NETLIST and SDF are empty here, run.sh
# takes netlist, SDF and SDC from the drop folder instead:
# PNR_DIR=/groups/ece427-group4/post_pnr_tb/drop
# An SDF build compiles with +neg_tchk +sdfverbose +define+NTC +define+RECREM
# (the cell-model switches for negative limits and recovery/removal checks)
# and fails on any SDFCOM_* message.
SDF="${SDF:-}"
SDF_CORNER="${SDF_CORNER:-max}"          # min | typ | max

# Verilog simulation models.  Compile order (pin.sh): PDK_FIRST, PAD_MODELS,
# SRAM_MODELS -- as ordinary sources, in the order listed, BEFORE the design --
# then the design and bench, then STDCELL_MODELS with -v (library: only the
# cells the netlist uses are elaborated).  build.log starts with the command.
PDK_FIRST=()                             # PDK primitives/headers the pad or SRAM models build on
PAD_MODELS=()                            # io_in / io_out (and what they instantiate)
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
#   VCS_FLAGS=(-j4 -fgp)
# +define+ARM_UD_MODEL (unit-delay SRAM models) is for zero-delay post-synthesis
# runs only: SDF builds drop it.  -debug_acc+all -kdb slow every run; WAVES=1
# builds a separate waveform build instead.
VCS_FLAGS=()

# Physical-only cells (fill, decap, tap, endcap) the libraries have no Verilog
# for, as cell-name globs, QUOTED (else the shell may expand them as file names):
#   IGNORE_CELLS=('FILLCAP*' 'DCAP*')
# Each matching cell gets an empty module (listed in build.log as 'build:
# ignored ...').  A cell whose instances connect anything but power/ground pins
# is refused: that one needs a real model.
IGNORE_CELLS=()
