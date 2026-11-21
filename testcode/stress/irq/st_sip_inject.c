// @stress tier=pr seeds=2 build=no_spike duts=legacy,forte timeout=40000000
//
// st_sip_inject -- the supervisor timer path every Linux tick takes.
//
// Sstc is absent, so Linux programs its timer through OpenSBI's SBI set_timer:
// an ecall to M writes mtimecmp and clears mip.STIP; when MTIP fires M disarms
// it and sets mip.STIP; S takes a supervisor timer interrupt (mideleg[5]) and
// calls set_timer again from inside its handler.  This test runs that exact
// loop for many ticks while S schedules a U computation that the ticks keep
// preempting, plus supervisor software interrupts raised by S itself and by M.
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define TICKS (40 * ST_SCALE)

static volatile uint64_t g_ticks, g_ssi, g_tick_from_u, g_last_tick_time, g_nonmono;
static uint8_t g_ustack[8192] ST_ALIGNED(16);

static int s_irq(st_frame_t *f) {
    if (f->cause == (CAUSE_INTR | IRQ_S_TIMER)) {
        g_ticks++;
        if (!(f->status & MSTATUS_SPP)) g_tick_from_u++;
        uint64_t now = st_mtime();
        if (now < g_last_tick_time) g_nonmono++;
        g_last_tick_time = now;
        /* re-arm from inside the handler: set_timer clears STIP */
        /* One tick costs ~3.3k cycles here (S trap, SBI ecall to M, M timer
         * trap forwarding STIP).  Re-arming sooner than that keeps STIP pending
         * at every sret: measured, S then took tick after tick back to back
         * and never returned to the kernel loop (0 ticks from U, 0 SSIs). */
        if (g_ticks < TICKS) st_ecall(ST_ECALL_SET_TIMER, now + 5000 + st_rand_range(5000));
        else st_ecall(ST_ECALL_SET_TIMER, ~0UL);
        return 1;
    }
    if (f->cause == (CAUSE_INTR | IRQ_S_SOFT)) { g_ssi++; csr_clear(sip, MIP_SSIP); return 1; }
    return 0;
}

static uint64_t u_compute(uint64_t n) {
    uint64_t a = 1;
    for (uint64_t i = 0; i < n; i++) a = a * 6364136223846793005ULL + 1442695040888963407ULL;
    return a;
}

static uint64_t s_kernel(uint64_t arg) {
    (void)arg;
    st_s_init();
    g_s_irq_hook = s_irq;
    csr_set(sie, MIP_STIP | MIP_SSIP);
    csr_set(sstatus, MSTATUS_SIE);
    /* the reference value first: computed after arming the timer, all the
     * ticks would land in this S loop and the U program would never run */
    uint64_t want = 1;
    for (uint64_t i = 0; i < 4000; i++) want = want * 6364136223846793005ULL + 1442695040888963407ULL;
    st_ecall(ST_ECALL_SET_TIMER, st_mtime() + 500);
    uint64_t bad = 0;
    while (g_ticks < TICKS) {
        if (st_s_run_user(u_compute, 4000, (uint64_t)(g_ustack + sizeof g_ustack)) != want) bad++;
        csr_set(sstatus, MSTATUS_SIE);                /* st_s_run_user returns with SIE = 0 */
        if ((g_ticks & 3) == 0) csr_set(sip, MIP_SSIP);           /* S raises its own SSI */
        else st_ecall(ST_ECALL_SET_SSIP, 0);                     /* M raises it for S    */
    }
    csr_clear(sstatus, MSTATUS_SIE);
    return bad;
}

int main(void) {
    st_init();
    csr_write(mideleg, MIP_SSIP | MIP_STIP | MIP_SEIP);
    csr_write(medeleg, 1UL << CAUSE_ECALL_U);
    g_m_irq_hook = st_sbi_timer_hook;
    st_section("S timer ticks via SBI set_timer + STIP injection");
    uint64_t bad = st_run(PRV_S, s_kernel, 0);
    ST_CHECK_EQ("U computation unaffected by preemption", bad, 0);
    ST_CHECK_EQ("all ticks delivered", g_ticks, TICKS);
    ST_CHECK("some ticks preempted U", g_tick_from_u > 0);
    ST_CHECK_EQ("tick times monotonic", g_nonmono, 0);
    ST_CHECK("supervisor software interrupts delivered", g_ssi > 0);
    ST_CHECK_EQ("STIP clear at the end", csr_read(mip) & MIP_STIP, 0);
    st_puts("[ST] ticks "); st_putdec(g_ticks); st_puts(" from U "); st_putdec(g_tick_from_u);
    st_puts(" ssi "); st_putdec(g_ssi); st_putc('\n');
    csr_write(mideleg, 0);
    csr_write(medeleg, 0);
    st_timer_off();
    return st_result();
}
