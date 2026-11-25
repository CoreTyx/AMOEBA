// @stress tier=pr seeds=3 nightly_seeds=16 weekly_seeds=64 build=spike duts=legacy timeout=60000000
// @stress-variant build=no_spike duts=forte
//
// st_smc_jit -- a JIT: random straight-line code, larger than the I$,
// generated into the same buffers over and over.
//
// Each round emits ~700 random RV64IM instructions (ALU, shifts, *W forms,
// multiply/divide including the divide-by-zero and overflow cases) operating on
// 14 registers loaded from a seed array, folds them into a0, and runs the code
// after fence.i.  The result is compared with a C interpreter of the same
// program implementing the ISA's exact semantics.  Successive rounds overwrite
// code the I$ still holds, alternate between two buffers, and occasionally
// insert a 2-byte c.nop so 32-bit instructions straddle lines.  Under Spike
// lock-step co-simulation every single generated instruction is also checked
// against the reference model as it retires -- this is the random-instruction
// test of the suite that needs no MMIO.
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define NINSN   700
#define ROUNDS  (6 * ST_SCALE)
#define CODE_BYTES 8192

static uint8_t g_code[2][CODE_BYTES] ST_ALIGNED(4096);

/* registers the generated code may use (caller-saved, not a0 = base) */
static const uint8_t g_regs[14] = { 5, 6, 7, 28, 29, 30, 31, 11, 12, 13, 14, 15, 16, 17 };

typedef struct { uint8_t kind, rd, rs1, rs2; int32_t imm; } op_t;
enum { K_ADD, K_SUB, K_XOR, K_OR, K_AND, K_SLL, K_SRL, K_SRA, K_SLT, K_SLTU,
       K_ADDW, K_SUBW, K_SLLW, K_SRLW, K_SRAW,
       K_MUL, K_MULH, K_MULHU, K_MULHSU, K_MULW, K_DIV, K_DIVU, K_REM, K_REMU,
       K_DIVW, K_DIVUW, K_REMW, K_REMUW,
       K_ADDI, K_XORI, K_ORI, K_ANDI, K_SLTI, K_SLTIU, K_SLLI, K_SRLI, K_SRAI,
       K_ADDIW, K_SLLIW, K_SRLIW, K_SRAIW, K_LUI, K_CNOP, K_N };

static op_t g_prog[NINSN];

