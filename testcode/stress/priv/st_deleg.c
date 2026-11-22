// @stress tier=pr build=no_spike duts=legacy,forte timeout=8000000
//
// st_deleg -- trap delegation exactly as OpenSBI sets it up for Linux.
//
// Linux never sees M-mode: OpenSBI delegates U ecalls, breakpoints, page
// faults, misaligned and access faults and the S-level interrupts to S, and the
// kernel's stvec/sret path does the rest.  This test runs a small S-mode
// "kernel" (st_s_trap_entry) under that delegation and checks, for each cause:
//   - the trap lands in S (scause/sepc/stval), not in M;
//   - S-mode faults are handled in S too (delegation is by cause, not origin);
//   - interrupts M cannot delegate (MTIP) still go to M while S runs;
//   - delegated S interrupts preempt U even with sstatus.SIE = 0;
//   - TSR / TVM / TW turn sret, satp/sfence.vma and wfi in S into illegal-
//     instruction traps (the hooks a hypervisor-less monitor relies on).
#include "../lib/stress.h"

#define DELEG_SYNC ((1UL << CAUSE_FETCH_ACCESS) | (1UL << CAUSE_ILLEGAL) | (1UL << CAUSE_BREAKPOINT) | \
                    (1UL << CAUSE_MISALIGNED_LOAD) | (1UL << CAUSE_LOAD_ACCESS) |                     \
                    (1UL << CAUSE_MISALIGNED_STORE) | (1UL << CAUSE_STORE_ACCESS) |                   \
                    (1UL << CAUSE_ECALL_U) | (1UL << CAUSE_FETCH_PAGE) | (1UL << CAUSE_LOAD_PAGE) |   \
                    (1UL << CAUSE_STORE_PAGE))

#define USTACK ((uint64_t)(g_ustack + sizeof g_ustack))
static uint8_t g_ustack[8192] ST_ALIGNED(16);
static uint64_t g_label;
static volatile uint64_t g_buf[4] ST_ALIGNED(16);

/* ---- U-mode bodies ------------------------------------------------------ */
static uint64_t u_ecall(uint64_t a) {
    (void)a;
    __asm__ volatile (".option push\n.option norvc\nla t0, 1f\n sd t0, 0(%0)\n li a7, 0x77\n1: ecall\n.option pop"
                      :: "r"(&g_label) : "t0", "a7", "a0", "memory");
    return 1;
}
static uint64_t u_illegal(uint64_t a) {
    (void)a;
    __asm__ volatile (".option push\n.option norvc\nla t0, 1f\n sd t0, 0(%0)\n1: .word 0xc0002573\n.option pop"
                      :: "r"(&g_label) : "t0", "a0", "memory");
    return 2;
}
static uint64_t u_ebreak(uint64_t a) {
    (void)a;
    __asm__ volatile (".option push\n.option norvc\nla t0, 1f\n sd t0, 0(%0)\n1: ebreak\n.option pop"
                      :: "r"(&g_label) : "t0", "memory");
    return 3;
}
static uint64_t u_load(uint64_t va) { return *(volatile uint64_t *)va; }
static uint64_t u_store(uint64_t va) { *(volatile uint64_t *)va = 0x1122334455667788UL; return 0; }
static uint64_t u_spin(uint64_t n) { volatile uint64_t i = 0; while (i < n) i++; return i; }

/* ---- S-mode kernel ------------------------------------------------------ */
static volatile uint64_t g_s_ssi, g_s_ssi_spp, g_s_ssi_epc_in_u;

static int s_irq(st_frame_t *f) {
    if (f->cause == (CAUSE_INTR | IRQ_S_SOFT)) {
        g_s_ssi++;
        g_s_ssi_spp = (f->status & MSTATUS_SPP) ? 1 : 0;
        g_s_ssi_epc_in_u = f->epc;
        csr_clear(sip, MIP_SSIP);
        return 1;
    }
    return 0;
}

static void s_expect_u_trap(const char *what, uint64_t (*fn)(uint64_t), uint64_t arg,
                            uint64_t cause, int check_label) {
    uint64_t m_before = g_trap_count;
    st_s_expect(ST_EXPECT_ABORT);
    uint64_t r = st_s_run_user(fn, arg, USTACK);
    g_s_exp_mode = ST_EXPECT_NONE;
    ST_CHECK_EQ(what, r, ST_TRAP_ABORTED);
    ST_CHECK_EQ("  scause", g_s_trap_cause, cause);
    if (check_label) ST_CHECK_EQ("  sepc", g_s_trap_epc, g_label);
    /* Only the harness's own S->M round trips may have touched M (none here). */
    ST_CHECK_EQ("  not taken in M", g_trap_count, m_before);
}

