dialect fbu
# CTRL-12b: sweep a one-cycle fault_inject pulse over all 512 phases with the
# pipeline-register ECC armed, then the register-file ECC.  Each detects at
# exactly one phase; its distance from the site's phase in fbu_fi_gen's model
# corrects FI_PHASE_OFS.  From the reset value (the core's 4 reset
# synchroniser cycles) both units must find nothing to correct.
load_lst $MEM
uart_div 1
reset 16
run_until_uart 2000000 CAL READY
calibrate_phase 5 4
expect_phase_delta 0
calibrate_phase 4 16
expect_phase_delta 0
expect_phase_ofs 4
uart_send q
run_until_uart 2000000 CAL DONE
run_until_tohost 2000000
expect_tohost 0
finish
