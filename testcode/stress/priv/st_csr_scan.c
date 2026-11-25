// @stress tier=pr build=no_spike duts=legacy timeout=30000000
//
// st_csr_scan -- all 4096 CSR addresses, read from M, S and U.
//
// A CSR that exists when it should not (a counter on a core with no Zicntr, an
// FP CSR with no FPU) makes software believe in hardware that is not there; one
// that is reachable from a lower privilege than its address encodes is a
// security hole; a read-only CSR that accepts a write corrupts state.  The
// legal/illegal answer for every address is checked against properties that
// follow from the privileged spec plus pkg/config.vh, rather than against a
// hand-written table that would go stale:
//   1. address bits [9:8] give the lowest privilege allowed to touch the CSR
//   2. legal in U  =>  legal in S  =>  legal in M   (except satp under TVM)
//   3. CSRs of absent extensions are illegal everywhere
//   4. CSRs Linux/OpenSBI require are legal where they must be
//   5. every legal read-only CSR (bits [11:10] = 3) rejects a write attempt
//   6. a WRITE that does not read (csrrw x0, N) to a CSR that is illegal in the
//      current mode traps too -- privilege and existence are checked on writes,
//      not only on reads.  Only CSRs the read scan found illegal in that mode are
//      probed, so nothing real is ever written.
//
// The probes come from an assembler-generated table -- entry N is
// `csrrs a0, N, x0 ; ret` at 8 * N -- so no self-modifying code is involved.
#include "../lib/stress.h"

