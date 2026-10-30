# fe_fault_site.c on the pin bench: an ALU and a cache round with
# fault_inject low, so nothing moves and no result is wrong, then quit.
load_lst $MEM
uart_div 1
reset 16
run_until_uart 2000000 SITE READY
uart_send 0
run_until_uart 2000000 SITE GO
uart_send x
run_until_uart 2000000 SITE d 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 w 0
uart_send 6
run_until_uart 4000000 SITE GO
uart_send x
run_until_uart 4000000 SITE d 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 w 0
uart_send q
run_until_uart 2000000 SITE DONE
run_until_tohost 2000000
expect_tohost 0
finish
