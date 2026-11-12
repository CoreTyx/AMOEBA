dialect fbu
# P1 / CTRL-14: one test-mode session against the frozen chip's scan stub,
# with the core held in reset (the DFT lock reopens on reset).  Every io lane
# in test mode: scan in on io_in, scan out on io_out, scan_q in between.
scan_session 1024 1
scan_session 1024 2
finish
