/*
 * mem: demand paging under Linux.
 *
 * Every page touched here starts unmapped, so each first access is a page
 * fault the kernel resolves by installing a PTE, and each first store to a
 * page first read through the shared zero page is a copy-on-write fault.  That
 * walks the Sv39 table, sets hardware A/D bits, and forces TLB refills and
 * sfence.vma on the way -- the paths a bare-metal test cannot reach.
 *
 *  1. brk: grow the heap by 64 KiB, fill every doubleword with an
 *     offset-derived pattern, read it all back, shrink it again.
 *  2. mmap: an anonymous 128 KiB mapping.  Read one word per page first (must
 *     be zero), then write every doubleword, then verify it, with byte and
 *     halfword stores mixed in so sub-word merging is covered too.  munmap,
 *     map again, and check the fresh pages are zero once more.
 */
#include "ulib.h"

#define PAGE      4096UL
#define BRK_LEN   (64UL * 1024)
#define MMAP_LEN  (128UL * 1024)

static const char *const name = "mem";

/* Keyed on the word's offset in the region, not its address: user mappings
 * are ASLR-randomised, and the printed checksum should be stable run to run.
 * Every word still gets a distinct value, so two virtual pages aliasing one
 * frame would show up as a mismatch. */
static unsigned long pattern(unsigned long idx, unsigned long seed)
{
    unsigned long x = (idx + 1) * 0x9e3779b97f4a7c15UL ^ seed;
    x ^= x >> 29;
    x *= 0xbf58476d1ce4e5b9UL;
    return x ^ (x >> 32);
}

/* Fill [base, base+len) with the pattern, then verify it.  On a mismatch,
 * print one diagnostic FAIL line and return 1.  The line says which word
 * first failed, what was read, what was expected, what a second read of the
 * same word returns, and how many words were bad in total -- enough to tell a
 * lost store (got 0: still the zero page), an aliased page (got another
 * word's pattern) and a transient read (reread correct) apart without having
 * to repeat a multi-hour boot. */
static int fill_and_check(unsigned long base, unsigned long len,
                          unsigned long seed, unsigned long *sum,
                          const char *what)
{
    volatile unsigned long *p = (volatile unsigned long *)base;
    unsigned long n = len / sizeof(unsigned long);
    unsigned long bad = 0, first = 0, got = 0;

    for (unsigned long i = 0; i < n; i++)
        p[i] = pattern(i, seed);
    for (unsigned long i = 0; i < n; i++) {
        unsigned long v = p[i];
        if (v != pattern(i, seed)) {
            if (!bad++) {
                first = i;
                got = v;
            }
            continue;
        }
        *sum += v;
    }
    if (!bad)
        return 0;

    out_str("PROG mem FAIL ");
    out_str(what);
    out_str(" word ");
    out_dec(first);
    out_str(" page ");
    out_dec(first * sizeof(unsigned long) / PAGE);
    out_str(" got ");
    out_hex(got);
    out_str(" want ");
    out_hex(pattern(first, seed));
    out_str(" reread ");
    out_hex(p[first]);
    out_str(" bad ");
    out_dec(bad);
    out_str("\n");
    return 1;
}

int main(void)
{
    unsigned long sum = 0;

    /* ---- brk ---- */
    long cur = sys_brk(0);
    if (cur <= 0)
        return prog_fail(name, "brk-query");
    long top = sys_brk((void *)(cur + BRK_LEN));
    if (top != cur + (long)BRK_LEN)
        return prog_fail(name, "brk-grow");
    if (fill_and_check(cur, BRK_LEN, 0x1111, &sum, "brk-pattern"))
        return 1;
    if (sys_brk((void *)cur) != cur)
        return prog_fail(name, "brk-shrink");

    /* ---- anonymous mmap ---- */
    for (int round = 0; round < 2; round++) {
        long m = sys_mmap(0, MMAP_LEN, PROT_READ | PROT_WRITE,
                          MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        if (m < 0 && m > -4096)
            return prog_fail(name, "mmap");
        if (m & (PAGE - 1))
            return prog_fail(name, "mmap-unaligned");

        /* Fresh anonymous memory is zero: read-fault every page, so each one
         * is first mapped to the zero page and the fill below then takes a
         * copy-on-write fault per page. */
        for (unsigned long off = 0; off < MMAP_LEN; off += PAGE)
            if (*(volatile unsigned long *)(m + off) != 0)
                return prog_fail(name, "mmap-not-zero");

        if (fill_and_check(m, MMAP_LEN, 0x2222 + round, &sum,
                           round ? "mmap-pattern r1" : "mmap-pattern r0"))
            return 1;

        /* Sub-word stores into the last page, then check the merge. */
        volatile unsigned char  *b = (volatile unsigned char *)(m + MMAP_LEN - PAGE);
        volatile unsigned short *h = (volatile unsigned short *)(m + MMAP_LEN - PAGE + 64);
        volatile unsigned long  *d = (volatile unsigned long *)(m + MMAP_LEN - PAGE);
        b[1] = 0xA5;
        b[6] = 0x5A;
        h[1] = 0xBEEF;
        unsigned long last = (MMAP_LEN - PAGE) / sizeof(unsigned long);
        unsigned long d0 = pattern(last, 0x2222 + round);
        unsigned long d8 = pattern(last + 8, 0x2222 + round);
        d0 = (d0 & ~0x00ff00000000ff00UL) | 0x005a00000000a500UL;
        d8 = (d8 & ~0x00000000ffff0000UL) | 0x00000000beef0000UL;
        if (d[0] != d0 || d[8] != d8)
            return prog_fail(name, "subword-merge");
        sum += d[0] + d[8];

        if (sys_munmap((void *)m, MMAP_LEN) != 0)
            return prog_fail(name, "munmap");
    }

    return prog_pass(name, sum);
}
