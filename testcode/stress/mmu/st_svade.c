// @stress tier=pr seeds=2 nightly_seeds=8 build=no_spike duts=legacy,forte timeout=30000000
//
// st_svade -- software-managed A/D bits (Svade; the core has no Svadu).
//
// With SVADU_SUPPORTED = 0 the hardware must never set A or D itself: a load,
// fetch or store to a page with A = 0 page-faults, and so does a store to a page
// with D = 0, and the kernel sets the bit and retries.  Linux's dirty tracking,
// page reclaim and file writeback all depend on this being exact:
//   - exactly ONE fault per first touch (load/fetch: A) and per first write (D)
//   - a store to an A=0,D=0 page faults once; the handler sets both
//   - a store that hits a cached D=0 translation still faults (TLB-hit path)
//   - after the run, PTE A/D bits are exactly what the handler set: the
//     hardware wrote none of them
// The U program follows a random script of loads, stores and calls into 32
// pages; an M-mode "kernel" handles the faults and a model predicts every one.
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define NPAGES  32
#define NSTEPS  (400 * ST_SCALE)
#define VA_BASE 0xC0000000UL

static uint64_t *g_pte[NPAGES];
static uint8_t  g_kind[NSTEPS], g_page[NSTEPS];
static volatile uint64_t g_faults[NPAGES][3], g_stray;

static int m_hook(st_frame_t *f) {
    int k = f->cause == CAUSE_LOAD_PAGE ? 0 : f->cause == CAUSE_STORE_PAGE ? 1 : f->cause == CAUSE_FETCH_PAGE ? 2 : -1;
    if (k < 0) return 0;
    uint64_t p = (f->tval - VA_BASE) / ST_PAGE;
    if (f->tval < VA_BASE || p >= NPAGES) { g_stray++; return 0; }
    g_faults[p][k]++;
    *g_pte[p] |= PTE_A | (k == 1 ? PTE_D : 0);
    sfence_va(f->tval);
    return 1;                        /* retry the faulting instruction */
}

static uint64_t u_script(uint64_t arg) {
    (void)arg;
    uint64_t acc = 0;
    for (int i = 0; i < NSTEPS; i++) {
        uint64_t va = VA_BASE + (uint64_t)g_page[i] * ST_PAGE;
        switch (g_kind[i]) {
        case 0: acc += *(volatile uint64_t *)(va + 0x800); break;
        case 1: *(volatile uint64_t *)(va + 0x800) = acc + (uint64_t)i; break;
        default: acc += ((uint64_t (*)(uint64_t))(va + 0x100))((uint64_t)i); break;
        }
    }
    return acc;
}

int main(void) {
    st_init();
    g_m_hook = m_hook;
    uint64_t root = pt_new_identity_root(0);
    st_map_u_alias(root);
    for (int p = 0; p < NPAGES; p++) {
        uint64_t fr = frame_alloc();
        volatile uint32_t *c = (volatile uint32_t *)(fr + 0x100);
        c[0] = 0x00150513;               /* addi a0, a0, 1 */
        c[1] = 0x00008067;               /* ret            */
        uint64_t va = VA_BASE + (uint64_t)p * ST_PAGE;
        g_pte[p] = pt_slot(root, va, 0);
        *g_pte[p] = pte_leaf(fr, PTE_R | PTE_W | PTE_X | PTE_U);   /* A = D = 0 */
    }
    st_fence_i();

    /* script + model */
    uint8_t a[NPAGES] = { 0 }, d[NPAGES] = { 0 };
    uint64_t want[NPAGES][3] = { { 0 } };
    for (int i = 0; i < NSTEPS; i++) {
        int p = (int)st_rand_range(NPAGES), k = (int)st_rand_range(3);
        g_page[i] = (uint8_t)p; g_kind[i] = (uint8_t)k;
        if (k == 1) { if (!a[p] || !d[p]) { want[p][1]++; a[p] = d[p] = 1; } }
        else if (!a[p]) { want[p][k]++; a[p] = 1; }
    }

    csr_write(satp, satp_sv39(0x42, root));
    sfence_all();
    st_section("U script under lazy A/D");
    uint64_t usp = st_u_alias((uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    (void)st_run_in_mode(PRV_U, (uint64_t (*)(uint64_t))st_u_alias((uint64_t)u_script), 0, usp);
    csr_write(satp, 0);
    sfence_all();

    ST_CHECK_EQ("no faults outside the test pages", g_stray, 0);
    uint64_t bad = 0, total = 0;
    for (int p = 0; p < NPAGES; p++)
        for (int k = 0; k < 3; k++) {
            total += g_faults[p][k];
            if (g_faults[p][k] != want[p][k]) {
                bad++;
                if (bad < 6) st_check_failed("fault count per page/kind", ((uint64_t)p << 8) | (uint64_t)k * 16 | g_faults[p][k], want[p][k], __LINE__);
            }
        }
    ST_CHECK_EQ("every fault predicted exactly", bad, 0);
    st_puts("[ST] faults taken: "); st_putdec(total); st_putc('\n');

    st_section("hardware never set A or D");
    uint64_t hw = 0;
    for (int p = 0; p < NPAGES; p++) {
        uint64_t got = *g_pte[p] & (PTE_A | PTE_D);
        uint64_t exp = (a[p] ? PTE_A : 0) | (d[p] ? PTE_D : 0);
        if (got != exp) hw++;
    }
    ST_CHECK_EQ("PTE A/D exactly as the handler left them", hw, 0);
    return st_result();
}
