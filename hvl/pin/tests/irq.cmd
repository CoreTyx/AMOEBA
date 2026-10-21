# hvl/pin/tests/irq.cmd -- the irq[1:0] pins, one at a time, level-sensitive.
# Run with: hvl/pin/pin.sh run hvl/pin/tests/irq.c hvl/pin/tests/irq.cmd
load_lst $MEM
uart_div 1
reset 16
run_until_uart 400000 PIN_IRQ_ARMED
irq 0 1
run_until_uart 200000 IRQ3
irq 0 0
run 200
irq 1 1
run_until_uart 200000 IRQ6
irq 1 0
run_until_uart 200000 PIN_IRQ_DONE
run_until_tohost 200000
expect_tohost 0
finish
