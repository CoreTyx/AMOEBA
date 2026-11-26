// @stress tier=pr seeds=2 nightly_seeds=8 weekly_seeds=32 build=no_spike duts=legacy,forte timeout=60000000
//
// st_pagefault_storm -- a program that page-faults continuously.
//
// A small S-mode kernel runs demand paging with far fewer physical frames than
// the U program's virtual pages, exactly the regime of a Linux system under
// memory pressure:
//   - every non-resident access faults (load 13 / store 15 / fetch 12), is
//     delegated to S (medeleg), and is resolved by evicting a victim frame
//     (clock algorithm), writing it back to a "swap" area if dirty, unmapping
//     it with `sfence.vma va, asid`, and paging the new page in
//   - dirty tracking is Svade: pages are mapped clean (D = 0) and the first
//     store to a resident page faults so the kernel can set D
//   - CODE pages are demand-paged too, copied in with `fence.i`, and include a
//     32-bit instruction that straddles a page boundary: when only its second
//     half is non-resident the fetch must fault with stval = the second page
//     and sepc = the instruction
// The U program does a seeded random read-modify-write walk and keeps its own
// expected values; every value read back after any number of evictions must
// match.  Hundreds of faults per PR run, thousands at nightly/weekly scale.
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define NDATA     96                 /* data pages                      */
#define NCODE     6                  /* code pages (incl. straddle pair) */
#define NPAGES    (NDATA + NCODE)
#define NFRAMES   12                 /* resident set << working set     */
/* Measured (GCC 14, legacy): ~2.4M cycles of setup, then ~47k cycles per
 * iteration (~52k per page-in: a 4 KiB copy in, plus a writeback when dirty,
 * through the then-4 KiB D$).  1500 iterations needed ~73M cycles against the 60M
 * budget; 500 is ~26M, ~800 faults at PR scale, thousands at nightly/weekly. */
#define ITERS     (500 * ST_SCALE)
#define SLOTS     8                  /* tracked words per page           */
#define VA_BASE   0xC0000000UL
#define VA_CODE   (VA_BASE + NDATA * ST_PAGE)
#define ASID      0x2a
#define STRADDLE  (NCODE - 2)        /* code page whose last insn straddles */
#define ECALL_EVICT 0x45564354UL

/* ---------------- kernel state (S, identity-mapped) ---------------- */
static uint64_t g_root;
static uint64_t *g_pte[NPAGES];
static uint64_t g_swap[NPAGES];            /* PA of each page's backing store */
static uint64_t g_frame[NFRAMES];
static int16_t  g_owner[NFRAMES];          /* page in frame, -1 = free         */
static uint32_t g_hand;
static volatile uint64_t g_nfault[3], g_nevict, g_nwriteback, g_ndirty, g_nbad;
static volatile uint64_t g_last_cause, g_last_tval, g_last_epc;

static inline int is_code(int p) { return p >= NDATA; }
static inline uint64_t page_va(int p) { return VA_BASE + (uint64_t)p * ST_PAGE; }

static void copy_page(uint64_t dst, uint64_t src) {
    volatile uint64_t *d = (volatile uint64_t *)dst, *s = (volatile uint64_t *)src;
    for (int i = 0; i < 512; i++) d[i] = s[i];
}

static void evict(int f) {
    int p = g_owner[f];
    if (p < 0) return;
    uint64_t pte = *g_pte[p];
    if (pte & PTE_D) { copy_page(g_swap[p], g_frame[f]); g_nwriteback++; }
    *g_pte[p] = 0;
    sfence_va_asid(page_va(p), ASID);
    g_owner[f] = -1;
    g_nevict++;
}

static int pick_victim(void) {
    for (int i = 0; i < NFRAMES; i++) if (g_owner[i] < 0) return i;
    for (;;) {                                   /* clock: give A=1 pages a second chance */
        int f = (int)(g_hand++ % NFRAMES);
        int p = g_owner[f];
        if (*g_pte[p] & PTE_A) { *g_pte[p] &= ~PTE_A; sfence_va_asid(page_va(p), ASID); continue; }
        return f;
    }
}

static void page_in(int p) {
    int f = pick_victim();
    evict(f);
    copy_page(g_frame[f], g_swap[p]);
    g_owner[f] = (int16_t)p;
    uint64_t perm = is_code(p) ? (PTE_R | PTE_X) : (PTE_R | PTE_W);
    *g_pte[p] = pte_leaf(g_frame[f], perm | PTE_U | PTE_A);   /* clean: D = 0 */
    if (is_code(p)) st_fence_i();
    sfence_va_asid(page_va(p), ASID);
}

