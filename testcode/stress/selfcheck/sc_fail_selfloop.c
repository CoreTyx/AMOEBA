// @stress tier=pr build=no_spike expect=fail timeout=200000 pin=no fail_sig=TB Error: Timed out
// Harness self-test for strict exit: parking in `j .` without a tohost exit
// used to be treated as a halt and PASS.  It must now run into the timeout.
#include "../lib/stress.h"
int main(void) {
    st_init();
    __asm__ volatile ("1: j 1b");
    return 0;
}
