# hvl/pin/fuzz/fuzz.cmd -- the bench side of one fuzz case.
# A generated program ends exactly like every other test (tohost, then
# fence.i, so the result reaches the pins) after storing its architectural
# signature at SIG_BASE.  The bench dumps that region; bin/pin_fuzz.py compares
# it with the reference model's.  SIG_BASE/SIG_BYTES are fixed by the
# generator contract in bin/pin_fuzz.py.
load_lst $MEM
reset 16
run_until_tohost 10000000
expect_tohost 0
# The tohost line is only one of the lines fence.i writes back, in set order;
# let the rest of the flush land before reading the signature.  8 KiB of D$ is
# 512 lines at 10 link cycles each, so 8000 cycles is a whole dirty cache.
run 8000
dump_mem 80f00000 4096 $RUN/signature.hex
finish