extern char st_csr_rd_table[];
extern char st_csr_wr_table[];
extern char st_csr_wo_table[];
static uint64_t wo_probe(uint64_t csr) {
    ((uint64_t (*)(uint64_t, uint64_t))(void *)(st_csr_wo_table + 8 * csr))(0, 0);
    return 0x1e9a1;
}
/* 1 if `csrrw x0, csr, x0` traps with an illegal instruction in mode prv. */
static int wo_traps(uint64_t csr, uint64_t prv) {
    if (prv == PRV_M) {
        st_expect(ST_EXPECT_SKIP);
        g_exp_resume = (uint64_t)(void *)(st_csr_wo_table + 8 * csr + 4);   /* the ret after it */
        wo_probe(csr);
        st_expect_clear();
        return st_trapped() && g_trap_cause == CAUSE_ILLEGAL;
    }
    uint64_t r = st_run_expect_abort(prv, wo_probe, csr, (uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    return r == ST_TRAP_ABORTED && g_trap_cause == CAUSE_ILLEGAL;
}
__asm__ (
    ".text\n.option push\n.option norvc\n.balign 8\n"
    ".globl st_csr_rd_table\n"
    "st_csr_rd_table:\n"
    ".set st_csr_n, 0\n"
    ".rept 4096\n"
    "    csrrs a0, st_csr_n, x0\n"
    "    ret\n"
    "    .set st_csr_n, st_csr_n + 1\n"
    ".endr\n"
    /* write attempts on the read-only half (0xc00-0xfff): csrrs x0, N, a1
     * with a1 = 0 changes no bits but is architecturally a write. */
    /* write-only probes: csrrw x0, N, x0 (rd = x0, so the CSR is NOT read) */
    ".globl st_csr_wo_table\n"
    "st_csr_wo_table:\n"
    ".set st_csr_n, 0\n"
    ".rept 4096\n"
    "    csrrw x0, st_csr_n, x0\n"
    "    ret\n"
    "    .set st_csr_n, st_csr_n + 1\n"
    ".endr\n"
    ".globl st_csr_wr_table\n"
    "st_csr_wr_table:\n"
    ".set st_csr_n, 0xc00\n"
    ".rept 1024\n"
    "    csrrs x0, st_csr_n, a1\n"
    "    ret\n"
    "    .set st_csr_n, st_csr_n + 1\n"
    ".endr\n"
    ".option pop\n"
);

static uint8_t g_legal[3][4096];   /* [0]=U [1]=S [2]=M */

static uint64_t probe_rd(uint64_t csr) {
    uint64_t (*fn)(uint64_t, uint64_t) = (uint64_t (*)(uint64_t, uint64_t))(void *)(st_csr_rd_table + 8 * csr);
    return fn(0, 0);
}
static uint64_t lower_probe(uint64_t csr) { probe_rd(csr); return 0x1e9a1; }

static int legal_in_m(uint64_t csr) {
    st_expect(ST_EXPECT_SKIP);
    probe_rd(csr);
    st_expect_clear();
    return !st_trapped();
}
static int legal_in_lower(uint64_t csr, uint64_t prv) {
    uint64_t r = st_run_expect_abort(prv, lower_probe, csr, (uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    if (r == ST_TRAP_ABORTED) {
        if (g_trap_cause != CAUSE_ILLEGAL) {
            st_check_failed("lower-mode CSR probe trapped with a non-illegal cause", g_trap_cause, csr, __LINE__);
        }
        return 0;
    }
    return r == 0x1e9a1;
}

static void expect_illegal_range(const char *what, unsigned lo, unsigned hi) {
    for (unsigned c = lo; c <= hi; c++) {
        if (g_legal[2][c] | g_legal[1][c] | g_legal[0][c]) st_check_failed(what, c, 0, __LINE__);
        else g_st_pass++;
    }
}
static void expect_legal(const char *what, unsigned csr, int min_prv) {
    for (int p = 2; p >= 0; p--) {
        int prv = p == 2 ? PRV_M : p;
        int want = prv >= min_prv;
        if (g_legal[p][csr] != want) st_check_failed(what, ((uint64_t)prv << 16) | csr, want, __LINE__);
        else g_st_pass++;
    }
}

int main(void) {
    st_init();

    st_section("probe 4096 CSRs x {M,S,U}");
    unsigned n_m = 0, n_s = 0, n_u = 0;
    for (unsigned c = 0; c < 4096; c++) {
        g_legal[2][c] = (uint8_t)legal_in_m(c);
        g_legal[1][c] = (uint8_t)legal_in_lower(c, PRV_S);
        g_legal[0][c] = (uint8_t)legal_in_lower(c, PRV_U);
        n_m += g_legal[2][c]; n_s += g_legal[1][c]; n_u += g_legal[0][c];
    }
    st_puts("[ST] legal CSRs: M="); st_putdec(n_m); st_puts(" S="); st_putdec(n_s);
    st_puts(" U="); st_putdec(n_u); st_putc('\n');
    st_puts("[ST] M-legal list:");
    for (unsigned c = 0; c < 4096; c++) if (g_legal[2][c]) { st_putc(' '); st_puthex(c); }
    st_putc('\n');

    st_section("privilege encoded in address bits [9:8]");
    for (unsigned c = 0; c < 4096; c++) {
        unsigned lvl = (c >> 8) & 3;
        if (lvl > PRV_S && g_legal[1][c]) st_check_failed("S reached a CSR above S", c, 0, __LINE__); else g_st_pass++;
        if (lvl > PRV_U && g_legal[0][c]) st_check_failed("U reached a CSR above U", c, 0, __LINE__); else g_st_pass++;
    }

    st_section("monotonic: legal in U => S => M");
    for (unsigned c = 0; c < 4096; c++) {
        if (g_legal[0][c] && !g_legal[1][c]) st_check_failed("legal in U but not S", c, 0, __LINE__); else g_st_pass++;
        if (g_legal[1][c] && !g_legal[2][c]) st_check_failed("legal in S but not M", c, 0, __LINE__); else g_st_pass++;
    }

    st_section("absent extensions have no CSRs");
    expect_illegal_range("F/D CSRs (fflags/frm/fcsr)", 0x001, 0x003);
    expect_illegal_range("vector CSRs", 0x008, 0x00f);
    expect_illegal_range("vector CSRs (vl/vtype/vlenb)", 0xc20, 0xc22);
#if !AMOEBA_HAS_COUNTERS
    expect_illegal_range("user counters (no Zicntr/Zihpm)", 0xc00, 0xc1f);
#endif
    expect_illegal_range("RV32-only counter halves", 0xc80, 0xc9f);
    expect_illegal_range("stimecmp/stimecmph (no Sstc)", 0x14d, 0x14d);
    expect_illegal_range("stimecmph", 0x15d, 0x15d);
    expect_illegal_range("hypervisor CSRs (0x6xx)", 0x600, 0x6ff);
    expect_illegal_range("VS CSRs (0x2xx)", 0x200, 0x2ff);
    expect_illegal_range("debug-mode-only CSRs", 0x7b0, 0x7bf);
    expect_illegal_range("pmpcfg1 (RV32 only)", 0x3a1, 0x3a1);
    expect_illegal_range("pmpcfg3 (RV32 only)", 0x3a3, 0x3a3);

    st_section("required CSRs are present");
    static const struct { unsigned csr; int min; const char *n; } req[] = {
        { 0x100, PRV_S, "sstatus" }, { 0x104, PRV_S, "sie" },    { 0x105, PRV_S, "stvec" },
        { 0x140, PRV_S, "sscratch"}, { 0x141, PRV_S, "sepc" },   { 0x142, PRV_S, "scause" },
        { 0x143, PRV_S, "stval" },   { 0x144, PRV_S, "sip" },    { 0x180, PRV_S, "satp" },
        { 0x300, PRV_M, "mstatus" }, { 0x301, PRV_M, "misa" },   { 0x302, PRV_M, "medeleg" },
        { 0x303, PRV_M, "mideleg" }, { 0x304, PRV_M, "mie" },    { 0x305, PRV_M, "mtvec" },
        { 0x340, PRV_M, "mscratch"}, { 0x341, PRV_M, "mepc" },   { 0x342, PRV_M, "mcause" },
        { 0x343, PRV_M, "mtval" },   { 0x344, PRV_M, "mip" },    { 0x3a0, PRV_M, "pmpcfg0" },
        { 0x3a2, PRV_M, "pmpcfg2" }, { 0xf11, PRV_M, "mvendorid"},{ 0xf12, PRV_M, "marchid" },
        { 0xf13, PRV_M, "mimpid" },  { 0xf14, PRV_M, "mhartid" },
        { 0x7c0, PRV_M, "AMOEBA msecfault" }, { 0x7c1, PRV_M, "AMOEBA randinstrfreq" },
        { 0x7c2, PRV_M, "AMOEBA mftstatus" },
    };
    for (unsigned i = 0; i < ST_ARRAY_LEN(req); i++) expect_legal(req[i].n, req[i].csr, req[i].min);
    for (unsigned i = 0; i < AMOEBA_PMP_ENTRIES; i++) expect_legal("pmpaddrN", 0x3b0 + i, PRV_M);

    st_section("read-only CSRs reject writes (from M)");
    for (unsigned c = 0xc00; c < 0x1000; c++) {
        if (!g_legal[2][c]) continue;
        uint64_t (*fn)(uint64_t, uint64_t) = (uint64_t (*)(uint64_t, uint64_t))(void *)(st_csr_wr_table + 8 * (c - 0xc00));
        st_expect(ST_EXPECT_SKIP);
        fn(0, 0);
        st_expect_clear();
        if (g_trap_cause != CAUSE_ILLEGAL) st_check_failed("write to read-only CSR accepted", c, CAUSE_ILLEGAL, __LINE__);
        else g_st_pass++;
    }

    st_section("a write that does not read (rd = x0) is privilege- and existence-checked too");
    {
        uint64_t missed[3] = { 0, 0, 0 }, probed[3] = { 0, 0, 0 };
        for (int p = 2; p >= 0; p--) {
            uint64_t prv = p == 2 ? PRV_M : (uint64_t)p;
            for (unsigned c = 0; c < 4096; c++) {
                if (g_legal[p][c]) continue;              /* never write a CSR that exists here */
                /* Every S- and M-level CSR (0x1xx, 0x3xx, custom 0x7c0-0x7ff) -- the
                 * ones a lower mode must not reach -- and every 16th address
                 * elsewhere: all 4096 in three modes is ~10x the run's budget. */
                int important = (c >> 8) == 0x1 || (c >> 8) == 0x3 || (c >= 0x7c0 && c <= 0x7ff);
                if (!important && (c & 15)) continue;
                probed[p]++;
                if (!wo_traps(c, prv)) {
                    if (missed[p] < 4) st_check_failed("csrrw x0 to a CSR illegal in this mode did not trap",
                                                       ((uint64_t)prv << 16) | c, CAUSE_ILLEGAL, __LINE__);
                    missed[p]++;
                }
            }
        }
        st_puts("[ST] write-only probes: M "); st_putdec(probed[2]); st_puts(" S "); st_putdec(probed[1]);
        st_puts(" U "); st_putdec(probed[0]); st_puts("; not trapped: M "); st_putdec(missed[2]);
        st_puts(" S "); st_putdec(missed[1]); st_puts(" U "); st_putdec(missed[0]); st_putc('\n');
        ST_CHECK_EQ("every write-only probe of an illegal CSR trapped (M)", missed[2], 0);
        ST_CHECK_EQ("every write-only probe of an illegal CSR trapped (S)", missed[1], 0);
        ST_CHECK_EQ("every write-only probe of an illegal CSR trapped (U)", missed[0], 0);
    }

    return st_result();
}
