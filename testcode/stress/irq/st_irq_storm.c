// @stress tier=pr seeds=3 nightly_seeds=16 weekly_seeds=64 build=no_spike duts=legacy,forte timeout=80000000
//
// st_irq_storm -- interrupts every 50-500 cycles, landing on every kind of
// instruction the core has, must be invisible to the interrupted program.
//
// A U-mode workload under Sv39 runs a mix chosen to keep long-latency and
// multi-step operations in flight when the interrupt arrives:
//   65-cycle multiplies and 32-step divides, AMOs, LR/SC loops, page walks
//   (working set > TLB), misaligned accesses emulated by an M handler (a trap
//   that may itself be interrupted on return), and ecalls into M.
// It runs twice: once with no interrupts, once under a randomized timer storm
// whose handler does its own memory traffic.  The two checksums and the final
// memory images must be bit-identical.  Any lost register, double-retired or
// skipped instruction, corrupted mepc, or AMO executed twice shows up here.
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define NPAGES  24
#define VA_BASE 0xC0000000UL
#define ITERS   (600 * ST_SCALE)
#define ECALL_MIX 0x4d495821UL

static uint64_t g_frames[NPAGES];
static volatile uint64_t g_irqs, g_emul, g_handler_scratch[64];
static volatile int g_storm;

static int m_hook(st_frame_t *f) {
    if (f->cause == (CAUSE_INTR | IRQ_M_TIMER)) {
        g_irqs++;
        for (int i = 0; i < 8; i++) g_handler_scratch[(g_irqs + (uint64_t)i * 7) & 63] += (uint64_t)i;
        if (g_storm) st_set_mtimecmp(st_mtime() + 50 + st_rand_range(450));
        else st_timer_off();
        return 1;
    }
    if (f->cause == CAUSE_ECALL_U && f->x[17] == ECALL_MIX) {
        f->x[10] = st_mix64(f->x[10] ^ f->x[11]);
        f->epc += 4;
        return 1;
    }
    if (f->cause == CAUSE_MISALIGNED_LOAD || f->cause == CAUSE_MISALIGNED_STORE) {
        /* minimal OpenSBI-style emulation of `ld rd, 0(rs1)` / `sd rs2, 0(rs1)`
         * (the workload only uses these two, through a VA: translate via MPRV) */
        uint64_t va = f->tval;
        uint32_t raw;
        {   /* instruction bytes through U's own mapping */
            uint64_t lo = 0, hi = 0;
            (void)probe_lhu(f->epc, PRV_U, &lo);
            (void)probe_lhu(f->epc + 2, PRV_U, &hi);
            raw = (uint32_t)(lo | (hi << 16));
        }
        if (f->cause == CAUSE_MISALIGNED_LOAD) {
            uint64_t v = 0;
            for (int i = 7; i >= 0; i--) { uint64_t b = 0; (void)probe_lbu(va + (uint64_t)i, PRV_U, &b); v = (v << 8) | b; }
            uint32_t rd = (raw >> 7) & 31;
            if (rd) f->x[rd] = v;
        } else {
            uint64_t v = f->x[(raw >> 20) & 31];
            for (int i = 0; i < 8; i++) (void)probe_sb(va + (uint64_t)i, PRV_U, (v >> (8 * i)) & 0xff);
        }
        g_emul++;
        f->epc += 4;
        return 1;
    }
    return 0;
}

static inline uint64_t u_mix(uint64_t a, uint64_t b) {
    register uint64_t a0 __asm__("a0") = a, a1 __asm__("a1") = b, a7 __asm__("a7") = ECALL_MIX;
    __asm__ volatile ("ecall" : "+r"(a0) : "r"(a1), "r"(a7) : "memory");
    return a0;
}

