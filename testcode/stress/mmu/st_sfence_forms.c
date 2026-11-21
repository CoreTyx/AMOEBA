// @stress tier=pr seeds=2 nightly_seeds=8 build=no_spike duts=legacy,forte timeout=30000000
//
// st_sfence_forms -- each sfence.vma form, used minimally, must make the new
// translation visible, on the data side and the instruction side.
//
// Linux picks the narrowest fence it can: flush_tlb_page() is `sfence.vma va`,
// flush_tlb_mm() is `sfence.vma x0, asid`, local_flush_tlb_all() is the bare
// form.  A TLB that only honours the bare form, ignores rs1 for superpage or
// global entries, or keys the ASID compare wrongly passes every boot and then
// returns stale data after a COW break or munmap on silicon.  So for each form
// the test: warms the translation, changes the PTE (new frame, or downgraded
// permission), executes ONLY that form, then requires the new behaviour --
// with the TLB polluted by unrelated entries in between, and for global (G)
// pages with the forms that must cover them.
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define ITERS     (48 * ST_SCALE)
#define VA_DATA   0xC0000000UL
#define VA_CODE   0xC8000000UL
#define VA_NOISE  0xD0000000UL
#define NNOISE    24

enum { F_ALL, F_VA, F_ASID, F_VA_ASID, F_N };
static const char *const g_fname[F_N] = { "sfence.vma", "sfence.vma va", "sfence.vma x0,asid", "sfence.vma va,asid" };

static uint64_t g_root;

static void do_fence(int form, uint64_t va, uint64_t asid) {
    switch (form) {
    case F_ALL:  sfence_all(); break;
    case F_VA:   sfence_va(va); break;
    case F_ASID: sfence_asid(asid); break;
    default:     sfence_va_asid(va, asid); break;
    }
}

/* Fill the DTLB with unrelated translations. */
static void pollute(void) {
    for (int i = 0; i < NNOISE; i++) (void)probe_ld(VA_NOISE + (uint64_t)i * ST_PAGE, PRV_S, 0);
}

/* code frame: `li a0, mark ; ret` (lui + addiw + jalr) */
static void write_code(uint64_t pa, uint32_t mark) {
    volatile uint32_t *c = (volatile uint32_t *)pa;
    uint32_t hi = (mark + 0x800) & 0xfffff000u, lo = mark & 0xfff;
    c[0] = hi | (10u << 7) | 0x37;                  /* lui a0, hi        */
    c[1] = (lo << 20) | (10u << 15) | (0u << 12) | (10u << 7) | 0x1b; /* addiw a0, a0, lo */
    c[2] = 0x00008067;                              /* ret               */
}

