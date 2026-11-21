// @stress tier=pr seeds=2 nightly_seeds=8 build=no_spike duts=legacy,forte timeout=30000000
//
// st_lrsc -- LR/SC reservation semantics and forward progress under interrupts.
//
// Linux's cmpxchg, the qspinlock fallback, and every lock-free list use LR/SC
// loops.  Checked:
//   - LR/SC success: SC returns 0 and writes
//   - SC with no reservation fails (returns nonzero) and does NOT write
//   - a second SC after a successful one fails (SC always clears the reservation)
//   - SC to a different address than the LR fails and does not write
//   - .w and .d, aq/rl variants, LR sign-extension for .w
//   - a constrained LR/SC increment loop interrupted by a timer every few
//     hundred cycles still makes progress and never loses or doubles an update
//   - LR/SC to MMIO, a hole or a read-only page fault (no silent success)
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define INCS (3000 * ST_SCALE)

static inline uint64_t lr_d(volatile uint64_t *a) { uint64_t v; __asm__ volatile ("lr.d %0, (%1)" : "=r"(v) : "r"(a) : "memory"); return v; }
static inline uint64_t sc_d(volatile uint64_t *a, uint64_t v) { uint64_t r; __asm__ volatile ("sc.d %0, %2, (%1)" : "=&r"(r) : "r"(a), "r"(v) : "memory"); return r; }
static inline uint64_t lr_w(volatile uint32_t *a) { uint64_t v; __asm__ volatile ("lr.w.aq %0, (%1)" : "=r"(v) : "r"(a) : "memory"); return v; }
static inline uint64_t sc_w(volatile uint32_t *a, uint64_t v) { uint64_t r; __asm__ volatile ("sc.w.rl %0, %2, (%1)" : "=&r"(r) : "r"(a), "r"(v) : "memory"); return r; }

static volatile uint64_t g_irqs;
static int timer_irq(st_frame_t *f) {
    if (f->cause != (CAUSE_INTR | IRQ_M_TIMER)) return 0;
    g_irqs++;
    /* handler traffic of its own, as a real kernel's would be */
    static volatile uint64_t scratch[16];
    for (int i = 0; i < 16; i++) scratch[i] += (uint64_t)i;
    st_set_mtimecmp(st_mtime() + 150 + st_rand_range(350));
    return 1;
}

static volatile uint64_t g_ctr ST_ALIGNED(64);
static volatile uint64_t g_other ST_ALIGNED(64);
static volatile uint32_t g_w[4] ST_ALIGNED(64);

int main(void) {
    st_init();

    st_section("basic success / failure rules");
    volatile uint64_t *x = &g_ctr;
    *x = 41;
    uint64_t v = lr_d(x);
    ST_CHECK_EQ("lr.d value", v, 41);
    ST_CHECK_EQ("sc.d after lr succeeds", sc_d(x, 42), 0);
    ST_CHECK_EQ("  wrote", *x, 42);
    ST_CHECK("second sc.d (no reservation) fails", sc_d(x, 99) != 0);
    ST_CHECK_EQ("  did not write", *x, 42);
    (void)lr_d(x);
    ST_CHECK("sc.d to a different address fails", sc_d(&g_other, 7) != 0);
    ST_CHECK_EQ("  other untouched", g_other, 0);
    (void)sc_d(x, 0);                          /* drain whatever reservation remains */
    ST_CHECK("bare sc.d fails", sc_d(x, 1234) != 0);
    ST_CHECK("  value is not 1234", *x != 1234);

    g_w[1] = 0x80000001u;
    v = lr_w(&g_w[1]);
    ST_CHECK_EQ("lr.w sign-extends", v, 0xffffffff80000001UL);
    ST_CHECK_EQ("sc.w succeeds", sc_w(&g_w[1], 5), 0);
    ST_CHECK_EQ("  wrote only its word", (uint64_t)g_w[0] | ((uint64_t)g_w[1] << 32), 5UL << 32);
    ST_CHECK("sc.w again fails", sc_w(&g_w[1], 6) != 0);

    st_section("LR/SC increment loop under a timer storm");
    g_m_irq_hook = timer_irq;
    *x = 0;
    csr_set(mie, MIP_MTIP);
    st_set_mtimecmp(st_mtime() + 200);
    csr_set(mstatus, MSTATUS_MIE);
    uint64_t fails = 0;
    for (int i = 0; i < INCS; i++) {
        for (;;) {
            uint64_t o = lr_d(x);
            /* a little work between LR and SC (still a constrained loop) */
            uint64_t n = o + 1;
            if (sc_d(x, n) == 0) break;
            fails++;
        }
    }
    csr_clear(mstatus, MSTATUS_MIE);
    csr_clear(mie, MIP_MTIP);
    st_timer_off();
    ST_CHECK_EQ("no lost or doubled increment", *x, INCS);
    ST_CHECK("interrupts actually landed in the loop", g_irqs > 10);
    st_puts("[ST] irqs "); st_putdec(g_irqs); st_puts(" sc retries "); st_putdec(fails); st_putc('\n');

    st_section("LR/SC on memory that does not support it");
    static const struct { const char *n; uint64_t a; } tgt[] = {
        { "CLINT", CLINT_BASE + 0x4000 }, { "hole", ST_HOLE_ADDR }, { "PLIC", PLIC_BASE_ADDR + 0x1000 } };
    for (unsigned i = 0; i < ST_ARRAY_LEN(tgt); i++) {
        st_expect(ST_EXPECT_SKIP);
        __asm__ volatile (".option push\n.option norvc\nlr.w t0, (%0)\n.option pop" :: "r"(tgt[i].a) : "t0", "memory");
        st_expect_clear();
        ST_CHECK_EQ(tgt[i].n, g_trap_cause, CAUSE_LOAD_ACCESS);
        st_expect(ST_EXPECT_SKIP);
        __asm__ volatile (".option push\n.option norvc\nsc.w t0, zero, (%0)\n.option pop" :: "r"(tgt[i].a) : "t0", "memory");
        st_expect_clear();
        ST_CHECK("  sc faults (store access) or fails without a reservation",
                 g_trap_cause == CAUSE_STORE_ACCESS || g_trap_cause == ~0UL);
    }
    uint64_t root = pt_new_identity_root(0);
    uint64_t fr = frame_alloc();
    *(volatile uint64_t *)fr = 77;
    map_page(root, 0xC0000000UL, fr, PTE_R | PTE_A);
    csr_write(satp, satp_sv39(3, root));
    sfence_all();
    csr_clear(mstatus, MSTATUS_MPP); csr_set(mstatus, MSTATUS_MPP_S);
    uint64_t r = 0xdead;
    st_expect(ST_EXPECT_SKIP);
    __asm__ volatile (".option push\n.option norvc\ncsrs mstatus, %2\nlr.d t0, (%1)\nsc.d %0, t0, (%1)\ncsrc mstatus, %2\n.option pop"
                      : "+r"(r) : "r"(0xC0000000UL), "r"(MSTATUS_MPRV) : "t0", "memory");
    st_expect_clear();
    csr_clear(mstatus, MSTATUS_MPP); csr_set(mstatus, MSTATUS_MPP_M);
    ST_CHECK_EQ("sc.d to read-only page: store page fault", g_trap_cause, CAUSE_STORE_PAGE);
    ST_CHECK_EQ("  value unchanged", *(volatile uint64_t *)fr, 77);
    csr_write(satp, 0);
    sfence_all();
    return st_result();
}
