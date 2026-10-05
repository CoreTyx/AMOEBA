/* test_fwd_depth.c
 *
 * Exercises register forwarding at pipeline depths 1-7+.
 * Each noinline function computes a value, returns it, and the
 * caller uses it immediately — Spike verifies every RVFI commit.
 *
 * Pattern summary
 * ---------------
 *  dist1(v) : write then read same reg 1 instr later  (M-stage bypass)
 *  dist2(v) : 2 instrs later                          (M-stage bypass)
 *  dist3(v) : 3 instrs later                          (W-stage bypass)
 *  dist4–6  : 4-6 instrs later                        (RQ forwarding)
 *  dist7+   : beyond RQ depth                         (regfile read)
 *  sp_*     : addi sp then sp-relative stores (the basic_arith pattern)
 */


/* Use register-constrained asm to guarantee a write→N-spacer→read
 * sequence with exactly N independent instructions between write and read.
 * The spacers use distinct outputs so the compiler can't merge them. */

#define FWD_TEST(NAME, N_SPACERS)                                        \
static long __attribute__((noinline)) NAME(long seed) {                  \
    long r, s0=0, s1=0, s2=0, s3=0, s4=0, s5=0, s6=0;                  \
    (void)s0; (void)s1; (void)s2; (void)s3;                             \
    (void)s4; (void)s5; (void)s6;                                       \
    /* Force the compiler to materialise seed in a register,             \
     * then read it back after N_SPACERS independent li-0 ops. */        \
    __asm__ volatile (                                                   \
        ".rept " #N_SPACERS "\n\t"                                       \
        "add x0, x0, x0     \n\t"  /* nop-equivalent spacer */          \
        ".endr\n\t"                                                      \
        "add %0, %1, x0     \n\t"  /* r = seed (N_SPACERS instrs later) */ \
        : "=r"(r)                                                        \
        : "r"(seed)                                                      \
    );                                                                   \
    return r;                                                            \
}

FWD_TEST(fwd1, 1)
FWD_TEST(fwd2, 2)
FWD_TEST(fwd3, 3)
FWD_TEST(fwd4, 4)
FWD_TEST(fwd5, 5)
FWD_TEST(fwd6, 6)
FWD_TEST(fwd7, 7)

/* SP-forwarding: noinline triggers I-cache miss on first call;
 * the function prologue emits "addi sp,sp,-N" which must forward
 * to the sp-relative stores that follow. */

static int __attribute__((noinline)) sp_d1(int v) {
    /* prologue: addi sp,-16; sw ra,12(sp) <- sp at dist 1 */
    volatile int a = v;
    return a + 1;
}
static int __attribute__((noinline)) sp_d2(int v) {
    volatile int a = v, b = v + 1;
    return a + b;
}
static int __attribute__((noinline)) sp_d3(int v) {
    volatile int a = v, b = v + 1, c = v + 2;
    return a + b + c;
}
static int __attribute__((noinline)) sp_d4(int v) {
    volatile int a = v, b = v + 1, c = v + 2, d = v + 3;
    return a + b + c + d;
}
static int __attribute__((noinline)) sp_d5(int v) {
    volatile int a = v, b = v+1, c = v+2, d = v+3, e = v+4;
    return a + b + c + d + e;
}

/* Nested calls: each call modifies and restores sp — tests that the
 * caller sees the correct sp after callee epilogue. */
static int __attribute__((noinline)) inner(int x) {
    volatile int t = x * 2;
    return t + 1;
}
static int __attribute__((noinline)) outer(int x) {
    volatile int a = inner(x);
    volatile int b = inner(x + 1);
    return a + b;
}

/* Dependency chain where each add feeds the next (dist-1 RAW hazard
 * through the entire chain). */
static long __attribute__((noinline)) chain7(long x) {
    volatile long a = x + 1;
    volatile long b = a + 2;
    volatile long c = b + 4;
    volatile long d = c + 8;
    volatile long e = d + 16;
    volatile long f = e + 32;
    volatile long g = f + 64;
    return g;
    /* g = x + 127 */
}

int main(void) {
    long r = 0;

    /* These just need to produce the right values; Spike verifies rvfi. */
    r += fwd1(10);  /* 10 */
    r += fwd2(20);  /* 20 */
    r += fwd3(30);  /* 30 */
    r += fwd4(40);  /* 40 */
    r += fwd5(50);  /* 50 */
    r += fwd6(60);  /* 60 */
    r += fwd7(70);  /* 70 */

    r += sp_d1(5);  /* 6  */
    r += sp_d2(5);  /* 11 */
    r += sp_d3(5);  /* 18 */
    r += sp_d4(5);  /* 26 */
    r += sp_d5(5);  /* 35 */

    r += outer(3);  /* inner(3)=7, inner(4)=9 → 16 */

    r += chain7(1); /* 128 */

    /* 10+20+30+40+50+60+70 + 6+11+18+26+35 + 16 + 128 = 520 */
    return (r == 520 ? 0 : 1);
}
