// @stress tier=pr seeds=2 nightly_seeds=8 build=spike duts=legacy timeout=30000000
// @stress-variant build=no_spike duts=forte
//
// st_dcache_conflict -- D$ set-conflict and write-back stress.
//
// The D$ is 2 ways x 64 sets x 16-byte lines (pkg/config.vh, via amoeba_cfg.h),
// so addresses 1 KiB apart share a set.  Each round picks a set and WAYS+1..16
// aliases of it -- always more than the ways -- and writes them with a random
// mix of sb/sh/sw/sd that together build known 64-bit patterns, then reads them
// back in a different order with different widths.  Every access is a conflict
// miss and most evictions are dirty, so the victim write-back, the refill
// merging with pending partial writes, and the byte-enable paths are all on the
// critical path.  Runs under Spike lock-step co-simulation: every load value is
// checked against the reference model as it retires, not just at the end.
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define WAY_BYTES  AMOEBA_DCACHE_WAYSIZEINBYTES
#define LINE       AMOEBA_DCACHE_LINE_BYTES
#define WAYS       AMOEBA_DCACHE_NUMWAYS
#define ROUNDS     (40 * ST_SCALE)
#define MAX_ALIAS  16
#define REGION     (MAX_ALIAS * 4 * WAY_BYTES)

static uint8_t g_buf[REGION + 4096] ST_ALIGNED(4096);

static inline uint64_t pat(uint64_t addr, uint64_t round) { return st_mix64(addr * 0x9E3779B97F4A7C15ULL ^ round); }

static void store_pattern(uint64_t a, uint64_t v, int how) {
    switch (how) {
    case 0: *(volatile uint64_t *)a = v; break;
    case 1: for (int i = 0; i < 2; i++) *(volatile uint32_t *)(a + 4 * i) = (uint32_t)(v >> (32 * i)); break;
    case 2: for (int i = 0; i < 4; i++) *(volatile uint16_t *)(a + 2 * i) = (uint16_t)(v >> (16 * i)); break;
    default: for (int i = 7; i >= 0; i--) *(volatile uint8_t *)(a + i) = (uint8_t)(v >> (8 * i)); break;
    }
}
static uint64_t load_pattern(uint64_t a, int how) {
    uint64_t v = 0;
    switch (how) {
    case 0: v = *(volatile uint64_t *)a; break;
    case 1: for (int i = 1; i >= 0; i--) v = (v << 32) | *(volatile uint32_t *)(a + 4 * i); break;
    case 2: for (int i = 3; i >= 0; i--) v = (v << 16) | *(volatile uint16_t *)(a + 2 * i); break;
    default: for (int i = 7; i >= 0; i--) v = (v << 8) | *(volatile uint8_t *)(a + i); break;
    }
    return v;
}

int main(void) {
    st_init();
    st_section("set-conflict rounds");
    uint64_t base = ((uint64_t)g_buf + WAY_BYTES - 1) & ~(uint64_t)(WAY_BYTES - 1);
    uint64_t bad = 0, checks = 0;
    for (int r = 0; r < ROUNDS; r++) {
        uint64_t set = st_rand_range(WAY_BYTES / LINE);
        int nalias = WAYS + 1 + (int)st_rand_range(MAX_ALIAS - WAYS);
        uint64_t stride = WAY_BYTES * (1 + st_rand_range(4));
        /* write: every dword of every alias line */
        for (int a = 0; a < nalias; a++)
            for (uint64_t d = 0; d < LINE; d += 8) {
                uint64_t addr = base + (uint64_t)a * stride + set * LINE + d;
                store_pattern(addr, pat(addr, (uint64_t)r), (int)st_rand_range(4));
            }
        /* partial overwrite of random bytes in random aliases, tracked in pat' */
        for (int k = 0; k < nalias; k++) {
            int a = (int)st_rand_range((uint64_t)nalias);
            uint64_t addr = base + (uint64_t)a * stride + set * LINE + 8 * st_rand_range(LINE / 8);
            uint64_t v = load_pattern(addr, (int)st_rand_range(4));
            int byte = (int)st_rand_range(8);
            *(volatile uint8_t *)(addr + byte) = (uint8_t)~(v >> (8 * byte));
            v ^= 0xffUL << (8 * byte);
            checks++;
            if (load_pattern(addr, (int)st_rand_range(4)) != v) bad++;
            store_pattern(addr, pat(addr, (uint64_t)r), (int)st_rand_range(4));   /* restore */
        }
        /* read back in reverse order, random widths */
        for (int a = nalias - 1; a >= 0; a--)
            for (uint64_t d = 0; d < LINE; d += 8) {
                uint64_t addr = base + (uint64_t)a * stride + set * LINE + d;
                checks++;
                if (load_pattern(addr, (int)st_rand_range(4)) != pat(addr, (uint64_t)r)) bad++;
            }
    }
    ST_CHECK_EQ("every conflict-miss readback matched", bad, 0);
    ST_CHECK("ran", checks > (uint64_t)ROUNDS * (WAYS + 1));

    st_section("streaming: footprint 16x the D$");
    uint64_t span = 16 * AMOEBA_DCACHE_BYTES;
    for (uint64_t o = 0; o < span; o += 8) *(volatile uint64_t *)(base + o) = pat(base + o, 0xabc);
    bad = 0;
    for (uint64_t o = span; o > 0; o -= 8) if (*(volatile uint64_t *)(base + o - 8) != pat(base + o - 8, 0xabc)) bad++;
    ST_CHECK_EQ("streamed write-back/refill", bad, 0);
    return st_result();
}
