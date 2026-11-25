# hvl/pin/tests/dft_lock.cmd -- see dft_lock.c.
# Run with: hvl/pin/pin.sh run hvl/pin/tests/dft_lock.c hvl/pin/tests/dft_lock.cmd
# Unlocked, a DFT hold must work; once software clears the lock, the same pins
# (and a scan_en toggling as for a shift) must be ignored while the program
# keeps running and printing.
load_lst $MEM
uart_div 1
uart_fail DFT_LOCK_BAD
uart_fail DFT_BAD_RESET
reset 16
run_until_uart 400000 DFT_UNLOCKED
dft_hold 200
uart_send l
run_until_uart 400000 DFT_LOCKED
dft_locked 20000
run_until_uart 2000000 DFT_LOCK_DONE
run_until_tohost 400000
expect_tohost 0
finish
