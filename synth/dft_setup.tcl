# Pre-compile PC-only DFT setup. Sourced once by synthesis.tcl.
# Select RTL registers here; synthesis.tcl binds control pins after mapping.

# Configure the complete ASIC, including the pad ring. Retain only the chip
# boundary so its three named control nets can be found after mapping. Permit
# optimization across that boundary; soc/uncore can still be ungrouped.
# The caller must have forte_top selected. This script does not change designs.
set_ungroup [get_cells chip] false
set_boundary_optimization [get_cells chip] true

# Preserve the existing control nets through mapping. Synthesis releases the
# net preservation after mapped hookups are declared, before checkpointing.
# Ordinary dont_touch can be ignored on nets attached to unmapped cells.
# Enable DC's net-preservation behavior before marking these three nets.
set enable_keep_signal_dt_net true
set_dont_touch [get_nets {chip/scan_en_dft chip/test_mode_dft}] true
# Preserve the lock-state net, not the unmapped unlocked_reg/Q pin name.
set lock_net [get_nets chip/dft_unlocked]
set_dont_touch $lock_net true

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
# Keep the lock nonscan even if a future selection pattern includes the uncore.
set lock_regs [get_cells -hier * -filter "is_sequential==true && full_name=~chip/soc/uncore/dftlock/*"]
if {[sizeof_collection $lock_regs] == 0} { error "DFT: no lock flops matched before compile" }
set_scan_element false $lock_regs
set_dont_retime $lock_regs true

# Define existing tester controls at the package pins. The single core_clk pad
# feeds both core_clk and link_clk inside chip; there is no second test clock.
set_scan_configuration -style multiplexed_flip_flop -clock_mixing no_mix
set_dft_drc_configuration -internal_pins enable
set_dft_signal -view existing_dft -type ScanClock -port core_clk -timing {45 55}
set_dft_signal -view existing_dft -type Reset -port rst_n -active_state 0
set_dft_signal -view existing_dft -type Constant -port test_mode -active_state 1

# Declare the external scan-enable role for scan-aware compilation. Internal
# hookups must be assigned AFTER mapping and change_names: RTL leaf pins can
# disappear during either step. synthesis.tcl replaces this port-only spec.
set_dft_signal -view spec -type ScanEnable -port scan_en -active_state 1

# Package scan-data roles and chain endpoints are declared in dft_insert.tcl.
