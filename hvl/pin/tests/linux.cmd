# hvl/pin/tests/linux.cmd -- soft-float Linux to userspace, through the pins.
# Image: make -C testcode/linux (build/boot.lst).  Milestones as in
# testcode/linux/README.md; each run_until_uart logs the cycle it was reached,
# which is what sets how far a gate-level run can get in its time budget.
# Timeouts are per milestone, in core cycles.  Measured on the RTL (pin bench,
# cumulative): M0 5.7M, M1 27.1M, M2 27.6M, M3 83.1M, M4 413.3M, M5 416.5M.
# VCS cannot do this in a working day; linux_m0.cmd and linux_m3.cmd stop early.
load_lst $MEM
uart_div 1
uart_fail Kernel panic
uart_fail Oops
uart_fail Unable to handle kernel
reset 16
run_until_uart  20000000 OpenSBI v1.
run_until_uart  80000000 Linux version 6.6
run_until_uart 150000000 printk: bootconsole
run_until_uart 300000000 Initmem setup node 0
run_until_uart 600000000 Freeing unused kernel image
run_until_uart 300000000 AMOEBA_LINUX_BOOT_OK
finish
