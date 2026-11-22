// @stress tier=pr build=no_spike duts=legacy,forte timeout=2000000 xfail=pmp-partial-match ecc=no dummy=no pin=no
//
// st_pmp_partial -- KNOWN RTL DEVIATION (xfail): PMP partial-match rule.
//
// Privileged spec, PMP priority and matching: "The lowest-numbered PMP entry
// that matches any byte of an access determines whether that access succeeds
// or fails. The matching PMP entry must match all bytes of an access, or the
// access fails, irrespective of the L, R, W, and X bits."
//
// CVW's pmpadrdec matches on the access's base address only (its Size input
// is unused), so an access that starts inside entry N and ends outside it is
// decided by entry N's permissions.  hvl/mmu/pmp_stress_tb.sv reports the same
// deviation from random vectors; this is the directed system-level check.
//
// Setup (grain 0, so 4-byte NA4 regions are legal): entry 0 = NA4 at A (RW),
// entry 1 = NA4 at A+4 (no permissions), last entry = allow-all.  A is 8-byte
// aligned, so an 8-byte access at A is naturally aligned (misaligned accesses
// trap on this core before PMP) and covers both regions.  Accesses are made
// with U-mode permissions through MPRV, satp = Bare.
#include "../lib/stress.h"

static volatile uint32_t g_cell[2] ST_ALIGNED(8);

int main(void) {
    st_init();
    uint64_t a = (uint64_t)&g_cell[0];
    g_cell[0] = 0x11111111u;
    g_cell[1] = 0x22222222u;

    pmp_clear_all();
    pmp_write_addr(0, a >> 2);
    pmp_write_cfg(0, PMP_NA4 | PMP_R | PMP_W);
    pmp_write_addr(1, (a + 4) >> 2);
    pmp_write_cfg(1, PMP_NA4);                       /* no access for S/U */
    pmp_allow_all();
    csr_write(satp, 0);

    uint64_t v = 0;
    st_section("controls: each 4-byte region on its own");
    ST_CHECK_EQ("lw at A (entry 0, R) allowed", probe_lwu(a, PRV_U, &v), 0);
    ST_CHECK_EQ("  value", v, 0x11111111u);
    ST_CHECK_EQ("lw at A+4 (entry 1, no R) faults", probe_lwu(a + 4, PRV_U, &v), 1);
    ST_CHECK_EQ("  cause = load access fault", g_trap_cause, CAUSE_LOAD_ACCESS);
    ST_CHECK_EQ("sw at A+4 (entry 1, no W) faults", probe_sw(a + 4, PRV_U, 0), 1);
    ST_CHECK_EQ("  cause = store access fault", g_trap_cause, CAUSE_STORE_ACCESS);

    st_section("8-byte access partially matching entry 0 must fail");
    v = 0;
    ST_CHECK_EQ("ld at A faults", probe_ld(a, PRV_U, &v), 1);
    ST_CHECK_EQ("  cause = load access fault", g_trap_cause, CAUSE_LOAD_ACCESS);
    ST_CHECK_EQ("sd at A faults", probe_sd(a, PRV_U, 0x3333333344444444UL), 1);
    ST_CHECK_EQ("  cause = store access fault", g_trap_cause, CAUSE_STORE_ACCESS);
    ST_CHECK_EQ("bytes at A+4 unchanged", g_cell[1], 0x22222222u);
    ST_CHECK_EQ("bytes at A unchanged", g_cell[0], 0x11111111u);

    pmp_clear_all();
    pmp_allow_all();
    return st_result();
}
