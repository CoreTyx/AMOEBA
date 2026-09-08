/*
 * tc_mem_stress.c -- exercise the memory backend past the cache.
 *
 * WHY THIS EXISTS.  Every other test in the FreeRTOS suite has a working set
 * of a few hundred bytes.  After the first touch it is cache-resident and the
 * external AHB carries nothing, so the suite passes identically against a
 * correct memory backend and against one that has never completed a burst.
 * That is exactly the gap that let a five-test suite go green on the FPGA
 * while the AXI/DDR path had never been built.
 *
 * This test's working set is deliberately larger than the D-cache, so most
 * accesses miss and the traffic that results -- 64-byte line fills, dirty
 * writebacks, back-to-back bursts -- is the traffic the backend is actually
 * responsible for.
 *
 * FOUR PASSES, each a different access order, because a memory path can be
 * correct for one order and wrong for another:
 *
 *   1. sequential   streaming.  Line fills and writebacks arrive in address
 *                   order, which is the easy case and the one a prefetcher or
 *                   a write-combining buffer is most likely to get right.
 *   2. congruent    every access maps to the same cache set as the previous
 *                   one, so each evicts a dirty line and immediately fills
 *                   another.  Maximum eviction pressure, minimum locality,
 *                   and the order most likely to expose a backend that
 *                   mishandles a writeback closely followed by a fill.
 *   3. reverse      descending addresses.  Distinguishes a genuine
 *                   address-translation bug from a direction-dependent one.
 *   4. read-modify  each word is read, altered and written back, so every
 *      -write       line is fetched for ownership and then written back
 *                   dirty -- fill and writeback of the SAME line, which
 *                   passes 1-3 never produce.
 *
 * Values are derived from the address (see memtest_common.h), so an access
 * that lands on the wrong location is caught even though the value it finds
 * there is a perfectly well-formed pattern word.
 *
 * WHY ONLY PASS 1 TOUCHES EVERY WORD.  Memory traffic is per line: a fill
 * brings in 64 bytes and a writeback sends 64 bytes whether the program read
 * one word of that line or all eight.  Passes 2-4 are about the ORDER lines
 * are filled and evicted in, so they step a line at a time and generate the
 * same bus traffic for an eighth of the instructions.  Pass 1 is the one that
 * has to touch every word, because the failure it exists to catch is a
 * backend that drops, duplicates or reorders a beat within an 8-beat burst --
 * which is invisible unless every word of the line is checked, and is the
 * single most likely defect in a freshly written AXI bridge.
 *
 * The scheduler is running throughout: the tick interrupt preempts these
 * loops at 10 kHz, so a line fill interrupted mid-burst is part of what gets
 * tested rather than something a bare-metal test would miss.
 *
 * Exit codes (10+, to stay clear of freertos_main.c's 2-5):
 *   0  PASS
 *  10  could not allocate a working set
 *  16  MEMTEST_BASE overlaps the program, the HTIF page or the end of memory
 *  11  working set too small to outrun the cache -- the test would be
 *      vacuous, so it fails loudly rather than passing
 *  12  sequential pass mismatch
 *  13  congruent pass mismatch
 *  14  reverse pass mismatch
 *  15  read-modify-write pass mismatch
 */

#include <stddef.h>
#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"
#include "test_utils_freertos.h"
#include "memtest_common.h"

/* Working set.  The default is sized for the 128 KiB block RAM build, where
 * it comes out of the 64 KiB FreeRTOS heap and must still be at least twice
 * the D-cache to guarantee capacity misses. */
#ifndef MEMTEST_KB
#define MEMTEST_KB 32
#endif

/*
 * MEMTEST_BASE -- use a fixed address instead of the FreeRTOS heap.
 *
 * Defined by TARGET=pynq-ddr and by nothing else, for a reason worth stating.
 * The program occupies the low 8 MiB of the carve-out, so a heap-allocated
 * working set keeps address bits 23 and up constant for the whole run: a
 * bridge that drops, transposes or sign-extends one of those bits would pass
 * every check here.  Placing the buffer 128 MiB in makes those bits live.
 *
 * It also sidesteps the heap entirely, so the working set is not bounded by
 * configTOTAL_HEAP_SIZE and a multi-megabyte run needs no other change.
 *
 * The address is unmanaged, so app_main checks it against the program's own
 * extent, the HTIF page and the end of memory before touching it.
 */
