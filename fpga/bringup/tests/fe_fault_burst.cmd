dialect fbu
# CTRL-10 on the board, fe_fault_burst.c: each round arms one FI_CONTROL unit
# and prints "FI GO"; a PL trigger on that text runs a 512-period BURST on
# fault_inject (262 144 cycles, inside the shortest armed kernel, and over
# before the next round's "FI GO").  Every round therefore sees exactly 512
# periods of site events, which bound what its detect counter may count.
load_lst $MEM
uart_div 1
fault_on_match burst 512 FI GO
reset 16
run_until_uart 50000000 FI ALL DONE
run_until_tohost 2000000
expect_tohost 0
expect_fi_events 7 512
check_fi_rounds 512
finish
