///////////////////////////////////////////
// tc_forwarding.c
//
// Tests register forwarding at every pipeline depth and the
// specific SHARD RQ forwarding paths:
//
//   TC_FWD_MW     : M/W-stage bypass (distance 1-3)
//   TC_FWD_RQ     : RQ forwarding (distance 4-6, N=3-deep RQ)
//   TC_FWD_REGFILE: regfile read (distance 7+, shadow committed)
//   TC_SP_FWD     : addi-sp then sp-relative stores (basic_arith pattern)
//   TC_DEP_CHAIN  : long dependency chains
//   TC_LOAD_USE   : load-use hazard then forwarding
//   TC_WAW        : write-after-write same register
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

#include "test_utils.h"

/* ---------------------------------------------------------------
 * Forward-at-distance helpers.
 * The .rept N / add x0,x0,x0 spacers generate exactly N nop-equivalent
 * instructions between the "move seed into output reg" and the read.
 * Compiled with GCC for RISC-V these expand to actual instructions.
 * --------------------------------------------------------------- */
static long __attribute__((noinline)) fwd_at(long seed, int d) {
    long r = seed;
    switch (d) {
    /* Each case has d independent nops then reads seed again. */
    case 1: __asm__ volatile (
        "add x0,x0,x0\n\tadd %0,%1,x0"
        :"=r"(r):"r"(seed)); break;
    case 2: __asm__ volatile (
        "add x0,x0,x0\n\tadd x0,x0,x0\n\tadd %0,%1,x0"
        :"=r"(r):"r"(seed)); break;
    case 3: __asm__ volatile (
        "add x0,x0,x0\n\tadd x0,x0,x0\n\tadd x0,x0,x0\n\tadd %0,%1,x0"
        :"=r"(r):"r"(seed)); break;
    case 4: __asm__ volatile (
        "add x0,x0,x0\n\tadd x0,x0,x0\n\tadd x0,x0,x0\n\t"
        "add x0,x0,x0\n\tadd %0,%1,x0"
        :"=r"(r):"r"(seed)); break;
    case 5: __asm__ volatile (
        "add x0,x0,x0\n\tadd x0,x0,x0\n\tadd x0,x0,x0\n\t"
        "add x0,x0,x0\n\tadd x0,x0,x0\n\tadd %0,%1,x0"
        :"=r"(r):"r"(seed)); break;
    case 6: __asm__ volatile (
        "add x0,x0,x0\n\tadd x0,x0,x0\n\tadd x0,x0,x0\n\t"
        "add x0,x0,x0\n\tadd x0,x0,x0\n\tadd x0,x0,x0\n\tadd %0,%1,x0"
        :"=r"(r):"r"(seed)); break;
    case 7: __asm__ volatile (
        "add x0,x0,x0\n\tadd x0,x0,x0\n\tadd x0,x0,x0\n\t"
        "add x0,x0,x0\n\tadd x0,x0,x0\n\tadd x0,x0,x0\n\t"
        "add x0,x0,x0\n\tadd %0,%1,x0"
        :"=r"(r):"r"(seed)); break;
    case 8: __asm__ volatile (
        "add x0,x0,x0\n\tadd x0,x0,x0\n\tadd x0,x0,x0\n\t"
        "add x0,x0,x0\n\tadd x0,x0,x0\n\tadd x0,x0,x0\n\t"
        "add x0,x0,x0\n\tadd x0,x0,x0\n\tadd %0,%1,x0"
        :"=r"(r):"r"(seed)); break;
    default: r = seed; break;
    }
    return r;
}

/* ---------------------------------------------------------------
 * SP forwarding: noinline functions whose prologue emits
 * "addi sp,sp,-N" immediately followed by sp-relative stores.
 * --------------------------------------------------------------- */
static __attribute__((noinline)) int sp_d1(int v) {
    volatile int a = v;
    return a + 1; /* expect v+1 */
}
static __attribute__((noinline)) int sp_d2(int v) {
    volatile int a = v, b = v + 1;
    return a + b; /* expect 2v+1 */
}
static __attribute__((noinline)) int sp_d3(int v) {
    volatile int a = v, b = v + 1, c = v + 2;
    return a + b + c; /* expect 3v+3 */
}
static __attribute__((noinline)) int sp_d4(int v) {
    volatile int a = v, b = v+1, c = v+2, d = v+3;
    return a + b + c + d; /* expect 4v+6 */
}