static uint32_t encode(const op_t *o) {
    uint32_t rd = o->rd, a = o->rs1, b = o->rs2;
    switch (o->kind) {
    case K_ADD:  return enc_r(0x00, b, a, 0, rd, 0x33);
    case K_SUB:  return enc_r(0x20, b, a, 0, rd, 0x33);
    case K_XOR:  return enc_r(0x00, b, a, 4, rd, 0x33);
    case K_OR:   return enc_r(0x00, b, a, 6, rd, 0x33);
    case K_AND:  return enc_r(0x00, b, a, 7, rd, 0x33);
    case K_SLL:  return enc_r(0x00, b, a, 1, rd, 0x33);
    case K_SRL:  return enc_r(0x00, b, a, 5, rd, 0x33);
    case K_SRA:  return enc_r(0x20, b, a, 5, rd, 0x33);
    case K_SLT:  return enc_r(0x00, b, a, 2, rd, 0x33);
    case K_SLTU: return enc_r(0x00, b, a, 3, rd, 0x33);
    case K_ADDW: return enc_r(0x00, b, a, 0, rd, 0x3b);
    case K_SUBW: return enc_r(0x20, b, a, 0, rd, 0x3b);
    case K_SLLW: return enc_r(0x00, b, a, 1, rd, 0x3b);
    case K_SRLW: return enc_r(0x00, b, a, 5, rd, 0x3b);
    case K_SRAW: return enc_r(0x20, b, a, 5, rd, 0x3b);
    case K_MUL:   return enc_r(1, b, a, 0, rd, 0x33);
    case K_MULH:  return enc_r(1, b, a, 1, rd, 0x33);
    case K_MULHSU:return enc_r(1, b, a, 2, rd, 0x33);
    case K_MULHU: return enc_r(1, b, a, 3, rd, 0x33);
    case K_DIV:   return enc_r(1, b, a, 4, rd, 0x33);
    case K_DIVU:  return enc_r(1, b, a, 5, rd, 0x33);
    case K_REM:   return enc_r(1, b, a, 6, rd, 0x33);
    case K_REMU:  return enc_r(1, b, a, 7, rd, 0x33);
    case K_MULW:  return enc_r(1, b, a, 0, rd, 0x3b);
    case K_DIVW:  return enc_r(1, b, a, 4, rd, 0x3b);
    case K_DIVUW: return enc_r(1, b, a, 5, rd, 0x3b);
    case K_REMW:  return enc_r(1, b, a, 6, rd, 0x3b);
    case K_REMUW: return enc_r(1, b, a, 7, rd, 0x3b);
    case K_ADDI:  return enc_i(o->imm, a, 0, rd, 0x13);
    case K_SLTI:  return enc_i(o->imm, a, 2, rd, 0x13);
    case K_SLTIU: return enc_i(o->imm, a, 3, rd, 0x13);
    case K_XORI:  return enc_i(o->imm, a, 4, rd, 0x13);
    case K_ORI:   return enc_i(o->imm, a, 6, rd, 0x13);
    case K_ANDI:  return enc_i(o->imm, a, 7, rd, 0x13);
    case K_SLLI:  return enc_i(o->imm & 63, a, 1, rd, 0x13);
    case K_SRLI:  return enc_i(o->imm & 63, a, 5, rd, 0x13);
    case K_SRAI:  return enc_i((o->imm & 63) | 0x400, a, 5, rd, 0x13);
    case K_ADDIW: return enc_i(o->imm, a, 0, rd, 0x1b);
    case K_SLLIW: return enc_i(o->imm & 31, a, 1, rd, 0x1b);
    case K_SRLIW: return enc_i(o->imm & 31, a, 5, rd, 0x1b);
    case K_SRAIW: return enc_i((o->imm & 31) | 0x400, a, 5, rd, 0x1b);
    case K_LUI:   return enc_u((uint32_t)o->imm & 0xfffff, rd, 0x37);
    default:      return 0;
    }
}

static inline int64_t sx32(uint64_t v) { return (int64_t)(int32_t)v; }

/* The model must not use the MDU it is checking: C's *, / and % (and __int128)
 * compile to mul/mulh/div/rem, so a consistent MDU bug would give the same wrong
 * answer in both.  Everything below is shifts, adds and st_soft_mul. */
static uint64_t soft_mulhu(uint64_t a, uint64_t b) {
    uint64_t al = a & 0xffffffffUL, ah = a >> 32, bl = b & 0xffffffffUL, bh = b >> 32;
    uint64_t ll = st_soft_mul(al, bl), lh = st_soft_mul(al, bh);
    uint64_t hl = st_soft_mul(ah, bl), hh = st_soft_mul(ah, bh);
    uint64_t mid = (ll >> 32) + (lh & 0xffffffffUL) + (hl & 0xffffffffUL);
    return hh + (lh >> 32) + (hl >> 32) + (mid >> 32);
}
static uint64_t soft_mulh(int64_t a, int64_t b) {          /* signed x signed */
    uint64_t h = soft_mulhu((uint64_t)a, (uint64_t)b);
    if (a < 0) h -= (uint64_t)b;
    if (b < 0) h -= (uint64_t)a;
    return h;
}
static uint64_t soft_mulhsu(int64_t a, uint64_t b) {       /* signed x unsigned */
    uint64_t h = soft_mulhu((uint64_t)a, b);
    if (a < 0) h -= b;
    return h;
}
/* Restoring division, b != 0. */
static void soft_divu(uint64_t a, uint64_t b, uint64_t *q, uint64_t *r) {
    uint64_t qq = 0, rr = 0;
    for (int i = 63; i >= 0; i--) {
        rr = (rr << 1) | ((a >> i) & 1);
        if (rr >= b) { rr -= b; qq |= 1UL << i; }
    }
    *q = qq; *r = rr;
}
static uint64_t soft_neg_if(uint64_t v, int neg) { return neg ? (uint64_t)0 - v : v; }
/* Signed, b != 0 and not (INT_MIN, -1): truncating, remainder takes a's sign. */
static void soft_divs(int64_t a, int64_t b, uint64_t *q, uint64_t *r) {
    uint64_t ua = soft_neg_if((uint64_t)a, a < 0), ub = soft_neg_if((uint64_t)b, b < 0), qq, rr;
    soft_divu(ua, ub, &qq, &rr);
    *q = soft_neg_if(qq, (a < 0) != (b < 0));
    *r = soft_neg_if(rr, a < 0);
}
static uint64_t soft_div(int64_t a, int64_t b)  { uint64_t q, r; soft_divs(a, b, &q, &r); return q; }
static uint64_t soft_rem(int64_t a, int64_t b)  { uint64_t q, r; soft_divs(a, b, &q, &r); return r; }
static uint64_t soft_quot(uint64_t a, uint64_t b) { uint64_t q, r; soft_divu(a, b, &q, &r); return q; }
static uint64_t soft_mod(uint64_t a, uint64_t b)  { uint64_t q, r; soft_divu(a, b, &q, &r); return r; }

