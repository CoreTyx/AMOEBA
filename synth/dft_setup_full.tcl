# Pre-compile DFT setup: the PC, the pipeline registers and the hardened CSRs.
# Sourced once by synthesis.tcl. Select RTL registers here; synthesis.tcl binds
# control pins after mapping.

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

# Scan registers, by group. One hierarchical pattern per line, matched against
# the elaborated (pre-compile) names under chip/soc/core; "*" spans hierarchy,
# so "*/ifu/*PCMReg/*" also finds a register inside a genblk.  priv and mdu are
# instances inside generate blocks of the same name, which DC names "priv.priv"
# and "mdu.mdu": hence "priv*" and "mdu*", not "priv/".  Only sequential
# cells are taken, each once.  Add a line to widen coverage; a pattern that
# matches nothing is reported, a group that matches nothing is an error.
#   pc            the fetch PC (tb_scan.sv's PC phases read it)
#   pipeline      the D/E/M/W stage registers of the IFU, IEU (controller and
#                 the ECC-protected datapath registers), LSU, MDU and the
#                 privileged unit.  Not the divider's iteration state, the
#                 caches, the TLBs or the regfile: those are arrays or FSMs.
#   hardened_csr  the triplicated privilege mode (data and check copies),
#                 mstatus.MPP (reserved-value check), MSECFAULT, MFTSTATUS and
#                 RANDINSTRFREQ.
set scan_reg_groups {
  pc {
    */ifu/pcreg/q_reg*
  }
  pipeline {
    */core/ifu/*PCDReg/*
    */core/ifu/*AlignedInstrRawDFlop/*
    */core/ifu/*CompressedDReg/*
    */core/ifu/*CompressedEReg/*
    */core/ifu/*CompressedMReg/*
    */core/ifu/*SpillDReg/*
    */core/ifu/*SpillEReg/*
    */core/ifu/*SpillMReg/*
    */core/ifu/*InstrEReg/*
    */core/ifu/*InstrMReg/*
    */core/ifu/*InstrRawEReg/*
    */core/ifu/*InstrRawMReg/*
    */core/ifu/*PCEReg/*
    */core/ifu/*PCMReg/*
    */core/ifu/*PCSrcMReg/*
    */core/ifu/*InstrMisalignedReg/*
    */core/ieu/c/*controlregD/*
    */core/ieu/c/*controlregE/*
    */core/ieu/c/*controlregM/*
    */core/ieu/c/*controlregW/*
    */core/ieu/c/*Rs1EReg/*
    */core/ieu/c/*Rs2EReg/*
    */core/ieu/c/*RdEReg/*
    */core/ieu/c/*RdMReg/*
    */core/ieu/c/*RdWReg/*
    */core/ieu/dp/*RD1EReg/*
    */core/ieu/dp/*RD2EReg/*
    */core/ieu/dp/*ImmExtEReg/*
    */core/ieu/dp/*SrcAMReg/*
    */core/ieu/dp/*IEUResultMReg/*
    */core/ieu/dp/*WriteDataMReg/*
    */core/ieu/dp/*IFResultWReg/*
    */core/lsu/*AddressMReg/*
    */core/lsu/*ReadDataMWReg/*
    */core/mdu*/*W64MReg/*
    */core/mdu*/*MDUResultWReg/*
    */core/mdu*/*divfaultreg/*
    */core/mdu*/*PP1Reg/*
    */core/mdu*/*PP2Reg/*
    */core/priv*/ppr/*faultregD/*
    */core/priv*/ppr/*faultregE/*
    */core/priv*/ppr/*faultregM/*
    */core/priv*/csr/*CSRValWReg/*
    */core/priv*/pmd/*wfiWReg/*
  }
  hardened_csr {
    */core/priv*/privmode/*privmodereg_*
    */core/priv*/privmode/*privchkreg_*
    */core/priv*/csr/csrsr/STATUS_MPP_reg*
    */core/priv*/csr/csrm/MSECFAULT_REGW_reg*
    */core/priv*/csr/csrm/*RANDINSTRFREQreg/*
    */core/FTStatusSticky_reg*
  }
}
set all_seq [get_cells -hier * -filter "is_sequential==true"]
set scan_regs {}
foreach {group patterns} $scan_reg_groups {
  set group_regs {}
  foreach pattern $patterns {
    set regs [filter_collection $all_seq "full_name=~$pattern"]
    if {[sizeof_collection $regs] == 0} { puts "DFT setup: WARNING: $group pattern $pattern matched no flops" }
    set group_regs [add_to_collection -unique $group_regs $regs]
  }
  puts "DFT setup: $group: [sizeof_collection $group_regs] flops"
  if {[sizeof_collection $group_regs] == 0} { error "DFT: scan group $group matched no flops before compile" }
  set scan_regs [add_to_collection -unique $scan_regs $group_regs]
}
puts "DFT setup: [sizeof_collection $scan_regs] scan flops selected"
# Kept out of retiming so the scan cells are the RTL registers the patterns
# name.  With -retime this also stops DC moving these registers for timing.
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
