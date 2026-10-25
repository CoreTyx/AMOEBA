# Functional constraints for the separate DFT experiment. Based on ../constraints.sdc.
# Board/pad budgets remain placeholders, just as in the original flow.
# Override with DFT_SDC for the actual implementation constraints/library units.
set period_ns [expr {[getenv ECE411_CLOCK_PERIOD_PS] / 1000.0}]
create_clock -period $period_ns -name my_clk [get_ports core_clk]
create_generated_clock -name link_fwd -source [get_ports core_clk] -divide_by 1 [get_ports clk_out]
set_clock_uncertainty 0.15 [get_clocks my_clk]
set_fix_hold [get_clocks my_clk]
set_false_path -from [get_ports rst_n]
set_false_path -from [get_ports {irq[*] uart_rx fault_inject test_mode scan_en}]
set link_in [get_ports {io[*] ready rvalid}]
set link_out [get_ports {io[*] dir req wr}]
set_input_delay -clock my_clk -max 4.0 $link_in
set_input_delay -clock my_clk -min 1.0 $link_in
set_output_delay -clock my_clk -max 3.0 $link_out
set_output_delay -clock my_clk -min -0.5 $link_out
set_output_delay -clock my_clk -max 3.0 [get_ports {uart_tx status}]
set_output_delay -clock my_clk -min 0.0 [get_ports {uart_tx status}]
set_load 5.0 [all_outputs]
set_max_fanout 1 [all_inputs]
set_fanout_load 8 [all_outputs]
