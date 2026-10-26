# PC-only scan insertion, using DFT attributes saved by dft_setup.tcl.
# Integrated: set dft_standalone false; source dft_insert.tcl
# Standalone: make dft (or dc_shell -x 'set dft_standalone true; source dft_insert.tcl').
if {![info exists dft_standalone]} { set dft_standalone true }
# Keep insertion reports separate from synthesis reports in both run modes.
set rpt [file join [file dirname [file normalize [info script]]] reports dft]
set out [expr {[info exists ::env(SYN_OUT_DIR)] ? $::env(SYN_OUT_DIR) : "outputs"}]
file mkdir $rpt $out

if {$dft_standalone} {
  # A fresh DC session needs libraries and the pre-insertion checkpoint. When
  # sourced by synthesis.tcl, use the already-compiled design and library setup.
  set search_path [concat $search_path [getenv TSMC_DB_DIR] [file join [getenv DCROOT] libraries syn]]
  set target_library [getenv TSMC_DB_FAST]
  set synthetic_library [list dw_foundation.sldb]
  set link_library [concat "*" $target_library $synthetic_library \
    [getenv SRAM_DB_FAST_44] [getenv SRAM_DB_FAST_128] [getenv SRAM_DB_FAST_68] \
    [getenv SRAM_DB_FAST_32_45] [getenv SRAM_DB_FAST_32_128] \
    [getenv SRAM_DB_FAST_16_46] [getenv SRAM_DB_FAST_16_128] \
    [getenv SRAM_DB_FAST_64_46] [getenv SRAM_DB_FAST_64_53] [getenv SRAM_DB_FAST_64_137]]
  set design_toplevel forte_top
  read_ddc synout/forte_top.pre_dft.ddc
}

current_design $design_toplevel
link

# These insertion knobs are intentionally outside the synthesis checkpoint.
# Reuse the predeclared eight SI/SO pairs; no internal signal/cell names are
# resolved here. Changing the selected registers or hookup signals needs synth.
set dft_chains 8
set test_default_period 100
set_dft_drc_configuration -internal_pins enable
set_scan_configuration -style multiplexed_flip_flop -chain_count $dft_chains -clock_mixing no_mix
for {set k 0} {$k < $dft_chains} {incr k} {
  set ko [expr {$k + 8}]
  # Reassert port roles in this design/test mode before creating the path.
  # These stable interface names require no mapped internal-signal lookup.
  set_dft_signal -view spec -type ScanDataIn -port io\[$k\]
  set_dft_signal -view spec -type ScanDataOut -port io\[$ko\]
  set_scan_path c$k -view spec -scan_data_in io\[$k\] -scan_data_out io\[$ko\]
}
# Permit scan-related mapping/optimization instead of freezing the mapped logic.
# Keep setup's exclusions/retiming restrictions limited to the PC test and lock.
set_dft_insertion_configuration -preserve_design_name true -synthesis_optimization all -unscan true

# The report makes the restored DFT specifications inspectable after read_ddc.
report_dft_signal -view spec > $rpt/dft_signals.rpt
create_test_protocol
dft_drc -verbose > $rpt/dft_drc_pre.rpt
preview_dft -show all > $rpt/dft_preview.rpt
insert_dft
dft_drc -verbose -coverage_estimate > $rpt/dft_drc_post.rpt

# Finish naming before protocol/report export so standalone and integrated
# outputs refer to the same final inserted objects.
current_design $design_toplevel
change_names -rules verilog -hierarchy
report_scan_path -view existing_dft -chain all > $rpt/dft_scan_path.rpt
report_scan_path -view existing_dft -cell all >> $rpt/dft_scan_path.rpt
write_test_protocol -output $out/forte_top.spf
write_scan_def -output $out/forte_top.scandef

current_design $design_toplevel
link
if {$dft_standalone} {
  write -format verilog -hierarchy -output $out/forte_top.gate.v
  write -format ddc -hierarchy -output $out/forte_top.gate.ddc
  exit
}
# Integrated mode returns to synthesis.tcl for its normal reports and writes.
