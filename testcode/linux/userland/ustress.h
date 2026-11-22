/*
 * ustress.h -- helpers for the Linux userland stress programs (header-only:
 * include once, from the program's .c).  Freestanding, like the rest of
 * userland/: no libc, raw syscalls from syscall.h, output via ulib.
 */
#ifndef AMOEBA_USTRESS_H
#define AMOEBA_USTRESS_H
#include "ulib.h"

/* ---- minimal setjmp/longjmp, for leaving a signal handler -------------- */
typedef unsigned long u_jmpbuf[14];
extern int  u_setjmp(u_jmpbuf jb);
extern void u_longjmp(u_jmpbuf jb, int v) __attribute__((noreturn));
__asm__ (
    ".text\n.globl u_setjmp\nu_setjmp:\n"
    "  sd ra, 0(a0)\n  sd sp, 8(a0)\n  sd s0, 16(a0)\n  sd s1, 24(a0)\n"
    "  sd s2, 32(a0)\n  sd s3, 40(a0)\n  sd s4, 48(a0)\n  sd s5, 56(a0)\n"
    "  sd s6, 64(a0)\n  sd s7, 72(a0)\n  sd s8, 80(a0)\n  sd s9, 88(a0)\n"
    "  sd s10, 96(a0)\n  sd s11, 104(a0)\n  li a0, 0\n  ret\n"
    ".globl u_longjmp\nu_longjmp:\n"
    "  ld ra, 0(a0)\n  ld sp, 8(a0)\n  ld s0, 16(a0)\n  ld s1, 24(a0)\n"
    "  ld s2, 32(a0)\n  ld s3, 40(a0)\n  ld s4, 48(a0)\n  ld s5, 56(a0)\n"
    "  ld s6, 64(a0)\n  ld s7, 72(a0)\n  ld s8, 80(a0)\n  ld s9, 88(a0)\n"
    "  ld s10, 96(a0)\n  ld s11, 104(a0)\n"
    "  seqz a0, a1\n  add a0, a0, a1\n  ret\n"
);

/* ---- signals ------------------------------------------------------------ */
typedef void (*u_sigfn)(int, void *, void *);
/* SA_NODEFER: handlers leave with u_longjmp, so the signal must not stay blocked */
static inline int u_signal(int sig, u_sigfn fn)
{
    struct k_sigaction a = { fn, SA_SIGINFO | SA_NODEFER | SA_RESTART, 0 };
    return sys_rt_sigaction(sig, &a, 0);
}
/* siginfo_t: si_signo @0, si_errno @4, si_code @8, si_addr @16 (64-bit) */
static inline int   si_code(void *info) { return ((int *)info)[2]; }
static inline void *si_addr(void *info) { return *(void **)((char *)info + 16); }

/* ---- PRNG / mixing ------------------------------------------------------ */
static unsigned long u_rng = 0x9E3779B97F4A7C15UL;
static inline unsigned long u_rand(void)
{
    unsigned long x = u_rng;
    x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
    u_rng = x;
    return x * 0x2545F4914F6CDD1DUL;
}
static inline unsigned long u_mix(unsigned long x)
{
    x ^= x >> 30; x *= 0xBF58476D1CE4E5B9UL;
    x ^= x >> 27; x *= 0x94D049BB133111EBUL;
    return x ^ (x >> 31);
}

static inline long u_now_ns(void)
{
    struct timespec t;
    sys_clock_gettime(CLOCK_MONOTONIC, &t);
    return t.tv_sec * 1000000000L + t.tv_nsec;
}

#define U_PAGE 4096UL
#define U_FAIL(name, why) do { return prog_fail((name), (why)); } while (0)
#endif
