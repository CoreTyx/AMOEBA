# Scan insertion, using the DFT attributes and hookups saved by dft_setup.tcl
# and dft_bind_hookups (the selection follows DFT_SCOPE at synthesis time).
# Integrated: set dft_standalone false; source dft_insert.tcl
# Standalone: make dft (or dc_shell -x 'set dft_standalone true; source dft_insert.tcl').
if {![info exists dft_standalone]} { set dft_standalone true }
set dft_dir [file dirname [file normalize [info script]]]
source [file join $dft_dir dft_procs.tcl]
# Keep insertion reports separate from synthesis reports in both run modes.
set rpt [file join $dft_dir reports dft]
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
    [getenv SRAM_DB_FAST_64_46] [getenv SRAM_DB_FAST_64_53] [getenv SRAM_DB_FAST_64_137] \
    [getenv SRAM_DB_FAST_256_53] [getenv SRAM_DB_FAST_256_137] \
    [getenv SRAM_DB_FAST_128_53] [getenv SRAM_DB_FAST_128_137]]
  set design_toplevel forte_top
  set pre_ddc [expr {[info exists ::env(DFT_PRE_DDC)] && $::env(DFT_PRE_DDC) ne "" ? $::env(DFT_PRE_DDC) : "synout/forte_top.pre_dft.ddc"}]
  read_ddc $pre_ddc
  current_design $design_toplevel
  link
  # No inverted-storage remapping during insertion.  The checkpoint's own
  # polarity comes from compile_ultra -no_seq_output_inversion in synthesis;
  # dft_write_phase below reports any cell stored inverted either way.
  set compile_seqmap_enable_output_inversion false
}
# Integrated mode inherits forte_top from synthesis.tcl; no scope change is
# needed. This script keeps that design selected throughout insertion/export.

# These insertion knobs are intentionally outside the synthesis checkpoint.
# Eight chains on the dedicated link pads: chain c<k> scans in on io_in[k] and
# out on io_out[k].  Both buses are one-way, so no pad changes direction in
# test mode; forte_chip only selects what io_out carries (scan_q stub vs link)
# and insert_dft adds its scan-out mux in front of each io_out pad.  insert_dft
# balances the scan flops across the eight chains.  No internal names are
# resolved here; changing the selected registers or hookups needs synthesis.
set dft_chains 8
set test_default_period 100
set_dft_drc_configuration -internal_pins enable
set_scan_configuration -style multiplexed_flip_flop -chain_count $dft_chains -clock_mixing no_mix
for {set k 0} {$k < $dft_chains} {incr k} {
  set si "io_in\[$k\]"
  set so "io_out\[$k\]"
  set_dft_signal -view spec -type ScanDataIn -port $si
  set_dft_signal -view spec -type ScanDataOut -port $so
  set_scan_path c$k -view spec -scan_data_in $si -scan_data_out $so
}
# Permit scan-related mapping/optimization instead of freezing the mapped logic.
# Setup's exclusions and retiming restrictions cover the scan groups, the lock
# and the test_mode synchroniser.
set_dft_insertion_configuration -preserve_design_name true -synthesis_optimization all -unscan true

# Clock-gate test pins (dft_procs.tcl, dft_cg_exclusions).  insert_dft hooks
# the test pin of every clock gate to scan enable unless told otherwise.  Keep
# the two RTL gates (chip/cg_ns, chip/cg_scan) as wired in RTL, hook the ICGs
# that gate scan flops, and leave the rest tied 0, so a hold-mode shift clocks
# the chains and nothing else.  Errors if a scan flop sits behind an excluded
# gate.  Must precede dft_drc: excluded gates are not reported as TEST-130.
set dft_scope [expr {[info exists ::env(DFT_SCOPE)] && $::env(DFT_SCOPE) ne "" ? $::env(DFT_SCOPE) : "pc"}]
set dft_cg_plan [dft_cg_exclusions chip]
set dft_cg_rtl_te [dft_cg_te_states [lindex $dft_cg_plan 2]]
report_dft_clock_gating_configuration > $rpt/dft_cg_config.rpt

# insert_dft picks each cell's scan output (Q or QN) by slack.  Either is
# fine: the scandef records it and the benches account for it.
# set test_disable_find_best_scan_out true

# The report makes the restored DFT specifications, including the Q/QN-aware
# hookups bound in synthesis, inspectable after read_ddc.
report_dft_signal -view spec > $rpt/dft_signals.rpt
report_dft_signal -view existing_dft >> $rpt/dft_signals.rpt
create_test_protocol
dft_drc -verbose > $rpt/dft_drc_pre.rpt
preview_dft -show all > $rpt/dft_preview.rpt
insert_dft
# Exactly the planned clock-gate test pins were connected (dft_procs.tcl).
dft_check_cg_hookups $dft_cg_plan $dft_cg_rtl_te
dft_drc -verbose -coverage_estimate > $rpt/dft_drc_post.rpt

# Finish naming before protocol/report export so standalone and integrated
# outputs refer to the same final inserted objects.
change_names -rules verilog -hierarchy
report_scan_path -view existing_dft -chain all > $rpt/dft_scan_path.rpt
report_scan_path -view existing_dft -cell all >> $rpt/dft_scan_path.rpt
write_test_protocol -output $out/forte_top.spf
write_scan_def -output $out/forte_top.scandef
# Per-cell logical phase for the benches (LOGICAL_PHASE / SCAN_PHASE), from the
# scandef just written and the final netlist.
dft_write_phase $out/forte_top.scandef $out/forte_top.scan_phase.txt $rpt/dft_phase.rpt
# The clock split on the final netlist: every cell on a chain is clocked
# through chip/cg_scan, and (DFT_SCOPE=full) every flop under cg_scan is on a
# chain.  Catches a scan cell lost by insert_dft -unscan or a gate rewired.
set dft_chain_cells {}
foreach {chain idx name so_pin} [dft_scandef_cells $out/forte_top.scandef] { lappend dft_chain_cells $name }
dft_check_clock_split chip [expr {$dft_scope eq "full"}] [get_cells -quiet $dft_chain_cells] "on a chain"

if {$dft_standalone} {
  write -format verilog -hierarchy -output $out/forte_top.gate.v
  write -format ddc -hierarchy -output $out/forte_top.gate.ddc
  exit
}
# Integrated mode returns to synthesis.tcl for its normal reports and writes.
