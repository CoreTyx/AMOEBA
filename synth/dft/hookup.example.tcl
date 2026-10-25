# Copy outside this example, fill in DC-resolved names AFTER the scan RTL
# integration described in plan.md, and pass its absolute path as DFT_HOOKUP_TCL.
# This file deliberately refuses insertion into today's one-flop scan stubs.
# No extra top-level ports may be created by insert_dft.
set DFT_HOOKS_READY 0

# Required collections are specified as exact pin names (not RTL net names).
# Use `get_pins -hierarchical` in the installed DC release to identify them.
# The scan input/output hooks must pass THROUGH the existing pad mux:
# low io pads -> scan input hooks -> chains -> scan output hooks -> high io pads.
# Check the installed manual's restrictions on internal hookup pin direction.
set DFT_LOCKED_MODE_PIN ""
set DFT_LOCKED_ENABLE_PIN ""
set DFT_CONTROL_CELL ""
set DFT_SCAN_IN_PINS {}
set DFT_SCAN_OUT_PINS {}
# Required for cumulative tiers 3/4 only: exact instance of the integrated controller.
set DFT_MBIST_CELL ""

# Required site-specific setup. Implement this after reviewing the actual RTL,
# library and DFT DRC. Do not replace it with unconditional autofix:
# - initialize reset synchronizers without making the lock reset bypassable;
# - inhibit APB writes (especially lock writes) and SRAM writes during scan;
# - provide ICG test control driven by the lock-qualified scan/test control;
# - apply approved memory black-box/test models and X masking as required.
proc dft_site_setup {} {
    error "Implement and review reset, ICG and memory isolation setup; see plan.md"
}