static uint64_t u_work(uint64_t seed) {
    uint64_t x = seed | 1, sum = 0;
    for (int i = 0; i < ITERS; i++) {
        x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
        uint64_t r = x * 0x2545F4914F6CDD1DULL;
        uint64_t p = r % NPAGES, off = (r >> 20) % (ST_PAGE - 16);
        volatile uint64_t *w = (volatile uint64_t *)(VA_BASE + p * ST_PAGE + (off & ~7UL));
        switch (r >> 60) {
        case 0: case 1: case 2:
            sum += (r * (sum | 3)) + (sum / ((r & 0xffff) | 1)) + (sum % ((r >> 32) | 7));
            break;
        case 3: case 4: {
            uint64_t old;
            __asm__ volatile ("amoadd.d %0, %2, (%1)" : "=r"(old) : "r"(w), "r"(r) : "memory");
            sum ^= old;
            break; }
        case 5: case 6: {
            /* constrained LR/SC loop in one asm block (see st_lrsc.c) */
            uint64_t o, n, fail;
            __asm__ volatile ("1: lr.d %[o], (%[a])\n"
                              "   addi %[n], %[o], 3\n"
                              "   sc.d %[f], %[n], (%[a])\n"
                              "   bnez %[f], 1b\n"
                              : [o] "=&r"(o), [n] "=&r"(n), [f] "=&r"(fail) : [a] "r"(w) : "memory");
            sum += o;
            break; }
        case 7: case 8: {   /* misaligned: emulated by M */
            uint64_t a = VA_BASE + p * ST_PAGE + (off | 1);
            uint64_t v;
            __asm__ volatile (".option push\n.option norvc\nld %0, 0(%1)\n.option pop" : "=r"(v) : "r"(a) : "memory");
            sum += v;
            __asm__ volatile (".option push\n.option norvc\nsd %0, 0(%1)\n.option pop" :: "r"(sum), "r"(a) : "memory");
            break; }
        case 9: case 10:
            sum = u_mix(sum, r);
            break;
        default:
            *w = *w * 3 + sum;
            sum += *w;
            break;
        }
    }
    return sum;
}

static uint64_t run_once(int storm, uint64_t root) {
    for (int p = 0; p < NPAGES; p++)
        for (int i = 0; i < 512; i++) ((volatile uint64_t *)g_frames[p])[i] = st_mix64((uint64_t)p * 4096 + (uint64_t)i);
    csr_write(satp, satp_sv39(0x77, root));
    sfence_all();
    g_storm = storm;
    if (storm) {
        csr_set(mie, MIP_MTIP);
        st_set_mtimecmp(st_mtime() + 100);
    }
    uint64_t usp = st_u_alias((uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    uint64_t r = st_run_in_mode(PRV_U, (uint64_t (*)(uint64_t))st_u_alias((uint64_t)u_work), 0xC0FFEE ^ (uint64_t)SEED, usp);
    g_storm = 0;
    st_timer_off();
    csr_clear(mie, MIP_MTIP);
    csr_write(satp, 0);
    sfence_all();
    return r;
}

static uint64_t image_hash(void) {
    uint64_t h = 0;
    for (int p = 0; p < NPAGES; p++)
        for (int i = 0; i < 512; i++) h = st_mix64(h ^ ((volatile uint64_t *)g_frames[p])[i]);
    return h;
}

int main(void) {
    st_init();
    g_m_hook = m_hook;
    uint64_t root = pt_new_identity_root(0);
    st_map_u_alias(root);
    for (int p = 0; p < NPAGES; p++) {
        g_frames[p] = frame_alloc();
        map_page(root, VA_BASE + (uint64_t)p * ST_PAGE, g_frames[p], PTE_R | PTE_W | PTE_U | PTE_AD);
    }

    st_section("reference run (no interrupts)");
    uint64_t emul0 = g_emul;
    uint64_t ref = run_once(0, root);
    uint64_t ref_img = image_hash();
    uint64_t emul_ref = g_emul - emul0;

    st_section("storm run");
    uint64_t irq0 = g_irqs;
    emul0 = g_emul;
    uint64_t got = run_once(1, root);
    uint64_t got_img = image_hash();
    uint64_t irqs = g_irqs - irq0;

    ST_CHECK_EQ("checksum identical under the storm", got, ref);
    ST_CHECK_EQ("memory image identical under the storm", got_img, ref_img);
    ST_CHECK_EQ("same number of emulated misaligned accesses", g_emul - emul0, emul_ref);
    ST_CHECK("storm actually stormed", irqs > (uint64_t)ITERS / 20);
    st_puts("[ST] interrupts during storm run: "); st_putdec(irqs);
    st_puts("  emulated misaligned: "); st_putdec(emul_ref); st_putc('\n');
    return st_result();
}
