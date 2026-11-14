# hvl/pin/tests/dft_hold.cmd -- DFT hold sessions in the middle of a program.
# Run with:
#   hvl/pin/pin.sh run testcode/baremetal/sorting_algo.c hvl/pin/tests/dft_hold.cmd
#   hvl/pin/pin.sh run testcode/baremetal/sorting_algo.c          # reference
#   hvl/pin/pin.sh compare --no-cycles <reference run> <this run>
# Each dft_hold pauses the link, enters a hold (scan_en armed before test_mode),
# idles frozen, and leaves it; under DUT=rtl it checks that the fetch PC, the
# register file and MTIME did not move.  The program must still exit 0 with the
# same link traffic as an uninterrupted run.  Holds land early (cold caches,
# misses), mid-run and late; one is long enough to cover many MTIME ticks.
load_lst $MEM
reset 16
run 1500
dft_hold 200
run 3777
dft_hold 1000
run 9001
dft_hold 50
run 20011
dft_hold 5000
run_until_tohost 4000000
expect_tohost 0
finish