/* ---------------------------------------------------------------
 * Dependency chain: each volatile assignment depends on the previous
 * (compiler enforces sequential stores/loads).
 * --------------------------------------------------------------- */
static __attribute__((noinline)) long dep_chain(long x) {
    volatile long a = x + 1;
    volatile long b = a + 2;
    volatile long c = b + 4;
    volatile long d = c + 8;
    volatile long e = d + 16;
    volatile long f = e + 32;
    return f; /* x + 63 */
}

/* ---------------------------------------------------------------
 * Load-use hazard: load from memory then immediately use the result.
 * --------------------------------------------------------------- */
static __attribute__((noinline)) long load_use(void) {
    volatile long arr[4] = {10, 20, 30, 40};
    return arr[0] + arr[1] + arr[2] + arr[3]; /* 100 */
}

/* ---------------------------------------------------------------
 * Write-after-write: two successive writes to the same logical
 * destination; the reader must see the latest one.
 * --------------------------------------------------------------- */
static __attribute__((noinline)) long waw(long x) {
    long r;
    /* first write x+10, then overwrite with x+20, then read */
    __asm__ volatile (
        "add  %0, %1, x0  \n\t"   /* r = x */
        "addi %0, %0, 10  \n\t"   /* r = x+10 */
        "addi %0, %1, 20  \n\t"   /* r = x+20  (same output reg) */
        : "+r"(r) : "r"(x)
    );
    return r; /* expect x+20 */
}

/* ---------------------------------------------------------------
 * Nested call: caller must see sp restored correctly after callee
 * modifies and restores the stack.
 * --------------------------------------------------------------- */
static __attribute__((noinline)) int inner(int x) {
    volatile int t = x * 3;
    return t;
}
static __attribute__((noinline)) int nested(int x) {
    volatile int a = inner(x);
    volatile int b = inner(x + 1);
    return a + b; /* 3x + 3(x+1) = 6x+3 */
}

/* ---------------------------------------------------------------
 * Main
 * --------------------------------------------------------------- */
int main(void) {

    test_begin("TC_FWD_MW");
    check("d1 seed=0xAA", fwd_at(0xAA, 1), 0xAAL);
    check("d2 seed=0xBB", fwd_at(0xBB, 2), 0xBBL);
    check("d3 seed=0xCC", fwd_at(0xCC, 3), 0xCCL);

    test_begin("TC_FWD_RQ");
    check("d4 seed=0xDD", fwd_at(0xDD, 4), 0xDDL);
    check("d5 seed=0xEE", fwd_at(0xEE, 5), 0xEEL);
    check("d6 seed=0xFF", fwd_at(0xFF, 6), 0xFFL);

    test_begin("TC_FWD_REGFILE");
    check("d7 seed=0x111", fwd_at(0x111, 7), 0x111L);
    check("d8 seed=0x222", fwd_at(0x222, 8), 0x222L);

    test_begin("TC_SP_FWD");
    check("sp_d1(10)=11",  (long)sp_d1(10), 11L);
    check("sp_d2(5)=11",   (long)sp_d2(5),  11L);
    check("sp_d3(4)=15",   (long)sp_d3(4),  15L);
    check("sp_d4(3)=18",   (long)sp_d4(3),  18L);

    test_begin("TC_DEP_CHAIN");
    check("chain(0)=63",  dep_chain(0),  63L);
    check("chain(1)=64",  dep_chain(1),  64L);
    check("chain(-1)=62", dep_chain(-1), 62L);

    test_begin("TC_LOAD_USE");
    check("load_use=100", load_use(), 100L);

    test_begin("TC_WAW");
    check("waw(0)=20",  waw(0),   20L);
    check("waw(5)=25",  waw(5),   25L);
    check("waw(-5)=15", waw(-5L), 15L);

    test_begin("TC_NESTED_CALL");
    check("nested(0)=3",  (long)nested(0), 3L);
    check("nested(2)=15", (long)nested(2), 15L);

    print_summary();
    test_finish();
}
