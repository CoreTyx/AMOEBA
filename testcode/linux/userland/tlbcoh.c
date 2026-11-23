/*
 * tlbcoh -- TLB, I$ and branch-predictor coherence across address spaces.
 *   1. four processes map different data and different code at the same
 *      virtual addresses and switch constantly (sched_yield): each must always
 *      read its own data and run its own code.  The code differs in shape (a
 *      jump over an instruction in odd processes only), so a branch target
 *      buffer or I$ keyed by virtual address alone mispredicts or runs another
 *      process's instructions; ASIDs and the ITLB/DTLB must keep them apart
 *   2. a translation that Linux removes must be gone at once: load after
 *      munmap -> SEGV_MAPERR; store after mprotect(PROT_READ) -> SEGV_ACCERR
 *      and the old value kept; MAP_FIXED over a touched page reads zeros;
 *      mremap moves the data and the old address faults
 *   3. page-table pages freed and reused: a 4 MiB region (two leaf tables)
 *      touched, unmapped -- every probe faults -- and mapped again: all zero
 */
#include "ustress.h"
#define NAME "tlbcoh"

#define SAME_VA     0x2000000000UL
#define BIG_VA      0x2100000000UL
#define BIG_LEN     (4UL << 20)
#define PROCS       4
#define SWITCHES    200

#define ADDI_A0_ID(id) (((unsigned)(id) << 20) | 0x513u)   /* addi a0, x0, id */
#define JAL_PLUS_8     0x0080006fu                          /* jal x0, .+8 */
#define ADDI_A0_200    0x20050513u                          /* addi a0, a0, 0x200 */
#define RET            0x00008067u

static long load_at(long a) { return *(volatile long *)a; }
static long store_at(long a) { *(volatile long *)a = 99; return 0; }

