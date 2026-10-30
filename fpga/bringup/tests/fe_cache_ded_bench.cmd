# fe_cache_ded.c on the pin bench with fault_inject low: the handshake only.
# No fault reaches the caches, so T1 and T2 see no trap and FAIL; T3, whose
# fault is invisible anyway, passes: exit code 2.
load_lst $MEM
uart_div 1
reset 16
run_until_uart 2000000 DED READY
uart_send g
run_until_uart 2000000 DED GO
uart_send x
run_until_uart 4000000 DED T1
uart_send g
run_until_uart 2000000 DED GO
uart_send x
run_until_uart 4000000 DED T2
uart_send g
run_until_uart 2000000 DED GO
uart_send xx
run_until_uart 4000000 DED DONE
run_until_tohost 2000000
expect_tohost 2
finish
