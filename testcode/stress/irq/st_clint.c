// @stress tier=pr seeds=2 build=no_spike duts=legacy,forte timeout=20000000
//
// st_clint -- the CLINT exactly as OpenSBI and Linux use it.
//   - mtime ticks monotonically, ~1 per core clock (TIMEBASE = clock in sim)
//   - MTIP == (mtime >= mtimecmp), level-sensitive, follows every rewrite
//   - the 32-bit hi/lo update sequence (hi = ~0, lo, hi) never raises a
//     spurious interrupt on the way to a future deadline
//   - 64-bit and partial writes of mtimecmp, writes of mtime
//   - MSIP raises/clears mip.MSIP and delivers a machine software interrupt
//   - timer interrupts are delivered once per arming, at or after the deadline
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif

static volatile uint64_t g_mti, g_msi, g_mti_late, g_deadline;
static int irq(st_frame_t *f) {
    if (f->cause == (CAUSE_INTR | IRQ_M_TIMER)) {
        g_mti++;
        if (st_mtime() < g_deadline) g_mti_late++;      /* early = wrong */
        st_timer_off();
        return 1;
    }
    if (f->cause == (CAUSE_INTR | IRQ_M_SOFT)) { g_msi++; CLINT_MSIP = 0; return 1; }
    return 0;
}

int main(void) {
    st_init();
    g_m_irq_hook = irq;

    st_section("mtime monotonic and advancing");
    uint64_t t0 = st_mtime(), prev = t0, back = 0;
    for (int i = 0; i < 500; i++) { uint64_t t = st_mtime(); if (t < prev) back++; prev = t; }
    ST_CHECK_EQ("never goes backwards", back, 0);
    ST_CHECK("advanced", prev > t0 + 500);

    st_section("MTIP follows mtimecmp (level)");
    st_set_mtimecmp(st_mtime() - 1);
    ST_CHECK("past deadline -> MTIP", csr_read(mip) & MIP_MTIP);
    st_set_mtimecmp(st_mtime() + 100000);
    ST_CHECK_EQ("future deadline -> no MTIP", csr_read(mip) & MIP_MTIP, 0);
    uint64_t dl = st_mtime() + 300;
    st_set_mtimecmp(dl);
    while (!(csr_read(mip) & MIP_MTIP)) ;
    ST_CHECK("MTIP rose at/after the deadline", st_mtime() >= dl);
    st_timer_off();
    ST_CHECK_EQ("MTIP drops when mtimecmp moves out", csr_read(mip) & MIP_MTIP, 0);

    st_section("32-bit hi/lo sequence: no spurious interrupt");
    csr_set(mie, MIP_MTIP);
    csr_set(mstatus, MSTATUS_MIE);
    uint64_t spurious = 0;
    for (int i = 0; i < 100 * ST_SCALE; i++) {
        uint64_t before = g_mti;
        uint64_t target = st_mtime() + 50000 + st_rand_range(1UL << 40);
        g_deadline = target;
        CLINT_MTIMECMP_HI = 0xffffffffu;
        CLINT_MTIMECMP_LO = (uint32_t)target;
        CLINT_MTIMECMP_HI = (uint32_t)(target >> 32);
        if (g_mti != before) spurious++;
        st_timer_off();
    }
    ST_CHECK_EQ("no interrupt during the update sequence", spurious, 0);

    st_section("one interrupt per arming, never early");
    uint64_t before = g_mti;
    for (int i = 0; i < 60 * ST_SCALE; i++) {
        uint64_t n = g_mti;
        g_deadline = st_mtime() + 20 + st_rand_range(600);
        st_set_mtimecmp(g_deadline);
        while (g_mti == n) ;
    }
    ST_CHECK_EQ("count", g_mti - before, 60 * ST_SCALE);
    ST_CHECK_EQ("none delivered before its deadline", g_mti_late, 0);
    csr_clear(mstatus, MSTATUS_MIE);
    csr_clear(mie, MIP_MTIP);

    st_section("partial and 64-bit mtimecmp writes");
    CLINT_MTIMECMP = 0x0000123456789abcUL;
    ST_CHECK_EQ("64-bit write", CLINT_MTIMECMP, 0x0000123456789abcUL);
    CLINT_MTIMECMP_LO = 0xdeadbeefu;
    ST_CHECK_EQ("low-word write keeps high", CLINT_MTIMECMP, 0x00001234deadbeefUL);
    st_timer_off();

    st_section("mtime write");
    uint64_t newt = st_mtime() + (1UL << 36);
    CLINT_MTIME = newt;
    uint64_t rt = st_mtime();
    ST_CHECK("mtime took the written value", rt >= newt && rt < newt + 2000);
    st_set_mtimecmp(newt - 10);
    ST_CHECK("deadline before new mtime -> MTIP", csr_read(mip) & MIP_MTIP);
    st_timer_off();

    st_section("MSIP");
    csr_set(mie, MIP_MSIP);
    for (int i = 0; i < 20; i++) {
        uint64_t n = g_msi;
        CLINT_MSIP = 1;
        st_fence_io();
        ST_CHECK("mip.MSIP set", csr_read(mip) & MIP_MSIP);
        csr_set(mstatus, MSTATUS_MIE);
        __asm__ volatile ("nop\nnop" ::: "memory");
        csr_clear(mstatus, MSTATUS_MIE);
        ST_CHECK_EQ("one MSI", g_msi, n + 1);
        ST_CHECK_EQ("cleared by the handler", csr_read(mip) & MIP_MSIP, 0);
    }
    csr_clear(mie, MIP_MSIP);
    return st_result();
}
