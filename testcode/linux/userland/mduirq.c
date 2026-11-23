/*
 * mduirq -- multiply and divide interrupted.  The MDU is sequential (mul and
 * div take tens of cycles), so a timer tick, a SIGALRM or a context switch
 * usually arrives while one is in flight: the instruction must either finish
 * before the trap or be squashed and redone, never retire a partial result.
 *   four CPU-bound processes, preempted by the tick and each hit by its own
 *   2 ms SIGALRM, run mul/mulh/mulhu/mulhsu/mulw and div/divu/rem/remu/divw/
 *   remw chains on random operands, checked by identities that need no
 *   second MDU result: q*b + r == a computed with shifts and adds, and
 *   mul against a shift-and-add product.  Each must see its alarms arrive.
 */
#include "ustress.h"
#define NAME "mduirq"

#define PROCS 4
#define ITERS 2000

static volatile long alarms;
static void on_alarm(int sig, void *info, void *uc) { (void)sig; (void)info; (void)uc; alarms++; }

/* a * b mod 2^64 without the MDU */
static unsigned long soft_mul(unsigned long a, unsigned long b)
{
    unsigned long p = 0;
    while (b) {
        if (b & 1) p += a;
        a <<= 1;
        b >>= 1;
    }
    return p;
}

/* high 64 bits of the unsigned 128-bit product, without the MDU */
static unsigned long soft_mulhu(unsigned long a, unsigned long b)
{
    unsigned long al = a & 0xffffffff, ah = a >> 32, bl = b & 0xffffffff, bh = b >> 32;
    unsigned long ll = soft_mul(al, bl), lh = soft_mul(al, bh), hl = soft_mul(ah, bl), hh = soft_mul(ah, bh);
    unsigned long mid = (ll >> 32) + (lh & 0xffffffff) + (hl & 0xffffffff);
    return hh + (lh >> 32) + (hl >> 32) + (mid >> 32);
}

#define OP(insn, a, b) ({ unsigned long r_; __asm__ volatile (insn " %0, %1, %2" : "=r"(r_) : "r"(a), "r"(b)); r_; })

static int worker(int id)
{
    u_rng ^= u_mix((unsigned long)id + 1);
    u_signal(SIGALRM, on_alarm);
    struct itimerval it = { { 0, 2000 }, { 0, 2000 } };
    sys_setitimer(ITIMER_REAL, &it, 0);
    for (int i = 0; i < ITERS; i++) {
        unsigned long a = u_rand(), b = u_rand() >> (u_rand() & 63);
        if (!b) b = 3;
        unsigned long lo = soft_mul(a, b), hu = soft_mulhu(a, b);
        long sa = (long)a, sb = (long)b;
        if (OP("mul", a, b) != lo) return 2;
        if (OP("mulhu", a, b) != hu) return 3;
        if (OP("mulh", a, b) != hu - (sa < 0 ? b : 0) - (sb < 0 ? a : 0)) return 4;
        if (OP("mulhsu", a, b) != hu - (sa < 0 ? b : 0)) return 5;
        if (OP("mulw", a, b) != (unsigned long)(long)(int)lo) return 6;
        unsigned long q = OP("divu", a, b), r = OP("remu", a, b);
        if (r >= b || soft_mul(q, b) + r != a) return 7;
        long sq = (long)OP("div", a, b), sr = (long)OP("rem", a, b);
        if ((unsigned long)soft_mul((unsigned long)sq, b) + (unsigned long)sr != a) return 8;
        if (sr && ((sr < 0) != (sa < 0))) return 9;
        int wa = (int)a, wb = (int)b ? (int)b : 7;
        long wq = (long)OP("divw", (unsigned long)wa, (unsigned long)wb), wr = (long)OP("remw", (unsigned long)wa, (unsigned long)wb);
        if (wb != -1 && (int)soft_mul((unsigned long)wq, (unsigned long)wb) + (int)wr != wa) return 10;
    }
    struct itimerval off = { { 0, 0 }, { 0, 0 } };
    sys_setitimer(ITIMER_REAL, &off, 0);
    return alarms > 0 ? 0 : 11;
}

int main(void)
{
    int pids[PROCS];
    for (int i = 0; i < PROCS; i++) {
        pids[i] = sys_fork();
        if (pids[i] < 0) U_FAIL(NAME, "fork");
        if (pids[i] == 0) sys_exit(worker(i));
    }
    unsigned long sum = 0;
    for (int i = 0; i < PROCS; i++) {
        int st = 0;
        if (sys_wait4(pids[i], &st, 0, 0) != pids[i] || !WIFEXITED(st)) U_FAIL(NAME, "worker died");
        int code = WEXITSTATUS(st);
        if (code == 11) U_FAIL(NAME, "no SIGALRM arrived");
        if (code >= 2 && code <= 6) U_FAIL(NAME, "multiply result wrong under interrupts");
        if (code >= 7 && code <= 10) U_FAIL(NAME, "divide result wrong under interrupts");
        if (code) U_FAIL(NAME, "worker");
        sum = u_mix(sum + (unsigned long)i);
    }
    return prog_pass(NAME, sum ^ ITERS);
}