static int same_va_child(int id)
{
    long *data = (long *)sys_mmap((void *)SAME_VA, U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    unsigned *code = (unsigned *)sys_mmap((void *)(SAME_VA + U_PAGE), U_PAGE, PROT_READ | PROT_WRITE | PROT_EXEC,
                                          MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
    if ((unsigned long)data != SAME_VA || (unsigned long)code != SAME_VA + U_PAGE) return 2;
    for (int i = 0; i < 512; i++) data[i] = (long)id << 32 | i;
    int n = 0;
    code[n++] = ADDI_A0_ID(id);
    if (id & 1) code[n++] = JAL_PLUS_8;
    code[n++] = ADDI_A0_200;
    code[n++] = RET;
    sys_flush_icache(code, code + n);
    long want = id & 1 ? id : id + 0x200;
    for (int s = 0; s < SWITCHES; s++) {
        for (int i = s % 8; i < 512; i += 37)
            if (data[i] != ((long)id << 32 | i)) return 3;
        if (((long (*)(void))code)() != want) return 4;
        sys_sched_yield();
    }
    return 0;
}

int main(void)
{
    unsigned long sum = 0;
    u_probe_install();

    /* 1 */
    int pids[PROCS];
    for (int i = 0; i < PROCS; i++) {
        pids[i] = sys_fork();
        if (pids[i] < 0) U_FAIL(NAME, "fork");
        if (pids[i] == 0) sys_exit(same_va_child(i + 1));
    }
    for (int i = 0; i < PROCS; i++) {
        int st = 0;
        if (sys_wait4(pids[i], &st, 0, 0) != pids[i] || !WIFEXITED(st)) U_FAIL(NAME, "same-VA child died");
        if (WEXITSTATUS(st) == 3) U_FAIL(NAME, "a process read another's data at the same VA");
        if (WEXITSTATUS(st) == 4) U_FAIL(NAME, "a process ran another's code at the same VA");
        if (WEXITSTATUS(st)) U_FAIL(NAME, "same-VA child setup");
    }

    /* 2 */
    for (int r = 0; r < 100; r++) {
        long *p = u_map(U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
        if (!p) U_FAIL(NAME, "mmap");
        p[r % 512] = r;
        if (load_at((long)&p[r % 512]) != r) U_FAIL(NAME, "readback");
        sys_munmap(p, U_PAGE);
        if (u_probe(load_at, (long)&p[r % 512]) != SIGSEGV || !u_faulted(SIGSEGV, SEGV_MAPERR, &p[r % 512]))
            U_FAIL(NAME, "load after munmap did not fault");
    }
    long *q = u_map(U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
    if (!q) U_FAIL(NAME, "mmap");
    for (int r = 0; r < 100; r++) {
        q[7] = r;
        sys_mprotect(q, U_PAGE, PROT_READ);
        if (u_probe(store_at, (long)&q[7]) != SIGSEGV || !u_faulted(SIGSEGV, SEGV_ACCERR, &q[7]))
            U_FAIL(NAME, "store after mprotect(PROT_READ) did not fault");
        if (q[7] != r) U_FAIL(NAME, "faulting store changed memory");
        sys_mprotect(q, U_PAGE, PROT_READ | PROT_WRITE);
        if (u_probe(store_at, (long)&q[7]) || q[7] != 99) U_FAIL(NAME, "store after mprotect back");
    }
    for (int r = 0; r < 50; r++) {
        long *p = u_map(U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
        if (!p) U_FAIL(NAME, "mmap");
        for (int i = 0; i < 512; i += 64) p[i] = -1;
        long *again = (long *)sys_mmap(p, U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
        if (again != p) U_FAIL(NAME, "MAP_FIXED");
        for (int i = 0; i < 512; i += 64) if (p[i]) U_FAIL(NAME, "MAP_FIXED page kept the old data");
        sys_munmap(p, U_PAGE);
    }
    for (int r = 0; r < 50; r++) {
        long *from = u_map(U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
        long *to = u_map(U_PAGE, PROT_NONE, MAP_PRIVATE);
        if (!from || !to) U_FAIL(NAME, "mmap");
        from[r] = 0x7e57 + r;
        if (sys_mremap(from, U_PAGE, U_PAGE, MREMAP_MAYMOVE | MREMAP_FIXED, to) != (long)to) U_FAIL(NAME, "mremap");
        if (to[r] != 0x7e57 + r) U_FAIL(NAME, "mremap lost the data");
        if (u_probe(load_at, (long)&from[r]) != SIGSEGV || !u_faulted(SIGSEGV, SEGV_MAPERR, &from[r]))
            U_FAIL(NAME, "old address readable after mremap");
        sys_munmap(to, U_PAGE);
        sum = u_mix(sum + (unsigned long)r);
    }

    /* 3 */
    for (int r = 0; r < 3; r++) {
        char *big = (char *)sys_mmap((void *)BIG_VA, BIG_LEN, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
        if ((unsigned long)big != BIG_VA) U_FAIL(NAME, "mmap 4 MiB");
        for (unsigned long o = 0; o < BIG_LEN; o += 64 * 1024) *(long *)(big + o) = (long)(o + 1);
        for (unsigned long o = 0; o < BIG_LEN; o += 64 * 1024) if (*(long *)(big + o) != (long)(o + 1)) U_FAIL(NAME, "4 MiB readback");
        sys_munmap(big, BIG_LEN);
        for (unsigned long o = 0; o < BIG_LEN; o += 512 * 1024)
            if (u_probe(load_at, (long)(big + o)) != SIGSEGV) U_FAIL(NAME, "freed page table still walked");
        big = (char *)sys_mmap((void *)BIG_VA, BIG_LEN, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS | MAP_FIXED, -1, 0);
        if ((unsigned long)big != BIG_VA) U_FAIL(NAME, "mmap 4 MiB again");
        for (unsigned long o = 0; o < BIG_LEN; o += 64 * 1024) if (*(long *)(big + o)) U_FAIL(NAME, "remapped region not zero");
        sys_munmap(big, BIG_LEN);
    }
    return prog_pass(NAME, sum ^ SWITCHES);
}
