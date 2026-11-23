/*
 * atomics -- A extension semantics where Linux makes them hard.
 *   1. four processes on one MAP_SHARED page, preempted by the tick and by
 *      sched_yield: amoadd.d, an LR/SC increment, amoadd.w on adjacent words
 *      of one line, and a plain load/add/store under an amoswap.aq/.rl spin
 *      lock.  Every count must come out exact
 *   2. every AMO, .w and .d, against a model: the old value (sign-extended
 *      for .w), the new value, the neighbouring word untouched.  The first
 *      AMO lands on a page with no PTE yet, so it page-faults and is retried
 *   3. after fork: LR/SC and an AMO on copy-on-write pages.  The SC and the
 *      AMO take the store fault; the kernel copies the page and returns, and
 *      the SC -- its reservation cleared by the trap return -- fails once and
 *      succeeds on the retry.  The parent keeps its values
 *   4. reservations: an SC after an ecall fails (Linux clears reservations
 *      on every return to user); an LR/SC pair with nothing between succeeds;
 *      a second SC after it fails;
 *      an SC to another address fails and kills the reservation
 */
#include "ustress.h"
#define NAME "atomics"

#define PROCS 4
#define ITERS 2000

struct shared {
    long amo, lrsc, lock, plain;
    int  words[8];
};

static void lrsc_add(long *p, long n)
{
    long v, fail;
    __asm__ volatile (
        "1: lr.d %0, (%2)\n"
        "   add  %0, %0, %3\n"
        "   sc.d %1, %0, (%2)\n"
        "   bnez %1, 1b\n"
        : "=&r"(v), "=&r"(fail) : "r"(p), "r"(n) : "memory");
}

/* LR/SC increment that reports how many times its SC failed. */
static long lrsc_add_count(long *p, long n)
{
    long v, fail, retries = -1;
    __asm__ volatile (
        "1: addi %2, %2, 1\n"
        "   lr.d %0, (%3)\n"
        "   add  %0, %0, %4\n"
        "   sc.d %1, %0, (%3)\n"
        "   bnez %1, 1b\n"
        : "=&r"(v), "=&r"(fail), "+r"(retries) : "r"(p), "r"(n) : "memory");
    return retries;
}

static void lock(long *l)
{
    for (int spins = 0;; spins++) {
        long was;
        __asm__ volatile ("amoswap.d.aq %0, %1, (%2)" : "=r"(was) : "r"(1L), "r"(l) : "memory");
        if (!was) return;
        if (spins % 32 == 31) sys_sched_yield();
    }
}

static void unlock(long *l)
{
    __asm__ volatile ("amoswap.d.rl zero, zero, (%0)" :: "r"(l) : "memory");
}

static int worker(struct shared *s, int id)
{
    for (int i = 0; i < ITERS; i++) {
        __asm__ volatile ("amoadd.d zero, %0, (%1)" :: "r"(1L), "r"(&s->amo) : "memory");
        lrsc_add(&s->lrsc, 1);
        __asm__ volatile ("amoadd.w zero, %0, (%1)" :: "r"(1L), "r"(&s->words[id]) : "memory");
        __asm__ volatile ("amoadd.w zero, %0, (%1)" :: "r"(1L), "r"(&s->words[7]) : "memory");
        lock(&s->lock);
        long v = *(volatile long *)&s->plain;
        for (int d = opaque(i & 7); d > 0; d--) opaque(d);
        *(volatile long *)&s->plain = v + 1;
        unlock(&s->lock);
        if (i % 128 == 127) sys_sched_yield();
    }
    return 0;
}

enum { SWAP, ADD, XOR, AND, OR, MIN, MAX, MINU, MAXU, NOPS };

#define AMO(insn, p, v) ({ long o_; __asm__ volatile (insn " %0, %2, (%1)" : "=&r"(o_) : "r"(p), "r"(v) : "memory"); o_; })

