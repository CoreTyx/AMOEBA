// @stress tier=pr seeds=2 build=no_spike duts=legacy,forte timeout=20000000
//
// st_wfi -- WFI wake-up semantics under randomized timer deadlines.
//
// Linux's idle loop is `wfi` with interrupts masked, then unmask: a WFI that
// misses a wake-up (deadline already passed, interrupt arriving in the same
// cycle WFI retires, MSIP instead of MTIP) is a hang that only shows up on
// silicon as a frozen board.  Every case below is repeated with random
// deadlines from "already expired" to a few thousand cycles.
//   1. MIE = 0: WFI must return once MTIP is pending, without taking a trap
//   2. MIE = 1: the interrupt is taken with mepc = the instruction after WFI
//   3. MSIP (software interrupt) wakes WFI the same way
//   4. WFI in S (TW = 0): an M interrupt wakes it and is taken in M
#include "../lib/stress.h"

#define ROUNDS 40

static volatile uint64_t g_timer_irqs, g_soft_irqs, g_irq_epc;
/* The handler never leaves the timer disarmed: it pushes the deadline far out
 * as a backstop.  If an interrupt is taken just BEFORE a wfi (deadline already
 * passed when MIE/S-mode enabled it), that wfi may legally sleep until the
 * next interrupt; the backstop guarantees there is one, so a test-side race can
 * never look like a hardware hang -- while a genuinely lost wake-up still
 * costs a whole backstop period per occurrence and fails the count checks. */
#define BACKSTOP 20000
static int irq_hook(st_frame_t *f) {
    if (f->cause == (CAUSE_INTR | IRQ_M_TIMER)) { g_timer_irqs++; g_irq_epc = f->epc; st_set_mtimecmp(st_mtime() + BACKSTOP); return 1; }
    if (f->cause == (CAUSE_INTR | IRQ_M_SOFT))  { g_soft_irqs++;  g_irq_epc = f->epc; CLINT_MSIP = 0; return 1; }
    return 0;
}

static uint64_t g_after_wfi;
/* wfi with the address of the following instruction recorded */
static void wfi_marked(void) {
    __asm__ volatile (".option push\n.option norvc\nla t0, 1f\n sd t0, 0(%0)\n wfi\n1: nop\n.option pop"
                      :: "r"(&g_after_wfi) : "t0", "memory");
}

static uint64_t s_wfi_body(uint64_t delay) {
    st_set_mtimecmp(st_mtime() + delay);   /* S can reach CLINT: bare mode, PMP allow-all */
    st_wfi();
    return 1;
}

static uint64_t rand_delay(int i) {
    switch (i % 4) {
    case 0:  return 0;                          /* already expired */
    case 1:  return 1 + st_rand_range(8);       /* races the WFI itself */
    case 2:  return 20 + st_rand_range(200);
    default: return 200 + st_rand_range(3000);
    }
}

int main(void) {
    st_init();
    g_m_irq_hook = irq_hook;

    st_section("WFI with MIE=0 wakes on pending MTIP, no trap");
    csr_set(mie, MIP_MTIP);
    for (int i = 0; i < ROUNDS; i++) {
        uint64_t before = g_timer_irqs;
        uint64_t cmp = st_mtime() + rand_delay(i);
        st_set_mtimecmp(cmp);
        st_wfi();
        /* WFI may also return early (spec allows it): wait out the deadline. */
        while (!(csr_read(mip) & MIP_MTIP)) ;
        ST_CHECK("mtime reached mtimecmp", st_mtime() >= cmp);
        ST_CHECK_EQ("no trap with MIE=0", g_timer_irqs, before);
        st_timer_off();
        ST_CHECK_EQ("MTIP clears when mtimecmp moves", csr_read(mip) & MIP_MTIP, 0);
    }

    st_section("WFI with MIE=1 takes the interrupt; mepc = next instruction");
    for (int i = 0; i < ROUNDS; i++) {
        uint64_t before = g_timer_irqs;
        uint64_t t0 = st_mtime();
        /* deadline well past the few instructions between here and the wfi */
        st_set_mtimecmp(t0 + 400 + rand_delay(i));
        csr_set(mstatus, MSTATUS_MIE);
        wfi_marked();
        /* an early return would leave the interrupt to arrive here */
        while (g_timer_irqs == before) ;
        csr_clear(mstatus, MSTATUS_MIE);
        ST_CHECK_EQ("exactly one timer interrupt", g_timer_irqs, before + 1);
        ST_CHECK("mepc is after the WFI (or later)", g_irq_epc >= g_after_wfi);
        ST_CHECK("woke well before the backstop", st_mtime() - t0 < BACKSTOP / 2);
    }
    st_timer_off();
    csr_clear(mie, MIP_MTIP);

    st_section("MSIP wakes WFI");
    csr_set(mie, MIP_MSIP);
    for (int i = 0; i < 8; i++) {
        uint64_t before = g_soft_irqs;
        CLINT_MSIP = 1;
        st_fence_io();
        ST_CHECK("MSIP visible in mip", csr_read(mip) & MIP_MSIP);
        /* Linux's idle pattern: wfi with MIE = 0 (must return: MSIP is
         * pending), then enable -- the interrupt is taken right there. */
        st_wfi();
        ST_CHECK_EQ("no trap while MIE=0", g_soft_irqs, before);
        csr_set(mstatus, MSTATUS_MIE);
        __asm__ volatile ("nop\nnop\nnop" ::: "memory");
        csr_clear(mstatus, MSTATUS_MIE);
        ST_CHECK_EQ("one software interrupt", g_soft_irqs, before + 1);
        ST_CHECK_EQ("MSIP cleared", csr_read(mip) & MIP_MSIP, 0);
    }
    csr_clear(mie, MIP_MSIP);

    st_section("WFI in S wakes on an M timer interrupt (taken in M)");
    csr_set(mie, MIP_MTIP);
    for (int i = 0; i < 16; i++) {
        uint64_t before = g_timer_irqs, t0 = st_mtime();
        ST_CHECK_EQ("S body returned", st_run(PRV_S, s_wfi_body, rand_delay(i) + 400), 1);
        ST_CHECK_EQ("timer taken in M", g_timer_irqs, before + 1);
        ST_CHECK("woke well before the backstop", st_mtime() - t0 < BACKSTOP / 2);
        st_timer_off();
    }
    csr_clear(mie, MIP_MTIP);

    return st_result();
}
