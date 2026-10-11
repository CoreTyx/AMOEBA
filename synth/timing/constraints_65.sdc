# Constraints for forte_top in the calibrated timing flow.
#
# Sourced by run_timing.tcl after tech.tcl, so TECH() and ns65 exist.  Every
# time is written in 65 nm nanoseconds and converted with ns65; see tech.tcl.
#
# This is the timing-analysis counterpart of ../constraints.sdc, which the
# course `make synth` flow still uses.  The differences are the ports that have
# changed since that file was written (`burst` is gone, `clk_out` and
# `fault_inject` exist) and that nothing here is a fixed number of nanoseconds.

set period [ns65 $TECH(PERIOD_NS)]

create_clock -period $period -name my_clk [get_ports core_clk]
set_clock_uncertainty [expr {$TECH(CLK_UNCERTAINTY_FRAC) * $period}] [get_clocks my_clk]

# The forwarded link clock.  Nothing on the die is timed against it; it is
# declared so the port is a clock and not an unconstrained data output.
create_generated_clock -name link_fwd -source [get_ports core_clk] -divide_by 1 [get_ports clk_out]

# Asynchronous, or synchronised on the die, or static for the life of a test.
set_false_path -from [get_ports rst_n]
set_false_path -from [get_ports {irq[*] uart_rx test_mode scan_en}]

# fault_inject: synchronised on the die like irq and uart_rx.  The else branch
# times it as a synchronous input, which is what it was before the synchroniser.
if {$TECH(FI_SYNCHRONISED)} {
   set_false_path -from [get_ports fault_inject]
} else {
   set_input_delay -clock my_clk -max [expr {$TECH(FI_IN_DELAY_FRAC) * $period}] [get_ports fault_inject]
}

# Link.  The FPGA launches on the rising edge and the phy captures on the
# falling one, so the inbound paths are half-cycle checks.
set link_in  [get_ports {io[*] ready rvalid}]
set link_out [get_ports {io[*] dir req wr}]
set_input_delay  -clock my_clk -max [expr {$TECH(LINK_IN_DELAY_FRAC)  * $period}] $link_in
set_output_delay -clock my_clk -max [expr {$TECH(LINK_OUT_DELAY_FRAC) * $period}] $link_out

# Slow outputs.
set_output_delay -clock my_clk -max [expr {$TECH(LINK_OUT_DELAY_FRAC) * $period}] [get_ports {uart_tx status}]

# The pad models have a fixed delay, so the board load is already inside
# PAD_OUT_NS and a set_load here would add nothing.
