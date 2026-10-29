# fe_fault_cal.c on the pin bench: one round per unit with fault_inject low,
# so every round prints CAL d 0 f 0, then quit.
load_lst $MEM
uart_div 1
reset 16
run_until_uart 2000000 CAL READY
uart_send 5
run_until_uart 2000000 CAL GO
uart_send x
run_until_uart 2000000 CAL d 0 f 0
uart_send 4
run_until_uart 2000000 CAL GO
uart_send x
run_until_uart 2000000 CAL d 0 f 0
uart_send q
run_until_uart 2000000 CAL DONE
run_until_tohost 2000000
expect_tohost 0
finish
