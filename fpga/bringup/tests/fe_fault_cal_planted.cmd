dialect fbu
# Calibration self-test: start at 37 instead of 4.  The pipeline sweep must
# find -33 and correct the offset to 4; the register-file sweep then finds 0.
load_lst $MEM
uart_div 1
reset 16
run_until_uart 2000000 CAL READY
fi_phase_ofs 37
calibrate_phase 5 4
expect_phase_delta -33
expect_phase_ofs 4
calibrate_phase 4 16
expect_phase_delta 0
uart_send q
run_until_uart 2000000 CAL DONE
run_until_tohost 2000000
expect_tohost 0
finish
