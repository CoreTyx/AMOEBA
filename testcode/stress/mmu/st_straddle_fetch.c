// @stress tier=pr build=no_spike duts=legacy,forte timeout=8000000 ecc=no dummy=no pin=no
//
// st_straddle_fetch -- a 32-bit instruction that straddles a page boundary
// must fault when EITHER page denies the fetch.  Regression test for an IFU
// bug (fixed in ifu.sv, firsthalffaultreg): only the second page's PTE was
// checked.  Original report:
//
// Found by riscv-tests rv64uc-v-rvc (the v env's evict() asserts PTE.A of a
// page that was executed from), reduced to this test.  With the instruction
// `addi a0,a0,1` at VA 0xC0000ffe (first half in page 0, second in page 1),
// run from U-mode, the core:
//   page 0 X=0                 executes it        (must: fetch page fault)
//   page 0 U=0 (supervisor)    executes it        (must: fetch page fault)
//   page 0 A=0 (Svade)         executes it        (must: fetch page fault)
//   page 0 V=0                 faults, tval = 0xC0000ffe   (correct)
//   page 1 A=0 / X=0 / V=0     faults, tval = 0xC0001000   (correct)
// so U-mode can execute bytes from non-executable or supervisor-only memory,
// and Svade A-bit tracking is lost for such pages.  Spike faults in every
// case.
#include "../lib/stress.h"

#define VA 0xC0000000UL

static uint64_t *g_pte[2];
static uint64_t g_usp;

static void setup(uint64_t b0, uint64_t b1, uint64_t fr0, uint64_t fr1) {
    *g_pte[0] = b0 ? pte_leaf(fr0, b0) : 0;
    *g_pte[1] = b1 ? pte_leaf(fr1, b1) : 0;
    sfence_all();
}

static void expect_cause(const char *what, uint64_t cause, uint64_t tval) {
    uint64_t r = st_run_expect_abort(PRV_U, (uint64_t (*)(uint64_t))(VA + 0xffe), 5, g_usp);
    st_puts("  "); st_puts(what);
    if (r == ST_TRAP_ABORTED) { st_puts(": fault cause "); st_putdec(g_trap_cause); st_puts(" tval "); st_puthex(g_trap_tval); }
    else { st_puts(": EXECUTED (returned "); st_putdec(r); st_putc(')'); }
    st_putc('\n');
    ST_CHECK_EQ(what, r, ST_TRAP_ABORTED);
    if (r == ST_TRAP_ABORTED) {
        ST_CHECK_EQ("  cause", g_trap_cause, cause);
        ST_CHECK_EQ("  tval", g_trap_tval, tval);
    }
}
static void expect_fault(const char *what, uint64_t tval) { expect_cause(what, CAUSE_FETCH_PAGE, tval); }

int main(void) {
    st_init();
    uint64_t root = pt_new_identity_root(0);
    st_map_u_alias(root);
    g_usp = st_u_alias((uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    uint64_t fr0 = frame_alloc(), fr1 = frame_alloc();
    *(volatile uint16_t *)(fr0 + 0xffe) = (uint16_t)0x00150513u;          /* addi a0,a0,1 (low half) */
    *(volatile uint16_t *)(fr1 + 0) = (uint16_t)(0x00150513u >> 16);      /*              (high half) */
    st_put_insn32(fr1 + 2, ENC_RET);
    st_fence_i();
    g_pte[0] = pt_slot(root, VA, 0);
    g_pte[1] = pt_slot(root, VA + ST_PAGE, 0);
    csr_write(satp, satp_sv39(0, root));
    const uint64_t ok = PTE_R | PTE_X | PTE_U | PTE_A;

    st_section("control: both pages executable");
    setup(ok, ok, fr0, fr1);
    ST_CHECK_EQ("straddling instruction runs", st_run_in_mode(PRV_U, (uint64_t (*)(uint64_t))(VA + 0xffe), 5, g_usp), 6);

    st_section("second page denies the fetch");
    setup(ok, 0, fr0, fr1);                              expect_fault("page 1 V=0", VA + ST_PAGE);
    setup(ok, PTE_R | PTE_U | PTE_A, fr0, fr1);          expect_fault("page 1 X=0", VA + ST_PAGE);
    setup(ok, PTE_R | PTE_X | PTE_U, fr0, fr1);          expect_fault("page 1 A=0", VA + ST_PAGE);

    st_section("first page denies the fetch");
    setup(0, ok, fr0, fr1);                              expect_fault("page 0 V=0", VA + 0xffe);
    setup(PTE_R | PTE_U | PTE_A, ok, fr0, fr1);          expect_fault("page 0 X=0", VA + 0xffe);
    setup(PTE_R | PTE_X | PTE_A, ok, fr0, fr1);          expect_fault("page 0 U=0 (supervisor page)", VA + 0xffe);
    setup(PTE_R | PTE_X | PTE_U, ok, fr0, fr1);          expect_fault("page 0 A=0 (Svade)", VA + 0xffe);

    // The same faults a second time with no sfence in between: wherever the walker
    // cached the translation, the check now comes from the TLB-hit path.
    st_section("again with nothing flushed (TLB-hit path)");
    setup(PTE_R | PTE_U | PTE_A, ok, fr0, fr1);          expect_fault("page 0 X=0", VA + 0xffe);
                                                         expect_fault("page 0 X=0, again", VA + 0xffe);
    setup(ok, PTE_R | PTE_U | PTE_A, fr0, fr1);          expect_fault("page 1 X=0", VA + ST_PAGE);
                                                         expect_fault("page 1 X=0, again", VA + ST_PAGE);

    st_section("both pages deny: the first half's fault wins");
    setup(PTE_R | PTE_U | PTE_A, PTE_R | PTE_U | PTE_A, fr0, fr1); expect_fault("both X=0", VA + 0xffe);
    setup(0, 0, fr0, fr1);                               expect_fault("both V=0", VA + 0xffe);

    // First half from the TLB (the control run cached page 0), second half walks
    // and finds no mapping: flush page 1 only.
    st_section("first half cached, second half's walk faults");
    setup(ok, ok, fr0, fr1);
    ST_CHECK_EQ("warm both pages", st_run_in_mode(PRV_U, (uint64_t (*)(uint64_t))(VA + 0xffe), 5, g_usp), 6);
    *g_pte[1] = 0;
    sfence_va(VA + ST_PAGE);
    expect_fault("page 1 V=0, page 0 cached", VA + ST_PAGE);

    // The first half is denied by PMP (an access fault, no page walk involved)
    // while the second page has no mapping (a page fault from its walk).  The
    // first half is checked first, so the access fault must be reported, at the
    // instruction's address -- not the walker's page fault for the second page.
    st_section("first half PMP-denied, second half unmapped");
    setup(ok, 0, fr0, fr1);
    pmp_write_addr(0, pmp_napot_addr(fr0, ST_PAGE));
    pmp_write_cfg(0, PMP_NAPOT | PMP_R | PMP_W);         // frame 0: no execute
    sfence_all();
    expect_cause("page 0 frame PMP no-X, page 1 V=0", CAUSE_FETCH_ACCESS, VA + 0xffe);
    pmp_write_cfg(0, 0);
    sfence_all();

    csr_write(satp, 0);
    sfence_all();
    return st_result();
}
