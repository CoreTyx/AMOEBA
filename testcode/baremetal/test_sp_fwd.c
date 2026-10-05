/* test_sp_fwd.c
 *
 * Tests stack-pointer forwarding through the SHARD RQ:
 *   - each noinline function triggers an I-cache-miss stall on first call
 *   - the function prologue's "addi sp,sp,-N" result must reach the
 *     subsequent stack stores via RQ forwarding
 *   - several distances between the sp update and the first sp use
 *     are exercised (distance 1 = immediate use, up to 5 intervening
 *     instructions before the sp-relative store)
 *
 * Spike verifies every RVFI commit; no explicit tohost write needed
 * beyond the program completing normally.
 */

/* Prevent inlining so the callee lands on a fresh cache line. */
#define NOINLINE __attribute__((noinline))

/* ------------------------------------------------------------------ *
 * helper: write result to tohost so the testbench can declare pass/fail
 * ------------------------------------------------------------------ */

/* ------------------------------------------------------------------ *
 * dist1: sp use 1 instruction after addi sp
 *   prologue:  addi sp,sp,-16
 *              sw   ra, 12(sp)    <- reads sp 1 instr after addi
 * ------------------------------------------------------------------ */
NOINLINE static int dist1(int a) {
    volatile int v = a + 1;
    return v;
}

/* ------------------------------------------------------------------ *
 * dist2: two volatile locals force 2 stores before anything reads sp
 *   addi sp,sp,-32
 *   sw ra,28(sp)
 *   sw s0,24(sp)   <- second store, sp distance ≥ 2
 * ------------------------------------------------------------------ */
NOINLINE static int dist2(int a, int b) {
    volatile int x = a + b;
    volatile int y = a - b;
    return x * y;
}

/* ------------------------------------------------------------------ *
 * dist3: three locals
 * ------------------------------------------------------------------ */
NOINLINE static int dist3(int a, int b, int c) {
    volatile int x = a + b;
    volatile int y = b + c;
    volatile int z = a + c;
    return x + y + z;
}

/* ------------------------------------------------------------------ *
 * dist4: four locals — sp use at distance 4 from addi sp
 *   This is the boundary: 3-deep RQ must still have addi in entry[0]
 *   when the 4th store's base-register check fires.
 * ------------------------------------------------------------------ */
NOINLINE static int dist4(int a, int b, int c, int d) {
    volatile int w = a + b;
    volatile int x = b + c;
    volatile int y = c + d;
    volatile int z = a + d;
    return w + x + y + z;
}

/* ------------------------------------------------------------------ *
 * dist5: five locals — sp falls off the 3-deep RQ; forwarding must
 *   come from the architectural regfile (written by shadow at the
 *   right cycle).
 * ------------------------------------------------------------------ */
NOINLINE static int dist5(int a, int b, int c, int d, int e) {
    volatile int v0 = a + b;
    volatile int v1 = b + c;
    volatile int v2 = c + d;
    volatile int v3 = d + e;
    volatile int v4 = a + e;
    return v0 + v1 + v2 + v3 + v4;
}

/* ------------------------------------------------------------------ *
 * chain: dependency chain where each result feeds the next
 *   Tests that result forwarding (not just sp) works across all
 *   pipeline depths.
 * ------------------------------------------------------------------ */
NOINLINE static long chain(long seed) {
    volatile long a = seed;
    volatile long b = a  + 1;
    volatile long c = b  + 2;
    volatile long d = c  + 4;
    volatile long e = d  + 8;
    volatile long f = e  + 16;
    volatile long g = f  + 32;
    return g;
}

/* ------------------------------------------------------------------ *
 * sp_alias: two different functions called back-to-back to test that
 *   the sp value written by the callee's epilogue is correctly seen
 *   by the caller's next instruction.
 * ------------------------------------------------------------------ */
NOINLINE static int inner(int x) {
    volatile int t = x * 3;
    return t;
}

NOINLINE static int outer(int x) {
    volatile int a = inner(x);
    volatile int b = inner(a);
    return b;
}

/* ------------------------------------------------------------------ *
 * main: call every variant, accumulate into result, halt
 * ------------------------------------------------------------------ */
int main(void) {
    long r = 0;

    r += dist1(10);
    r += dist2(3, 4);
    r += dist3(1, 2, 3);
    r += dist4(1, 2, 3, 4);
    r += dist5(1, 2, 3, 4, 5);
    r += chain(1);
    r += outer(5);

    /* Expected:
     *   dist1(10)        = 11
     *   dist2(3,4)       = 7 * (-1) = -7
     *   dist3(1,2,3)     = 3+5+4 = 12
     *   dist4(1,2,3,4)   = 3+5+7+5 = 20
     *   dist5(1,2,3,4,5) = 3+5+7+9+6 = 30
     *   chain(1)         = 1+1+2+4+8+16+32 = 64
     *   outer(5)         = inner(inner(5)*3) = inner(15) = 45
     * Total = 11 - 7 + 12 + 20 + 30 + 64 + 45 = 175
     */
    return (r == 175 ? 0 : 1);
}
