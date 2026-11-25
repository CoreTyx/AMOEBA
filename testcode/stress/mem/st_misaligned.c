// @stress tier=pr seeds=2 build=no_spike duts=legacy,forte timeout=30000000
//
// st_misaligned -- misaligned loads/stores on a core without hardware support.
//
// ZICCLSM_SUPPORTED = 0 (pkg/config.vh): every misaligned load/store must
// trap with cause 4/6 and mtval = the exact misaligned address, leaving memory
// and the destination register untouched; OpenSBI then emulates the access
// byte-wise from its M-mode handler.  Linux userland (packed structs, network
// headers, memcpy tails in hand-written asm) hits that path routinely, so both
// halves are tested:
//   1. every width x every misaligned offset, from M, S and U: exact trap
//   2. a U workload doing thousands of random misaligned loads/stores through
//      an OpenSBI-style emulator: every value and the final memory image exact
//   3. misaligned AMO / LR / SC: must trap (address-misaligned or access fault),
//      never be emulated or performed
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define NWORK (1500 * ST_SCALE)

static uint8_t g_mem[4096] ST_ALIGNED(64);

/* ---------------- part 1: exact traps ---------------- */
typedef int (*ld_probe_t)(uint64_t, uint64_t, uint64_t *);
typedef int (*st_probe_t)(uint64_t, uint64_t, uint64_t);
static const struct { const char *n; ld_probe_t f; int sz; } g_lds[] = {
    { "lh", probe_lh, 2 }, { "lhu", probe_lhu, 2 }, { "lw", probe_lw, 4 }, { "lwu", probe_lwu, 4 }, { "ld", probe_ld, 8 } };
static const struct { const char *n; st_probe_t f; int sz; } g_sts[] = {
    { "sh", probe_sh, 2 }, { "sw", probe_sw, 4 }, { "sd", probe_sd, 8 } };

/* ---------------- part 2: emulator (what OpenSBI does) ---------------- */
static volatile uint64_t g_emul_ld, g_emul_st, g_emul_bad;
static int emulate(st_frame_t *f) {
    if (f->cause != CAUSE_MISALIGNED_LOAD && f->cause != CAUSE_MISALIGNED_STORE) return 0;
    uint32_t insn = *(volatile uint16_t *)f->epc | ((uint32_t)*(volatile uint16_t *)(f->epc + 2) << 16);
    if ((insn & 3) != 3) { g_emul_bad++; return 0; }      /* workload uses no compressed ld/st */
    uint32_t op = insn & 0x7f, f3 = (insn >> 12) & 7;
    uint64_t addr = f->tval;
    if (op == 0x03 && f->cause == CAUSE_MISALIGNED_LOAD) {
        int sz = 1 << (f3 & 3);
        uint64_t v = 0;
        for (int i = sz - 1; i >= 0; i--) v = (v << 8) | *(volatile uint8_t *)(addr + i);
        if (!(f3 & 4) && sz < 8) { int sh = 64 - 8 * sz; v = (uint64_t)((int64_t)(v << sh) >> sh); }
        uint32_t rd = (insn >> 7) & 31;
        if (rd) f->x[rd] = v;
        g_emul_ld++;
    } else if (op == 0x23 && f->cause == CAUSE_MISALIGNED_STORE) {
        int sz = 1 << (f3 & 3);
        uint64_t v = f->x[(insn >> 20) & 31];
        for (int i = 0; i < sz; i++) *(volatile uint8_t *)(addr + i) = (uint8_t)(v >> (8 * i));
        g_emul_st++;
    } else { g_emul_bad++; return 0; }
    f->epc += 4;
    return 1;
}

#define ULD(insn, a) ({ uint64_t __r; __asm__ volatile (".option push\n.option norvc\n" insn " %0, 0(%1)\n.option pop" : "=r"(__r) : "r"(a) : "memory"); __r; })
#define UST(insn, a, v) __asm__ volatile (".option push\n.option norvc\n" insn " %0, 0(%1)\n.option pop" :: "r"(v), "r"(a) : "memory")

static uint8_t g_model[4096];
static volatile uint64_t g_u_bad;

static uint64_t rd_model(uint64_t off, int sz, int sgn) {
    uint64_t v = 0;
    for (int i = sz - 1; i >= 0; i--) v = (v << 8) | g_model[off + (uint64_t)i];
    if (sgn && sz < 8) { int sh = 64 - 8 * sz; v = (uint64_t)((int64_t)(v << sh) >> sh); }
    return v;
}

static uint64_t u_work(uint64_t seed) {
    uint64_t x = seed | 1, bad = 0;
    for (int i = 0; i < NWORK; i++) {
        x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
        uint64_t r = x * 0x2545F4914F6CDD1DULL;
        int kind = (int)(r % 8);
        uint64_t off = (r >> 8) % (4096 - 8);
        uint64_t a = (uint64_t)g_mem + off, v = r ^ (r << 29), got = 0, want = 0;
        switch (kind) {
        case 0: got = ULD("lh", a);  want = rd_model(off, 2, 1); break;
        case 1: got = ULD("lhu", a); want = rd_model(off, 2, 0); break;
        case 2: got = ULD("lw", a);  want = rd_model(off, 4, 1); break;
        case 3: got = ULD("lwu", a); want = rd_model(off, 4, 0); break;
        case 4: got = ULD("ld", a);  want = rd_model(off, 8, 0); break;
        case 5: UST("sh", a, v); for (int k = 0; k < 2; k++) g_model[off + k] = (uint8_t)(v >> (8 * k)); break;
        case 6: UST("sw", a, v); for (int k = 0; k < 4; k++) g_model[off + k] = (uint8_t)(v >> (8 * k)); break;
        default: UST("sd", a, v); for (int k = 0; k < 8; k++) g_model[off + k] = (uint8_t)(v >> (8 * k)); break;
        }
        if (got != want) bad++;
    }
    g_u_bad = bad;
    return bad;
}

