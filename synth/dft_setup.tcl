# Pre-compile PC-only DFT setup. Sourced once by synthesis.tcl.
# All internal names are resolved here; their DFT attributes travel with the DDC.

# Configure the complete ASIC, including the pad ring. No chip hierarchy needs
# to be retained for insertion; internal hookups are resolved before mapping.
current_design $design_toplevel

# Preserve the existing control nets through mapping. Synthesis releases the
# net preservation before checkpointing so insertion can add scan-enable loads.
set_dont_touch [get_nets -hier {scan_en_dft test_mode_dft}] true
# Anchor lock state at its existing driving leaf pin, not a SoC module port.
# Only this one-bit net is preserved; soc/uncore hierarchy can optimize freely.
set lock_net [get_nets -hier dft_unlocked]
set_dont_touch $lock_net true
set lock_drv [get_pins -leaf -of_objects $lock_net -filter "direction==out"]

# Add one hierarchical register-name pattern per line to expand scan coverage.
# Patterns are ORed; only sequential cells are selected, with no duplicates.
set scan_reg_patterns {
  */ifu/pcreg/q_reg*
}
set scan_reg_filters {}
foreach pattern $scan_reg_patterns {
  lappend scan_reg_filters "full_name=~$pattern"
}
set scan_regs [get_cells -hier * -filter "is_sequential==true && ([join $scan_reg_filters { || }])"]
puts "DFT setup: [sizeof_collection $scan_regs] scan flops selected"
if {[sizeof_collection $scan_regs] == 0} { error "DFT: no scan flops matched before compile" }
set_dont_retime $scan_regs true
set_scan_element false [all_registers -edge_triggered]
set_scan_element true $scan_regs
set_dont_retime [get_cells -hier * -filter "full_name=~*/dftlock"] true

# Define existing tester controls at the package pins. The single core_clk pad
# feeds both core_clk and link_clk inside chip; there is no second test clock.
set_scan_configuration -style multiplexed_flip_flop -clock_mixing no_mix
set_dft_drc_configuration -internal_pins enable
set_dft_signal -view existing_dft -type ScanClock -port core_clk -timing {45 55}
set_dft_signal -view existing_dft -type Reset -port rst_n -active_state 0
set_dft_signal -view existing_dft -type Constant -port test_mode -active_state 1

# Model the existing lock as unlocked for DFT DRC, as in the prior flow. This
# does not force the hardware lock open: tester reset/initialization is required.
set_dft_signal -view existing_dft -type Constant \
  -hookup_pin $lock_drv -active_state 1

# Resolve the existing RTL scan-enable driver before mapping. DFT attributes
# carry the hookup into the checkpoint; dft_insert.tcl does not search for gate names.
# This retains the existing test setup: test_mode is held high during scan.
set se_net [get_nets -hier scan_en_dft]
set se_drv [get_pins -leaf -of_objects $se_net -filter "direction==out"]
set_dft_signal -view spec -type ScanEnable -port scan_en -active_state 1 \
  -hookup_pin $se_drv

# Use the existing lock-qualified test mode for any inserted test-mode logic,
# including shared scan-output control. Do not bypass the lock with test_mode.
set tm_net [get_nets -hier test_mode_dft]
set tm_drv [get_pins -leaf -of_objects $tm_net -filter "direction==out"]
set_dft_signal -view spec -type TestMode -port test_mode -active_state 1 \
  -hookup_pin $tm_drv

# Reuse the bidirectional package pads: low byte in, high byte out during test.
# The existing test_mode_dft logic fixes these pad directions while unlocked.
# DC must trace through the pad library models; no below-pad ports are endpoints.
# Chain ordering/count remains in dft_insert.tcl for insertion-only iteration.
for {set k 0} {$k < 8} {incr k} {
  set ko [expr {$k + 8}]
  set_dft_signal -view spec -type ScanDataIn -port io\[$k\]
  set_dft_signal -view spec -type ScanDataOut -port io\[$ko\]
}

current_design $design_toplevel
