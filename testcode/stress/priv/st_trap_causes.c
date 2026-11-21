// @stress tier=pr build=no_spike duts=legacy,forte timeout=4000000
//
// st_trap_causes -- every synchronous exception the shipped core can raise,
// from every privilege mode, with exact mcause / mepc and a legal mtval.
//
// The chip is RV64IMAC with no counters, no Sstc, no F/D/Zb/Zk (pkg/config.vh),
// while programs are compiled -march=rv64gc.  If an instruction from one of the
// missing extensions ever executed instead of trapping, compiled code that
// accidentally emits it (or a userland binary built for a bigger core) would
// silently compute garbage after tapeout.  So every "absent" encoding here must
// raise an illegal-instruction exception with the right PC, from M, S and U.
#include "../lib/stress.h"

/* One instruction, executed via a probe that records the trap and skips it. */
#define EXEC32(enc) __asm__ volatile (".option push\n.option norvc\n.word " #enc "\n.option pop" ::: "memory")

typedef struct { const char *name; uint32_t enc; int len; } insn_t;

/* Encodings that must be illegal on this core. */
static const insn_t g_illegal[] = {
    { "all-zero (c.unimp)",        0x00000000, 2 },
    { "all-ones",                  0xffffffff, 4 },
    { "rdcycle (no Zicntr)",       0xc0002573, 4 },
    { "rdtime (no Zicntr)",        0xc0102573, 4 },
    { "rdinstret (no Zicntr)",     0xc0202573, 4 },
    { "csrr fflags (no F)",        0x00102573, 4 },
    { "csrr frm (no F)",           0x00202573, 4 },
    { "csrr fcsr (no F)",          0x00302573, 4 },
    { "csrr stimecmp (no Sstc)",   0x14d02573, 4 },
    { "csrr hpmcounter3",          0xc0302573, 4 },
    { "flw f0,0(a0)",              0x00052007, 4 },
    { "fsw f0,0(a0)",              0x00052027, 4 },
    { "fld f0,0(a0)",              0x00053007, 4 },
    { "fadd.s f0,f0,f0",           0x00007053, 4 },
    { "fmv.x.d a0,f0",             0xe2000553, 4 },
    { "c.fld f8,0(a0) (no Zcd)",   0x00002100, 2 },
    { "c.fsd f8,0(a0) (no Zcd)",   0x0000a100, 2 },
    { "c.fldsp f0,0(sp)",          0x00002002, 2 },
    { "clz a0,a0 (no Zbb)",        0x60051513, 4 },
    { "andn a0,a0,a1 (no Zbb)",    0x40b57533, 4 },
    { "sh1add a0,a0,a1 (no Zba)",  0x20b52533, 4 },
    { "bset a0,a0,a1 (no Zbs)",    0x28b51533, 4 },
    { "clmul a0,a0,a1 (no Zbc)",   0x0ab51533, 4 },
    { "czero.eqz (no Zicond)",     0x0eb55533, 4 },
    { "cbo.zero (no Zicboz)",      0x0045200f, 4 },
    { "vsetvli (no V)",            0x0d007057, 4 },
    { "custom-0 opcode",           0x0000000b, 4 },
};

/* Executes the encoding at a fixed, aligned slot so mepc is known exactly.
 * A 2-byte encoding is followed by a c.nop to keep the slot 4 bytes. */
static uint32_t g_slot[2] ST_ALIGNED(8);
extern char st_exec_slot[];
__asm__ (
    ".text\n.option push\n.option norvc\n.balign 8\n"
    ".globl st_exec_slot\n"
    "st_exec_slot:\n"
    "    .word 0x00000013\n"      /* patched */
    "    .word 0x00000013\n"
    "    ret\n"
    ".option pop\n"
);

/* RAM is RWX for M; patch, fence.i, call.  Runs in whatever mode calls it. */
static void exec_slot(void) { ((void (*)(void))(void *)st_exec_slot)(); }

static void patch_slot(uint32_t enc, int len) {
    volatile uint32_t *p = (volatile uint32_t *)(void *)st_exec_slot;
    if (len == 2) p[0] = (enc & 0xffff) | (0x0001u << 16);   /* insn + c.nop */
    else          p[0] = enc;
    p[1] = 0x00000013;
    st_fence_i();
}

static uint64_t lower_exec(uint64_t arg) { (void)arg; exec_slot(); return 0x600d; }

