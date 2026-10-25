# Copy to a site-specific hookup file and set DFT_HOOKUP_TCL to its path.
# This file is sourced AFTER the mapped netlist is read and linked.
# Use actual mapped names: retiming, ungrouping and name rules may remove or
# change the original RTL hierarchy. get_cells -hierarchical / report_hierarchy
# in dc_shell can be used to identify the desired pipeline and CSR cells.

# Tier-1 partial-scan population: replace these names with mapped pipeline-control,
# PC, privilege/status/interrupt/trap and PMP/satp register cells. Expand this list
# for higher tiers only after measuring the resulting area/timing overhead.
set scan_regs [get_cells {
    REPLACE_WITH_PIPELINE_REGISTER_CELLS
    REPLACE_WITH_CRITICAL_CSR_REGISTER_CELLS
}]

# Actual mapped lock/authorization cells, or preserved hierarchical instances.
# Both are excluded from scan and protected from DFT optimization.
set dft_lock [get_cells {REPLACE_WITH_MAPPED_LOCK_CELLS}]
set dft_control [get_cells {REPLACE_WITH_MAPPED_TEST_CONTROL_CELLS}]

# Existing lock-qualified output-side hookup pins. The scan enable must also
# require test mode/session selection. These declarations do not add those gates.
set dft_test_mode [get_pins {REPLACE_WITH_AUTHORIZED_TEST_MODE_PIN}]
set dft_scan_enable [get_pins {REPLACE_WITH_AUTHORIZED_SCAN_ENABLE_PIN}]

# Ordered lists of eight actual internal pin names, one SI/SO pair per chain.
# Paths retain io[7:0] inputs, io[15:8] outputs and the existing pad mux. The
# input netlist must provide valid endpoints in place of the scan_q placeholders.
set dft_scan_inputs {
    REPLACE_SI0 REPLACE_SI1 REPLACE_SI2 REPLACE_SI3
    REPLACE_SI4 REPLACE_SI5 REPLACE_SI6 REPLACE_SI7
}
set dft_scan_outputs {
    REPLACE_SO0 REPLACE_SO1 REPLACE_SO2 REPLACE_SO3
    REPLACE_SO4 REPLACE_SO5 REPLACE_SO6 REPLACE_SO7
}

# Site-specific DFT setup commands may follow here for reset initialization, ICG
# test control, memory test models and implemented APB/SRAM isolation. The input
# netlist must contain the actual authorization/isolation logic and, for MBIST,
# a controller and raw-memory test access path. This template generates none.
