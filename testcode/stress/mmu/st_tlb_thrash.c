// @stress tier=pr seeds=2 nightly_seeds=8 build=no_spike duts=legacy,forte timeout=40000000
//
// st_tlb_thrash -- U-mode working set of 512 pages against 8-entry I/D TLBs,
// with the kernel remapping pages underneath it.
//
// Every access is (almost always) a DTLB miss and a hardware page walk; every
// 32 accesses the U program asks the "kernel" (an M hook) to swap two pages'
// physical frames AND their contents, then invalidate with one of the four
// sfence.vma forms.  The U program's view must never change: a translation that
// survives the sfence would read the other page's data and fail the signature
// check.  This is the TLB-shootdown pattern Linux uses for page migration, COW
// and munmap, compressed into a few million cycles.
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define NPAGES   512
#define VA_BASE  0xC0000000UL
#define ROUNDS   (2 * ST_SCALE)
#define SWAP_EVERY 32
#define ECALL_SWAP 0x53574150UL

static uint64_t g_root, g_asid;
static uint64_t *g_leaf[NPAGES];            /* PTE slot for each page */
static volatile uint64_t g_swaps, g_bad_ecall;
static uint64_t g_u_errors, g_u_checks;      /* written by U through the alias */
static uint64_t g_u_rng;

static inline uint64_t sig(uint64_t page, uint64_t slot, uint64_t round) {
    return st_mix64((page << 32) ^ (slot << 8) ^ round ^ 0xA5A5000000000000UL);
}

static void swap_frames(uint64_t a, uint64_t b) {
    uint64_t pa = pte_pa(*g_leaf[a]), pb = pte_pa(*g_leaf[b]);
    volatile uint64_t *xa = (volatile uint64_t *)pa, *xb = (volatile uint64_t *)pb;
    for (int i = 0; i < 512; i++) { uint64_t t = xa[i]; xa[i] = xb[i]; xb[i] = t; }
    uint64_t bits = PTE_R | PTE_W | PTE_U | PTE_AD;
    *g_leaf[a] = pte_leaf(pb, bits);
    *g_leaf[b] = pte_leaf(pa, bits);
    uint64_t va = VA_BASE + a * ST_PAGE, vb = VA_BASE + b * ST_PAGE;
    switch (g_swaps % 4) {
    case 0: sfence_all(); break;
    case 1: sfence_va(va); sfence_va(vb); break;
    case 2: sfence_asid(g_asid); break;
    default: sfence_va_asid(va, g_asid); sfence_va_asid(vb, g_asid); break;
    }
    g_swaps++;
}

static int m_hook(st_frame_t *f) {
    if (f->cause == CAUSE_ECALL_U && f->x[17] == ECALL_SWAP) {
        uint64_t a = f->x[10] % NPAGES, b = f->x[11] % NPAGES;
        if (a != b) swap_frames(a, b);
        f->epc += 4;
        return 1;
    }
    return 0;
}

static inline uint64_t u_rand(void) {
    uint64_t x = g_u_rng; x ^= x >> 12; x ^= x << 25; x ^= x >> 27; g_u_rng = x;
    return x * 0x2545F4914F6CDD1DULL;
}
static inline void u_swap(uint64_t a, uint64_t b) {
    register uint64_t a0 __asm__("a0") = a, a1 __asm__("a1") = b, a7 __asm__("a7") = ECALL_SWAP;
    __asm__ volatile ("ecall" : "+r"(a0) : "r"(a1), "r"(a7) : "memory");
}

/* U program.  Each page holds sig(page, slot, round) in 8 slots spread over
 * the page; every pass rewrites them for the next round after checking. */
