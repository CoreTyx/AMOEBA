// @stress tier=pr build=no_spike duts=legacy,forte timeout=4000000
//
// st_nested_traps -- traps taken inside trap handlers, and the
// privileged-state stacking that makes that safe.
//
// Linux takes faults inside its own exception paths constantly (a page fault
// on a user pointer inside a syscall, an interrupt during a fault), and OpenSBI
// emulates misaligned accesses and rdtime from inside its trap handler.  Each
// nested trap overwrites mepc/mcause/mtval/mstatus.MPP; software only survives
// if the hardware stacks xIE/xPIE/xPP exactly and leaves every GPR intact.
//   1. every GPR survives an M trap whose handler itself traps (3 deep)
//   2. same, entered from U (stack switch via mscratch, then M-on-M nesting)
//   3. mstatus MIE/MPIE stacking across trap and mret
//   4. sstatus SIE/SPIE stacking across a delegated trap and sret
#include "../lib/stress.h"

#define MAGIC_OUTER 0x4e455354UL
#define MAGIC_INNER 0x4e455355UL

extern void st_regcheck(uint64_t *out, uint64_t magic);
__asm__ (
    ".text\n.option push\n.option norvc\n.balign 4\n"
    ".globl st_regcheck\n"
    "st_regcheck:\n"
    "    addi sp, sp, -384\n"
    "    sd ra, 0(sp)\n"
    "    sd s0, 8(sp)\n"
    "    sd s1, 16(sp)\n"
    "    sd s2, 24(sp)\n"
    "    sd s3, 32(sp)\n"
    "    sd s4, 40(sp)\n"
    "    sd s5, 48(sp)\n"
    "    sd s6, 56(sp)\n"
    "    sd s7, 64(sp)\n"
    "    sd s8, 72(sp)\n"
    "    sd s9, 80(sp)\n"
    "    sd s10, 88(sp)\n"
    "    sd s11, 96(sp)\n"
    "    sd a0, 104(sp)\n"
    "    mv a7, a1\n"
    "    li x1, 0x5a010101\n"
    "    li x5, 0x5a050505\n"
    "    li x6, 0x5a060606\n"
    "    li x7, 0x5a070707\n"
    "    li x8, 0x5a080808\n"
    "    li x9, 0x5a090909\n"
    "    li x10, 0x5a0a0a0a\n"
    "    li x11, 0x5a0b0b0b\n"
    "    li x12, 0x5a0c0c0c\n"
    "    li x13, 0x5a0d0d0d\n"
    "    li x14, 0x5a0e0e0e\n"
    "    li x15, 0x5a0f0f0f\n"
    "    li x16, 0x5a101010\n"
    "    li x18, 0x5a121212\n"
    "    li x19, 0x5a131313\n"
    "    li x20, 0x5a141414\n"
    "    li x21, 0x5a151515\n"
    "    li x22, 0x5a161616\n"
    "    li x23, 0x5a171717\n"
    "    li x24, 0x5a181818\n"
    "    li x25, 0x5a191919\n"
    "    li x26, 0x5a1a1a1a\n"
    "    li x27, 0x5a1b1b1b\n"
    "    li x28, 0x5a1c1c1c\n"
    "    li x29, 0x5a1d1d1d\n"
    "    li x30, 0x5a1e1e1e\n"
    "    li x31, 0x5a1f1f1f\n"
    "    ecall\n"
    "    sd x1, 136(sp)\n"
    "    sd x3, 152(sp)\n"
    "    sd x4, 160(sp)\n"
    "    sd x5, 168(sp)\n"
    "    sd x6, 176(sp)\n"
    "    sd x7, 184(sp)\n"
    "    sd x8, 192(sp)\n"
    "    sd x9, 200(sp)\n"
    "    sd x10, 208(sp)\n"
    "    sd x11, 216(sp)\n"
    "    sd x12, 224(sp)\n"
    "    sd x13, 232(sp)\n"
    "    sd x14, 240(sp)\n"
    "    sd x15, 248(sp)\n"
    "    sd x16, 256(sp)\n"
    "    sd x17, 264(sp)\n"
    "    sd x18, 272(sp)\n"
    "    sd x19, 280(sp)\n"
    "    sd x20, 288(sp)\n"
    "    sd x21, 296(sp)\n"
    "    sd x22, 304(sp)\n"
    "    sd x23, 312(sp)\n"
    "    sd x24, 320(sp)\n"
    "    sd x25, 328(sp)\n"
    "    sd x26, 336(sp)\n"
    "    sd x27, 344(sp)\n"
    "    sd x28, 352(sp)\n"
    "    sd x29, 360(sp)\n"
    "    sd x30, 368(sp)\n"
    "    sd x31, 376(sp)\n"
    "    ld a0, 104(sp)\n"
    "    ld t0, 136(sp)\n    sd t0, 8(a0)\n"
    "    ld t0, 152(sp)\n    sd t0, 24(a0)\n"
    "    ld t0, 160(sp)\n    sd t0, 32(a0)\n"
    "    ld t0, 168(sp)\n    sd t0, 40(a0)\n"
    "    ld t0, 176(sp)\n    sd t0, 48(a0)\n"
    "    ld t0, 184(sp)\n    sd t0, 56(a0)\n"
    "    ld t0, 192(sp)\n    sd t0, 64(a0)\n"
    "    ld t0, 200(sp)\n    sd t0, 72(a0)\n"
    "    ld t0, 208(sp)\n    sd t0, 80(a0)\n"
    "    ld t0, 216(sp)\n    sd t0, 88(a0)\n"
    "    ld t0, 224(sp)\n    sd t0, 96(a0)\n"
    "    ld t0, 232(sp)\n    sd t0, 104(a0)\n"
    "    ld t0, 240(sp)\n    sd t0, 112(a0)\n"
    "    ld t0, 248(sp)\n    sd t0, 120(a0)\n"
    "    ld t0, 256(sp)\n    sd t0, 128(a0)\n"
    "    ld t0, 264(sp)\n    sd t0, 136(a0)\n"
    "    ld t0, 272(sp)\n    sd t0, 144(a0)\n"
    "    ld t0, 280(sp)\n    sd t0, 152(a0)\n"
    "    ld t0, 288(sp)\n    sd t0, 160(a0)\n"
    "    ld t0, 296(sp)\n    sd t0, 168(a0)\n"
    "    ld t0, 304(sp)\n    sd t0, 176(a0)\n"
    "    ld t0, 312(sp)\n    sd t0, 184(a0)\n"
    "    ld t0, 320(sp)\n    sd t0, 192(a0)\n"
    "    ld t0, 328(sp)\n    sd t0, 200(a0)\n"
    "    ld t0, 336(sp)\n    sd t0, 208(a0)\n"
    "    ld t0, 344(sp)\n    sd t0, 216(a0)\n"
    "    ld t0, 352(sp)\n    sd t0, 224(a0)\n"
    "    ld t0, 360(sp)\n    sd t0, 232(a0)\n"
    "    ld t0, 368(sp)\n    sd t0, 240(a0)\n"
    "    ld t0, 376(sp)\n    sd t0, 248(a0)\n"
    "    ld ra, 0(sp)\n"
    "    ld s0, 8(sp)\n"
    "    ld s1, 16(sp)\n"
    "    ld s2, 24(sp)\n"
    "    ld s3, 32(sp)\n"
    "    ld s4, 40(sp)\n"
    "    ld s5, 48(sp)\n"
    "    ld s6, 56(sp)\n"
    "    ld s7, 64(sp)\n"
    "    ld s8, 72(sp)\n"
    "    ld s9, 80(sp)\n"
    "    ld s10, 88(sp)\n"
    "    ld s11, 96(sp)\n"
    "    addi sp, sp, 384\n"
    "    ret\n"
    ".option pop\n"
);

