// @stress tier=pr build=no_spike expect=fail timeout=500000 pin=no
// Harness self-test: a program that returns nonzero must be reported FAIL.
#include "../lib/stress.h"
int main(void) { st_init(); return 1; }
