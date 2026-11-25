// @stress tier=pr build=no_spike expect=fail timeout=500000 pin=no
// Harness self-test: an unexpected trap must end the run as a FAIL.
#include "../lib/stress.h"
int main(void) {
    st_init();
    __asm__ volatile (".word 0x00000000");   /* illegal instruction */
    return 0;
}
