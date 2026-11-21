// @stress tier=pr seeds=2 build=no_spike duts=legacy,forte timeout=20000000
//
// st_smc_alias -- writing code through one virtual mapping and executing it
// through another (the W^X pattern of every JIT, of the kernel's text patching
// via a fixmap alias, and of module loading).
//
// The code frame is mapped RW (supervisor) at VA_W and RX (user) at VA_X.  The
// patch goes through VA_W; then fence.i (sfence.vma alone does NOT order stores
// against fetches) and the new code must execute at VA_X.  Also: remapping VA_X
// to a different, previously-prepared frame with only sfence.vma must switch the
// code (no fence.i needed: the bytes were fenced long ago).
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define VA_W 0xC0000000UL
#define VA_X 0xC8000000UL

int main(void) {
    st_init();
    uint64_t root = pt_new_identity_root(0);
    st_map_u_alias(root);
    uint64_t usp = st_u_alias((uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    uint64_t fr[2] = { frame_alloc(), frame_alloc() };
    map_page(root, VA_W, fr[0], PTE_R | PTE_W | PTE_AD);
    uint64_t *xslot = pt_slot(root, VA_X, 0);
    *xslot = pte_leaf(fr[0], PTE_R | PTE_X | PTE_U | PTE_A);
    csr_write(satp, satp_sv39(4, root));
    sfence_all();

    st_section("patch via the RW alias, run via the RX alias");
    uint64_t bad = 0;
    for (int i = 0; i < 64 * ST_SCALE; i++) {
        int32_t v = (int32_t)(st_rand() & 0x7fffffff);
        uint32_t hi = ((uint32_t)v + 0x800u) >> 12;
        uint64_t off = 8 * st_rand_range(64);
        /* write `lui a0; addiw a0; ret` through VA_W with S-mode stores */
        (void)probe_sw(VA_W + off, PRV_S, enc_u(hi & 0xfffff, 10, 0x37));
        (void)probe_sw(VA_W + off + 4, PRV_S, enc_i(v & 0xfff, 10, 0, 10, 0x1b));
        (void)probe_sw(VA_W + off + 8, PRV_S, ENC_RET);
        st_fence_i();
        uint64_t r = st_run_in_mode(PRV_U, (uint64_t (*)(uint64_t))(VA_X + off), 0, usp);
        if (r != (uint64_t)(int64_t)v) bad++;
    }
    ST_CHECK_EQ("every alias patch executed", bad, 0);

    st_section("switch the RX alias between prepared frames with sfence.vma only");
    for (int f = 0; f < 2; f++) {
        volatile uint32_t *c = (volatile uint32_t *)fr[f];
        c[0] = ENC_ADDI(10, 0, 100 + f);
        c[1] = ENC_RET;
    }
    st_fence_i();
    bad = 0;
    for (int i = 0; i < 40 * ST_SCALE; i++) {
        int f = i & 1;
        *xslot = pte_leaf(fr[f], PTE_R | PTE_X | PTE_U | PTE_A);
        sfence_va(VA_X);
        uint64_t r = st_run_in_mode(PRV_U, (uint64_t (*)(uint64_t))VA_X, 0, usp);
        if (r != (uint64_t)(100 + f)) bad++;
    }
    ST_CHECK_EQ("ITLB switched frames on every sfence.vma", bad, 0);

    st_section("RW alias of code must not be executable");
    uint64_t r = st_run_expect_abort(PRV_S, (uint64_t (*)(uint64_t))VA_W, 0, (uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    ST_CHECK_EQ("fetch via RW alias faults", r, ST_TRAP_ABORTED);
    ST_CHECK_EQ("  cause", g_trap_cause, CAUSE_FETCH_PAGE);

    csr_write(satp, 0);
    sfence_all();
    return st_result();
}
