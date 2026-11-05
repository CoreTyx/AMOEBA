dialect fbu
# STAT-06 in simulation: clk_out's rising edges over the last whole window
# equal the window in clk cycles.  (The status classes take 2^25-cycle
# half-periods; they are fbu_status_mon's unit test and the board's, fe_status.cmd.)
load_lst $MEM
uart_div 1
reset 16
run_until_uart 2000000 ST READY
run 2200000
expect_clkout
uart_send d
run_until_uart 2000000 ST DONE
run_until_tohost 2000000
expect_tohost 0
finish
