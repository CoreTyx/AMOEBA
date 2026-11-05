dialect fbu
# STAT-01, STAT-02, STAT-06 on the board.  The program holds the link active
# (streaming through 64 KiB), then quiet (a cached spin): each class must be
# reported from two equal half-periods of exactly 2^25 and 2^27 link cycles,
# and clk_out must give one edge per cycle.  At 25 MHz active takes ~4 s and
# quiet ~16 s.
load_lst $MEM
uart_div 1
reset 16
run_until_uart 2000000 ST READY
uart_send a
run_until_uart 2000000 ST ACTIVE
status_clear
wait_status active 150000000
uart_send x
uart_send q
run_until_uart 2000000 ST QUIET
status_clear
wait_status quiet 600000000
uart_send x
expect_clkout
uart_send d
run_until_uart 2000000 ST DONE
run_until_tohost 2000000
expect_tohost 0
finish
