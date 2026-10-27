# hvl/pin/tests/linux_m0.cmd -- soft-float Linux image to the OpenSBI banner
# (M0: shim, M-mode firmware, console).  5.7M cycles on the RTL: the Linux
# step that fits a gate-level run's time budget.  Full boot: linux.cmd.
load_lst $MEM
uart_div 1
uart_fail Kernel panic
uart_fail Oops
uart_fail Unable to handle kernel
reset 16
run_until_uart  20000000 OpenSBI v1.
finish
