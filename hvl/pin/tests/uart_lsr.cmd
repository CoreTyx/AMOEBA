# hvl/pin/tests/uart_lsr.cmd -- one framing-error byte; LSR[7] and LSR[3] must be set.
# Run with: hvl/pin/pin.sh run hvl/pin/tests/uart_lsr.c hvl/pin/tests/uart_lsr.cmd
load_lst $MEM
uart_div 1
reset 16
run_until_uart 400000 PIN_LSR_READY
uart_send_ferr 55
run_until_uart 400000 PIN_LSR_DONE
run_until_tohost 400000
expect_tohost 0
finish
