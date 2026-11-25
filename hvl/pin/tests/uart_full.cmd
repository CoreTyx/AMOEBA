# hvl/pin/tests/uart_full.cmd -- see uart_full.c.
# Run with: hvl/pin/pin.sh run hvl/pin/tests/uart_full.c hvl/pin/tests/uart_full.cmd
load_lst $MEM
uart_div 1
uart_fail PIN_UART_FULL_BAD
reset 16
run_until_uart 400000 PIN_UART_READY
uart_send hello pins\n
run_until_uart 800000 echo:HELLO PINS
# wait for the "\n" too: the agent decodes a character at mid-stop-bit, and
# switching its rate while the newline is still on the wire at div 1 is a
# framing error of the BENCH's making (the chip waits TEMT before it switches)
run_until_uart 400000 DIV2\n
uart_div 2
run_until_uart 800000 AT_DIV2
uart_send second rate\n
run_until_uart 1600000 echo:SECOND RATE
run_until_uart 800000 IRQ_RX
uart_send hello!
run_until_uart 800000 FLOOD
uart_send OVERRUN-BURST
run_until_uart 3000000 PIN_UART_FULL_DONE
run_until_tohost 800000
expect_tohost 0
finish