static uint64_t u_body(uint64_t arg) {
    (void)arg;
    uint64_t errors = 0, checks = 0;
    for (uint64_t p = 0; p < NPAGES; p++)
        for (uint64_t s = 0; s < 8; s++)
            *(volatile uint64_t *)(VA_BASE + p * ST_PAGE + s * 504) = sig(p, s, 0);
    for (uint64_t round = 0; round < ROUNDS; round++) {
        /* random order: a full-period LCG over 512 */
        uint64_t p = u_rand() % NPAGES, step = (u_rand() % NPAGES) | 1;
        for (uint64_t n = 0; n < NPAGES; n++, p = (p * 5 + step) % NPAGES) {
            for (uint64_t s = 0; s < 8; s++) {
                volatile uint64_t *w = (volatile uint64_t *)(VA_BASE + p * ST_PAGE + s * 504);
                checks++;
                if (*w != sig(p, s, round)) errors++;
                *w = sig(p, s, round + 1);
            }
            if ((n % SWAP_EVERY) == SWAP_EVERY - 1) {
                /* Swap the page just accessed -- its translation is in the DTLB
                 * -- with another, then read it again at once: a translation that
                 * survived the sfence reads the other page's frame. */
                uint64_t q = (p + 1 + u_rand() % (NPAGES - 1)) % NPAGES;
                u_swap(p, q);
                for (uint64_t s = 0; s < 8; s++) {
                    volatile uint64_t *w = (volatile uint64_t *)(VA_BASE + p * ST_PAGE + s * 504);
                    checks++;
                    if (*w != sig(p, s, round + 1)) errors++;
                }
            }
        }
    }
    g_u_errors = errors;
    g_u_checks = checks;
    return errors;
}

int main(void) {
    st_init();
    g_m_hook = m_hook;
    g_u_rng = 0x1234567ULL ^ ((uint64_t)SEED << 17);

    st_section("build 512-page U address space");
    g_root = pt_new_identity_root(0);
    st_map_u_alias(g_root);
    g_asid = 1 + st_rand_range(0xfffe);
    /* frames in a random permutation of a contiguous pool */
    uint64_t base = frame_alloc_aligned(ST_PAGE);
    for (int i = 1; i < NPAGES; i++) (void)frame_alloc();
    uint16_t perm[NPAGES];
    for (int i = 0; i < NPAGES; i++) perm[i] = (uint16_t)i;
    for (int i = NPAGES - 1; i > 0; i--) { int j = (int)st_rand_range((uint64_t)i + 1); uint16_t t = perm[i]; perm[i] = perm[j]; perm[j] = t; }
    for (int i = 0; i < NPAGES; i++) {
        uint64_t va = VA_BASE + (uint64_t)i * ST_PAGE;
        g_leaf[i] = pt_slot(g_root, va, 0);
        *g_leaf[i] = pte_leaf(base + (uint64_t)perm[i] * ST_PAGE, PTE_R | PTE_W | PTE_U | PTE_AD);
    }
    csr_write(satp, satp_sv39(g_asid, g_root));
    sfence_all();

    st_section("U random walk with remap churn");
    uint64_t usp = st_u_alias((uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    uint64_t r = st_run_in_mode(PRV_U, (uint64_t (*)(uint64_t))st_u_alias((uint64_t)u_body), 0, usp);
    ST_CHECK_EQ("U saw no stale translation", r, 0);
    ST_CHECK_EQ("U error count", g_u_errors, 0);
    ST_CHECK_EQ("all slots checked", g_u_checks, (uint64_t)ROUNDS * NPAGES * 8 + g_swaps * 8);
    ST_CHECK("swaps happened", g_swaps >= (uint64_t)ROUNDS * NPAGES / SWAP_EVERY / 2);

    st_section("kernel view agrees with U view");
    uint64_t bad = 0;
    for (uint64_t p = 0; p < NPAGES; p++)
        for (uint64_t s = 0; s < 8; s++)
            if (*(volatile uint64_t *)(pte_pa(*g_leaf[p]) + s * 504) != sig(p, s, ROUNDS)) bad++;
    ST_CHECK_EQ("physical frames hold the final signatures", bad, 0);

    csr_write(satp, 0);
    sfence_all();
    return st_result();
}
