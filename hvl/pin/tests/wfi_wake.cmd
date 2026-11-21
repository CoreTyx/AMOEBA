# hvl/pin/tests/wfi_wake.cmd -- see wfi_wake.c.
load_lst $MEM
uart_div 1
uart_fail PIN_WFI_BAD
reset 16
run_until_uart 400000 SLEEP_1
run 10
irq 0 1
run_until_uart 200000 WOKE_3
irq 0 0
run 50
uart_send n
run_until_uart 400000 SLEEP_2
run 700
irq 0 1
run_until_uart 200000 WOKE_3
irq 0 0
run 50
uart_send n
run_until_uart 400000 SLEEP_3
run 4000
irq 0 1
run_until_uart 200000 WOKE_3
irq 0 0
run 50
uart_send n
run_until_uart 400000 SLEEP_4
run 25000
irq 0 1
run_until_uart 200000 WOKE_3
irq 0 0
run 50
uart_send n
run_until_uart 400000 TIMER
run_until_uart 400000 PIN_WFI_DONE
run_until_tohost 400000
expect_tohost 0
finish