int main(void) {
    st_init();
    g_root = pt_new_identity_root(0);
    st_map_u_alias(g_root);
    for (int i = 0; i < NNOISE; i++)
        map_page(g_root, VA_NOISE + (uint64_t)i * ST_PAGE, frame_alloc(), PTE_R | PTE_W | PTE_AD);
    uint64_t *dslot = pt_slot(g_root, VA_DATA, 0);
    uint64_t *cslot = pt_slot(g_root, VA_CODE, 0);
    uint64_t frames[2] = { frame_alloc(), frame_alloc() };
    uint64_t cframes[2] = { frame_alloc(), frame_alloc() };
    uint64_t usp = st_u_alias((uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    uint64_t pass_per_form[F_N] = { 0 };

    for (int it = 0; it < ITERS; it++) {
        int form = it % F_N;
        uint64_t asid = 1 + st_rand_range(0xfffe);
        uint64_t g = (form == F_ALL || form == F_VA) && (st_rand() & 1) ? PTE_G : 0;
        uint64_t m0 = st_rand() | 1, m1 = st_rand() & ~1UL;
        uint64_t off = (st_rand_range(512)) * 8;
        csr_write(satp, satp_sv39(asid, g_root));
        sfence_all();

        /* ---- data: frame swap ---- */
        *(volatile uint64_t *)(frames[0] + off) = m0;
        *(volatile uint64_t *)(frames[1] + off) = m1;
        *dslot = pte_leaf(frames[0], PTE_R | PTE_W | PTE_AD | g);
        sfence_all();
        uint64_t v = 0;
        (void)probe_ld(VA_DATA + off, PRV_S, &v);            /* warm */
        if (v != m0) st_check_failed("warm read", v, m0, __LINE__);
        if (it & 1) pollute();
        *dslot = pte_leaf(frames[1], PTE_R | PTE_W | PTE_AD | g);
        do_fence(form, VA_DATA + (st_rand_range(ST_PAGE) & ~7UL), asid);
        if (probe_ld(VA_DATA + off, PRV_S, &v) || v != m1) st_check_failed(g_fname[form], v, m1, __LINE__);
        else pass_per_form[form]++;

        /* ---- data: permission downgrade RW -> RO (the COW case) ---- */
        (void)probe_sd(VA_DATA + off, PRV_S, 1);               /* warm writable */
        *dslot = pte_leaf(frames[1], PTE_R | PTE_A | g);
        do_fence(form, VA_DATA, asid);
        if (!probe_sd(VA_DATA + off, PRV_S, 2) || g_trap_cause != CAUSE_STORE_PAGE)
            st_check_failed("store after RO downgrade must fault", g_trap_cause, CAUSE_STORE_PAGE, __LINE__);
        else g_st_pass++;

        /* ---- data: unmap ---- */
        (void)probe_ld(VA_DATA + off, PRV_S, &v);
        *dslot = 0;
        do_fence(form, VA_DATA + 8, asid);
        if (!probe_ld(VA_DATA + off, PRV_S, &v) || g_trap_cause != CAUSE_LOAD_PAGE)
            st_check_failed("load after unmap must fault", g_trap_cause, CAUSE_LOAD_PAGE, __LINE__);
        else g_st_pass++;

        /* ---- instruction side: code frame swap, executed in U ---- */
        uint32_t c0 = (uint32_t)(st_rand() & 0x7ffff000u) | 0x123, c1 = c0 ^ 0x5550;
        write_code(cframes[0], c0);
        write_code(cframes[1], c1);
        st_fence_i();
        *cslot = pte_leaf(cframes[0], PTE_R | PTE_X | PTE_U | PTE_A | g);
        sfence_all();
        uint64_t r = st_run_in_mode(PRV_U, (uint64_t (*)(uint64_t))VA_CODE, 0, usp);
        if (r != (uint64_t)(int64_t)(int32_t)c0) st_check_failed("warm fetch", r, c0, __LINE__);
        *cslot = pte_leaf(cframes[1], PTE_R | PTE_X | PTE_U | PTE_A | g);
        do_fence(form, VA_CODE, asid);
        r = st_run_in_mode(PRV_U, (uint64_t (*)(uint64_t))VA_CODE, 0, usp);
        ST_CHECK_EQ("fetch sees new code page", r, (uint64_t)(int64_t)(int32_t)c1);

        /* ---- instruction side: X removed -> fetch page fault ---- */
        *cslot = pte_leaf(cframes[1], PTE_R | PTE_U | PTE_A | g);
        do_fence(form, VA_CODE + 4, asid);
        r = st_run_expect_abort(PRV_U, (uint64_t (*)(uint64_t))VA_CODE, 0, usp);
        ST_CHECK_EQ("fetch after X removed faults", r, ST_TRAP_ABORTED);
        ST_CHECK_EQ("  cause", g_trap_cause, CAUSE_FETCH_PAGE);
        ST_CHECK_EQ("  tval", g_trap_tval, VA_CODE);
    }
    for (int f = 0; f < F_N; f++) {
        st_puts("[ST] "); st_puts(g_fname[f]); st_puts(": "); st_putdec(pass_per_form[f]); st_putc('\n');
        ST_CHECK_EQ("every iteration of this form passed", pass_per_form[f], (uint64_t)ITERS / F_N);
    }
    csr_write(satp, 0);
    sfence_all();
    return st_result();
}