static uint64_t exec_model(const op_t *o, uint64_t a, uint64_t b) {
    int64_t sa = (int64_t)a, sb = (int64_t)b;
    int64_t imm = o->imm;
    switch (o->kind) {
    case K_ADD: return a + b;
    case K_SUB: return a - b;
    case K_XOR: return a ^ b;
    case K_OR:  return a | b;
    case K_AND: return a & b;
    case K_SLL: return a << (b & 63);
    case K_SRL: return a >> (b & 63);
    case K_SRA: return (uint64_t)(sa >> (b & 63));
    case K_SLT: return sa < sb;
    case K_SLTU: return a < b;
    case K_ADDW: return (uint64_t)sx32(a + b);
    case K_SUBW: return (uint64_t)sx32(a - b);
    case K_SLLW: return (uint64_t)sx32((uint32_t)a << (b & 31));
    case K_SRLW: return (uint64_t)sx32((uint32_t)a >> (b & 31));
    case K_SRAW: return (uint64_t)(int64_t)((int32_t)a >> (b & 31));
    case K_MUL:  return st_soft_mul(a, b);
    case K_MULH: return soft_mulh(sa, sb);
    case K_MULHU: return soft_mulhu(a, b);
    case K_MULHSU: return soft_mulhsu(sa, b);
    case K_MULW: return (uint64_t)sx32(st_soft_mul(a, b));
    case K_DIV:  return b == 0 ? ~0UL : (sa == INT64_MIN && sb == -1) ? a : soft_div(sa, sb);
    case K_DIVU: return b == 0 ? ~0UL : soft_quot(a, b);
    case K_REM:  return b == 0 ? a : (sa == INT64_MIN && sb == -1) ? 0 : soft_rem(sa, sb);
    case K_REMU: return b == 0 ? a : soft_mod(a, b);
    case K_DIVW: { int32_t x = (int32_t)a, y = (int32_t)b;
                   return (uint64_t)(int64_t)(y == 0 ? -1 : (x == INT32_MIN && y == -1) ? x
                                                     : (int32_t)soft_div(x, y)); }
    case K_DIVUW: { uint32_t x = (uint32_t)a, y = (uint32_t)b;
                    return (uint64_t)sx32(y == 0 ? ~0u : (uint32_t)soft_quot(x, y)); }
    case K_REMW: { int32_t x = (int32_t)a, y = (int32_t)b;
                   return (uint64_t)(int64_t)(y == 0 ? x : (x == INT32_MIN && y == -1) ? 0
                                                     : (int32_t)soft_rem(x, y)); }
    case K_REMUW: { uint32_t x = (uint32_t)a, y = (uint32_t)b;
                    return (uint64_t)sx32(y == 0 ? x : (uint32_t)soft_mod(x, y)); }
    case K_ADDI: return a + (uint64_t)imm;
    case K_SLTI: return sa < imm;
    case K_SLTIU: return a < (uint64_t)imm;
    case K_XORI: return a ^ (uint64_t)imm;
    case K_ORI:  return a | (uint64_t)imm;
    case K_ANDI: return a & (uint64_t)imm;
    case K_SLLI: return a << (imm & 63);
    case K_SRLI: return a >> (imm & 63);
    case K_SRAI: return (uint64_t)(sa >> (imm & 63));
    case K_ADDIW: return (uint64_t)sx32(a + (uint64_t)imm);
    case K_SLLIW: return (uint64_t)sx32((uint32_t)a << (imm & 31));
    case K_SRLIW: return (uint64_t)sx32((uint32_t)a >> (imm & 31));
    case K_SRAIW: return (uint64_t)(int64_t)((int32_t)a >> (imm & 31));
    case K_LUI:  return (uint64_t)(int64_t)(int32_t)((uint32_t)imm << 12);
    default: return 0;
    }
}

