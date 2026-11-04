dialect fbu
# CTRL-20: always-on fault tolerance.  An image patched by fi_arm_lst.py arms
# FI_CONTROL before its first instruction, with fault_inject high (STATIC) from
# before release and never dropped.  The test must pass as it does unarmed;
# in simulation the chip's counters must show detections and nothing
# uncorrectable, unresolved or TMR-uncorrectable.
load_lst $MEM
fault_inject 1
reset 16
run_until_tohost 20000000
expect_tohost 0
check_chip_counters
finish
