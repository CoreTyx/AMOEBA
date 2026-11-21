# Level-sensitive IRQ service across holds; use irq.c and compare with irq.cmd.
load_lst $MEM
uart_div 1
reset 16
run_until_uart 400000 PIN_IRQ_ARMED
dft_hold 1
irq 0 1
dft_hold 1000
run_until_uart 200000 IRQ3
irq 0 0
dft_hold 17
run 200
irq 1 1
dft_hold 5000
run_until_uart 200000 IRQ6
irq 1 0
run_until_uart 200000 PIN_IRQ_DONE
run_until_tohost 200000
expect_tohost 0
finish
