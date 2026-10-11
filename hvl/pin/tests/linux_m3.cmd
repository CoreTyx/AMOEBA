# hvl/pin/tests/linux_m3.cmd -- soft-float Linux to "Initmem setup node 0"
# (M3: kernel entry, console handover, MMU on, page tables walked).  83M
# cycles on the RTL: for VCS RTL runs.  Full boot: linux.cmd (416M cycles).
load_lst $MEM
uart_div 1
uart_fail Kernel panic
uart_fail Oops
uart_fail Unable to handle kernel
reset 16
run_until_uart  20000000 OpenSBI v1.
run_until_uart  80000000 Linux version 6.6
run_until_uart  10000000 printk: bootconsole
run_until_uart 120000000 Initmem setup node 0
finish
