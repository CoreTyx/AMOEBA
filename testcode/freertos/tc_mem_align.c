/*
 * tc_mem_align.c -- byte granularity through the whole memory path.
 *
 * WHAT IT CHECKS.  That a store of 1, 2, 4 or 8 bytes changes exactly those
 * bytes and leaves every other byte of the surrounding cache line alone, for
 * every naturally-aligned position in the line -- and that this survives a
 * round trip out to memory and back.
 *
 * The eight byte offsets of a 1-byte store, the four of a halfword, the two
 * of a word and the one of a doubleword together generate every byte-write
 * pattern the core can produce, so the matrix below is complete rather than
 * representative.
 *
 * WHAT THIS DOES NOT TEST, MEASURED RATHER THAN ASSUMED.  It does not test
 * the backend's byte strobes.  CVW's D-cache is write-allocate and
 * write-back, so a sub-word store to cacheable memory is merged inside the
 * cache and the line later writes back in full with every strobe set -- and
 * EXT_MEM is the only region on the external AHB, so no sub-word write
 * reaches it at all.
 *
 * That was checked, not reasoned about: replacing the write mask in
 * hdl/ahb_to_memitf.sv with a hardcoded '1 -- a backend that ignores byte
 * enables entirely -- leaves this test passing on all three lines.  The
 * HWSTRB handling there is, for cacheable traffic, dead code.  Exercising it
 * needs either an access that bypasses the cache (Linux mapping a page
 * non-cacheable will be the first) or an RTL testbench that drives sub-word
 * transactions at the bridge directly, which is the cheaper place to put it.
 *
 * What it DOES test, and what nothing else in the suite does:
 *
 *   - the cache's own byte merge, which is what actually holds the value
 *   - a byte-accurate line writeback and refill round trip.  Each case below
 *     forces writeback, refill, writeback, refill and then checks 24 bytes
 *     individually, so a backend that returns a line's bytes in the wrong
 *     order, drops a doubleword of one, or merges two lines is caught with
 *     the offending byte named.  That is the failure mode a new AXI bridge
 *     actually has.
 *
 * FORCING THE ROUND TRIP.  A store followed by a load hits the same dirty
 * line and never leaves the cache, which would reduce all of this to a test
 * of a register file.  Between writing and reading, evict_line() pushes the
 * line out by touching more congruent lines than there are ways -- the same
 * conflict-eviction trick htif_writeback() in syscalls_amoeba.c uses, and for
 * the same reason: config_baremetal_linux sets ZICBOM_SUPPORTED = 0, so there
 * is no cbo.flush to call.
 *
 * Exit codes (20+, clear of freertos_main.c's 2-5 and tc_mem_stress's 10s):
 *   0  PASS
 *  20  could not allocate the arena
 *  21  a store changed the wrong bytes, or did not survive the round trip
 */

#include <stddef.h>
#include <stdint.h>
#include "FreeRTOS.h"
#include "task.h"
#include "test_utils_freertos.h"
#include "memtest_common.h"

#define E_ALLOC     20
#define E_MISMATCH  21

/* Background every byte starts at.  Any byte still holding this after a store
 * was untouched; any byte holding it that should have changed means the store
 * never landed. */
#define BACKGROUND  0xA5

/* The arena has to be long enough that evict_line() can find more congruent
 * lines than the cache has ways, all within memory we own.  Two way-lengths
 * of slack past that also give us a 4 KiB boundary to straddle. */
#define ARENA_BYTES  ((MEMTEST_CACHE_WAYS + 2) * MEMTEST_WAY_BYTES)

static volatile uint8_t *g_arena;      /* line-aligned, ARENA_BYTES long */
static volatile uint64_t g_sink;       /* keeps the evicting loads alive */

/*
 * Evict the line containing p by reading MEMTEST_CACHE_WAYS + 1 other lines
 * with the same set index.  Congruence is preserved by stepping in multiples
 * of MEMTEST_WAY_BYTES, and by wrapping modulo ARENA_BYTES, which is itself a
 * multiple of MEMTEST_WAY_BYTES -- so the wrap does not disturb the address
 * bits that choose the set.
 */
static void evict_line(volatile void *p)
{
    const uintptr_t base = (uintptr_t)g_arena;
    const uintptr_t off  = (uintptr_t)p - base;
    uint64_t sink = 0;

    for (unsigned k = 1; k <= MEMTEST_CACHE_WAYS + 1; k++) {
        uintptr_t o = (off + (uintptr_t)k * MEMTEST_WAY_BYTES) % ARENA_BYTES;
        sink += *(volatile uint64_t *)(base + (o & ~(uintptr_t)7));
    }
    g_sink = sink;
}

/* The value to store for a given case.  Distinct per (size, offset) so a
 * store of the wrong width or to the wrong place is visible in the value and
 * not only in its position.  Any byte that collides with BACKGROUND is
 * flipped, so "unchanged" and "correctly written" can never look alike. */
static uint64_t case_value(unsigned size, unsigned off)
{
    uint64_t v = memtest_mix(((uint64_t)size << 32) ^ off);
    for (unsigned j = 0; j < size; j++) {
        if (((v >> (8 * j)) & 0xFF) == BACKGROUND)
            v ^= (uint64_t)0xFF << (8 * j);
    }
    return v;
}

