# dft_pc.tcl -- scan out the current PC (PCF, ifu/pcreg) on all 8 chains.
# Sourced by synthesis.tcl right after compile_ultra -scan.  synthesis.tcl must
# set_dont_touch the scan_en_dft net before compile so it survives.
#
#   scan in   io_i[k]       io[k], k = 0..7; the RTL turns io[7:0] inward when test_mode=1
#   scan out  io_o[k+8]     io[k+8]; the RTL turns io[15:8] outward when test_mode=1;
#                           insert_dft adds a scan-enable mux on each, after the RTL's test-mode mux
#   scan en   scan_en_dft   existing RTL net, scan_en & dft_unlocked
#   clock     core_clk

set rpt [expr {[info exists ::env(REPORT_DIR)]  ? $::env(REPORT_DIR)  : "reports"}]
set out [expr {[info exists ::env(SYN_OUT_DIR)] ? $::env(SYN_OUT_DIR) : "outputs"}]

# ---- insert below the pads ------------------------------------------------------
current_design [get_attribute [get_cells chip] ref_name]
link

# ---- the chain: PCF -------------------------------------------------------------
# Match on full_name: after ungrouping the cell's own name is "pcreg/q_reg_4_",
# so a -hier pattern starting with */ifu/ never matches.
set pc_regs [get_cells -hier * -filter "is_sequential==true && full_name=~*/ifu/pcreg/q_reg*"]
puts "DFT: [sizeof_collection $pc_regs] PC flops on the chains"
if {[sizeof_collection $pc_regs] == 0} { error "DFT: no PC flops matched" }

# ---- scan enable: the existing scan_en_dft ----------------------------------------
set se_net [get_nets -hier scan_en_dft]
if {[sizeof_collection $se_net] != 1} { error "DFT: scan_en_dft net not found uniquely (dont_touch it before compile)" }
set se_drv [get_pins -leaf -of_objects $se_net -filter "direction==out"]
puts "DFT: scan enable hookup [get_object_name $se_drv]"
if {[sizeof_collection $se_drv] != 1} { error "DFT: scan_en_dft driver not found uniquely" }
# dont_touch was only to get the net through compile; insert_dft has to add the
# scan-enable loads to it, which a dont_touch net refuses.
set_dont_touch $se_net false

# ---- what the tester holds -------------------------------------------------------
set_dft_signal -view existing_dft -type ScanClock -port {core_clk link_clk} -timing {45 55}
set_dft_signal -view existing_dft -type Reset     -port rst_n     -active_state 0
set_dft_signal -view existing_dft -type Constant  -port test_mode -active_state 1

# dft_unlocked is a non-scan flop that resets to 1; without this, DRC sees
# scan_en_dft as X and every chain as blocked.  Name the Q pin: filtering on
# direction==out also returns QN.
set_dft_drc_configuration -internal_pins enable
set lock_ff [get_cells -hier * -filter "is_sequential==true && full_name=~*unlocked_reg*"]
if {[sizeof_collection $lock_ff] != 1} { error "DFT: DFT lock flop not found uniquely" }
set lock_q [get_pins [get_object_name $lock_ff]/Q]
set_dft_signal -view existing_dft -type Constant -hookup_pin $lock_q -active_state 1

# ---- what insert_dft wires up ----------------------------------------------------
set_dft_signal -view spec -type ScanEnable  -port scan_en -active_state 1 -hookup_pin $se_drv

# ---- 8 chains, io[k] in -> io[k+8] out; PC only, everything else unscanned -------
set dft_chains 8
set_scan_configuration -style multiplexed_flip_flop -chain_count $dft_chains -clock_mixing no_mix

for {set k 0} {$k < $dft_chains} {incr k} {
  set ko [expr {$k + 8}]
  set_dft_signal -view spec -type ScanDataIn  -port io_i[$k]
  set_dft_signal -view spec -type ScanDataOut -port io_o[$ko]
  # No -include_elements: insert_dft balances the PC flops across the 8 chains.
  set_scan_path c$k -view spec -scan_data_in io_i[$k] -scan_data_out io_o[$ko]
}

set_scan_element false [remove_from_collection [all_registers -edge_triggered] $pc_regs]
set_dft_insertion_configuration -preserve_design_name true -synthesis_optimization none -unscan true

# ---- check, insert, check ----------------------------------------------------------
create_test_protocol
dft_drc -verbose                     > $rpt/dft_drc_pre.rpt
preview_dft -show all                > $rpt/dft_preview.rpt
insert_dft
dft_drc -verbose -coverage_estimate  > $rpt/dft_drc_post.rpt
report_scan_path -view existing_dft -chain all  > $rpt/dft_scan_path.rpt
report_scan_path -view existing_dft -cell all  >> $rpt/dft_scan_path.rpt

write_test_protocol -output $out/forte_chip.spf
write_scan_def      -output $out/forte_chip.scandef

# ---- back to the top for synthesis.tcl's own reports and writes ---------------------
current_design $design_toplevel
link
