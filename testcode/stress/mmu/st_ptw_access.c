// @stress tier=pr build=no_spike duts=legacy,forte timeout=20000000
//
// st_ptw_access -- access faults raised by the page-table walker itself, and
// by the final physical access after a successful walk.
//
// The walker's implicit reads are S-mode accesses checked by PMP and PMA.  A
// page table placed (by a buggy or malicious kernel) in a hole, or in memory
// that PMP denies to S, must produce an ACCESS fault of the original access
// type (fetch 1 / load 5 / store 7) -- not a page fault, not a hang, not data
// from somewhere else.  OpenSBI relies on PMP protecting its own memory from
// exactly these implicit accesses.
#include "../lib/stress.h"

#define VA 0xC0000000UL

static uint64_t g_usp;

static void expect_access(const char *what, uint64_t va, uint64_t prv) {
    uint64_t v;
    int t = probe_ld(va, prv, &v);
    if (!t || g_trap_cause != CAUSE_LOAD_ACCESS) st_check_failed(what, g_trap_cause, CAUSE_LOAD_ACCESS, 5);
    else g_st_pass++;
    t = probe_sd(va + 8, prv, 1);
    if (!t || g_trap_cause != CAUSE_STORE_ACCESS) st_check_failed(what, g_trap_cause, CAUSE_STORE_ACCESS, 7);
    else g_st_pass++;
    uint64_t r = st_run_expect_abort(prv, (uint64_t (*)(uint64_t))va, 0, prv == PRV_U ? g_usp : (uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    if (r != ST_TRAP_ABORTED || g_trap_cause != CAUSE_FETCH_ACCESS) st_check_failed(what, g_trap_cause, CAUSE_FETCH_ACCESS, 1);
    else g_st_pass++;
}

int main(void) {
    st_init();
    uint64_t root = pt_new_identity_root(0);
    st_map_u_alias(root);
    g_usp = st_u_alias((uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    uint64_t data = frame_alloc();
    *(volatile uint64_t *)data = 0xda7a;

    st_section("satp root in a hole");
    csr_write(satp, satp_sv39(1, ST_HOLE_ADDR));
    sfence_all();
    expect_access("root table in hole", VA, PRV_S);

    st_section("level-1 pointer into a hole");
    csr_write(satp, satp_sv39(1, root));
    *pt_slot(root, VA, 2) = pte_table(ST_HOLE_ADDR);
    sfence_all();
    expect_access("L1 table in hole", VA, PRV_S);
    expect_access("L1 table in hole (U)", VA, PRV_U);

    st_section("leaf points into a hole");
    *pt_slot(root, VA, 2) = 0;                       /* rebuild a real chain */
    map_page(root, VA, ST_HOLE_ADDR, PTE_RWX | PTE_AD);
    sfence_all();
    expect_access("leaf PA in hole", VA, PRV_S);

    st_section("PMP denies the level-0 table to S/U");
    uint64_t *leaf = pt_slot(root, VA, 0);
    *leaf = pte_leaf(data, PTE_RWX | PTE_AD | PTE_U);
    uint64_t l0 = (uint64_t)leaf & ~(ST_PAGE - 1);
    sfence_all();
    uint64_t v = 0;
    ST_CHECK_EQ("walk works before PMP", probe_ld(VA, PRV_U, &v), 0);
    ST_CHECK_EQ("  data", v, 0xda7a);
    pmp_write_addr(0, pmp_napot_addr(l0, ST_PAGE));
    pmp_write_cfg(0, PMP_NAPOT);                     /* no R/W/X for S/U */
    sfence_all();
    expect_access("L0 table PMP-denied", VA, PRV_U);
    expect_access("L0 table PMP-denied (S)", VA, PRV_S);
    ST_CHECK_EQ("M still reads the table (no L bit)", *leaf, pte_leaf(data, PTE_RWX | PTE_AD | PTE_U));

    st_section("PMP denies the final frame, not the tables");
    pmp_write_addr(0, pmp_napot_addr(data, ST_PAGE));
    pmp_write_cfg(0, PMP_NAPOT | PMP_R);             /* read-only, no exec */
    sfence_all();
    ST_CHECK_EQ("load allowed", probe_ld(VA, PRV_U, &v), 0);
    ST_CHECK_EQ("store refused by PMP", probe_sd(VA, PRV_U, 1), 1);
    ST_CHECK_EQ("  as a store ACCESS fault", g_trap_cause, CAUSE_STORE_ACCESS);
    ST_CHECK_EQ("  data unchanged", *(volatile uint64_t *)data, 0xda7a);
    uint64_t r = st_run_expect_abort(PRV_U, (uint64_t (*)(uint64_t))VA, 0, g_usp);
    ST_CHECK_EQ("fetch refused by PMP", r, ST_TRAP_ABORTED);
    ST_CHECK_EQ("  as a fetch ACCESS fault", g_trap_cause, CAUSE_FETCH_ACCESS);
    pmp_write_cfg(0, PMP_OFF);
    sfence_all();

    st_section("MMIO through a page mapping");
    uint64_t vm = VA + 0x200000;
    map_page(root, vm, CLINT_BASE + 0xb000, PTE_R | PTE_W | PTE_AD);
    sfence_all();
    uint64_t t0 = 0, t1 = 0;
    ST_CHECK_EQ("mtime readable via VA", probe_ld(vm + 0xff8, PRV_S, &t0), 0);
    ST_CHECK_EQ("mtime readable again", probe_ld(vm + 0xff8, PRV_S, &t1), 0);
    ST_CHECK("mtime advances through the mapping", t1 > t0);

    csr_write(satp, 0);
    sfence_all();
    return st_result();
}
