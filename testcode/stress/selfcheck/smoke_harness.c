// @stress tier=pr build=no_spike timeout=2000000
#include "../lib/stress.h"
static uint64_t u_fn(uint64_t a) { return a * 3 + 1; }
static uint64_t u_ecall(uint64_t a) { (void)a; __asm__ volatile ("li a7, 0x1234\n ecall" ::: "a7", "a0", "memory"); return 7; }
int main(void) {
    st_init();
    st_section("run_in_mode");
    ST_CHECK_EQ("U ret", st_run(PRV_U, u_fn, 5), 16);
    ST_CHECK_EQ("S ret", st_run(PRV_S, u_fn, 6), 19);
    st_section("abort");
    uint64_t r = st_run_expect_abort(PRV_U, u_ecall, 0, (uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    ST_CHECK_EQ("aborted", r, ST_TRAP_ABORTED);
    ST_CHECK_EQ("cause", g_trap_cause, CAUSE_ECALL_U);
    st_section("probe");
    uint64_t v;
    ST_CHECK_EQ("hole ld traps", m_try_ld(ST_HOLE_ADDR, &v), 1);
    ST_CHECK_EQ("hole cause", g_trap_cause, CAUSE_LOAD_ACCESS);
    ST_CHECK_EQ("hole tval", g_trap_tval, ST_HOLE_ADDR);
    return st_result();
}
