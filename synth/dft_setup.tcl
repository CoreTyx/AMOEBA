# Pre-compile DFT setup.  Sourced once by synthesis.tcl, with forte_top
# selected, after dft_procs.tcl.  Selects the scan flops, keeps the DFT control
# nets alive through mapping, and declares the existing tester controls.
# synthesis.tcl binds the control hookups after mapping (dft_bind_hookups).
#
# DFT_SCOPE (environment) picks the scan selection:
#   pc    (default)  the fetch PC only: 63/64 flops, the pc_tb bench
#   full             PC + pipeline registers + hardened CSRs (~1,600 flops),
#                    the full_tb bench
# DFT_KEEP_ALL=1 (environment) keeps flops DC would otherwise optimize out
# (constant, unloaded, duplicate); see where scan_regs is set below.
# Changing either needs a full re-synthesis: the attributes go into the
# pre-DFT ddc.

set dft_scope [expr {[info exists ::env(DFT_SCOPE)] && $::env(DFT_SCOPE) ne "" ? $::env(DFT_SCOPE) : "pc"}]
puts "DFT setup: scope $dft_scope"

# Configure the complete ASIC, including the pad ring. Retain only the chip
# boundary so its named control nets can be found after mapping. Permit
# optimization across that boundary; soc/uncore can still be ungrouped.
set_ungroup [get_cells chip] false
set_boundary_optimization [get_cells chip] true

# Never let mapping store a register inverted (D inverted, value read off QN).
# This variable covers compile only: compile_ultra ignores it and needs
# -no_seq_output_inversion, which synthesis.tcl passes.  With both, and the
# scan flops kept out of retiming, every scan cell holds its RTL bit in true
# polarity; dft_write_phase checks the netlist for any that do not.
set compile_seqmap_enable_output_inversion false
printvar compile_seqmap_enable_output_inversion

# Preserve the DFT control nets through mapping (hdl/forte_chip.sv):
#   scan_en_dft    = scan_en & test_mode_dft
#   test_mode_dft  = test_mode_s & dft_unlocked
#   test_mode_s    test_mode after the two tmsync flops
#   dft_unlocked   the DFT lock register's output
#   hold_mode      scan_en (through sesync) sampled while test_mode_s is low
# synthesis.tcl binds them to their mapped drivers, then releases them.
# Ordinary dont_touch can be ignored on nets attached to unmapped cells, so
# enable DC's net-preservation behaviour first.
set enable_keep_signal_dt_net true
set dft_ctrl_nets [get_nets -quiet {chip/scan_en_dft chip/test_mode_dft chip/test_mode_s chip/dft_unlocked chip/hold_mode}]
if {[sizeof_collection $dft_ctrl_nets] != 5} {
  error "DFT: expected 5 control nets in chip (scan_en_dft test_mode_dft test_mode_s dft_unlocked hold_mode); found [sizeof_collection $dft_ctrl_nets]: [get_object_name $dft_ctrl_nets]"
}
set_dont_touch $dft_ctrl_nets true

# The clock split (hdl/forte_chip.sv, hdl/forte_clk_gate.sv).  core_clk feeds
# two RTL clock gates, both enabled by ~hold (hold = test_mode_dft & hold_mode):
#   cg_ns    te = 0             every non-scan register, forte_soc included
#   cg_scan  te = scan_en_dft   exactly the scan-selected registers
# In hold mode a shift clocks only the chains, so a scan dump does not disturb
# the register file, CSRs, UART, ...  Their test pins are wired in RTL and must
# stay that way: dft_insert.tcl excludes both from insert_dft's clock-gate
# hookup, and dft_check_clock_split (synthesis.tcl, after compile) checks that
# cg_scan clocks exactly the scan selection.  Both are kept as hierarchy, so
# their gclk pins can be found after mapping, without boundary optimisation,
# so nothing is pushed into or out of them, and out of retiming.
set dft_clock_gates [get_cells -quiet {chip/cg_ns chip/cg_scan}]
if {[sizeof_collection $dft_clock_gates] != 2} {
  error "DFT: expected the RTL clock gates chip/cg_ns and chip/cg_scan (forte_clk_gate); found [get_object_name $dft_clock_gates]"
}
set_ungroup $dft_clock_gates false
set_boundary_optimization $dft_clock_gates false
set_dont_retime $dft_clock_gates true