static void check_illegal_trap(const insn_t *in, uint64_t prv) {
    uint64_t slot = (uint64_t)(void *)st_exec_slot;
    patch_slot(in->enc, in->len);
    if (prv == PRV_M) {
        st_expect(ST_EXPECT_SKIP);
        g_exp_len = (uint64_t)in->len;
        exec_slot();
        st_expect_clear();
    } else {
        (void)st_run_expect_abort(prv, lower_exec, 0, (uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    }
    ST_CHECK_EQ(in->name, g_trap_cause, CAUSE_ILLEGAL);
    ST_CHECK_EQ("  mepc = slot", g_trap_epc, slot);
    /* mtval: 0 or the faulting instruction bits (spec allows either). */
    uint64_t want = in->len == 2 ? (in->enc & 0xffff) : in->enc;
    ST_CHECK("  mtval is 0 or the instruction", g_trap_tval == 0 || g_trap_tval == want);
}

/* ---- ecall / ebreak --------------------------------------------------- */
static uint64_t g_ecall_pc;
static uint64_t do_ecall(uint64_t arg) {
    (void)arg;
    __asm__ volatile (".option push\n.option norvc\n"
                      "la t0, 1f\n sd t0, 0(%0)\n li a7, 0\n"
                      "1: ecall\n .option pop"
                      :: "r"(&g_ecall_pc) : "t0", "a7", "a0", "memory");
    return 0;
}
static uint64_t do_ebreak(uint64_t arg) {
    (void)arg;
    __asm__ volatile (".option push\n.option norvc\n"
                      "la t0, 1f\n sd t0, 0(%0)\n"
                      "1: ebreak\n .option pop"
                      :: "r"(&g_ecall_pc) : "t0", "memory");
    return 0;
}
static uint64_t do_c_ebreak(uint64_t arg) {
    (void)arg;
    __asm__ volatile (".option push\n.option rvc\n"
                      "la t0, 1f\n sd t0, 0(%0)\n"
                      "1: c.ebreak\n .option pop"
                      :: "r"(&g_ecall_pc) : "t0", "memory");
    return 0;
}

/* Privileged instructions that a lower mode must not execute. */
static uint64_t do_mret(uint64_t a)  { (void)a; EXEC32(0x30200073); return 0; }
static uint64_t do_sret(uint64_t a)  { (void)a; EXEC32(0x10200073); return 0; }
static uint64_t do_sfence(uint64_t a){ (void)a; EXEC32(0x12000073); return 0; }
static uint64_t do_rd_mstatus(uint64_t a) { (void)a; EXEC32(0x30002573); return 0; }  /* csrr a0, mstatus */
static uint64_t do_rd_sstatus(uint64_t a) { (void)a; EXEC32(0x10002573); return 0; }  /* csrr a0, sstatus */
static uint64_t do_rd_mhartid(uint64_t a) { (void)a; EXEC32(0xf1402573); return 0; }  /* csrr a0, mhartid */
static uint64_t do_wr_custom(uint64_t a)  { (void)a; EXEC32(0x7c0010f3); return 0; }  /* csrrw ra, 0x7c0, x0 */

static void expect_lower_illegal(const char *what, uint64_t prv, uint64_t (*fn)(uint64_t)) {
    uint64_t r = st_run_expect_abort(prv, fn, 0, (uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    ST_CHECK_EQ(what, r, ST_TRAP_ABORTED);
    ST_CHECK_EQ("  cause illegal", g_trap_cause, CAUSE_ILLEGAL);
}

int main(void) {
    st_init();

    st_section("illegal encodings from M");
    for (unsigned i = 0; i < ST_ARRAY_LEN(g_illegal); i++) check_illegal_trap(&g_illegal[i], PRV_M);
    st_section("illegal encodings from S");
    for (unsigned i = 0; i < ST_ARRAY_LEN(g_illegal); i++) check_illegal_trap(&g_illegal[i], PRV_S);
    st_section("illegal encodings from U");
    for (unsigned i = 0; i < ST_ARRAY_LEN(g_illegal); i++) check_illegal_trap(&g_illegal[i], PRV_U);

    st_section("ecall from M/S/U");
    st_expect(ST_EXPECT_SKIP);
    do_ecall(0);
    st_expect_clear();
    ST_CHECK_EQ("M ecall cause", g_trap_cause, CAUSE_ECALL_M);
    ST_CHECK_EQ("M ecall epc", g_trap_epc, g_ecall_pc);
    ST_CHECK_EQ("S ecall aborted", st_run_expect_abort(PRV_S, do_ecall, 0, (uint64_t)(g_st_lstack + ST_LSTACK_BYTES)), ST_TRAP_ABORTED);
    ST_CHECK_EQ("S ecall cause", g_trap_cause, CAUSE_ECALL_S);
    ST_CHECK_EQ("S ecall epc", g_trap_epc, g_ecall_pc);
    ST_CHECK_EQ("U ecall aborted", st_run_expect_abort(PRV_U, do_ecall, 0, (uint64_t)(g_st_lstack + ST_LSTACK_BYTES)), ST_TRAP_ABORTED);
    ST_CHECK_EQ("U ecall cause", g_trap_cause, CAUSE_ECALL_U);
    ST_CHECK_EQ("U ecall epc", g_trap_epc, g_ecall_pc);

    st_section("ebreak / c.ebreak from M/S/U");
    st_expect(ST_EXPECT_SKIP);
    do_ebreak(0);
    st_expect_clear();
    ST_CHECK_EQ("M ebreak cause", g_trap_cause, CAUSE_BREAKPOINT);
    ST_CHECK_EQ("M ebreak epc", g_trap_epc, g_ecall_pc);
    st_expect(ST_EXPECT_SKIP);
    g_exp_len = 2;
    do_c_ebreak(0);
    st_expect_clear();
    ST_CHECK_EQ("M c.ebreak cause", g_trap_cause, CAUSE_BREAKPOINT);
    ST_CHECK_EQ("M c.ebreak epc", g_trap_epc, g_ecall_pc);
    ST_CHECK_EQ("S ebreak", st_run_expect_abort(PRV_S, do_ebreak, 0, (uint64_t)(g_st_lstack + ST_LSTACK_BYTES)), ST_TRAP_ABORTED);
    ST_CHECK_EQ("S ebreak cause", g_trap_cause, CAUSE_BREAKPOINT);
    ST_CHECK_EQ("U ebreak", st_run_expect_abort(PRV_U, do_ebreak, 0, (uint64_t)(g_st_lstack + ST_LSTACK_BYTES)), ST_TRAP_ABORTED);
    ST_CHECK_EQ("U ebreak cause", g_trap_cause, CAUSE_BREAKPOINT);

    st_section("privileged instructions from lower modes");
    expect_lower_illegal("mret from S", PRV_S, do_mret);
    expect_lower_illegal("mret from U", PRV_U, do_mret);
    expect_lower_illegal("sret from U", PRV_U, do_sret);
    expect_lower_illegal("sfence.vma from U", PRV_U, do_sfence);
    expect_lower_illegal("csrr mstatus from S", PRV_S, do_rd_mstatus);
    expect_lower_illegal("csrr mstatus from U", PRV_U, do_rd_mstatus);
    expect_lower_illegal("csrr sstatus from U", PRV_U, do_rd_sstatus);
    expect_lower_illegal("csrr mhartid from S", PRV_S, do_rd_mhartid);
    expect_lower_illegal("custom CSR 0x7c0 from S", PRV_S, do_wr_custom);

    st_section("access faults (PMA holes) from M");
    uint64_t v;
    ST_CHECK_EQ("ld hole traps", m_try_ld(ST_HOLE_ADDR, &v), 1);
    ST_CHECK_EQ("ld hole cause", g_trap_cause, CAUSE_LOAD_ACCESS);
    ST_CHECK_EQ("ld hole tval", g_trap_tval, ST_HOLE_ADDR);
    ST_CHECK_EQ("sd hole traps", m_try_sd(ST_HOLE_ADDR + 8, 1), 1);
    ST_CHECK_EQ("sd hole cause", g_trap_cause, CAUSE_STORE_ACCESS);
    ST_CHECK_EQ("sd hole tval", g_trap_tval, ST_HOLE_ADDR + 8);
    ST_CHECK_EQ("ld past RAM end traps", m_try_ld(ST_RAM_END, &v), 1);
    ST_CHECK_EQ("ld past RAM end cause", g_trap_cause, CAUSE_LOAD_ACCESS);

    st_section("fetch access fault from M (jump into a hole)");
    st_expect(ST_EXPECT_SKIP);
    __asm__ volatile (".option push\n.option norvc\n"
                      "la t0, 1f\n sd t0, 0(%0)\n"
                      "li t1, 0x40000000\n jalr zero, 0(t1)\n"
                      "1:\n .option pop"
                      :: "r"(&g_exp_resume) : "t0", "t1", "memory");
    st_expect_clear();
    ST_CHECK_EQ("fetch hole cause", g_trap_cause, CAUSE_FETCH_ACCESS);
    ST_CHECK_EQ("fetch hole epc", g_trap_epc, ST_HOLE_ADDR);
    ST_CHECK("fetch hole tval 0 or addr", g_trap_tval == 0 || g_trap_tval == ST_HOLE_ADDR);

    st_section("fetch from MMIO (not executable)");
    st_expect(ST_EXPECT_SKIP);
    __asm__ volatile (".option push\n.option norvc\n"
                      "la t0, 1f\n sd t0, 0(%0)\n"
                      "jalr zero, 0(%1)\n"
                      "1:\n .option pop"
                      :: "r"(&g_exp_resume), "r"(CLINT_BASE + 0x4000) : "t0", "memory");
    st_expect_clear();
    ST_CHECK_EQ("fetch CLINT cause", g_trap_cause, CAUSE_FETCH_ACCESS);
    ST_CHECK_EQ("fetch CLINT epc", g_trap_epc, CLINT_BASE + 0x4000);

    (void)g_slot;
    return st_result();
}
