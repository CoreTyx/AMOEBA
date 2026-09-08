#ifndef MEMTEST_COMMON_H
#define MEMTEST_COMMON_H

/*
 * memtest_common.h -- shared geometry, patterns and reporting for the two
 * memory-system tests (tc_mem_stress.c, tc_mem_align.c).
 *
 * These two tests exist because the rest of the FreeRTOS suite does not
 * exercise memory.  tc_semaphore and friends have a working set of a few
 * hundred bytes: after the first touch it lives entirely in the D-cache and
 * the external AHB goes quiet.  That is fine for testing the scheduler and
 * useless for testing a memory backend, which is why all five passed against
 * a block RAM whose adapter had never seen a burst.
 *
 * Everything here is compile-time parameterised so the same source builds a
 * small working set for the 128 KiB block RAM target and a large one for the
 * DDR target.
 */

#include <stdint.h>
#include "wally_uart.h"

/* ---- Cache geometry ------------------------------------------------------
 * Defaults match DCACHE_* in pkg/config_baremetal_linux.vh.  The tests use
 * these to construct access patterns that are guaranteed to miss, so if the
 * config changes and these do not, the tests still pass but stop proving
 * anything.  Keep them in step.
 */
#ifndef MEMTEST_CACHE_WAYS
#define MEMTEST_CACHE_WAYS   4
#endif
#ifndef MEMTEST_WAY_BYTES
#define MEMTEST_WAY_BYTES    4096
#endif
#ifndef MEMTEST_LINE_BYTES
#define MEMTEST_LINE_BYTES   64
#endif

#define MEMTEST_CACHE_BYTES  (MEMTEST_CACHE_WAYS * MEMTEST_WAY_BYTES)

/* Set index is (addr >> log2(LINE)) & (WAY_BYTES/LINE - 1), so two addresses
 * are congruent -- they compete for the same set -- exactly when they differ
 * by a multiple of MEMTEST_WAY_BYTES.  Both tests lean on this. */
#define MEMTEST_CONGRUENT_STRIDE  MEMTEST_WAY_BYTES

/* A fill brings in a whole line and a writeback sends a whole line, so the
 * bus traffic a loop generates depends on how many LINES it touches, not how
 * many words.  Stepping a line at a time gives identical memory traffic for
 * an eighth of the instructions, which is the difference between a test that
 * fits in the Verilator tier and one that does not. */
#define MEMTEST_WORDS_PER_LINE  (MEMTEST_LINE_BYTES / 8)

/* ---- Value pattern -------------------------------------------------------
 * Stored values are derived from the ADDRESS, not from a loop counter.  That
 * distinction is the whole point: a constant or counter pattern passes
 * happily when the memory path drops, duplicates or transposes an address
 * bit, because the wrong location holds a value that is still "valid".  With
 * an address-derived value, an aliased access reads a value that belongs to
 * some other address and the mismatch names both.
 *
 * One round of splitmix64's finalizer: a single wrong address bit changes
 * about half the value bits rather than one, so an aliased read looks nothing
 * like the value it should have found.  The full two-round finalizer is
 * stronger and costs a second 64-bit multiply on every access -- which is
 * measurable here, because these tests are multiply-bound in simulation
 * rather than memory-bound.  One round is far past what detecting a wrong
 * address needs.
 */
static inline uint64_t memtest_mix(uint64_t x)
{
    x ^= x >> 30;
    x *= 0xbf58476d1ce4e5b9ULL;
    x ^= x >> 29;
    return x;
}

/* ---- Reporting -----------------------------------------------------------
 * A bare exit code tells you a pass failed; on a memory path you need to know
 * WHICH address and HOW the value was wrong, because the shape of the
 * corruption is the diagnosis.
 */
static inline void memtest_put_hex(uint64_t v)
{
    static const char digits[] = "0123456789abcdef";
    uart_puts("0x");
    for (int i = 60; i >= 0; i -= 4)
        uart_putc(digits[(v >> i) & 0xF]);
}

static inline void memtest_put_dec(uint64_t v)
{
    char buf[21];
    int  i = 0;
    if (v == 0ULL) { uart_putc('0'); return; }
    while (v > 0ULL) { buf[i++] = (char)('0' + (v % 10ULL)); v /= 10ULL; }
    while (i > 0) uart_putc(buf[--i]);
}

/*
 * The xor is the field to read first:
 *   a single set bit      -> a data-path bit is stuck or swapped
 *   ~half the bits set    -> the read came from the WRONG ADDRESS, because
 *                            memtest_mix() avalanches; look for a dropped
 *                            address bit in the bridge or a wrapped access
 *   all bits, got == 0    -> the write never landed at all
 */
static inline void memtest_fail(const char *what, uint64_t addr,
                                uint64_t want, uint64_t got)
{
    uart_puts("MEMTEST FAIL ");
    uart_puts(what);
    uart_puts(" addr=");  memtest_put_hex(addr);
    uart_puts(" want=");  memtest_put_hex(want);
    uart_puts(" got=");   memtest_put_hex(got);
    uart_puts(" xor=");   memtest_put_hex(want ^ got);
    uart_puts("\n");
}

#endif /* MEMTEST_COMMON_H */
