// @stress tier=pr build=no_spike duts=legacy,forte timeout=2000000 ecc=no dummy=no pin=no
//
// st_pmp_partial -- the PMP partial-match rule (Priv. spec, PMP priority and
// matching): "The matching PMP entry must match all bytes of an access, or the
// access fails, irrespective of the L, R, W, and X bits."
//
// The checker (pmpadrdec) decides an access by its base address, which is
// exact only if no access can straddle a PMP grain.  The chip therefore uses a
// grain of one cache line (pkg/config.vh PMP_G = 2, 16 B):
//   * data accesses are naturally aligned (misaligned ones trap first) and at
//     most 8 bytes, so they never cross a grain;
//   * a fetch never crosses a grain inside a line, and one that crosses a line
//     is split by the IFU into two fetches, each checked -- the first half's
//     fault is kept (ifu.sv firsthalffaultreg) with mtval = PC.
// With G = 0 (4-byte NA4/TOR regions) an 8-byte access starting in an R/W word
// and ending in a no-access word was decided by the first word's entry; this
// test asserts the configuration that makes that impossible, then checks
// accesses and straddling fetches at grain boundaries.  Accesses are made with
// U-mode permissions (MPRV probes / U-mode runs), satp = Bare.
#include "../lib/stress.h"

#define GRAIN 16UL

static volatile uint64_t g_cell[4] ST_ALIGNED(32);     /* two grains */
static uint16_t g_code[16] ST_ALIGNED(32);              /* two grains (= two I$ lines) of code */

static uint64_t ctz64(uint64_t v) { uint64_t n = 0; while (v && !(v & 1)) { v >>= 1; n++; } return n; }

static void fetch_case(const char *what, uint64_t deny_base, uint64_t code, int expect_fault, uint64_t tval) {
    pmp_clear_all();
    if (deny_base) {                                    /* that grain: readable, not executable */
        pmp_write_addr(0, pmp_napot_addr(deny_base, GRAIN));
        pmp_write_cfg(0, PMP_NAPOT | PMP_R);
    }
    pmp_allow_all();
    uint64_t r = st_run_expect_abort(PRV_U, (uint64_t (*)(uint64_t))(code + GRAIN - 2), 5,
                                     (uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    if (!expect_fault) { ST_CHECK_EQ(what, r, 6); return; }
    ST_CHECK_EQ(what, r, ST_TRAP_ABORTED);
    if (r == ST_TRAP_ABORTED) {
        ST_CHECK_EQ("  cause = fetch access fault", g_trap_cause, CAUSE_FETCH_ACCESS);
        ST_CHECK_EQ("  tval = address of the denied half", g_trap_tval, tval);
    }
}

int main(void) {
    st_init();
    csr_write(satp, 0);

    st_section("grain: one cache line, NA4 not selectable");
    pmp_clear_all();
    pmp_write_addr(0, ~0UL);                            /* OFF: the low G bits read as 0 */
    uint64_t g = ctz64(pmp_read_addr(0));
    ST_CHECK_EQ("G read back from pmpaddr0", g, AMOEBA_PMP_G);
    ST_CHECK("grain covers an I$/D$ line and the widest access", (4UL << g) >= GRAIN);
    pmp_write_cfg(0, PMP_NA4 | PMP_R);
    ST_CHECK_EQ("pmpcfg.A = NA4 is not retained (WARL)", csr_read(pmpcfg0) & 0x18, PMP_OFF);

    uint64_t a = (uint64_t)&g_cell[0];
    g_cell[0] = 0x1111111111111111UL; g_cell[1] = 0x2222222222222222UL;
    g_cell[2] = 0x3333333333333333UL; g_cell[3] = 0x4444444444444444UL;
    pmp_clear_all();
    pmp_write_addr(0, pmp_napot_addr(a, GRAIN));         pmp_write_cfg(0, PMP_NAPOT | PMP_R | PMP_W);
    pmp_write_addr(1, pmp_napot_addr(a + GRAIN, GRAIN)); pmp_write_cfg(1, PMP_NAPOT);   /* no access */
    pmp_allow_all();

    uint64_t v = 0;
    st_section("8-byte accesses on either side of a grain boundary");
    ST_CHECK_EQ("ld at A+8 (last dword of the R/W grain) allowed", probe_ld(a + 8, PRV_U, &v), 0);
    ST_CHECK_EQ("  value", v, 0x2222222222222222UL);
    ST_CHECK_EQ("sd at A+8 allowed", probe_sd(a + 8, PRV_U, 0x5555555555555555UL), 0);
    ST_CHECK_EQ("  stored", g_cell[1], 0x5555555555555555UL);
    ST_CHECK_EQ("ld at A+16 (no-access grain) faults", probe_ld(a + GRAIN, PRV_U, &v), 1);
    ST_CHECK_EQ("  cause = load access fault", g_trap_cause, CAUSE_LOAD_ACCESS);
    ST_CHECK_EQ("sd at A+16 faults", probe_sd(a + GRAIN, PRV_U, 0x6666666666666666UL), 1);
    ST_CHECK_EQ("  cause = store access fault", g_trap_cause, CAUSE_STORE_ACCESS);
    ST_CHECK_EQ("  no-access grain unchanged", g_cell[2], 0x3333333333333333UL);

    st_section("32-bit instruction straddling two grains (and two I$ lines)");
    uint64_t c = (uint64_t)&g_code[0];
    g_code[GRAIN / 2 - 1] = (uint16_t)0x00150513u;          /* addi a0,a0,1: low half, end of grain 0 */
    g_code[GRAIN / 2]     = (uint16_t)(0x00150513u >> 16);  /*               high half, grain 1 */
    st_put_insn32(c + GRAIN + 2, ENC_RET);
    st_fence_i();
    fetch_case("control: both grains executable", 0, c, 0, 0);
    fetch_case("second grain not executable: faults", c + GRAIN, c, 1, c + GRAIN);
    fetch_case("first grain not executable: faults", c, c, 1, c + GRAIN - 2);

    pmp_clear_all();
    pmp_allow_all();
    return st_result();
}
