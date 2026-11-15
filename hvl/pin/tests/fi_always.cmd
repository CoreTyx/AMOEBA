# Always-on fault injection: an image patched by bin/fi_arm_lst.py arms
# FI_CONTROL before its first instruction, with fault_inject high from before
# release and never dropped.  The test must still pass (hvl/pin/fi_always.sh).
load_lst $MEM
fault_inject 1
reset 16
run_until_tohost 20000000
expect_tohost 0
finish
