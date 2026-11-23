/*
 * straddle -- instructions and data that span a page, under Linux.
 * A 32-bit instruction at offset 4094 is fetched as two halves from two pages
 * (two ITLB lookups, two I$ lines); a misaligned access over a page boundary
 * goes U -> M, where OpenSBI emulates it byte by byte through MPRV and
 * redirects any page fault it takes to S.
 *   1. fetch: both pages executable, mapped fresh each round (both halves
 *      page-fault and are retried) -- the instruction executes once
 *   2. fetch: the second page not executable, unmapped or PROT_NONE --
 *      SIGSEGV at the second page; the first not executable -- SIGSEGV at
 *      the instruction (the first-half fault fixed in 990653c)
 *   3. a 16-bit instruction ending a page before a non-executable page runs,
 *      and the fault is at the next page
 *   4. a page of 32-bit instructions at offsets 2 mod 4, one in four over a
 *      16-byte line, fetched warm and from a fresh mapping
 *   5. data: misaligned loads over a boundary into PROT_NONE and stores into
 *      a read-only page fault inside the boundary; misaligned stores over a
 *      copy-on-write boundary after fork (two COW faults taken from inside
 *      the M-mode emulation) land whole, and the parent keeps its copy;
 *      misaligned loads from never-touched pages read zeros
 */
#include "ustress.h"
#define NAME "straddle"

#define C_LI_A0_0     0x4501u        /* c.li a0, 0 */
#define C_LI_A0_7     0x451du        /* c.li a0, 7 */
#define ADDI_A0_123   0x12350513u    /* addi a0, a0, 0x123 */
#define ADDI_A0_1     0x00150513u    /* addi a0, a0, 1 */
#define C_RET         0x8082u        /* c.jr ra */
#define LINE_INSNS    1022

static int fd;
static unsigned short *rw;           /* the file's two pages, writable view */

static void put16(unsigned short *at, unsigned v) { *at = (unsigned short)v; }
static void put32(unsigned short *at, unsigned v) { at[0] = (unsigned short)v; at[1] = (unsigned short)(v >> 16); }

/* The executable view, mapped fresh so that neither page has a PTE yet. */
static char *map_x(void)
{
    long p = sys_mmap(0, 2 * U_PAGE, PROT_READ | PROT_EXEC, MAP_SHARED, fd, 0);
    return p < 0 && p > -4096 ? 0 : (char *)p;
}

static long call(long addr) { return ((long (*)(long))addr)(0); }

static long load_misaligned(long a)
{
    long v;
    __asm__ volatile ("ld %0, 0(%1)" : "=r"(v) : "r"(a) : "memory");
    return v;
}
static long store_misaligned(long a)
{
    __asm__ volatile ("sd %0, 0(%1)" :: "r"(0x0102030405060708L), "r"(a) : "memory");
    return 0;
}
static long store_word_misaligned(long a)
{
    __asm__ volatile ("sw %0, 0(%1)" :: "r"(0x0a0b0c0dL), "r"(a) : "memory");
    return 0;
}

static int in_access(const void *fault, const char *a, int width)
{
    return (const char *)fault >= a && (const char *)fault < a + width;
}

