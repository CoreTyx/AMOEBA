dialect fbu
# CTRL-22: with a whole FI_CONTROL unit armed, a PHASE pattern lets through
# one site's events only; that site alone must be detected, on its unit's
# counter, with every kernel result still right.  The ALU's six channels and
# the CMP's two (both replicas each) share one counter per unit, so each must
# be detected by itself; the cache bit arms both caches, and the I$ and D$
# phases must move only their own counter.  A phase with no site moves nothing.
load_lst $MEM
uart_div 1
reset 16
run_until_uart 2000000 SITE READY
# ALU replica 0: result, arithmetic, shift channels; then replica 1
target_site 0 1fe 256 8
target_site 0 1ee 256 8
target_site 0 1de 256 8
target_site 0 1be 256 8
target_site 0 1ae 256 8
target_site 0 19e 256 8
target_site 0 1f0 256 none
# CMP replica 0, replica 1
target_site 1 1ce 256 10
target_site 1 18e 256 10
target_site 2 17e 256 12
target_site 3 15e 4096 14
# I$, D$, then neither
target_site 6 13e 256 4
target_site 6 11e 256 6
target_site 6 12e 256 none
uart_send q
run_until_uart 2000000 SITE DONE
run_until_tohost 2000000
expect_tohost 0
finish
