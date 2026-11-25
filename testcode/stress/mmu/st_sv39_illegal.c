// @stress tier=pr build=no_spike duts=legacy,forte timeout=20000000
//
// st_sv39_illegal -- every PTE/VA combination the Sv39 spec says must fault,
// for loads, stores and fetches, from S and U, with exact cause and tval.
//
// A walker that accepts a reserved encoding gives software a mapping the OS
// never created.  Each case faults on a TLB miss (raised by the walker).  An
// illegal PTE can never be cached, so the TLB-hit path is tested separately,
// for the faults that depend on permission bits of a cached, legal entry:
// cache the translation through an access it allows, then make the access it
// forbids with no PTE change and no sfence.
//
// Cases (privileged spec, Sv39 4.3.2 / 4.4):
//   V=0; W=1,R=0 (reserved); reserved bits 63:54 set (no Svnapot/Svpbmt);
//   non-leaf at level 0; non-leaf with A, D or U set; non-canonical VA;
//   U page from S without SUM; S fetch from a U page even with SUM;
//   S page from U; X-only load without MXR; A=0 any access; D=0 store.
#include "../lib/stress.h"

#define VA0 0xC0000000UL

enum { LD, ST, FX };
static uint64_t g_root, g_usp;
static uint64_t g_frame;

static uint64_t page_cause(int kind) { return kind == LD ? CAUSE_LOAD_PAGE : kind == ST ? CAUSE_STORE_PAGE : CAUSE_FETCH_PAGE; }

/* One access of `kind` at va from `prv`; returns 1 if it faulted with the page
 * fault for that access type and tval == va. */
