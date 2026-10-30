dialect fbu
# CTRL-21, fe_cache_ded.c: one fault_inject pulse per trial at a cache's
# phase (calibrated: FI_PHASE_OFS resets to the chip's offset), with
# FI_CONTROL bit 7 (uncorrectable) armed by the program.  T1 and T2 at the
# D$ phase, T3 at the I$ phase; T3's code runs twice, hence two releases.
load_lst $MEM
uart_div 1
reset 16
run_until_uart 2000000 DED READY
fault_trial 11e x DED GO
run_until_uart 4000000 DED T1
fault_trial 11e x DED GO
run_until_uart 4000000 DED T2
fault_trial 13e xx DED GO
run_until_uart 4000000 DED DONE
run_until_tohost 2000000
expect_tohost 0
finish