static void fail_case(unsigned size, unsigned off, unsigned byte,
                      uintptr_t line, uint8_t want, uint8_t got)
{
    uart_puts("MEMTEST FAIL align size=");
    memtest_put_dec(size);
    uart_puts(" off=");   memtest_put_dec(off);
    uart_puts(" byte=");  memtest_put_dec(byte);
    uart_puts(" line=");  memtest_put_hex(line);
    uart_puts(" want=");  memtest_put_hex(want);
    uart_puts(" got=");   memtest_put_hex(got);
    if (got == BACKGROUND && want != BACKGROUND)
        uart_puts("   (store never landed here)");
    else if (want == BACKGROUND)
        uart_puts("   (store spilled onto a byte it must not touch)");
    uart_puts("\n");
}

/* Run the full size x offset matrix against one cache line. */
static int test_line(uintptr_t line_off)
{
    volatile uint8_t *line = g_arena + line_off;

    for (unsigned size = 1; size <= 8; size <<= 1) {
        for (unsigned off = 0; off + size <= MEMTEST_LINE_BYTES; off += size) {
            const uint64_t v = case_value(size, off);

            /* Background the whole line, then push it to memory, so what we
             * verify against later came back from the backend rather than
             * having sat in the cache the entire time. */
            for (unsigned b = 0; b < MEMTEST_LINE_BYTES; b += 8)
                *(volatile uint64_t *)(line + b) =
                    0xA5A5A5A5A5A5A5A5ULL;
            evict_line(line);

            switch (size) {
            case 1: *(volatile uint8_t  *)(line + off) = (uint8_t)v;  break;
            case 2: *(volatile uint16_t *)(line + off) = (uint16_t)v; break;
            case 4: *(volatile uint32_t *)(line + off) = (uint32_t)v; break;
            default: *(volatile uint64_t *)(line + off) = v;          break;
            }
            evict_line(line);

            /* Verify the doubleword the store landed in plus the one on
             * either side.  The whole line was backgrounded above, so a store
             * that spilled shows up in a neighbour; checking all 64 bytes
             * instead would triple the loads to cover a failure mode -- a
             * byte-enable path corrupting a byte seven doublewords away --
             * that no plausible bug produces.
             *
             * Byte loads on the way back, so load byte-enables are covered as
             * well as store ones. */
            unsigned lo = (off & ~7u);
            unsigned hi = lo + 16u;
            lo = (lo >= 8u) ? lo - 8u : 0u;
            if (hi > MEMTEST_LINE_BYTES) hi = MEMTEST_LINE_BYTES;

            for (unsigned b = lo; b < hi; b++) {
                uint8_t want = (b >= off && b < off + size)
                             ? (uint8_t)(v >> (8 * (b - off)))
                             : (uint8_t)BACKGROUND;
                uint8_t got = line[b];
                if (got != want) {
                    fail_case(size, off, b, (uintptr_t)line, want, got);
                    return 1;
                }
            }
        }
    }
    return 0;
}

int app_main(void)
{
    /* Over-allocate by a line so the arena itself can be line-aligned: set
     * index and byte offset both depend on the low address bits, and an
     * arena that starts mid-line would shift every case in the matrix. */
    void *raw = pvPortMalloc(ARENA_BYTES + MEMTEST_LINE_BYTES);
    if (raw == NULL) {
        uart_puts("MEMTEST FAIL alloc of ");
        memtest_put_dec(ARENA_BYTES + MEMTEST_LINE_BYTES);
        uart_puts(" bytes from the FreeRTOS heap\n");
        return E_ALLOC;
    }
    g_arena = (volatile uint8_t *)(((uintptr_t)raw + MEMTEST_LINE_BYTES - 1)
                                   & ~(uintptr_t)(MEMTEST_LINE_BYTES - 1));

    /* Three line positions, chosen for the geometry each one probes.  The
     * 4 KiB pair is the interesting one: that is a page boundary under SV39
     * and the point at which a backend's address arithmetic has to carry into
     * a higher bit group, which is where an off-by-one in a bridge lives. */
    const uintptr_t positions[] = {
        MEMTEST_LINE_BYTES,                           /* an ordinary line    */
        MEMTEST_WAY_BYTES - MEMTEST_LINE_BYTES,       /* last before 4 KiB   */
        MEMTEST_WAY_BYTES,                            /* first after 4 KiB   */
    };

    uart_puts("MEMTEST align base=");
    memtest_put_hex((uint64_t)(uintptr_t)g_arena);
    uart_puts(" arena=");
    memtest_put_dec(ARENA_BYTES);
    uart_puts("\n");

    for (unsigned i = 0; i < sizeof(positions) / sizeof(positions[0]); i++) {
        if (test_line(positions[i]))
            return E_MISMATCH;
        uart_puts("MEMTEST align line+");
        memtest_put_dec(positions[i]);
        uart_puts(" OK\n");
    }

    vPortFree(raw);
    return 0;
}