static long amo_d(int op, long *p, long v)
{
    switch (op) {
    case SWAP: return AMO("amoswap.d", p, v);
    case ADD:  return AMO("amoadd.d", p, v);
    case XOR:  return AMO("amoxor.d", p, v);
    case AND:  return AMO("amoand.d", p, v);
    case OR:   return AMO("amoor.d", p, v);
    case MIN:  return AMO("amomin.d", p, v);
    case MAX:  return AMO("amomax.d", p, v);
    case MINU: return AMO("amominu.d", p, v);
    default:   return AMO("amomaxu.d", p, v);
    }
}

static long amo_w(int op, int *p, long v)
{
    switch (op) {
    case SWAP: return AMO("amoswap.w", p, v);
    case ADD:  return AMO("amoadd.w", p, v);
    case XOR:  return AMO("amoxor.w", p, v);
    case AND:  return AMO("amoand.w", p, v);
    case OR:   return AMO("amoor.w", p, v);
    case MIN:  return AMO("amomin.w", p, v);
    case MAX:  return AMO("amomax.w", p, v);
    case MINU: return AMO("amominu.w", p, v);
    default:   return AMO("amomaxu.w", p, v);
    }
}

static unsigned long model_d(int op, unsigned long a, unsigned long b)
{
    switch (op) {
    case SWAP: return b;
    case ADD:  return a + b;
    case XOR:  return a ^ b;
    case AND:  return a & b;
    case OR:   return a | b;
    case MIN:  return (long)a < (long)b ? a : b;
    case MAX:  return (long)a > (long)b ? a : b;
    case MINU: return a < b ? a : b;
    default:   return a > b ? a : b;
    }
}

static unsigned model_w(int op, unsigned a, unsigned b)
{
    switch (op) {
    case MIN:  return (int)a < (int)b ? a : b;
    case MAX:  return (int)a > (int)b ? a : b;
    default:   return (unsigned)model_d(op, a, b);
    }
}