static uint64_t expect_reg(int r) { return 0x5a000000UL + (uint64_t)r * 0x10101UL; }

static volatile uint64_t g_depth, g_max_depth, g_inner_illegal;
static volatile uint64_t g_hook_mstatus, g_hook_saw_frame_ok;

/* M hook: ecall MAGIC_OUTER -> (ecall MAGIC_INNER -> illegal) */
static int m_hook(st_frame_t *f) {
    if (f->cause != CAUSE_ECALL_M && f->cause != CAUSE_ECALL_S && f->cause != CAUSE_ECALL_U) return 0;
    uint64_t fn = f->x[17];
    if (fn != MAGIC_OUTER && fn != MAGIC_INNER) return 0;
    g_depth++;
    if (g_depth > g_max_depth) g_max_depth = g_depth;
    if (fn == MAGIC_OUTER) g_hook_mstatus = csr_read(mstatus);
    uint64_t epc = f->epc, cause = f->cause;
    if (fn == MAGIC_OUTER) {
        /* nested ecall from M, preserving the outer frame */
        __asm__ volatile ("mv a7, %0\n ecall" :: "r"(MAGIC_INNER) : "a7", "a0", "memory");
    } else {
        /* innermost: an illegal instruction, recorded and skipped */
        st_expect(ST_EXPECT_SKIP);
        __asm__ volatile (".option push\n.option norvc\n.word 0xc0002573\n.option pop" ::: "a0", "memory");
        if (g_trap_cause == CAUSE_ILLEGAL) g_inner_illegal++;
    }
    g_hook_saw_frame_ok += (f->epc == epc && f->cause == cause);
    f->epc += 4;
    g_depth--;
    return 1;
}

