#!/bin/bash
# synth/scripts/full_tb/standin/build.sh <outdir> -- an IP-free stand-in for the
# VM's PnR netlist, built on EWS, for testing full_tb without the VM.
#
# This tree's own synthesis + DFT flow (synth/synthesis.tcl, dft_insert.tcl) on
# FreePDK45 (/class/ece411/freepdk-45nm), full scope: expect 1299 scan cells
# on 8 chains, like the VM.  Takes ~20 min.  Writes into <outdir>:
#   repo/synth/synout/dft/  netlist, DC scandef and phase (the reference for
#                           discovery), forte_top.standin.sdf (DC, synthesis-only)
#   drop/forte_top.pnr.v    the netlist alone, as the VM's PnR drop has it
#   vm_paths.sh             for run.sh / postpnr_dft.sh / pin.sh (--vm-paths)
#
# Stand-in quirks (EWS only; the VM's TSMC netlist has none of them):
#   - The FreePDK45 .lib has no test_cell groups; add_test_cell.py adds them for
#     the SDFF* cells and lc_shell compiles the .db.
#   - The FreePDK45 Verilog DFFR model, without NTC, drives its own RN input:
#     vm_paths.sh sets +define+TETRAMAX, which selects the plain functional model.
#   - Pads are synthesized from hvl/pin/models/pad_behav.sv (flattened away);
#     the SRAM macros stay black boxes, simulated with sram_behav.sv.
#   - The DC SDF has no clock tree and unbuffered ~1300-fanout scan enable: it
#     exercises the SDF plumbing (prep, annotation rules, violation counts) but
#     the chip does not run with it.  Functional timing is a VM-only check.
#   - internal_hookups.py probes the net named chip.scan_en_dft, which this
#     mapping inverts: phase S reports a false "effective SE=1 outside test
#     mode".  Run with SCAN_HOOKUPS=0 on the stand-in.
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 <outdir>" >&2; exit 2; }
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO="$(cd "$HERE/../../../.." && pwd)"
OUT="$(mkdir -p "$1" && cd "$1" && pwd)"
PDK=/class/ece411/freepdk-45nm
SYN=/software/Synopsys-2024_x86_64
export PATH="$SYN/syn/W-2024.09/bin:$SYN/lc/W-2024.09/bin:$SYN/vcs/W-2024.09/bin:$PATH"

# 1. scan-capable library
mkdir -p "$OUT/lib"
python3 "$HERE/add_test_cell.py" "$PDK/stdcells.lib" "$OUT/lib/stdcells_scan.lib"
printf 'read_lib stdcells_scan.lib\nwrite_lib NangateOpenCellLibrary -format db -output stdcells_scan.db\nexit\n' > "$OUT/lib/mk.tcl"
# lc_shell on EWS needs the system Kerberos/terminfo libraries, not the tool's.
( cd "$OUT/lib" && LD_LIBRARY_PATH= LD_PRELOAD="/lib64/libk5crypto.so.3 /lib64/libtinfo.so.5" \
    lc_shell -f mk.tcl > lc.log 2>&1 )
[ -s "$OUT/lib/stdcells_scan.db" ] || { echo "lc_shell failed: $OUT/lib/lc.log" >&2; exit 1; }

# 2. a copy of the sources the flow reads, with FreePDK45 settings
R="$OUT/repo"; rm -rf "$R"; mkdir -p "$R/io_drivers"
cp -r "$REPO/hdl" "$REPO/pkg" "$REPO/synth" "$REPO/options.json" "$R/"
printf '`timescale 1ns/1ps\nmodule io_in  (input  wire chipout, output wire chipin);  assign chipin  = chipout; endmodule\n' > "$R/io_drivers/io_in.sv"
printf '`timescale 1ns/1ps\nmodule io_out (output wire chipout, input  wire chipin);  assign chipout = chipin;  endmodule\n' > "$R/io_drivers/io_out.sv"
sed -i 's/^set_wire_load_model -name tsmc65_wl10/# &/' "$R/synth/synthesis.tcl"
cat > "$R/synth/env.sh" <<EOF
export TSMC_DB_DIR=$OUT/lib TSMC_DB_FAST=stdcells_scan.db DCROOT=$SYN/syn/W-2024.09
for v in 44 128 68 32_45 32_128 16_46 16_128 64_46 64_53 64_137 256_53 256_137 128_53 128_137; do export SRAM_DB_FAST_\$v=""; done
export REPORT_DIR=reports SYN_OUT_DIR=synout DFT_SCOPE=full DFT_KEEP_ALL=0
EOF

# 3. synthesis, standalone insertion, SDF
cd "$R/synth"
source ./env.sh     # ./ : bash's source searches PATH first
mkdir -p reports synout
echo "standin: synthesis ($(date +%T))"
dc_shell -64bit -f synthesis.tcl > reports/synthesis.log 2>&1
mkdir -p reports/dft synout/dft
echo "standin: scan insertion ($(date +%T))"
REPORT_DIR="$PWD/reports/dft" SYN_OUT_DIR="$PWD/synout/dft" \
  dc_shell -x 'set dft_standalone true; source dft_insert.tcl' > reports/dft/dft.log 2>&1
cat > sdf.tcl <<'T'
set search_path [concat . [getenv TSMC_DB_DIR] [file join [getenv DCROOT] libraries syn]]
set target_library [getenv TSMC_DB_FAST]
set link_library [concat "*" $target_library dw_foundation.sldb]
read_ddc synout/dft/forte_top.gate.ddc
current_design forte_top
link
write_sdf -version 3.0 synout/dft/forte_top.standin.sdf
exit
T
echo "standin: SDF ($(date +%T))"
dc_shell -64bit -f sdf.tcl > reports/dft/sdf.log 2>&1
grep -m1 'DFT phase:' reports/synthesis.log || true
[ -s synout/dft/forte_top.gate.v ] || { echo "no netlist: see $R/synth/reports" >&2; exit 1; }

# 4. the drop (netlist alone, no scandef beside it) and its vm_paths.sh
mkdir -p "$OUT/drop"
cp synout/dft/forte_top.gate.v "$OUT/drop/forte_top.pnr.v"
cp synout/dft/forte_top.standin.sdf "$OUT/drop/forte_top.pnr.sdf"
cat > "$OUT/vm_paths.sh" <<EOF
NETLIST=$OUT/drop/forte_top.pnr.v
SDF=$OUT/drop/forte_top.pnr.sdf
SDF_CORNER=min
PDK_FIRST=()
PAD_MODELS=($REPO/hvl/pin/models/pad_behav.sv)
SRAM_MODELS=($REPO/hvl/pin/models/sram_behav.sv)
STDCELL_MODELS=($PDK/stdcells.v)
VCS_FLAGS=(-j4 +define+TETRAMAX)
IGNORE_CELLS=()
EOF
echo "standin: done.  Try:"
echo "  synth/scripts/full_tb/run.sh --vm-paths $OUT/vm_paths.sh --discover-only --discover   # vs DC's scandef: use NETLIST=$R/synth/synout/dft/forte_top.gate.v"
echo "  SCAN_HOOKUPS=0 synth/scripts/full_tb/run.sh --vm-paths $OUT/vm_paths.sh --regen +SCAN_PHASES=C"
