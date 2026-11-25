/*
 * misalign -- misaligned accesses from userland on a core that traps them.
 * ZICCLSM = 0, so every one of these goes U -> M, where OpenSBI emulates it
 * byte by byte through MPRV and returns.  Every width, every offset, across a
 * 16-byte line and across a 4 KiB page; values checked against a byte model.
 * A misaligned AMO cannot be emulated and must be refused with a signal
 * (SIGBUS, or SIGSEGV) -- not performed, not a hang, not an SBI panic.
 */
#include "ustress.h"
#define NAME "misalign"

#define LD(insn, a) ({ unsigned long r; __asm__ volatile (insn " %0, 0(%1)" : "=r"(r) : "r"(a) : "memory"); r; })
#define ST(insn, a, v) __asm__ volatile (insn " %0, 0(%1)" :: "r"(v), "r"(a) : "memory")

static u_jmpbuf jb;
static volatile int g_sig;
static void on_sig(int sig, void *i, void *u) { (void)i; (void)u; g_sig = sig; u_longjmp(jb, 1); }

static unsigned long model(volatile unsigned char *p, int n, int sgn)
{
    unsigned long v = 0;
    for (int i = n - 1; i >= 0; i--) v = (v << 8) | p[i];
    if (sgn && n < 8) { int sh = 64 - 8 * n; v = (unsigned long)((long)(v << sh) >> sh); }
    return v;
}

int main(void)
{
    volatile unsigned char *buf = (volatile unsigned char *)sys_mmap(0, 2 * U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if ((long)buf < 0 && (long)buf > -4096) U_FAIL(NAME, "mmap");
    unsigned long sum = 0, n = 0;
    static const long bases[] = { 64, 64 + 13, U_PAGE - 4, U_PAGE - 6, U_PAGE - 1 };
    for (int rep = 0; rep < 6; rep++)
        for (unsigned b = 0; b < sizeof bases / sizeof bases[0]; b++)
            for (int off = 1; off < 8; off++) {
                volatile unsigned char *a = buf + bases[b] + off - 1;
                unsigned long v = u_rand();
                ST("sd", a, v);
                if (LD("ld", a) != model(a, 8, 0)) U_FAIL(NAME, "ld");
                if (model(a, 8, 0) != v) U_FAIL(NAME, "sd");
                ST("sw", a + 1, v >> 7);
                if (LD("lw", a + 1) != model(a + 1, 4, 1)) U_FAIL(NAME, "lw");
                if (LD("lwu", a + 1) != model(a + 1, 4, 0)) U_FAIL(NAME, "lwu");
                ST("sh", a + 3, v >> 13);
                if (LD("lh", a + 3) != model(a + 3, 2, 1)) U_FAIL(NAME, "lh");
                if (LD("lhu", a + 3) != model(a + 3, 2, 0)) U_FAIL(NAME, "lhu");
                sum += model(a, 8, 0);
                n++;
            }
    u_signal(SIGBUS, on_sig);
    u_signal(SIGSEGV, on_sig);
    volatile unsigned long *x = (volatile unsigned long *)(buf + 128);
    *x = 5;
    if (u_setjmp(jb) == 0) {
        __asm__ volatile ("amoadd.w zero, %1, (%0)" :: "r"((char *)x + 2), "r"(1L) : "memory");
        U_FAIL(NAME, "misaligned AMO was performed");
    }
    if (g_sig != SIGBUS && g_sig != SIGSEGV) U_FAIL(NAME, "misaligned AMO: wrong signal");
    if (*x != 5) U_FAIL(NAME, "misaligned AMO modified memory");
    return prog_pass(NAME, sum ^ n);
}
