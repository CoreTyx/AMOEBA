dialect fbu
# P1 / CTRL-14: one test-mode session against the frozen chip's scan stub,
# with the core held in reset (the DFT lock reopens on reset).  Every io lane
# in its test direction: io[7:0] in, io[15:8] out, scan_q in between.
scan_session 1024 1
scan_session 1024 2
finish
