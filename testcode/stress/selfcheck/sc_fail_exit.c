// @stress tier=pr build=no_spike expect=fail timeout=500000 pin=no fail_sig=tohost exit(1) -- test FAILED
// Harness self-test: a program that returns nonzero must be reported FAIL.
#include "../lib/stress.h"
int main(void) { st_init(); return 1; }
