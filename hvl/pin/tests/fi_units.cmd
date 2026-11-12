# fi_units.c (hvl/pin/fi_always.sh): fault_inject held high, so each armed
# unit's sites inject once every 512 cycles while it is armed.
load_lst $MEM
uart_div 1
fault_inject 1
reset 16
run_until_uart 100000000 FI ALL DONE
run_until_tohost 2000000
expect_tohost 0
finish
