// @stress tier=pr seeds=2 nightly_seeds=8 build=no_spike duts=legacy,forte timeout=40000000
//
// st_smc_irq -- self-modifying code while a timer interrupt fires every few
// hundred cycles, with the interrupt handler doing its own SMC + fence.i.
//
// Kernels patch code (static keys, alternatives, ftrace) with interrupts
// arriving mid-sequence, and an interrupt can land between the code store and
// the fence.i, or between fence.i and the first fetch of the new code.  The
// handler also rewrites and runs a function of its own, so a fence.i inside the
// trap path must not disturb the interrupted context's pending fence.
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define ROUNDS (400 * ST_SCALE)

static uint8_t g_main_code[4096] ST_ALIGNED(4096);
static uint8_t g_irq_code[256] ST_ALIGNED(64);
static volatile uint64_t g_irqs, g_irq_bad;

static int timer_irq(st_frame_t *f) {
    if (f->cause != (CAUSE_INTR | IRQ_M_TIMER)) return 0;
    g_irqs++;
    int32_t v = (int32_t)(g_irqs * 7 + 3) & 0x7ff;
    uint64_t a = (uint64_t)g_irq_code + (g_irqs & 3) * 2;
    st_put_insn32(a, ENC_ADDI(10, 0, v));
    st_put_insn32(a + 4, ENC_RET);
    st_fence_i();
    if (((uint64_t (*)(void))a)() != (uint64_t)v) g_irq_bad++;
    /* fence.i writes back the whole D$ (thousands of cycles); re-arming
     * closer than that would leave the interrupted code no room to finish
     * its own fence.i.  1-9k cycles still lands interrupts throughout the
     * store / fence.i / call sequence below. */
    st_set_mtimecmp(st_mtime() + 1000 + st_rand_range(8000));
    return 1;
}

int main(void) {
    st_init();
    g_m_irq_hook = timer_irq;
    csr_set(mie, MIP_MTIP);
    st_set_mtimecmp(st_mtime() + 200);
    csr_set(mstatus, MSTATUS_MIE);

    st_section("patch / fence.i / run with interrupts landing anywhere");
    uint64_t bad = 0;
    for (int i = 0; i < ROUNDS; i++) {
        uint64_t a = (uint64_t)g_main_code + (uint64_t)(i % 200) * 18;    /* all alignments */
        int32_t v = (int32_t)st_rand_range(4000) - 2000;
        st_put_insn32(a, ENC_ADDI(10, 10, v));
        st_put_insn32(a + 4, ENC_ADDI(10, 10, 1));
        st_put_insn32(a + 8, ENC_RET);
        st_fence_i();
        if (((uint64_t (*)(uint64_t))a)(5000) != (uint64_t)(5001 + v)) bad++;
    }
    csr_clear(mstatus, MSTATUS_MIE);
    csr_clear(mie, MIP_MTIP);
    st_timer_off();
    ST_CHECK_EQ("main-line SMC under interrupts", bad, 0);
    ST_CHECK_EQ("handler SMC", g_irq_bad, 0);
    ST_CHECK("interrupts landed", g_irqs > 20 * ST_SCALE);
    st_puts("[ST] interrupts: "); st_putdec(g_irqs); st_putc('\n');
    return st_result();
}
