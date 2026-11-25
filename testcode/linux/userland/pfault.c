/*
 * pfault -- page-fault storm in a real Linux process.
 *   1. demand-zero: mmap 128 anonymous pages, first touch of each is a fault
 *   2. fork: parent and child both write every page (copy-on-write faults on
 *      both sides); each must see only its own data afterwards
 *   3. MADV_DONTNEED drops half the pages: they read back as zero (refault)
 *   4. mprotect(PROT_READ) then a write: SIGSEGV with SEGV_ACCERR at the
 *      exact address; mprotect back and the write succeeds
 *   5. munmap + mmap again, three rounds
 * Every fault goes U -> S (delegated) -> Linux's handler -> sret, and the COW
 * path additionally does sfence.vma on a live mm.
 */
#include "ustress.h"
#define NAME   "pfault"
#define NPG    128
#define BYTES  (NPG * U_PAGE)

static u_jmpbuf jb;
static volatile void *g_fault_addr;
static volatile int g_fault_code;
static void on_segv(int sig, void *info, void *uc) { (void)sig; (void)uc; g_fault_addr = si_addr(info); g_fault_code = si_code(info); u_longjmp(jb, 1); }

static unsigned long pat(unsigned long pg, unsigned long who, unsigned long round) { return u_mix((pg << 20) ^ (who << 8) ^ round); }

int main(void)
{
    unsigned long sum = 0;
    for (int round = 0; round < 3; round++) {
        unsigned long *m = (unsigned long *)sys_mmap(0, BYTES, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if ((long)m < 0 && (long)m > -4096) U_FAIL(NAME, "mmap");
        /* 1: demand zero */
        for (unsigned long p = 0; p < NPG; p++) if (m[p * 512 + (p & 511)] != 0) U_FAIL(NAME, "not zero");
        for (unsigned long p = 0; p < NPG; p++) m[p * 512 + 7] = pat(p, 0, round);
        /* 2: fork, both sides write everything */
        int pid = sys_fork();
        if (pid == 0) {
            for (unsigned long p = 0; p < NPG; p++) if (m[p * 512 + 7] != pat(p, 0, round)) sys_exit(11);
            for (unsigned long p = 0; p < NPG; p++) m[p * 512 + 7] = pat(p, 2, round);
            for (unsigned long p = 0; p < NPG; p++) if (m[p * 512 + 7] != pat(p, 2, round)) sys_exit(12);
            sys_exit(0);
        }
        for (unsigned long p = 0; p < NPG; p++) m[p * 512 + 7] = pat(p, 1, round);
        int st = 0;
        if (sys_wait4(pid, &st, 0, 0) != pid || !WIFEXITED(st) || WEXITSTATUS(st) != 0) U_FAIL(NAME, "child saw COW leak");
        for (unsigned long p = 0; p < NPG; p++) if (m[p * 512 + 7] != pat(p, 1, round)) U_FAIL(NAME, "parent saw COW leak");
        /* 3: MADV_DONTNEED on the even half of the range */
        if (sys_madvise(m, BYTES / 2, MADV_DONTNEED)) U_FAIL(NAME, "madvise");
        for (unsigned long p = 0; p < NPG; p++) {
            unsigned long want = p < NPG / 2 ? 0 : pat(p, 1, round);
            if (m[p * 512 + 7] != want) U_FAIL(NAME, "DONTNEED readback");
            sum += m[p * 512 + 7];
        }
        /* 4: write to a read-only page faults at the exact address */
        if (sys_mprotect(m, BYTES, PROT_READ)) U_FAIL(NAME, "mprotect ro");
        u_signal(SIGSEGV, on_segv);
        volatile unsigned long *target = &m[(NPG - 3) * 512 + 9];
        if (u_setjmp(jb) == 0) { *target = 1; U_FAIL(NAME, "write to RO page succeeded"); }
        if (g_fault_addr != (void *)target || g_fault_code != SEGV_ACCERR) U_FAIL(NAME, "SIGSEGV info");
        if (sys_mprotect(m, BYTES, PROT_READ | PROT_WRITE)) U_FAIL(NAME, "mprotect rw");
        *target = 0x5a5a;
        if (*target != 0x5a5a) U_FAIL(NAME, "write after mprotect");
        /* 5 */
        if (sys_munmap(m, BYTES)) U_FAIL(NAME, "munmap");
        if (u_setjmp(jb) == 0) { (void)*(volatile unsigned long *)m; U_FAIL(NAME, "read after munmap"); }
        if (g_fault_code != SEGV_MAPERR) U_FAIL(NAME, "SEGV_MAPERR expected");
    }
    return prog_pass(NAME, sum);
}
