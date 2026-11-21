/*
 * signals -- signal delivery and sigreturn, the kernel paths that write a
 * frame onto the user stack and sret into a handler.
 *   1. SIGSEGV on unmapped addresses: si_addr exact, SEGV_MAPERR -- x20
 *   2. SIGILL on an illegal instruction: si_addr = the instruction
 *   3. SIGUSR1 to self: delivered before kill() returns
 *   4. SIGALRM every 10 ms (setitimer) landing on an asm loop that keeps 25
 *      registers at known values: after five alarms every register must still
 *      hold its value -- a register the trap/signal/sigreturn path loses or
 *      swaps breaks the loop
 */
#include "ustress.h"
#define NAME "signals"

extern long u_regloop(long cap, volatile long *alarms);
__asm__ (
".text\n.globl u_regloop\nu_regloop:\n"
"  addi sp, sp, -112\n  sd ra, 0(sp)\n  sd s0, 8(sp)\n  sd s1, 16(sp)\n  sd s2, 24(sp)\n  sd s3, 32(sp)\n  sd s4, 40(sp)\n  sd s5, 48(sp)\n  sd s6, 56(sp)\n  sd s7, 64(sp)\n  sd s8, 72(sp)\n  sd s9, 80(sp)\n  sd s10, 88(sp)\n  sd s11, 96(sp)\n"
"  li x5, 0x5a050505\n"
"  li x6, 0x5a060606\n"
"  li x7, 0x5a070707\n"
"  li x9, 0x5a090909\n"
"  li x12, 0x5a0c0c0c\n"
"  li x13, 0x5a0d0d0d\n"
"  li x14, 0x5a0e0e0e\n"
"  li x15, 0x5a0f0f0f\n"
"  li x16, 0x5a101010\n"
"  li x17, 0x5a111111\n"
"  li x18, 0x5a121212\n"
"  li x19, 0x5a131313\n"
"  li x20, 0x5a141414\n"
"  li x21, 0x5a151515\n"
"  li x22, 0x5a161616\n"
"  li x23, 0x5a171717\n"
"  li x24, 0x5a181818\n"
"  li x25, 0x5a191919\n"
"  li x26, 0x5a1a1a1a\n"
"  li x27, 0x5a1b1b1b\n"
"  li x28, 0x5a1c1c1c\n"
"  li x29, 0x5a1d1d1d\n"
"  li x30, 0x5a1e1e1e\n"
"  li x31, 0x5a1f1f1f\n"
"1:\n"
"  li s0, 0x5a050505\n  bne x5, s0, 3f\n"
"  li s0, 0x5a060606\n  bne x6, s0, 3f\n"
"  li s0, 0x5a070707\n  bne x7, s0, 3f\n"
"  li s0, 0x5a090909\n  bne x9, s0, 3f\n"
"  li s0, 0x5a0c0c0c\n  bne x12, s0, 3f\n"
"  li s0, 0x5a0d0d0d\n  bne x13, s0, 3f\n"
"  li s0, 0x5a0e0e0e\n  bne x14, s0, 3f\n"
"  li s0, 0x5a0f0f0f\n  bne x15, s0, 3f\n"
"  li s0, 0x5a101010\n  bne x16, s0, 3f\n"
"  li s0, 0x5a111111\n  bne x17, s0, 3f\n"
"  li s0, 0x5a121212\n  bne x18, s0, 3f\n"
"  li s0, 0x5a131313\n  bne x19, s0, 3f\n"
"  li s0, 0x5a141414\n  bne x20, s0, 3f\n"
"  li s0, 0x5a151515\n  bne x21, s0, 3f\n"
"  li s0, 0x5a161616\n  bne x22, s0, 3f\n"
"  li s0, 0x5a171717\n  bne x23, s0, 3f\n"
"  li s0, 0x5a181818\n  bne x24, s0, 3f\n"
"  li s0, 0x5a191919\n  bne x25, s0, 3f\n"
"  li s0, 0x5a1a1a1a\n  bne x26, s0, 3f\n"
"  li s0, 0x5a1b1b1b\n  bne x27, s0, 3f\n"
"  li s0, 0x5a1c1c1c\n  bne x28, s0, 3f\n"
"  li s0, 0x5a1d1d1d\n  bne x29, s0, 3f\n"
"  li s0, 0x5a1e1e1e\n  bne x30, s0, 3f\n"
"  li s0, 0x5a1f1f1f\n  bne x31, s0, 3f\n"
"  ld s0, 0(a1)\n  addi s0, s0, -5\n  bgez s0, 2f\n  addi a0, a0, -1\n  bnez a0, 1b\n"
"2: li a0, 0\n  j 4f\n3: li a0, 1\n"
"4: ld ra, 0(sp)\n  ld s0, 8(sp)\n  ld s1, 16(sp)\n  ld s2, 24(sp)\n  ld s3, 32(sp)\n  ld s4, 40(sp)\n  ld s5, 48(sp)\n  ld s6, 56(sp)\n  ld s7, 64(sp)\n  ld s8, 72(sp)\n  ld s9, 80(sp)\n  ld s10, 88(sp)\n  ld s11, 96(sp)\n  addi sp, sp, 112\n  ret\n"
);

