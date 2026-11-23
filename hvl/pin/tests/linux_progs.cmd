# hvl/pin/tests/linux_progs.cmd -- Linux to userspace and every /bin program
# (testcode/linux/README.md, M6), through the pins.  linux.cmd's milestones,
# then AMOEBA_LINUX_PROGS_OK; a program's FAIL line or a kernel/SBI panic ends
# the run.  Image: make -C testcode/linux (build/boot.lst).  The programs cost
# about 50M cycles each in Verilator (20 programs: 1.07G); the kernel boot
# runs past linux.cmd's 600M on the FPGA with real DDR timing.
load_lst $MEM
uart_div 1
uart_fail Kernel panic
uart_fail Oops
uart_fail Unable to handle kernel
uart_fail SBI panic
uart_fail AMOEBA_PROG_FAIL
reset 16
run_until_uart  20000000 OpenSBI v1.
run_until_uart  80000000 Linux version 6.6
run_until_uart 150000000 printk: bootconsole
run_until_uart 300000000 Initmem setup node 0
run_until_uart 1500000000 Freeing unused kernel image
run_until_uart 300000000 AMOEBA_LINUX_BOOT_OK
run_until_uart 2500000000 AMOEBA_LINUX_PROGS_OK
finish
