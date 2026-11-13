/*
 * arith: integer datapath under Linux, in U-mode with the MMU on.
 *
 *  1. Every RV64M instruction and the shift family, by inline asm, against a
 *     table of expected results.  The table covers the corners the spec pins
 *     down (divide by zero, INT_MIN / -1, the W forms' sign extension, shift
 *     amounts above XLEN) and was generated offline from a Python model of the
 *     ISA manual's M-extension semantics.
 *  2. Oracle-free identities over pseudo-random operands: a*b against a
 *     software shift-and-add multiply, and q*b + r == a with |r| < |b| for
 *     signed and unsigned division.
 *  3. CRC-32: the standard check value of "123456789" (0xCBF43926), then a
 *     bitwise CRC of a 4 KiB buffer against a table-driven CRC of the same.
 */
#include "ulib.h"

enum {
    OP_MUL, OP_MULH, OP_MULHU, OP_MULHSU, OP_MULW,
    OP_DIV, OP_DIVU, OP_REM, OP_REMU,
    OP_DIVW, OP_DIVUW, OP_REMW, OP_REMUW,
    OP_SLL, OP_SRL, OP_SRA, OP_SLLW, OP_SRLW, OP_SRAW,
};

struct vec { int op; unsigned long a, b, want; };

static const struct vec vecs[] = {
    { OP_MUL,    0x0123456789abcdefUL, 0xfedcba9876543210UL, 0x2236d88fe5618cf0UL },
    { OP_MULH,   0x0123456789abcdefUL, 0xfedcba9876543210UL, 0xfffeb49923cc0953UL },
    { OP_MULHU,  0x0123456789abcdefUL, 0xfedcba9876543210UL, 0x0121fa00ad77d742UL },
    { OP_MULHSU, 0xfedcba9876543210UL, 0x0123456789abcdefUL, 0xfffeb49923cc0953UL },
    { OP_MULHSU, 0x0123456789abcdefUL, 0xfedcba9876543210UL, 0x0121fa00ad77d742UL },
    { OP_MULH,   0x8000000000000000UL, 0x8000000000000000UL, 0x4000000000000000UL },
    { OP_MULHU,  0xffffffffffffffffUL, 0xffffffffffffffffUL, 0xfffffffffffffffeUL },
    { OP_MULW,   0x00000000deadbeefUL, 0x0000000000012345UL, 0xffffffff84de236bUL },
    { OP_MUL,    0x7fffffffffffffffUL, 0x7fffffffffffffffUL, 0x0000000000000001UL },
    { OP_DIV,    0x0123456789abcdefUL, 0x0000000000001234UL, 0x000010004c016906UL },
    { OP_DIV,    0xfedcba9876543210UL, 0x0000000000001234UL, 0xffffefffb3fe96faUL },
    { OP_DIV,    0xfedcba9876543210UL, 0xfffffffffffffff9UL, 0x00299c335ccf6690UL },
    { OP_DIV,    0x0123456789abcdefUL, 0x0000000000000000UL, 0xffffffffffffffffUL },
    { OP_DIV,    0x8000000000000000UL, 0xffffffffffffffffUL, 0x8000000000000000UL },
    { OP_DIVU,   0xfedcba9876543210UL, 0x0000000000001234UL, 0x000e0042813be5dcUL },
    { OP_DIVU,   0x0123456789abcdefUL, 0x0000000000000000UL, 0xffffffffffffffffUL },
    { OP_REM,    0xfedcba9876543210UL, 0x0000000000001234UL, 0xfffffffffffff348UL },
    { OP_REM,    0x0123456789abcdefUL, 0xfffffffffffffff9UL, 0x0000000000000006UL },
    { OP_REM,    0x0123456789abcdefUL, 0x0000000000000000UL, 0x0123456789abcdefUL },
    { OP_REM,    0x8000000000000000UL, 0xffffffffffffffffUL, 0x0000000000000000UL },
    { OP_REMU,   0xfedcba9876543210UL, 0x0000000000001234UL, 0x0000000000000960UL },
    { OP_REMU,   0x0123456789abcdefUL, 0x0000000000000000UL, 0x0123456789abcdefUL },
    { OP_DIVW,   0x00000000deadbeefUL, 0x0000000000000007UL, 0xfffffffffb3d646cUL },
    { OP_DIVW,   0xffffffff80000000UL, 0xffffffffffffffffUL, 0xffffffff80000000UL },
    { OP_DIVW,   0x00000000deadbeefUL, 0x0000000000000000UL, 0xffffffffffffffffUL },
    { OP_DIVUW,  0x00000000deadbeefUL, 0x0000000000000007UL, 0x000000001fcfad8fUL },
    { OP_DIVUW,  0x00000000deadbeefUL, 0x0000000000000000UL, 0xffffffffffffffffUL },
    { OP_REMW,   0x00000000deadbeefUL, 0x0000000000000007UL, 0xfffffffffffffffbUL },
    { OP_REMW,   0xffffffff80000000UL, 0xffffffffffffffffUL, 0x0000000000000000UL },
    { OP_REMW,   0x00000000deadbeefUL, 0x0000000000000000UL, 0xffffffffdeadbeefUL },
    { OP_REMUW,  0x00000000deadbeefUL, 0x0000000000000007UL, 0x0000000000000006UL },
    { OP_REMUW,  0x00000000deadbeefUL, 0x0000000000000000UL, 0xffffffffdeadbeefUL },
    { OP_SLL,    0x0123456789abcdefUL, 0x0000000000000004UL, 0x123456789abcdef0UL },
    { OP_SLL,    0x0123456789abcdefUL, 0x0000000000000043UL, 0x091a2b3c4d5e6f78UL },
    { OP_SRL,    0xfedcba9876543210UL, 0x000000000000000dUL, 0x0007f6e5d4c3b2a1UL },
    { OP_SRA,    0xfedcba9876543210UL, 0x000000000000000dUL, 0xfffff6e5d4c3b2a1UL },
    { OP_SRA,    0xfedcba9876543210UL, 0x000000000000003fUL, 0xffffffffffffffffUL },
    { OP_SLLW,   0x00000000deadbeefUL, 0x0000000000000004UL, 0xffffffffeadbeef0UL },
    { OP_SRLW,   0x00000000deadbeefUL, 0x0000000000000021UL, 0x000000006f56df77UL },
    { OP_SRAW,   0x00000000deadbeefUL, 0x0000000000000005UL, 0xfffffffffef56df7UL },
    { OP_SRAW,   0xffffffff80000000UL, 0x000000000000001fUL, 0xffffffffffffffffUL },
};

