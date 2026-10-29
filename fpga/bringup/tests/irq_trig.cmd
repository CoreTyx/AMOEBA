dialect fbu
# hvl/pin/tests/irq.cmd with each irq deassert made by a PL trigger on the
# console text, so it lands cycle-exactly however slowly the PS polls.
load_lst $MEM
uart_div 1
reset 16
run_until_uart 400000 PIN_IRQ_ARMED
irq_clear_on 0 IRQ3
irq 0 1
run_until_uart 200000 IRQ3
run 200
irq_clear_on 1 IRQ6
irq 1 1
run_until_uart 200000 IRQ6
run_until_uart 200000 PIN_IRQ_DONE
run_until_tohost 200000
expect_tohost 0
finish