static uint64_t g_out[32];
static void check_regs(const char *who) {
    for (int r = 1; r < 32; r++) {
        if (r == 2 || r == 3 || r == 4) continue;
        uint64_t want = (r == 17) ? MAGIC_OUTER : expect_reg(r);
        if (g_out[r] != want) st_check_failed(who, g_out[r], want, r);
        else g_st_pass++;
    }
}
static uint64_t u_regcheck(uint64_t a) { (void)a; st_regcheck(g_out, MAGIC_OUTER); return 0x77; }

/* ---- S stacking ---- */
static volatile uint64_t g_s_hook_sstatus;
static int s_hook(st_frame_t *f) {
    if (f->cause == CAUSE_ILLEGAL) { g_s_hook_sstatus = csr_read(sstatus); f->epc += 4; return 1; }
    return 0;
}
static uint64_t s_stack_test(uint64_t a) {
    (void)a;
    st_s_init();
    g_s_hook = s_hook;
    csr_set(sstatus, MSTATUS_SIE);         /* sie = 0: no interrupt can actually fire */
    __asm__ volatile (".option push\n.option norvc\n.word 0xc0002573\n.option pop" ::: "a0", "memory");
    uint64_t after = csr_read(sstatus);
    csr_clear(sstatus, MSTATUS_SIE);
    g_s_hook = 0;
    ST_CHECK_EQ("in handler: SIE = 0", g_s_hook_sstatus & MSTATUS_SIE, 0);
    ST_CHECK_EQ("in handler: SPIE = old SIE (1)", g_s_hook_sstatus & MSTATUS_SPIE, MSTATUS_SPIE);
    ST_CHECK_EQ("in handler: SPP = S", g_s_hook_sstatus & MSTATUS_SPP, MSTATUS_SPP);
    ST_CHECK_EQ("after sret: SIE restored", after & MSTATUS_SIE, MSTATUS_SIE);
    ST_CHECK_EQ("after sret: SPIE = 1", after & MSTATUS_SPIE, MSTATUS_SPIE);
    ST_CHECK_EQ("after sret: SPP = U", after & MSTATUS_SPP, 0);
    return 0x99;
}

int main(void) {
    st_init();
    g_m_hook = m_hook;

    st_section("GPRs across 3-deep nested traps from M");
    for (int i = 0; i < 32; i++) g_out[i] = 0;
    st_regcheck(g_out, MAGIC_OUTER);
    check_regs("M reg");
    ST_CHECK_EQ("max nesting depth 2 (+illegal)", g_max_depth, 2);
    ST_CHECK_EQ("innermost illegal recorded", g_inner_illegal, 1);
    ST_CHECK_EQ("outer frames intact after nesting", g_hook_saw_frame_ok, 2);

    st_section("GPRs across nested traps entered from U");
    for (int i = 0; i < 32; i++) g_out[i] = 0;
    g_max_depth = 0;
    ST_CHECK_EQ("U body completed", st_run(PRV_U, u_regcheck, 0), 0x77);
    check_regs("U reg");
    ST_CHECK_EQ("U nesting depth", g_max_depth, 2);
    ST_CHECK_EQ("innermost illegal recorded (U)", g_inner_illegal, 2);

    st_section("mstatus MIE/MPIE stacking (mie = 0, so nothing fires)");
    csr_write(mie, 0);
    csr_set(mstatus, MSTATUS_MIE);
    st_regcheck(g_out, MAGIC_OUTER);
    uint64_t after = csr_read(mstatus);
    csr_clear(mstatus, MSTATUS_MIE);
    ST_CHECK_EQ("in handler: MIE = 0", g_hook_mstatus & MSTATUS_MIE, 0);
    ST_CHECK_EQ("in handler: MPIE = old MIE (1)", g_hook_mstatus & MSTATUS_MPIE, MSTATUS_MPIE);
    ST_CHECK_EQ("in handler: MPP = M", g_hook_mstatus & MSTATUS_MPP, MSTATUS_MPP_M);
    ST_CHECK_EQ("after mret: MIE restored", after & MSTATUS_MIE, MSTATUS_MIE);
    ST_CHECK_EQ("after mret: MPIE = 1", after & MSTATUS_MPIE, MSTATUS_MPIE);
    st_regcheck(g_out, MAGIC_OUTER);   /* now with MIE = 0 going in */
    ST_CHECK_EQ("in handler: MPIE = old MIE (0)", g_hook_mstatus & MSTATUS_MPIE, 0);

    st_section("sstatus SIE/SPIE/SPP stacking (delegated illegal)");
    g_m_hook = 0;
    csr_write(medeleg, 1UL << CAUSE_ILLEGAL);
    ST_CHECK_EQ("S stacking test ran", st_run(PRV_S, s_stack_test, 0), 0x99);
    csr_write(medeleg, 0);

    return st_result();
}