int main(void)
{
    unsigned long sum = 0;
    u_probe_install();
    fd = sys_openat(AT_FDCWD, "/straddle.bin", O_RDWR | O_CREAT | O_TRUNC, 0700);
    if (fd < 0) U_FAIL(NAME, "open");
    if (sys_ftruncate(fd, 2 * U_PAGE)) U_FAIL(NAME, "ftruncate");
    long p = sys_mmap(0, 2 * U_PAGE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (p < 0 && p > -4096) U_FAIL(NAME, "mmap RW view");
    rw = (unsigned short *)p;
    unsigned short *edge = rw + U_PAGE / 2 - 2;     /* byte offset 4092 */
    put16(edge, C_LI_A0_0);
    put32(edge + 1, ADDI_A0_123);                   /* 4094..4097 */
    put16(edge + 3, C_RET);                         /* 4098 */

    /* 1 */
    for (int round = 0; round < 16; round++) {
        char *x = map_x();
        if (!x) U_FAIL(NAME, "mmap RX view");
        sys_flush_icache(x, x + 2 * U_PAGE);
        if (u_probe(call, (long)(x + U_PAGE - 4)) || u_fault.ret != 0x123) U_FAIL(NAME, "straddling instruction, both pages fresh");
        if (u_probe(call, (long)(x + U_PAGE - 4)) || u_fault.ret != 0x123) U_FAIL(NAME, "straddling instruction, warm");
        sys_munmap(x, 2 * U_PAGE);
    }

    /* 2 */
    char *x = map_x();
    if (!x) U_FAIL(NAME, "mmap RX view");
    char *straddler = x + U_PAGE - 2, *second = x + U_PAGE;
    for (int round = 0; round < 8; round++) {
        sys_mprotect(second, U_PAGE, PROT_READ);
        if (u_probe(call, (long)straddler) != SIGSEGV || !u_faulted(SIGSEGV, SEGV_ACCERR, second))
            U_FAIL(NAME, "second page not executable");
        sys_mprotect(second, U_PAGE, PROT_NONE);
        if (u_probe(call, (long)straddler) != SIGSEGV || !u_faulted(SIGSEGV, SEGV_ACCERR, second))
            U_FAIL(NAME, "second page PROT_NONE");
        sys_mprotect(second, U_PAGE, PROT_READ | PROT_EXEC);
        sys_mprotect(x, U_PAGE, PROT_READ);
        int sig = u_probe(call, (long)straddler);
        if (sig == 0) U_FAIL(NAME, "executed with the first page not executable");
        if (!u_faulted(SIGSEGV, SEGV_ACCERR, straddler)) U_FAIL(NAME, "first page not executable: wrong fault");
        sys_mprotect(x, U_PAGE, PROT_READ | PROT_EXEC);
        if (u_probe(call, (long)(x + U_PAGE - 4)) || u_fault.ret != 0x123) U_FAIL(NAME, "straddler after mprotect back");
    }
    sys_munmap(second, U_PAGE);
    if (u_probe(call, (long)straddler) != SIGSEGV || !u_faulted(SIGSEGV, SEGV_MAPERR, second))
        U_FAIL(NAME, "second page unmapped");
    sys_munmap(x, U_PAGE);

    /* 3 */
    put16(edge + 1, C_LI_A0_7);                     /* 16-bit, 4094..4095 */
    x = map_x();
    if (!x) U_FAIL(NAME, "mmap RX view");
    sys_flush_icache(x, x + 2 * U_PAGE);
    sys_mprotect(x + U_PAGE, U_PAGE, PROT_READ);
    if (u_probe(call, (long)(x + U_PAGE - 2)) != SIGSEGV || !u_faulted(SIGSEGV, SEGV_ACCERR, x + U_PAGE))
        U_FAIL(NAME, "16-bit instruction at the end of a page");
    sys_munmap(x, 2 * U_PAGE);

    /* 4 */
    put16(rw, C_LI_A0_0);
    for (int i = 0; i < LINE_INSNS; i++)
        put32(rw + 1 + 2 * i, ADDI_A0_1);
    put16(rw + 1 + 2 * LINE_INSNS, C_RET);
    for (int round = 0; round < 6; round++) {
        x = map_x();
        if (!x) U_FAIL(NAME, "mmap RX view");
        sys_flush_icache(x, x + 2 * U_PAGE);
        for (int warm = 0; warm < 2; warm++)
            if (u_probe(call, (long)x) || u_fault.ret != LINE_INSNS) U_FAIL(NAME, "line-straddling instructions");
        sys_munmap(x, 2 * U_PAGE);
    }
    sum = u_mix(sum + LINE_INSNS);

    /* 5: faults inside a misaligned access */
    char *d = u_map(2 * U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
    if (!d) U_FAIL(NAME, "mmap");
    memset(d, 0x33, 2 * U_PAGE);
    sys_mprotect(d + U_PAGE, U_PAGE, PROT_NONE);
    for (int k = 1; k < 8; k++) {
        char *a = d + U_PAGE - k;
        if (u_probe(load_misaligned, (long)a) != SIGSEGV || !in_access(u_fault.addr, a, 8))
            U_FAIL(NAME, "misaligned load into PROT_NONE");
    }
    sys_mprotect(d + U_PAGE, U_PAGE, PROT_READ);
    for (int k = 1; k < 8; k++) {
        char *a = d + U_PAGE - k;
        if (u_probe(store_misaligned, (long)a) != SIGSEGV || !in_access(u_fault.addr, a, 8))
            U_FAIL(NAME, "misaligned store into a read-only page");
    }
    sys_munmap(d, 2 * U_PAGE);

    /* 5: misaligned stores over a copy-on-write boundary */
    char *c = u_map(2 * U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
    if (!c) U_FAIL(NAME, "mmap");
    for (int k = 1; k < 8; k++) {
        memset(c, 0x44, 2 * U_PAGE);
        char *a = c + U_PAGE - k;
        int pid = sys_fork();
        if (pid < 0) U_FAIL(NAME, "fork");
        if (pid == 0) {
            if (u_probe(store_misaligned, (long)a)) sys_exit(2);
            for (int i = 0; i < 8; i++) if (a[i] != (char)(8 - i)) sys_exit(4);
            if (a[-1] != 0x44 || a[8] != 0x44) sys_exit(5);
            sys_exit(0);
        }
        int st = 0;
        if (sys_wait4(pid, &st, 0, 0) != pid || !WIFEXITED(st) || WEXITSTATUS(st)) U_FAIL(NAME, "misaligned store over a COW boundary");
        for (int i = -1; i < 9; i++) if (a[i] != 0x44) U_FAIL(NAME, "child's misaligned store reached the parent");
        sum = u_mix(sum + (unsigned long)k);
    }

    /* 5: misaligned loads from never-touched pages */
    for (int k = 1; k < 8; k++) {
        char *z = u_map(2 * U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
        if (!z) U_FAIL(NAME, "mmap");
        if (u_probe(load_misaligned, (long)(z + U_PAGE - k)) || u_fault.ret != 0) U_FAIL(NAME, "misaligned load from fresh pages");
        char *w = z + U_PAGE - 1 - (k % 3);
        if (u_probe(store_word_misaligned, (long)w)) U_FAIL(NAME, "misaligned store to fresh pages");
        if (w[0] != 0x0d || w[1] != 0x0c || w[2] != 0x0b || w[3] != 0x0a) U_FAIL(NAME, "misaligned store to fresh pages: data");
        sys_munmap(z, 2 * U_PAGE);
    }
    return prog_pass(NAME, sum);
}