int main(void)
{
    unsigned long sum = 0;

    /* 1 */
    struct shared *s = u_map(U_PAGE, PROT_READ | PROT_WRITE, MAP_SHARED);
    if (!s) U_FAIL(NAME, "mmap shared");
    int pids[PROCS];
    for (int i = 0; i < PROCS; i++) {
        pids[i] = sys_fork();
        if (pids[i] < 0) U_FAIL(NAME, "fork");
        if (pids[i] == 0) sys_exit(worker(s, i));
    }
    for (int i = 0; i < PROCS; i++) {
        int st = 0;
        if (sys_wait4(pids[i], &st, 0, 0) != pids[i] || !WIFEXITED(st) || WEXITSTATUS(st)) U_FAIL(NAME, "worker died");
    }
    if (s->amo != PROCS * ITERS) U_FAIL(NAME, "amoadd.d lost updates");
    if (s->lrsc != PROCS * ITERS) U_FAIL(NAME, "LR/SC lost updates");
    if (s->plain != PROCS * ITERS) U_FAIL(NAME, "amoswap lock let two holders in");
    if (s->words[7] != PROCS * ITERS) U_FAIL(NAME, "amoadd.w lost updates on a shared word");
    for (int i = 0; i < PROCS; i++) if (s->words[i] != ITERS) U_FAIL(NAME, "amoadd.w disturbed a neighbouring word");
    for (int i = PROCS; i < 7; i++) if (s->words[i]) U_FAIL(NAME, "amoadd.w wrote an unused word");
    if (s->lock) U_FAIL(NAME, "lock left held");

    /* 2 */
    long *m = u_map(U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
    if (!m) U_FAIL(NAME, "mmap");
    unsigned long dshadow = 0;
    unsigned wshadow[2] = { 0, 0 };
    for (int i = 0; i < 400; i++) {
        int op = (int)(u_rand() % NOPS);
        unsigned long v = u_rand();
        if (i & 1) {
            int lane = (int)(u_rand() & 1);
            int *w = (int *)&m[1] + lane;
            long old = amo_w(op, w, (long)v);
            if (old != (long)(int)wshadow[lane]) U_FAIL(NAME, "AMO.w old value or its sign extension");
            wshadow[lane] = model_w(op, wshadow[lane], (unsigned)v);
            if ((unsigned)w[0] != wshadow[lane] || (unsigned)((int *)&m[1])[lane ^ 1] != wshadow[lane ^ 1])
                U_FAIL(NAME, "AMO.w result or neighbour");
        } else {
            long old = amo_d(op, &m[0], (long)v);
            if ((unsigned long)old != dshadow) U_FAIL(NAME, "AMO.d old value");
            dshadow = model_d(op, dshadow, v);
            if ((unsigned long)m[0] != dshadow) U_FAIL(NAME, "AMO.d result");
        }
        sum = u_mix(sum + (unsigned long)op);
    }
    sum = u_mix(sum ^ dshadow ^ wshadow[0] ^ ((unsigned long)wshadow[1] << 32));

    /* 3 */
    long *c = u_map(3 * U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
    if (!c) U_FAIL(NAME, "mmap");
    long *lr_page = c, *amo_page = c + 512, *both = c + 1024;
    for (int r = 0; r < 8; r++) {
        *lr_page = 5;
        *amo_page = 50;
        *both = 500;
        int pid = sys_fork();
        if (pid < 0) U_FAIL(NAME, "fork");
        if (pid == 0) {
            long retries = lrsc_add_count(lr_page, 1);
            if (*lr_page != 6) sys_exit(2);
            if (retries > 16) sys_exit(3);
            if (AMO("amoadd.d", amo_page, 7L) != 50 || *amo_page != 57) sys_exit(4);
            if (AMO("amoswap.d", both, 1L) != 500) sys_exit(5);
            lrsc_add(both, 2);
            if (*both != 3) sys_exit(6);
            sys_exit(0);
        }
        int st = 0;
        if (sys_wait4(pid, &st, 0, 0) != pid || !WIFEXITED(st)) U_FAIL(NAME, "COW child died");
        switch (WEXITSTATUS(st)) {
        case 0: break;
        case 2: U_FAIL(NAME, "LR/SC on a COW page");
        case 3: U_FAIL(NAME, "LR/SC on a COW page never succeeded");
        case 4: U_FAIL(NAME, "AMO on a COW page");
        default: U_FAIL(NAME, "AMO then LR/SC on a COW page");
        }
        if (*lr_page != 5 || *amo_page != 50 || *both != 500) U_FAIL(NAME, "COW child's atomics reached the parent");
    }

    /* 4 */
    static long x[2] __attribute__((aligned(64)));
    static long y[8] __attribute__((aligned(64)));
    int pairs_ok = 0;
    for (int r = 0; r < 50; r++) {
        long v, fail, fail2;
        __asm__ volatile ("lr.d %1, (%2)\n li a7, 172\n ecall\n sc.d %0, %1, (%2)"
                          : "=&r"(fail), "=&r"(v) : "r"(x) : "a0", "a7", "memory");
        if (!fail) U_FAIL(NAME, "SC succeeded across an ecall");
        __asm__ volatile ("lr.d %2, (%3)\n sc.d %0, %2, (%3)\n sc.d %1, %2, (%3)"
                          : "=&r"(fail), "=&r"(fail2), "=&r"(v) : "r"(x) : "memory");
        pairs_ok += !fail;
        if (!fail2) U_FAIL(NAME, "second SC succeeded without a reservation");
        __asm__ volatile ("lr.d %2, (%3)\n sc.d %0, %2, (%4)\n sc.d %1, %2, (%3)"
                          : "=&r"(fail), "=&r"(fail2), "=&r"(v) : "r"(x), "r"(y) : "memory");
        if (!fail) U_FAIL(NAME, "SC to an address without a reservation succeeded");
        if (!fail2) U_FAIL(NAME, "SC succeeded after a failed SC");
    }
    /* A lone SC may fail spuriously; one that never succeeds is broken. */
    if (!pairs_ok) U_FAIL(NAME, "LR/SC pair never succeeded with nothing between");
    return prog_pass(NAME, sum);
}
