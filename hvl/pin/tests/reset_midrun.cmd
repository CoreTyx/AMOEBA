# hvl/pin/tests/reset_midrun.cmd -- rst_n pulsed while a memory-stress program
# is running (D$ write-backs and link bursts in flight), twice, then the program
# must run to a clean exit.  A chip that comes out of a mid-transaction reset
# with a wedged link FSM, a stale CDC FIFO pointer or a half-written cache line
# would hang or fail here; on silicon that is "the board needs a power cycle".
# Run with: hvl/pin/pin.sh run testcode/stress/mem/st_dcache_conflict.c hvl/pin/tests/reset_midrun.cmd
load_lst $MEM
uart_div 1
reset 16
run 61733
reset 16
run 140011
reset 37
run_until_tohost 40000000
expect_tohost 0
finish