static int s_fault(st_frame_t *f) {
    int k = f->cause == CAUSE_LOAD_PAGE ? 0 : f->cause == CAUSE_STORE_PAGE ? 1 : f->cause == CAUSE_FETCH_PAGE ? 2 : -1;
    if (f->cause == CAUSE_ECALL_U && f->x[17] == ECALL_EVICT) {      /* U asks: evict page a0 */
        int p = (int)f->x[10];
        for (int i = 0; i < NFRAMES; i++) if (g_owner[i] == p) evict(i);
        f->epc += 4;
        return 1;
    }
    if (k < 0) return 0;
    g_last_cause = f->cause; g_last_tval = f->tval; g_last_epc = f->epc;
    uint64_t va = f->tval;
    if (va < VA_BASE || va >= VA_BASE + (uint64_t)NPAGES * ST_PAGE) { g_nbad++; return 0; }
    int p = (int)((va - VA_BASE) / ST_PAGE);
    g_nfault[k]++;
    uint64_t pte = *g_pte[p];
    if ((pte & PTE_V) && k == 1 && !is_code(p)) {   /* resident, clean: mark dirty */
        *g_pte[p] = pte | PTE_D | PTE_A;
        sfence_va_asid(va, ASID);
        g_ndirty++;
        return 1;
    }
    if ((pte & PTE_V) && !(pte & PTE_A)) {          /* second-chance cleared A */
        *g_pte[p] = pte | PTE_A;
        sfence_va_asid(va, ASID);
        return 1;
    }
    if (pte & PTE_V) { g_nbad++; return 0; }        /* fault on a good mapping */
    page_in(p);
    return 1;                                       /* retry */
}

/* ---------------- U program (runs through the U alias) ---------------- */
static uint64_t g_expect[NDATA][SLOTS];
static volatile uint64_t g_u_err, g_u_calls, g_u_strad_ok, g_u_rng;
static volatile uint64_t g_strad_cause, g_strad_tval, g_strad_epc;

static inline uint64_t u_rand(void) {
    uint64_t x = g_u_rng; x ^= x >> 12; x ^= x << 25; x ^= x >> 27; g_u_rng = x;
    return x * 0x2545F4914F6CDD1DULL;
}
static inline void u_evict(int p) {
    register uint64_t a0 __asm__("a0") = (uint64_t)p, a7 __asm__("a7") = ECALL_EVICT;
    __asm__ volatile ("ecall" : "+r"(a0) : "r"(a7) : "memory");
}

static uint64_t u_main(uint64_t arg) {
    (void)arg;
    uint64_t err = 0;
    for (int i = 0; i < ITERS; i++) {
        int p = (int)(u_rand() % NDATA);
        int s = (int)(u_rand() % SLOTS);
        volatile uint64_t *w = (volatile uint64_t *)(page_va(p) + (uint64_t)s * 512 + (uint64_t)p * 8 % 512);
        uint64_t v = *w;
        if (v != g_expect[p][s]) err++;
        if (u_rand() & 1) {
            uint64_t n = v * 0x9E3779B97F4A7C15ULL + (uint64_t)i + 1;
            *w = n;
            g_expect[p][s] = n;
        }
        if ((i & 15) == 0) {                         /* call into a paged code page */
            int c = (int)(u_rand() % (NCODE - 2));
            uint64_t r = ((uint64_t (*)(uint64_t))page_va(NDATA + c))((uint64_t)i);
            if (r != (uint64_t)i + 1000 + (uint64_t)c) err++;
            g_u_calls++;
        }
    }
    /* straddling instruction: entry 4 bytes before the end of code page
     * STRADDLE; the 32-bit addi at end-2 crosses into STRADDLE+1. */
    uint64_t (*sfn)(uint64_t) = (uint64_t (*)(uint64_t))(page_va(NDATA + STRADDLE) + ST_PAGE - 4);
    for (int k = 0; k < 4; k++) {
        if (sfn(5) != 5 + 101) err++;                /* both pages resident now */
        u_evict(NDATA + STRADDLE + 1);               /* drop only the second half */
        g_last_cause = 0;
        if (sfn(7) != 7 + 101) err++;
        g_strad_cause = g_last_cause; g_strad_tval = g_last_tval; g_strad_epc = g_last_epc;
        if (g_strad_cause == CAUSE_FETCH_PAGE && g_strad_tval == page_va(NDATA + STRADDLE + 1) &&
            g_strad_epc == page_va(NDATA + STRADDLE) + ST_PAGE - 2)
            g_u_strad_ok++;
    }
    g_u_err = err;
    return err;
}