static uint64_t s_main(uint64_t arg) {
    (void)arg;
    st_s_init();

    st_section("U traps delegated to S");
    s_expect_u_trap("U ecall -> S", u_ecall, 0, CAUSE_ECALL_U, 1);
    s_expect_u_trap("U illegal -> S", u_illegal, 0, CAUSE_ILLEGAL, 1);
    s_expect_u_trap("U ebreak -> S", u_ebreak, 0, CAUSE_BREAKPOINT, 1);
    s_expect_u_trap("U misaligned ld -> S", u_load, (uint64_t)&g_buf[0] + 1, CAUSE_MISALIGNED_LOAD, 0);
    ST_CHECK_EQ("  stval = address", g_s_trap_tval, (uint64_t)&g_buf[0] + 1);
    s_expect_u_trap("U misaligned sd -> S", u_store, (uint64_t)&g_buf[0] + 4, CAUSE_MISALIGNED_STORE, 0);
    ST_CHECK_EQ("  stval = address", g_s_trap_tval, (uint64_t)&g_buf[0] + 4);
    s_expect_u_trap("U ld hole -> S", u_load, ST_HOLE_ADDR, CAUSE_LOAD_ACCESS, 0);
    ST_CHECK_EQ("  stval = address", g_s_trap_tval, ST_HOLE_ADDR);
    s_expect_u_trap("U sd hole -> S", u_store, ST_HOLE_ADDR, CAUSE_STORE_ACCESS, 0);

    st_section("U page faults delegated to S, then fixed by S");
    /* S runs the identity map (supervisor-only); U runs the U alias. */
    uint64_t root = pt_new_identity_root(0);
    st_map_u_alias(root);
    uint64_t va = 0xC0000000UL, frame = frame_alloc();
    csr_write(satp, satp_sv39(5, root));
    sfence_all();
    uint64_t (*a_load)(uint64_t)  = (uint64_t (*)(uint64_t))st_u_alias((uint64_t)u_load);
    uint64_t (*a_store)(uint64_t) = (uint64_t (*)(uint64_t))st_u_alias((uint64_t)u_store);
    uint64_t usp = st_u_alias(USTACK);
    st_s_expect(ST_EXPECT_ABORT);
    ST_CHECK_EQ("U ld unmapped -> S", st_s_run_user(a_load, va, usp), ST_TRAP_ABORTED);
    ST_CHECK_EQ("  scause", g_s_trap_cause, CAUSE_LOAD_PAGE);
    ST_CHECK_EQ("  stval = va", g_s_trap_tval, va);
    st_s_expect(ST_EXPECT_ABORT);
    ST_CHECK_EQ("U sd unmapped -> S", st_s_run_user(a_store, va + 8, usp), ST_TRAP_ABORTED);
    ST_CHECK_EQ("  scause", g_s_trap_cause, CAUSE_STORE_PAGE);
    ST_CHECK_EQ("  stval = va", g_s_trap_tval, va + 8);
    map_page(root, va, frame, PTE_R | PTE_U | PTE_A);
    sfence_va(va);
    st_s_expect(ST_EXPECT_ABORT);
    ST_CHECK_EQ("U sd read-only -> S", st_s_run_user(a_store, va + 16, usp), ST_TRAP_ABORTED);
    ST_CHECK_EQ("  scause", g_s_trap_cause, CAUSE_STORE_PAGE);
    g_s_exp_mode = ST_EXPECT_NONE;
    map_page(root, va, frame, PTE_R | PTE_W | PTE_U | PTE_AD);
    sfence_va(va);
    ST_CHECK_EQ("U sd after fix", st_s_run_user(a_store, va + 24, usp), 0);
    ST_CHECK_EQ("U ld after fix", st_s_run_user(a_load, va + 24, usp), 0x1122334455667788UL);
    ST_CHECK_EQ("S sees the U store via identity", *(volatile uint64_t *)(frame + 24), 0x1122334455667788UL);
    csr_write(satp, 0);
    sfence_all();
    g_st_u_alias_off = 0;

    st_section("S-mode faults are delegated too");
    st_s_expect(ST_EXPECT_SKIP);
    __asm__ volatile (".option push\n.option norvc\nla t0, 1f\n sd t0, 0(%0)\n1: .word 0xc0002573\n.option pop"
                      :: "r"(&g_label) : "t0", "a0", "memory");
    ST_CHECK_EQ("S illegal -> S", g_s_trap_cause, CAUSE_ILLEGAL);
    ST_CHECK_EQ("  sepc", g_s_trap_epc, g_label);
    st_s_expect(ST_EXPECT_SKIP);
    __asm__ volatile (".option push\n.option norvc\nld t0, 0(%0)\n.option pop" :: "r"(ST_HOLE_ADDR) : "t0", "memory");
    ST_CHECK_EQ("S ld hole -> S", g_s_trap_cause, CAUSE_LOAD_ACCESS);
    ST_CHECK_EQ("  stval", g_s_trap_tval, ST_HOLE_ADDR);

    st_section("delegated SSIP preempts U even with SIE=0");
    g_s_irq_hook = s_irq;
    csr_clear(sstatus, MSTATUS_SIE);
    csr_set(sie, MIP_SSIP);
    csr_set(sip, MIP_SSIP);           /* pending, masked in S by SIE=0 */
    ST_CHECK_EQ("not taken in S with SIE=0", g_s_ssi, 0);
    uint64_t spun = st_s_run_user(u_spin, 50, USTACK);
    ST_CHECK_EQ("U body completed", spun, 50);
    ST_CHECK_EQ("SSI taken exactly once", g_s_ssi, 1);
    ST_CHECK_EQ("taken from U (SPP=0)", g_s_ssi_spp, 0);
    csr_set(sip, MIP_SSIP);
    ST_CHECK_EQ("still masked in S", g_s_ssi, 1);
    csr_set(sstatus, MSTATUS_SIE);    /* now enabled: taken immediately */
    st_compiler_barrier();
    csr_clear(sstatus, MSTATUS_SIE);
    ST_CHECK_EQ("taken in S once SIE=1", g_s_ssi, 2);
    ST_CHECK_EQ("taken from S (SPP=1)", g_s_ssi_spp, 1);
    csr_clear(sie, MIP_SSIP);
    return 0x5a;
}