int main(void) {
    st_init();
    for (int i = 0; i < 4096; i++) g_mem[i] = g_model[i] = (uint8_t)st_rand();

    st_section("every misaligned width/offset traps exactly (M via MPRV=M, S, U)");
    static const uint64_t prvs[3] = { PRV_M, PRV_S, PRV_U };
    uint64_t base = (uint64_t)g_mem + 128;
    for (int pi = 0; pi < 3; pi++) {
        for (unsigned l = 0; l < ST_ARRAY_LEN(g_lds); l++)
            for (int off = 1; off < g_lds[l].sz; off++) {
                uint64_t v = 0x1111;
                int t = g_lds[l].f(base + (uint64_t)off, prvs[pi], &v);
                if (!t || g_trap_cause != CAUSE_MISALIGNED_LOAD || g_trap_tval != base + (uint64_t)off)
                    st_check_failed(g_lds[l].n, g_trap_cause | (g_trap_tval << 8), CAUSE_MISALIGNED_LOAD, pi * 100 + off);
                else g_st_pass++;
            }
        for (unsigned k = 0; k < ST_ARRAY_LEN(g_sts); k++)
            for (int off = 1; off < g_sts[k].sz; off++) {
                uint64_t before = *(volatile uint64_t *)base, before2 = *(volatile uint64_t *)(base + 8);
                int t = g_sts[k].f(base + (uint64_t)off, prvs[pi], 0xdeadbeefcafef00dUL);
                if (!t || g_trap_cause != CAUSE_MISALIGNED_STORE || g_trap_tval != base + (uint64_t)off)
                    st_check_failed(g_sts[k].n, g_trap_cause | (g_trap_tval << 8), CAUSE_MISALIGNED_STORE, pi * 100 + off);
                else g_st_pass++;
                ST_CHECK("  trapping store wrote nothing", *(volatile uint64_t *)base == before && *(volatile uint64_t *)(base + 8) == before2);
            }
    }
    /* across a 16-byte line and a 4 KiB page boundary */
    uint64_t pb = ((uint64_t)g_mem + 4096) & ~4095UL;
    if (pb + 8 <= (uint64_t)g_mem + 4096) {
        ST_CHECK_EQ("ld across page boundary traps", probe_ld(pb - 4, PRV_M, 0), 1);
        ST_CHECK_EQ("  cause", g_trap_cause, CAUSE_MISALIGNED_LOAD);
    }
    ST_CHECK_EQ("ld across line boundary traps", probe_ld(base + 12, PRV_S, 0), 1);
    ST_CHECK_EQ("  tval", g_trap_tval, base + 12);

    st_section("misaligned AMO / LR / SC never complete");
    uint64_t a = base + 2;
    uint64_t before = *(volatile uint64_t *)base;
    st_expect(ST_EXPECT_SKIP);
    __asm__ volatile (".option push\n.option norvc\namoadd.w zero, %1, (%0)\n.option pop" :: "r"(a), "r"(1UL) : "memory");
    st_expect_clear();
    ST_CHECK("misaligned amoadd.w traps (6 or 7)", g_trap_cause == CAUSE_MISALIGNED_STORE || g_trap_cause == CAUSE_STORE_ACCESS);
    st_expect(ST_EXPECT_SKIP);
    __asm__ volatile (".option push\n.option norvc\namoswap.d zero, %1, (%0)\n.option pop" :: "r"(base + 4), "r"(1UL) : "memory");
    st_expect_clear();
    ST_CHECK("misaligned amoswap.d traps (6 or 7)", g_trap_cause == CAUSE_MISALIGNED_STORE || g_trap_cause == CAUSE_STORE_ACCESS);
    st_expect(ST_EXPECT_SKIP);
    __asm__ volatile (".option push\n.option norvc\nlr.d t0, (%0)\n.option pop" :: "r"(base + 4) : "t0", "memory");
    st_expect_clear();
    ST_CHECK("misaligned lr.d traps (4 or 5)", g_trap_cause == CAUSE_MISALIGNED_LOAD || g_trap_cause == CAUSE_LOAD_ACCESS);
    st_expect(ST_EXPECT_SKIP);
    __asm__ volatile (".option push\n.option norvc\nsc.w t0, %1, (%0)\n.option pop" :: "r"(base + 2), "r"(5UL) : "t0", "memory");
    st_expect_clear();
    ST_CHECK("misaligned sc.w traps (6 or 7)", g_trap_cause == CAUSE_MISALIGNED_STORE || g_trap_cause == CAUSE_STORE_ACCESS);
    ST_CHECK_EQ("memory untouched by misaligned atomics", *(volatile uint64_t *)base, before);

    st_section("U workload through an M-mode emulator");
    g_m_hook = emulate;
    uint64_t bad = st_run(PRV_U, u_work, 0x1234567ULL * (uint64_t)SEED);
    g_m_hook = 0;
    ST_CHECK_EQ("every emulated value matched the byte model", bad, 0);
    ST_CHECK_EQ("emulator never saw an unexpected instruction", g_emul_bad, 0);
    ST_CHECK("emulated loads happened", g_emul_ld > (uint64_t)NWORK / 4);
    ST_CHECK("emulated stores happened", g_emul_st > (uint64_t)NWORK / 8);
    uint64_t diff = 0;
    for (int i = 0; i < 4096; i++) diff += g_mem[i] != g_model[i];
    ST_CHECK_EQ("final memory image matches the model", diff, 0);
    return st_result();
}
