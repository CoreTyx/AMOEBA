// @stress tier=pr build=no_spike expect=fail timeout=200000 pin=no
// Harness self-test for strict exit: the explicit halt encoding reached
// without a tohost exit must FAIL, not end the run cleanly.
#include "../lib/stress.h"
int main(void) {
    st_init();
    __asm__ volatile ("slti x0, x0, -256\n1: j 1b");
    return 0;
}
