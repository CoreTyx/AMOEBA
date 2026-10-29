# fe_fault_rfpipe.c on the pin bench: fault_inject held high.
load_lst $MEM
uart_div 1
fault_inject 1
reset 16
run_until_uart 50000000 RFPIPE DONE
run_until_tohost 2000000
expect_tohost 0
finish
