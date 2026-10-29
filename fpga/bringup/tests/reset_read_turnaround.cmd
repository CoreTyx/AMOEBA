dialect fbu
# Reset the chip the first time the link enters read_turnaround; it must reboot and
# finish (CTRL-01).  For header, read_turnaround and read_data the boot fetch
# itself is cut, so the rebooted trace equals the bench's.
load_lst $MEM
reset_at state read_turnaround 16
reset 16
run_until_tohost 1000000
expect_tohost 0
finish