#define RR(insn, a, b) ({ unsigned long _r;                                   \
        __asm__ volatile (insn " %0, %1, %2" : "=r"(_r) : "r"(a), "r"(b));     \
        _r; })

static unsigned long exec_op(int op, unsigned long a, unsigned long b)
{
    switch (op) {
    case OP_MUL:    return RR("mul",    a, b);
    case OP_MULH:   return RR("mulh",   a, b);
    case OP_MULHU:  return RR("mulhu",  a, b);
    case OP_MULHSU: return RR("mulhsu", a, b);
    case OP_MULW:   return RR("mulw",   a, b);
    case OP_DIV:    return RR("div",    a, b);
    case OP_DIVU:   return RR("divu",   a, b);
    case OP_REM:    return RR("rem",    a, b);
    case OP_REMU:   return RR("remu",   a, b);
    case OP_DIVW:   return RR("divw",   a, b);
    case OP_DIVUW:  return RR("divuw",  a, b);
    case OP_REMW:   return RR("remw",   a, b);
    case OP_REMUW:  return RR("remuw",  a, b);
    case OP_SLL:    return RR("sll",    a, b);
    case OP_SRL:    return RR("srl",    a, b);
    case OP_SRA:    return RR("sra",    a, b);
    case OP_SLLW:   return RR("sllw",   a, b);
    case OP_SRLW:   return RR("srlw",   a, b);
    case OP_SRAW:   return RR("sraw",   a, b);
    }
    return 0;
}

static unsigned long rng = 0x9e3779b97f4a7c15UL;
static unsigned long next_rand(void)
{
    /* xorshift64 */
    rng ^= rng << 13;
    rng ^= rng >> 7;
    rng ^= rng << 17;
    return rng;
}

static unsigned long soft_mul(unsigned long a, unsigned long b)
{
    unsigned long r = 0;
    for (int i = 0; i < 64; i++)
        if ((b >> i) & 1)
            r += a << i;
    return r;
}

static unsigned char buf[4096];

int main(void)
{
    static const char *const name = "arith";
    unsigned sum = 0;

    for (unsigned i = 0; i < sizeof vecs / sizeof vecs[0]; i++) {
        const struct vec *v = &vecs[i];
        unsigned long got = exec_op(v->op, opaque(v->a), opaque(v->b));
        if (got != v->want) {
            out_str("PROG arith FAIL vec ");
            out_dec(i);
            out_str(" got ");
            out_hex(got);
            out_str(" want ");
            out_hex(v->want);
            out_str("\n");
            return 1;
        }
        sum = crc32_update(sum, &got, sizeof got);
    }

    for (int i = 0; i < 64; i++) {
        unsigned long a = next_rand(), b = next_rand();
        /* Vary the divisor's magnitude so small and large quotients both
         * appear, and never let it be zero. */
        unsigned long ub = (b >> (b & 63)) | 1;
        long sa = (long)a, sb = (long)ub * ((a & 1) ? -1 : 1);

        if (opaque(a) * opaque(b) != soft_mul(a, b))
            return prog_fail(name, "mul-vs-soft");

        unsigned long uq = opaque(a) / opaque(ub), ur = opaque(a) % opaque(ub);
        if (uq * ub + ur != a || ur >= ub)
            return prog_fail(name, "divu-identity");

        long sq = (long)opaque(sa) / (long)opaque(sb);
        long sr = (long)opaque(sa) % (long)opaque(sb);
        unsigned long asr = sr < 0 ? -(unsigned long)sr : (unsigned long)sr;
        unsigned long asb = sb < 0 ? -(unsigned long)sb : (unsigned long)sb;
        if (sq * sb + sr != sa || asr >= asb || (sr != 0 && (sr < 0) != (sa < 0)))
            return prog_fail(name, "div-identity");

        sum = crc32_update(sum, &uq, sizeof uq);
        sum = crc32_update(sum, &sr, sizeof sr);
    }

    if (crc32("123456789", 9) != 0xCBF43926u)
        return prog_fail(name, "crc32-check-value");

    unsigned table[256];
    for (unsigned n = 0; n < 256; n++) {
        unsigned c = n;
        for (int k = 0; k < 8; k++)
            c = (c >> 1) ^ (0xEDB88320u & -(c & 1));
        table[n] = c;
    }
    for (unsigned i = 0; i < sizeof buf; i++)
        buf[i] = (unsigned char)next_rand();
    unsigned t = ~0u;
    for (unsigned i = 0; i < sizeof buf; i++)
        t = table[(t ^ buf[i]) & 0xff] ^ (t >> 8);
    t = ~t;
    unsigned b = crc32(buf, sizeof buf);
    if (t != b)
        return prog_fail(name, "crc32-table-vs-bitwise");

    sum = crc32_update(sum, &b, sizeof b);
    return prog_pass(name, sum);
}