/* ---------------- S kernel entry ---------------- */
static uint8_t g_ustack[16384] ST_ALIGNED(16);
static uint64_t s_kernel(uint64_t arg) {
    (void)arg;
    st_s_init();
    g_s_hook = s_fault;
    csr_write(satp, satp_sv39(ASID, g_root));
    sfence_all();
    /* U gets its own stack: g_st_lstack is the S kernel's stack (st_run). */
    uint64_t usp = st_u_alias((uint64_t)(g_ustack + sizeof g_ustack));
    uint64_t r = st_s_run_user((uint64_t (*)(uint64_t))st_u_alias((uint64_t)u_main), 0, usp);
    csr_write(satp, 0);
    sfence_all();
    g_s_hook = 0;
    return r;
}

static void write16(uint64_t pa, uint16_t v) { *(volatile uint16_t *)pa = v; }
static void write32(uint64_t pa, uint32_t v) { write16(pa, (uint16_t)v); write16(pa + 2, (uint16_t)(v >> 16)); }

int main(void) {
    st_init();
    g_u_rng = 0x51ed2701ULL ^ ((uint64_t)SEED * 0x9E3779B97F4A7C15ULL);

    /* address space: identity (S), U alias of the image, paged region */
    g_root = pt_new_identity_root(0);
    st_map_u_alias(g_root);
    for (int p = 0; p < NPAGES; p++) {
        g_pte[p] = pt_slot(g_root, page_va(p), 0);
        *g_pte[p] = 0;
        g_swap[p] = frame_alloc();                       /* zeroed backing store */
    }
    for (int f = 0; f < NFRAMES; f++) { g_frame[f] = frame_alloc(); g_owner[f] = -1; }

    /* code pages: `addi a0, a0, 1000 + c ; ret` at offset 0 */
    for (int c = 0; c < NCODE - 2; c++) {
        write32(g_swap[NDATA + c] + 0, (uint32_t)((1000 + c) << 20) | (10u << 15) | (10u << 7) | 0x13);
        write32(g_swap[NDATA + c] + 4, 0x00008067);
    }
    /* straddle pair: [end-4] c.addi a0,1 ; [end-2] addi a0,a0,100 (crosses) ;
     * next page [+2] ret */
    uint64_t sp0 = g_swap[NDATA + STRADDLE], sp1 = g_swap[NDATA + STRADDLE + 1];
    write16(sp0 + ST_PAGE - 4, 0x0505);
    write16(sp0 + ST_PAGE - 2, (uint16_t)0x06450513u);
    write16(sp1 + 0, (uint16_t)(0x06450513u >> 16));
    write32(sp1 + 2, 0x00008067);

    csr_write(medeleg, (1UL << CAUSE_ECALL_U) | (1UL << CAUSE_LOAD_PAGE) |
                       (1UL << CAUSE_STORE_PAGE) | (1UL << CAUSE_FETCH_PAGE));

    st_section("demand paging under memory pressure");
    uint64_t r = st_run(PRV_S, s_kernel, 0);
    csr_write(medeleg, 0);

    ST_CHECK_EQ("U program saw no corrupted value", r, 0);
    ST_CHECK_EQ("U error count", g_u_err, 0);
    ST_CHECK_EQ("no fault on a valid mapping / outside the region", g_nbad, 0);
    uint64_t faults = g_nfault[0] + g_nfault[1] + g_nfault[2];
    st_puts("[ST] faults ld/st/fetch: "); st_putdec(g_nfault[0]); st_putc('/');
    st_putdec(g_nfault[1]); st_putc('/'); st_putdec(g_nfault[2]);
    st_puts(" evictions "); st_putdec(g_nevict); st_puts(" writebacks "); st_putdec(g_nwriteback);
    st_puts(" dirty-marks "); st_putdec(g_ndirty); st_putc('\n');
    ST_CHECK("at least one fault per two iterations", faults >= (uint64_t)ITERS / 2);
    ST_CHECK("dirty pages were written back", g_nwriteback > 0);
    ST_CHECK("Svade dirty faults happened", g_ndirty > 0);
    ST_CHECK("code pages faulted in", g_nfault[2] > 0);
    ST_CHECK_EQ("straddling fetch faulted on the second page, every time", g_u_strad_ok, 4);
    st_puts("[ST] last straddle fault cause/tval/epc: "); st_puthex(g_strad_cause); st_putc(' ');
    st_puthex(g_strad_tval); st_putc(' '); st_puthex(g_strad_epc); st_putc('\n');

    /* final state of every data page, from swap or resident frame */
    uint64_t bad = 0;
    for (int p = 0; p < NDATA; p++) {
        uint64_t base = g_swap[p];
        for (int f = 0; f < NFRAMES; f++)
            if (g_owner[f] == p && (*g_pte[p] & PTE_D)) base = g_frame[f];
        for (int s = 0; s < SLOTS; s++)
            if (*(volatile uint64_t *)(base + (uint64_t)s * 512 + (uint64_t)p * 8 % 512) != g_expect[p][s]) bad++;
    }
    ST_CHECK_EQ("kernel's copy of every page matches U's model", bad, 0);
    return st_result();
}
