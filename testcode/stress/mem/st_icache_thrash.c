// @stress tier=pr seeds=2 build=spike duts=legacy timeout=30000000
// @stress-variant build=no_spike duts=forte
//
// st_icache_thrash -- I$ conflict misses, line-straddling instructions.
//
// The I$ is 2 ways x 1 KiB with 16-byte lines.  Sixteen generated functions sit
// at 1 KiB alignment, so the same sets are wanted by all sixteen and every call
// in a random order evicts.  Half the functions mix compressed and 32-bit
// instructions behind a leading c.nop, so many 32-bit instructions straddle a
// 16-byte line boundary and need two line fetches -- the case where a refill
// racing a fetch-buffer split goes wrong.  Each function's result is
// predicted in C; under Spike co-simulation every instruction is also checked.
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define NFUNC 16
#define CALLS (2000 * ST_SCALE)

/* fN: a0 = 0; repeat 40x { a0 += N+1 ; a0 ^= 0x55 } ; ret.
 * Odd N: compressed variant (c.addi, then 32-bit xori -> straddles). */
#define FUNC(N, RVC) \
    ".balign 1024\n" \
    ".globl st_ifn" #N "\n" \
    "st_ifn" #N ":\n" \
    ".option push\n" RVC "\n" \
    "    li a0, 0\n" \
    "    .2byte 0x0001\n" /* c.nop: misaligns what follows */ \
    "    .rept 40\n" \
    "    addi a0, a0, " #N " + 1\n" \
    "    xori a0, a0, 0x55\n" \
    "    .endr\n" \
    "    ret\n" \
    ".option pop\n"

__asm__ (".text\n"
    FUNC(0, ".option norvc") FUNC(1, ".option rvc") FUNC(2, ".option norvc") FUNC(3, ".option rvc")
    FUNC(4, ".option norvc") FUNC(5, ".option rvc") FUNC(6, ".option norvc") FUNC(7, ".option rvc")
    FUNC(8, ".option norvc") FUNC(9, ".option rvc") FUNC(10, ".option norvc") FUNC(11, ".option rvc")
    FUNC(12, ".option norvc") FUNC(13, ".option rvc") FUNC(14, ".option norvc") FUNC(15, ".option rvc"));

extern uint64_t st_ifn0(void), st_ifn1(void), st_ifn2(void), st_ifn3(void), st_ifn4(void), st_ifn5(void),
                st_ifn6(void), st_ifn7(void), st_ifn8(void), st_ifn9(void), st_ifn10(void), st_ifn11(void),
                st_ifn12(void), st_ifn13(void), st_ifn14(void), st_ifn15(void);
static uint64_t (*const g_fn[NFUNC])(void) = {
    st_ifn0, st_ifn1, st_ifn2, st_ifn3, st_ifn4, st_ifn5, st_ifn6, st_ifn7,
    st_ifn8, st_ifn9, st_ifn10, st_ifn11, st_ifn12, st_ifn13, st_ifn14, st_ifn15 };

static uint64_t model(int n) {
    int64_t a = 0;
    for (int i = 0; i < 40; i++) { a += n + 1; a ^= 0x55; }
    return (uint64_t)a;
}

int main(void) {
    st_init();
    st_section("random calls across 16 conflicting functions");
    uint64_t want[NFUNC];
    for (int i = 0; i < NFUNC; i++) want[i] = model(i);
    uint64_t bad = 0;
    for (int c = 0; c < CALLS; c++) {
        int f = (int)st_rand_range(NFUNC);
        if (g_fn[f]() != want[f]) bad++;
    }
    ST_CHECK_EQ("every call returned its predicted value", bad, 0);
    st_section("ping-pong between 3 functions in the same sets (2 ways)");
    bad = 0;
    for (int c = 0; c < CALLS / 2; c++) {
        int f = (c % 3) * 5;
        if (g_fn[f]() != want[f]) bad++;
    }
    ST_CHECK_EQ("3-way ping-pong on a 2-way cache", bad, 0);
    return st_result();
}
