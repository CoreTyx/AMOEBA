dialect fbu
# fe_fault_burst.c with fault_inject held low: every unit is armed in
# FI_CONTROL in turn, and no fault may get through.
load_lst $MEM
uart_div 1
fault_inject 0
reset 16
run_until_uart 50000000 FI ALL DONE
run_until_tohost 2000000
expect_tohost 0
expect_fi_events 0 0
check_fi_rounds 0
finish
