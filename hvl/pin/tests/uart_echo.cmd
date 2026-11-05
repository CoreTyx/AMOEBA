# hvl/pin/tests/uart_echo.cmd -- both UART directions, through the command script.
# Run with: hvl/pin/pin.sh run hvl/pin/tests/uart_echo.c hvl/pin/tests/uart_echo.cmd
load_lst $MEM
uart_div 1
uart_fail PANIC
reset 16
run_until_uart 400000 PIN_UART_READY
uart_send ping\n.
run_until_uart 400000 echo:ping
run_until_uart 400000 PIN_UART_DONE
run_until_tohost 400000
expect_tohost 0
finish