#ifndef MEMTEST_MEM_END
#define MEMTEST_MEM_END 0x90000000UL     /* EXT_MEM_BASE + EXT_MEM_RANGE + 1 */
#endif

#define E_ALLOC      10
#define E_TOO_SMALL  11
#define E_SEQ        12
#define E_CONGRUENT  13
#define E_REVERSE    14
#define E_RMW        15
#define E_BAD_BASE   16

/* volatile so the compiler cannot satisfy a read from the value it just
 * stored: the point of every loop here is the round trip through memory. */
static volatile uint64_t *g_buf;
static size_t             g_words;

static inline uint64_t want_at(volatile uint64_t *p, uint64_t salt)
{
    return memtest_mix((uint64_t)(uintptr_t)p ^ salt);
}

/* ---- pass 1: sequential -------------------------------------------------- */
static int pass_sequential(uint64_t salt)
{
    for (size_t i = 0; i < g_words; i++)
        g_buf[i] = want_at(&g_buf[i], salt);

    for (size_t i = 0; i < g_words; i++) {
        uint64_t want = want_at(&g_buf[i], salt);
        uint64_t got  = g_buf[i];
        if (got != want) {
            memtest_fail("seq", (uint64_t)(uintptr_t)&g_buf[i], want, got);
            return 1;
        }
    }
    return 0;
}

/* ---- pass 2: congruent (set-conflict) ------------------------------------
 * Walks the buffer set-major rather than address-major: all the words that
 * share a cache set, then the next set.  The buffer spans more than
 * MEMTEST_CACHE_WAYS way-lengths, so the inner loop visits more congruent
 * lines than there are ways and every single access evicts.
 */
static int pass_congruent(uint64_t salt)
{
    const size_t stride = MEMTEST_CONGRUENT_STRIDE / sizeof(uint64_t);
    const size_t span   = stride < g_words ? stride : g_words;
    const size_t step   = MEMTEST_WORDS_PER_LINE;

    /* off advances a line at a time, so each value of off names a distinct
     * cache set; the inner loop then walks every line in the buffer that
     * shares that set. */
    for (size_t off = 0; off < span; off += step)
        for (size_t i = off; i < g_words; i += stride)
            g_buf[i] = want_at(&g_buf[i], salt);

    for (size_t off = 0; off < span; off += step)
        for (size_t i = off; i < g_words; i += stride) {
            uint64_t want = want_at(&g_buf[i], salt);
            uint64_t got  = g_buf[i];
            if (got != want) {
                memtest_fail("congruent", (uint64_t)(uintptr_t)&g_buf[i],
                             want, got);
                return 1;
            }
        }
    return 0;
}

/* ---- pass 3: reverse ----------------------------------------------------- */
static int pass_reverse(uint64_t salt)
{
    const size_t step = MEMTEST_WORDS_PER_LINE;

    for (size_t i = g_words; i >= step; i -= step)
        g_buf[i - step] = want_at(&g_buf[i - step], salt);

    for (size_t i = g_words; i >= step; i -= step) {
        uint64_t want = want_at(&g_buf[i - step], salt);
        uint64_t got  = g_buf[i - step];
        if (got != want) {
            memtest_fail("reverse", (uint64_t)(uintptr_t)&g_buf[i - step],
                         want, got);
            return 1;
        }
    }
    return 0;
}

/* ---- pass 4: read-modify-write ------------------------------------------- */
static int pass_rmw(uint64_t salt)
{
    const uint64_t delta = 0x0123456789abcdefULL;
    const size_t   step  = MEMTEST_WORDS_PER_LINE;

    for (size_t i = 0; i < g_words; i += step)
        g_buf[i] = want_at(&g_buf[i], salt);

    /* Second sweep reads each word back and writes it altered, so the line is
     * fetched for ownership and then written back dirty.  Whether it misses
     * depends on the working set outrunning the cache, which app_main has
     * already checked. */
    for (size_t i = 0; i < g_words; i += step)
        g_buf[i] = g_buf[i] ^ delta;

    for (size_t i = 0; i < g_words; i += step) {
        uint64_t want = want_at(&g_buf[i], salt) ^ delta;
        uint64_t got  = g_buf[i];
        if (got != want) {
            memtest_fail("rmw", (uint64_t)(uintptr_t)&g_buf[i], want, got);
            return 1;
        }
    }
    return 0;
}