/* operand values that hit the M-extension corner cases */
static const uint64_t g_seeds_edge[] = { 0, 1, ~0UL, 0x8000000000000000UL, 0x7fffffffffffffffUL,
                                         0x80000000UL, 0xffffffff80000000UL, 0x7fffffffUL, 2, 3 };

int main(void) {
    st_init();
    st_section("JIT rounds");
    uint64_t bad = 0;
    static uint64_t init[32];
    for (int r = 0; r < ROUNDS; r++) {
        uint64_t base = (uint64_t)g_code[r & 1];
        /* register init values: mix of random and corner cases */
        for (int i = 0; i < 14; i++) init[i] = (st_rand() & 3) ? st_rand() : g_seeds_edge[st_rand_range(ST_ARRAY_LEN(g_seeds_edge))];
        uint64_t at = base;
        if (r & 2) { *(volatile uint16_t *)at = ENC_C_NOP; at += 2; }   /* misalign everything */
        for (int i = 0; i < 14; i++) { st_put_insn32(at, enc_i(8 * i, 10, 3, g_regs[i], 0x03)); at += 4; }  /* ld */
        for (int i = 0; i < NINSN; i++) {
            op_t *o = &g_prog[i];
            o->kind = (uint8_t)st_rand_range(K_N);
            o->rd = g_regs[st_rand_range(14)]; o->rs1 = g_regs[st_rand_range(14)]; o->rs2 = g_regs[st_rand_range(14)];
            o->imm = (int32_t)st_rand_range(4096) - 2048;
            if (o->kind == K_LUI) o->imm = (int32_t)st_rand_range(1 << 20);
            if (o->kind == K_CNOP) { *(volatile uint16_t *)at = ENC_C_NOP; at += 2; continue; }
            st_put_insn32(at, encode(o));
            at += 4;
        }
        /* fold: a0 = xor of all 14 registers */
        st_put_insn32(at, enc_i(0, 0, 0, 10, 0x13)); at += 4;              /* li a0, 0 */
        for (int i = 0; i < 14; i++) { st_put_insn32(at, enc_r(0, g_regs[i], 10, 4, 10, 0x33)); at += 4; }
        st_put_insn32(at, ENC_RET);
        st_fence_i();
        uint64_t got = ((uint64_t (*)(uint64_t))base)((uint64_t)init);

        uint64_t reg[32] = { 0 };
        for (int i = 0; i < 14; i++) reg[g_regs[i]] = init[i];
        for (int i = 0; i < NINSN; i++) {
            const op_t *o = &g_prog[i];
            if (o->kind == K_CNOP) continue;
            reg[o->rd] = exec_model(o, reg[o->rs1], reg[o->rs2]);
        }
        uint64_t want = 0;
        for (int i = 0; i < 14; i++) want ^= reg[g_regs[i]];
        if (got != want) { bad++; st_check_failed("JIT result", got, want, r); }
        else g_st_pass++;
    }
    ST_CHECK_EQ("every JIT round matched the ISA model", bad, 0);
    return st_result();
}
