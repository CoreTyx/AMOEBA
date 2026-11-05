# fe_status.c on the pin bench: each mode acknowledged and left, then done.
# The gateware must reproduce the console.
load_lst $MEM
uart_div 1
reset 16
run_until_uart 2000000 ST READY
uart_send a
run_until_uart 2000000 ST ACTIVE
run 200000
uart_send x
uart_send q
run_until_uart 2000000 ST QUIET
run 200000
uart_send x
uart_send d
run_until_uart 2000000 ST DONE
run_until_tohost 2000000
expect_tohost 0
finish