static int access_faults(int kind, uint64_t va, uint64_t prv) {
    if (kind == FX) {
        uint64_t r = st_run_expect_abort(prv, (uint64_t (*)(uint64_t))va, 0, prv == PRV_U ? g_usp : (uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
        return r == ST_TRAP_ABORTED && g_trap_cause == CAUSE_FETCH_PAGE && g_trap_tval == va;
    }
    int t = kind == LD ? probe_ld(va, prv, 0) : probe_sd(va, prv, 0x77);
    return t && g_trap_cause == page_cause(kind) && g_trap_tval == va;
}
static int access_ok(int kind, uint64_t va, uint64_t prv) {
    if (kind == FX) {
        uint64_t r = st_run_expect_abort(prv, (uint64_t (*)(uint64_t))va, 0, prv == PRV_U ? g_usp : (uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
        return r == 0x600d;
    }
    return kind == LD ? !probe_ld(va, prv, 0) : !probe_sd(va, prv, 0x77);
}

static uint64_t g_slot_va = VA0;
/* each case gets its own fresh VA, so no stale TLB state carries over */
static uint64_t next_va(void) { g_slot_va += 0x200000; return g_slot_va; }

static const char *const kname[3] = { "load", "store", "fetch" };

static void expect_fault_leaf(const char *what, uint64_t pte_bits_raw, int kind, uint64_t prv) {
    uint64_t va = next_va();
    uint64_t *slot = pt_slot(g_root, va, 0);
    *slot = pte_bits_raw;
    sfence_all();
    if (!access_faults(kind, va + 0x10, prv)) st_check_failed(what, g_trap_cause, page_cause(kind), (int)kind);
    else g_st_pass++;
}

/* TLB-hit path: map va with legal but restricted bits, make an access they allow
 * (the translation is now cached), then the one they forbid -- no PTE write, no
 * sfence in between, so the hardware can only decide from the cached entry. */
static void expect_fault_cached(const char *what, uint64_t bits, int allowed_kind, int kind, uint64_t prv) {
    uint64_t va = next_va();
    *pt_slot(g_root, va, 0) = pte_leaf(g_frame, bits);
    sfence_all();
    if (!access_ok(allowed_kind, va + 0x10, prv)) st_check_failed(what, g_trap_cause, 0, 0x200 | kind);
    else g_st_pass++;
    if (!access_faults(kind, va + 0x18, prv)) st_check_failed(what, g_trap_cause, page_cause(kind), 0x100 | kind);
    else g_st_pass++;
}

int main(void) {
    st_init();
    g_root = pt_new_identity_root(0);
    st_map_u_alias(g_root);
    g_usp = st_u_alias((uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    g_frame = frame_alloc();
    /* +0x10: `lui a0, 6 ; addi a0, a0, 13 ; ret` returns 0x600d.  Fetch cases
     * enter at +0x10 (TLB miss) and +0x18 (TLB-hit retry): the latter only has
     * to fault, never to run to completion. */
    {
        volatile uint32_t *c = (volatile uint32_t *)(g_frame + 0x10);
        c[0] = (6u << 12) | (10u << 7) | 0x37;
        c[1] = (0x00du << 20) | (10u << 15) | (10u << 7) | 0x13;
        c[2] = 0x00008067;
    }
    st_fence_i();
    csr_write(satp, satp_sv39(9, g_root));
    sfence_all();
    uint64_t rw  = PTE_R | PTE_W | PTE_X | PTE_AD;
    uint64_t ppn = pte_leaf(g_frame, 0) & ~PTE_V;

    for (int pass = 0; pass < 2; pass++) {
        uint64_t prv = pass ? PRV_U : PRV_S;
        uint64_t u = pass ? PTE_U : 0;
        st_section(pass ? "U-mode" : "S-mode");
        for (int k = LD; k <= ST; k++) {
            expect_fault_leaf(kname[k], ppn | rw | u, k, prv) ; /* valid=0 */
            expect_fault_leaf("W without R", ppn | PTE_V | PTE_W | PTE_AD | u, k, prv);
            expect_fault_leaf("reserved bit 54", ppn | PTE_V | rw | u | (1UL << 54), k, prv);
            expect_fault_leaf("reserved bit 60", ppn | PTE_V | rw | u | (1UL << 60), k, prv);
            expect_fault_leaf("PBMT bits (no Svpbmt)", ppn | PTE_V | rw | u | (1UL << 61), k, prv);
            expect_fault_leaf("N bit (no Svnapot)", ppn | PTE_V | rw | u | (1UL << 63), k, prv);
            expect_fault_leaf("A = 0", ppn | PTE_V | PTE_R | PTE_W | PTE_D | u, k, prv);
        }
        expect_fault_leaf("D = 0 store", ppn | PTE_V | PTE_R | PTE_W | PTE_A | u, ST, prv);
        expect_fault_leaf("read-only store", ppn | PTE_V | PTE_R | PTE_AD | u, ST, prv);
        expect_fault_leaf("X-only load, MXR=0", ppn | PTE_V | PTE_X | PTE_AD | u, LD, prv);
        expect_fault_leaf("wrong U bit (load)", ppn | PTE_V | rw | (u ^ PTE_U), LD, prv);
        expect_fault_leaf("wrong U bit (store)", ppn | PTE_V | rw | (u ^ PTE_U), ST, prv);
    }

    st_section("fetch faults");
    expect_fault_leaf("fetch V=0", ppn | PTE_R | PTE_X | PTE_A | PTE_U, FX, PRV_U);
    expect_fault_leaf("fetch from non-X page", ppn | PTE_V | PTE_R | PTE_W | PTE_AD | PTE_U, FX, PRV_U);
    expect_fault_leaf("fetch A=0", ppn | PTE_V | PTE_R | PTE_X | PTE_U, FX, PRV_U);
    expect_fault_leaf("U fetch from S page", ppn | PTE_V | PTE_R | PTE_X | PTE_A, FX, PRV_U);
    expect_fault_leaf("fetch reserved bit 55", ppn | PTE_V | PTE_R | PTE_X | PTE_A | PTE_U | (1UL << 55), FX, PRV_U);
    csr_set(mstatus, MSTATUS_SUM);
    expect_fault_leaf("S fetch from U page (even with SUM)", ppn | PTE_V | PTE_R | PTE_X | PTE_A | PTE_U, FX, PRV_S);
    csr_clear(mstatus, MSTATUS_SUM);

    st_section("permission faults from a cached translation (TLB hit)");
    for (int pass = 0; pass < 2; pass++) {
        uint64_t prv = pass ? PRV_U : PRV_S;
        uint64_t u = pass ? PTE_U : 0;
        expect_fault_cached("cached read-only page, store", PTE_R | PTE_AD | u, LD, ST, prv);
        expect_fault_cached("cached D=0 page, store (Svade)", PTE_R | PTE_W | PTE_A | u, LD, ST, prv);
    }
    {
        /* S reads a U page with SUM set (cached), then SUM is cleared: the cached
         * entry's U bit must now deny it.  mstatus changes, the PTE does not. */
        uint64_t va = next_va();
        *pt_slot(g_root, va, 0) = pte_leaf(g_frame, PTE_R | PTE_W | PTE_AD | PTE_U);
        sfence_all();
        csr_set(mstatus, MSTATUS_SUM);
        ST_CHECK("cached U page, S load with SUM", access_ok(LD, va + 0x10, PRV_S));
        csr_clear(mstatus, MSTATUS_SUM);
        ST_CHECK("  same entry, SUM cleared: S load faults", access_faults(LD, va + 0x18, PRV_S));
    }

    st_section("non-leaf PTE encodings");
    {
        uint64_t va = next_va();
        uint64_t *l0 = pt_slot(g_root, va, 0);
        *l0 = pte_table(frame_alloc());                  /* pointer at the last level */
        sfence_all();
        ST_CHECK("non-leaf at level 0 faults (load)", access_faults(LD, va, PRV_S));
        uint64_t *l1 = pt_slot(g_root, next_va(), 1);
        uint64_t l0tab = frame_alloc();
        ((uint64_t *)l0tab)[0] = pte_leaf(g_frame, rw);
        static const uint64_t bad_bits[] = { PTE_A, PTE_D, PTE_U };
        static const char *const bad_name[] = { "non-leaf with A", "non-leaf with D", "non-leaf with U" };
        uint64_t va1 = g_slot_va;
        for (int i = 0; i < 3; i++) {
            *l1 = pte_table(l0tab) | bad_bits[i];
            sfence_all();
            if (!access_faults(LD, va1, PRV_S)) st_check_failed(bad_name[i], g_trap_cause, CAUSE_LOAD_PAGE, i);
            else g_st_pass++;
        }
        *l1 = pte_table(l0tab);
        sfence_all();
        ST_CHECK("legal pointer then works", access_ok(LD, va1, PRV_S));
    }

    st_section("non-canonical virtual addresses");
    static const uint64_t noncanon[] = { 0x0000004000000000UL, 0x0000008000000000UL, 0x7fffffc000000000UL,
                                         0xffffff0000000000UL ^ (1UL << 38), 0x8000000000000000UL };
    for (unsigned i = 0; i < ST_ARRAY_LEN(noncanon); i++) {
        uint64_t va = noncanon[i];
        int t = probe_ld(va, PRV_S, 0);
        // Priv. spec 4.4: an address whose bits 63:39 are not all equal to bit 38
        // raises a PAGE fault -- not an access fault.
        ST_CHECK("non-canonical load faults", t);
        ST_CHECK_EQ("  as a load page fault", g_trap_cause, CAUSE_LOAD_PAGE);
        t = probe_sd(va, PRV_S, 1);
        ST_CHECK("non-canonical store faults", t);
        ST_CHECK_EQ("  as a store page fault", g_trap_cause, CAUSE_STORE_PAGE);
    }

    st_section("SUM / MXR enable exactly what they should");
    {
        uint64_t va = next_va();
        map_page(g_root, va, g_frame, PTE_R | PTE_W | PTE_AD | PTE_U);
        sfence_all();
        ST_CHECK("S load of U page without SUM faults", access_faults(LD, va, PRV_S));
        csr_set(mstatus, MSTATUS_SUM);
        ST_CHECK("S load of U page with SUM ok", access_ok(LD, va, PRV_S));
        ST_CHECK("S store of U page with SUM ok", access_ok(ST, va, PRV_S));
        csr_clear(mstatus, MSTATUS_SUM);
        uint64_t vx = next_va();
        map_page(g_root, vx, g_frame, PTE_X | PTE_AD);
        sfence_all();
        ST_CHECK("X-only load without MXR faults", access_faults(LD, vx, PRV_S));
        csr_set(mstatus, MSTATUS_MXR);
        ST_CHECK("X-only load with MXR ok", access_ok(LD, vx, PRV_S));
        ST_CHECK("X-only store with MXR still faults", access_faults(ST, vx, PRV_S));
        csr_clear(mstatus, MSTATUS_MXR);
    }

    csr_write(satp, 0);
    sfence_all();
    return st_result();
}