static u_jmpbuf jb;
static volatile void *g_addr;
static volatile int g_code, g_sig;
static volatile long g_alarms, g_usr1;
static void on_fault(int sig, void *info, void *uc) { (void)uc; g_sig = sig; g_addr = si_addr(info); g_code = si_code(info); u_longjmp(jb, 1); }
static void on_alarm(int sig, void *info, void *uc) { (void)sig; (void)info; (void)uc; g_alarms++; }
static void on_usr1(int sig, void *info, void *uc) { (void)sig; (void)info; (void)uc; g_usr1++; }

int main(void)
{
    u_signal(SIGSEGV, on_fault);
    u_signal(SIGILL, on_fault);
    for (int i = 0; i < 20; i++) {
        volatile unsigned long *bad = (volatile unsigned long *)(0x1000UL * (unsigned long)(i + 1) + (unsigned long)(i * 8));
        if (u_setjmp(jb) == 0) { (void)*bad; U_FAIL(NAME, "load from unmapped page succeeded"); }
        if (g_sig != SIGSEGV || g_addr != (void *)bad || g_code != SEGV_MAPERR) U_FAIL(NAME, "SIGSEGV info");
    }
    static volatile unsigned long ill_at[1];
    if (u_setjmp(jb) == 0) {
        __asm__ volatile (".option push\n.option norvc\nla t0, 1f\nsd t0, 0(%0)\n1: .word 0x00000000\n.option pop" :: "r"(ill_at) : "t0", "memory");
        U_FAIL(NAME, "illegal instruction executed");
    }
    if (g_sig != SIGILL || g_addr != (void *)*(volatile unsigned long *)ill_at) U_FAIL(NAME, "SIGILL info");

    u_signal(SIGUSR1, on_usr1);
    for (int i = 0; i < 10; i++) {
        long before = g_usr1;
        sys_kill(sys_getpid(), SIGUSR1);
        if (g_usr1 != before + 1) U_FAIL(NAME, "SIGUSR1 not delivered on return from kill");
    }

    u_signal(SIGALRM, on_alarm);
    struct itimerval it = { { 0, 10000 }, { 0, 10000 } };
    if (sys_setitimer(ITIMER_REAL, &it, 0)) U_FAIL(NAME, "setitimer");
    long r = u_regloop(50000000, &g_alarms);
    struct itimerval off = { { 0, 0 }, { 0, 0 } };
    sys_setitimer(ITIMER_REAL, &off, 0);
    if (r != 0) U_FAIL(NAME, "register corrupted across signal delivery");
    if (g_alarms < 5) U_FAIL(NAME, "alarms did not arrive");
    return prog_pass(NAME, (unsigned long)g_alarms * 1000 + (unsigned long)g_usr1);
}
