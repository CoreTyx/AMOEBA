/*
 * faultsweep -- a faulting store at every placement the two lost-store bugs
 * needed (d069ee5: I$ stale row after an ITLB miss; 4fc5b31: a store fault
 * waiting out a committed fetch next to a mispredicted branch).
 * The code is generated into a file and executed through a view mapped fresh
 * for every call, so each call starts with an ITLB miss:
 *
 *     entry:  bne  a0, x0, 1f      taken or not at random: mispredicts
 *             c.nop
 *     1:      c.nop x pad          pad 0..7
 *             sd   a1, 0(a2)       a2: a page with no PTE, or copy-on-write
 *             ld   a3, 0(a2)
 *             sub  a0, a3, a1      0 if the store landed
 *             ret
 *
 * at entry offsets 0..14 within a 16-byte line.  Every store page-faults;
 * Linux maps or copies the page and sret retries the store, which must land.
 *   1. demand-zero: each call stores to its own untouched page
 *   2. copy-on-write: a forked child stores to pages the parent wrote
 */
#include "ustress.h"
#define NAME "faultsweep"

#define BNE_A0_PLUS6 0x00051363u
#define C_NOP        0x0001u
#define SD_A1_A2     0x00b63023u
#define LD_A3_A2     0x00063683u
#define SUB_A0_A3_A1 0x40b68533u
#define C_RET        0x8082u

#define OFFSETS 8
#define PADS    8
#define CALLS   (OFFSETS * PADS)

static int fd;
static unsigned short *rw;

static void put32(unsigned short *at, unsigned v) { at[0] = (unsigned short)v; at[1] = (unsigned short)(v >> 16); }

/* The sequence for one placement, at byte offset `entry` of the code page. */
static void generate(int entry, int pad)
{
    unsigned short *p = rw + entry / 2;
    put32(p, BNE_A0_PLUS6); p += 2;
    *p++ = C_NOP;
    for (int i = 0; i < pad; i++) *p++ = C_NOP;
    put32(p, SD_A1_A2); p += 2;
    put32(p, LD_A3_A2); p += 2;
    put32(p, SUB_A0_A3_A1); p += 2;
    *p = C_RET;
}

/* One call through a view mapped just for it. */
static long call_fresh(int entry, long taken, long value, long *addr)
{
    long x = sys_mmap(0, U_PAGE, PROT_READ | PROT_EXEC, MAP_SHARED, fd, 0);
    if (x < 0 && x > -4096) return -1;
    sys_flush_icache((void *)x, (void *)(x + U_PAGE));
    long r = ((long (*)(long, long, long *))(x + entry))(taken, value, addr);
    sys_munmap((void *)x, U_PAGE);
    return r;
}

static int sweep(char *pages, int cow, unsigned long *sum)
{
    for (int c = 0; c < CALLS; c++) {
        int entry = 2 * (c % OFFSETS), pad = c / OFFSETS;
        generate(entry, pad);
        long *addr = (long *)(pages + (unsigned long)c * U_PAGE + 8 * (unsigned long)(c % 16));
        long value = (long)u_mix((unsigned long)c + 1) | 1;
        long taken = (long)(u_rand() & 1);
        if (call_fresh(entry, taken, value, addr) != 0) return 1;
        if (*addr != value) return 2;
        if (cow && addr[1] != (long)0x6363636363636363L) return 3;
        *sum = u_mix(*sum + (unsigned long)value);
    }
    return 0;
}

int main(void)
{
    unsigned long sum = 0;
    fd = sys_openat(AT_FDCWD, "/faultsweep.bin", O_RDWR | O_CREAT | O_TRUNC, 0700);
    if (fd < 0) U_FAIL(NAME, "open");
    if (sys_ftruncate(fd, U_PAGE)) U_FAIL(NAME, "ftruncate");
    long p = sys_mmap(0, U_PAGE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    if (p < 0 && p > -4096) U_FAIL(NAME, "mmap RW view");
    rw = (unsigned short *)p;

    /* 1 */
    char *fresh = u_map(CALLS * U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
    if (!fresh) U_FAIL(NAME, "mmap");
    switch (sweep(fresh, 0, &sum)) {
    case 0: break;
    case 1: U_FAIL(NAME, "demand-zero store lost (the retried store did not land)");
    default: U_FAIL(NAME, "demand-zero store: memory disagrees with the load");
    }

    /* 2 */
    char *cow = u_map(CALLS * U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
    if (!cow) U_FAIL(NAME, "mmap");
    memset(cow, 0x63, CALLS * U_PAGE);
    int pid = sys_fork();
    if (pid < 0) U_FAIL(NAME, "fork");
    if (pid == 0) {
        unsigned long child_sum = 0;
        sys_exit(sweep(cow, 1, &child_sum));
    }
    int st = 0;
    if (sys_wait4(pid, &st, 0, 0) != pid || !WIFEXITED(st)) U_FAIL(NAME, "child died");
    switch (WEXITSTATUS(st)) {
    case 0: break;
    case 1: U_FAIL(NAME, "copy-on-write store lost (the retried store did not land)");
    case 2: U_FAIL(NAME, "copy-on-write store: memory disagrees with the load");
    default: U_FAIL(NAME, "copy-on-write copy corrupted the rest of the page");
    }
    for (unsigned long i = 0; i < CALLS * U_PAGE; i += 512)
        if (cow[i] != 0x63) U_FAIL(NAME, "child's store reached the parent");
    return prog_pass(NAME, sum);
}