/* ---- M-mode parts: MTIP while S runs, TSR/TVM/TW ------------------------ */
static volatile uint64_t g_m_timer;
static int m_timer_irq(st_frame_t *f) {
    if (f->cause == (CAUSE_INTR | IRQ_M_TIMER)) { g_m_timer++; st_timer_off(); return 1; }
    return 0;
}
static uint64_t s_spin(uint64_t n) { volatile uint64_t i = 0; while (i < n) i++; return 1; }
static uint64_t s_do_sret(uint64_t a)   { (void)a; __asm__ volatile (".word 0x10200073"); return 0; }
static uint64_t s_wr_satp(uint64_t a)   { (void)a; csr_write(satp, 0); return 0; }
static uint64_t s_rd_satp(uint64_t a)   { (void)a; return csr_read(satp); }
static uint64_t s_sfence(uint64_t a)    { (void)a; sfence_all(); return 0; }
static uint64_t s_wfi(uint64_t a)       { (void)a; st_wfi(); return 0; }

static void m_expect_s_illegal(const char *what, uint64_t (*fn)(uint64_t)) {
    uint64_t r = st_run_expect_abort(PRV_S, fn, 0, (uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    ST_CHECK_EQ(what, r, ST_TRAP_ABORTED);
    ST_CHECK_EQ("  cause illegal (in M)", g_trap_cause, CAUSE_ILLEGAL);
}

int main(void) {
    st_init();
    csr_write(medeleg, DELEG_SYNC);
    csr_write(mideleg, MIP_SSIP | MIP_STIP | MIP_SEIP);
    ST_CHECK_EQ("S kernel ran", st_run(PRV_S, s_main, 0), 0x5a);

    st_section("MTIP is never delegated: taken in M while S runs");
    g_m_irq_hook = m_timer_irq;
    csr_set(mie, MIP_MTIP);
    st_set_mtimecmp(st_mtime() + 200);
    ST_CHECK_EQ("S body completed", st_run(PRV_S, s_spin, 3000), 1);
    ST_CHECK_EQ("M timer taken once", g_m_timer, 1);
    csr_clear(mie, MIP_MTIP);

    /* For these the illegal-instruction trap must reach M, not the S kernel. */
    csr_write(medeleg, 0);

    st_section("TSR: sret in S traps");
    csr_set(mstatus, MSTATUS_TSR);
    m_expect_s_illegal("sret with TSR", s_do_sret);
    csr_clear(mstatus, MSTATUS_TSR);

    st_section("TVM: satp and sfence.vma in S trap");
    csr_set(mstatus, MSTATUS_TVM);
    m_expect_s_illegal("satp write with TVM", s_wr_satp);
    m_expect_s_illegal("satp read with TVM", s_rd_satp);
    m_expect_s_illegal("sfence.vma with TVM", s_sfence);
    csr_clear(mstatus, MSTATUS_TVM);
    ST_CHECK_EQ("satp readable in S without TVM", st_run(PRV_S, s_rd_satp, 0), 0);

    st_section("TW: wfi in S traps (no interrupt pending)");
    csr_set(mstatus, MSTATUS_TW);
    m_expect_s_illegal("wfi with TW", s_wfi);
    csr_clear(mstatus, MSTATUS_TW);

    return st_result();
}