/* Reject a fixed base that overlaps anything that matters, rather than
 * discovering it as a program that corrupts itself. */
#ifdef MEMTEST_BASE
extern char _end[];
extern volatile uint64_t tohost;

static int base_is_usable(uintptr_t base, size_t bytes)
{
    const uintptr_t end   = base + bytes;
    const uintptr_t prog  = (uintptr_t)_end;
    const uintptr_t htif  = (uintptr_t)&tohost & ~(uintptr_t)4095;

    if (base & 7u) {
        uart_puts("MEMTEST FAIL base is not 8-byte aligned\n");
        return 0;
    }
    if (end <= base || end > (uintptr_t)MEMTEST_MEM_END) {
        uart_puts("MEMTEST FAIL working set runs past the end of memory\n");
        return 0;
    }
    if (base < prog) {
        uart_puts("MEMTEST FAIL base is below _end, inside the program\n");
        return 0;
    }
    if (base < htif + 4096u && htif < end) {
        uart_puts("MEMTEST FAIL working set covers the HTIF page\n");
        return 0;
    }
    return 1;
}
#endif

int app_main(void)
{
    const size_t bytes = (size_t)MEMTEST_KB * 1024u;

#ifdef MEMTEST_BASE
    if (!base_is_usable((uintptr_t)MEMTEST_BASE, bytes)) {
        uart_puts("  base=");
        memtest_put_hex((uint64_t)(uintptr_t)MEMTEST_BASE);
        uart_puts(" bytes=");
        memtest_put_dec(bytes);
        uart_puts("\n");
        return E_BAD_BASE;
    }
    g_buf = (volatile uint64_t *)(uintptr_t)MEMTEST_BASE;
#else
    g_buf = (volatile uint64_t *)pvPortMalloc(bytes);
    if (g_buf == NULL) {
        uart_puts("MEMTEST FAIL alloc of ");
        memtest_put_dec(bytes);
        uart_puts(" bytes from the FreeRTOS heap\n");
        return E_ALLOC;
    }
#endif
    g_words = bytes / sizeof(uint64_t);

    /* A working set that fits in the cache makes every pass below a test of
     * the cache and nothing else -- it would go green against a memory
     * backend that was not connected.  Refuse rather than mislead. */
    if (bytes < 2u * MEMTEST_CACHE_BYTES) {
        uart_puts("MEMTEST FAIL working set ");
        memtest_put_dec(bytes);
        uart_puts(" B does not exceed 2x the cache (");
        memtest_put_dec(2u * MEMTEST_CACHE_BYTES);
        uart_puts(" B); the test would prove nothing\n");
        return E_TOO_SMALL;
    }

    uart_puts("MEMTEST stress base=");
    memtest_put_hex((uint64_t)(uintptr_t)g_buf);
    uart_puts(" bytes=");
    memtest_put_dec(bytes);
    uart_puts(" cache=");
    memtest_put_dec(MEMTEST_CACHE_BYTES);
    uart_puts("\n");

    if (pass_sequential(0x1111111111111111ULL)) return E_SEQ;
    uart_puts("MEMTEST seq OK\n");

    if (pass_congruent(0x2222222222222222ULL)) return E_CONGRUENT;
    uart_puts("MEMTEST congruent OK\n");

    if (pass_reverse(0x3333333333333333ULL))   return E_REVERSE;
    uart_puts("MEMTEST reverse OK\n");

    if (pass_rmw(0x4444444444444444ULL))       return E_RMW;
    uart_puts("MEMTEST rmw OK\n");

#ifndef MEMTEST_BASE
    vPortFree((void *)g_buf);
#endif
    return 0;
}
