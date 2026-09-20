# Constraints for amoeba_top (docs/top_level_plan.md s6).
#
# One clock, from the FPGA.  Link inputs are captured on the falling edge in
# RTL (amoeba_link_master / amoeba_link_train), so the FPGA->ASIC paths are
# half-cycle checks against the same clock; the tool derives that from the
# negedge flops.  Numbers marked PLACEHOLDER are to be replaced with the pad
# library's and the board's once known; the structure is what matters now.
#
# Post-CTS (not in this DC run): set_propagated_clock [all_clocks] and re-check
# the inbound hold paths -- that check is the proof that dropping a forwarded
# clock was safe (docs/impl_plan_onchip_periph.md tier 3).

set period_ns [expr [getenv ECE411_CLOCK_PERIOD_PS] / 1000.0]
create_clock -period $period_ns -name my_clk [get_ports clk]
set_clock_uncertainty 0.15 [get_clocks my_clk]                     ;# PLACEHOLDER: jitter + skew budget
set_fix_hold [get_clocks my_clk]

# Asynchronous or on-chip-synchronised inputs: no timing arc to constrain.
set_false_path -from [get_ports rst_n]
set_false_path -from [get_ports {irq[*] uart_rx test_mode scan_en}]

# ---- link ---------------------------------------------------------------
# FPGA launches on the rising edge; delays are FPGA clock-to-out + board
# trace (max) and the minimum of the same (min), relative to clk at our pad.
set link_in  [get_ports {io[*] ready rvalid}]
set link_out [get_ports {io[*] dir req wr burst}]
set_input_delay  -clock my_clk -max 4.0  $link_in                  ;# PLACEHOLDER: Tco_fpga(max) + trace
set_input_delay  -clock my_clk -min 1.0  $link_in                  ;# PLACEHOLDER: Tco_fpga(min) + trace
set_output_delay -clock my_clk -max 3.0  $link_out                 ;# PLACEHOLDER: FPGA Tsu + trace
set_output_delay -clock my_clk -min -0.5 $link_out                 ;# PLACEHOLDER: -(FPGA Th) + trace

# ---- slow outputs --------------------------------------------------------
set_output_delay -clock my_clk -max 3.0 [get_ports {uart_tx status}]
set_output_delay -clock my_clk -min 0.0 [get_ports {uart_tx status}]

# ---- pads -----------------------------------------------------------------
set_load 5.0 [all_outputs]                                         ;# PLACEHOLDER: pad + trace + FPGA pin, pF
set_max_fanout 1 [all_inputs]
set_fanout_load 8 [all_outputs]
