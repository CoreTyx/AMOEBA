// @stress tier=pr build=no_spike expect=fail timeout=500000 pin=no
// Harness self-test: a failing ST_CHECK_EQ must turn into a FAIL exit code.
#include "../lib/stress.h"
int main(void) {
    st_init();
    st_section("must fail");
    ST_CHECK_EQ("1 == 2", ST_OPAQUE(1), 2);
    return st_result();
}