# Scan registers, by group. One hierarchical pattern per line, matched against
# the elaborated (pre-compile) names under chip/soc/core; "*" spans hierarchy,
# so "*/ifu/*PCMReg/*" also finds a register inside a genblk.  priv and mdu are
# instances inside generate blocks of the same name, which DC names "priv.priv"
# and "mdu.mdu": hence "priv*" and "mdu*", not "priv/".  Only sequential
# cells are taken, each once.  A pattern that matches nothing is reported, a
# group that matches nothing is an error.
#   pc            the fetch PC (both benches read it)
#   pipeline      the D/E/M/W stage registers of the IFU, IEU (controller and
#                 the ECC-protected datapath registers), LSU, MDU and the
#                 privileged unit.  Not the divider's iteration state, the
#                 caches, the TLBs or the regfile: those are arrays or FSMs.
#   hardened_csr  the triplicated privilege mode (data and check copies),
#                 mstatus.MPP (reserved-value check), MSECFAULT, MFTSTATUS and
#                 RANDINSTRFREQ.
set scan_group_pc {
  */ifu/pcreg/q_reg*
}
set scan_group_pipeline {
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
  */core/priv*/ppr/*faultregD/*
  */core/priv*/ppr/*faultregE/*
  */core/priv*/ppr/*faultregM/*
  */core/priv*/csr/*CSRValWReg/*
  */core/priv*/pmd/*wfiWReg/*
}
set scan_group_hardened_csr {
  */core/priv*/privmode/*privmodereg_*
  */core/priv*/privmode/*privchkreg_*
  */core/priv*/csr/csrsr/STATUS_MPP_reg*
  */core/priv*/csr/csrm/MSECFAULT_REGW_reg*
  */core/priv*/csr/csrm/*RANDINSTRFREQreg/*
  */core/FTStatusSticky_reg*
}
switch -- $dft_scope {
  pc      { set scan_reg_groups [list pc $scan_group_pc] }
  full    { set scan_reg_groups [list pc $scan_group_pc pipeline $scan_group_pipeline hardened_csr $scan_group_hardened_csr] }
  default { error "DFT: DFT_SCOPE must be pc or full, not '$dft_scope'" }
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
# name, in true polarity.  With -retime this also stops DC moving them.
set_dont_retime $scan_regs true
set_scan_element false [all_registers -edge_triggered]
set_scan_element true $scan_regs

# DFT_KEEP_ALL=1 (environment, default 0): keep every selected flop as its own
# scan cell, so a scan dump maps bit for bit onto the RTL registers.  By
# default compile_ultra deletes flops that hold a constant (PC[0], unused
# controlreg fields), have no load (Funct7E), or duplicate another flop, and
# those bits are simply not on the chains.  Keeping them costs area and adds
# no fault coverage.  Merging is turned off for the scan flops only; the two
# variables are design-wide, so check the area report after using it.
set dft_keep_all [expr {[info exists ::env(DFT_KEEP_ALL)] && $::env(DFT_KEEP_ALL) eq "1"}]
if {$dft_keep_all} {
  set_register_merging $scan_regs false
  set compile_seqmap_propagate_constants false
  set compile_delete_unloaded_sequential_cells false
  puts "DFT setup: DFT_KEEP_ALL=1: constant, unloaded and duplicate flops are kept"
}
printvar compile_seqmap_propagate_constants
printvar compile_delete_unloaded_sequential_cells

# Flops that must never be on a chain, whatever the selection:
#   the DFT lock      observable is bad, settable is worse (forte_dft_lock.sv)
#   tmsync            shifting test_mode's synchroniser would drop test mode
#                     mid-shift; DRC is told it holds 1 (dft_bind_hookups)
#   sesync, hold_mode the hold-mode select: scan_en through two flops, sampled
#                     while test_mode_s is low and frozen in test mode.  On a
#                     chain it would change mid-shift; DRC is told it holds 0
#                     (legacy test mode: both clock gates pass the clock)
#   holdlinksync      hold carried into the link_clk domain
# All but the lock sit on the ungated core_clk/link_clk, outside both RTL
# gates; the lock is in forte_soc, under cg_ns.
foreach {what pattern} {
  lock         chip/soc/uncore/dftlock/*
  tmsync       chip/tmsync/*
  sesync       chip/sesync/*
  hold_mode    chip/hold_mode*
  holdlinksync chip/holdlinksync/*
} {
  set regs [filter_collection $all_seq "full_name=~$pattern"]
  if {[sizeof_collection $regs] == 0} { error "DFT: no $what flops matched $pattern before compile" }
  puts "DFT setup: $what: [sizeof_collection $regs] flops kept non-scan"
  set_scan_element false $regs
  set_dont_retime $regs true
}

# scan_en's one functional load.  Declaring scan_en as the ScanEnable port
# (below) makes test-ready compile treat it as inactive in functional logic,
# and without this compile_ultra folded sesync away and tied hold_mode's D to
# 0: hold mode could never be selected and every session was a legacy one
# (found by full_tb phase S on a FreePDK45 run, 2026-11-12).  A separate
# boundary with no boundary optimisation keeps that constant out of sesync;
# dft_check_hold_select (dft_procs.tcl) checks the result after compile.
set_ungroup [get_cells chip/sesync] false
set_boundary_optimization [get_cells chip/sesync] false

# Existing tester controls at the package pins. The single core_clk pad feeds
# both core_clk and link_clk inside chip; there is no second test clock.
set_scan_configuration -style multiplexed_flip_flop -clock_mixing no_mix
set_dft_drc_configuration -internal_pins enable
set_dft_signal -view existing_dft -type ScanClock -port core_clk -timing {45 55}
set_dft_signal -view existing_dft -type Reset -port rst_n -active_state 0
set_dft_signal -view existing_dft -type Constant -port test_mode -active_state 1

# The external scan-enable role for scan-aware compilation. Internal hookups
# must be assigned AFTER mapping and change_names: RTL leaf pins can disappear
# during either step. dft_bind_hookups replaces this port-only spec.
set_dft_signal -view spec -type ScanEnable -port scan_en -active_state 1

# Scan-data ports and chain endpoints are declared in dft_insert.tcl.
