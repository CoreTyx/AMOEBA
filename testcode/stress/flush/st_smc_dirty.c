// @stress tier=pr seeds=2 build=spike duts=legacy timeout=40000000
// @stress-variant build=no_spike duts=forte
//
// st_smc_dirty -- fence.i must reach code that is in every possible cache state.
//
// On this core fence.i writes the whole D$ back and invalidates the I$.  The
// new code can be: still dirty in the D$ (never written back), already evicted
// to memory by unrelated traffic, a single changed halfword in a line the I$
// holds, or a code region twice the size of the D$ (write-backs happening
// while it is being written).  Each case regenerates functions with fresh
// return values and requires every one of them after a single fence.i.
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define NF 64                 /* functions, 128 bytes apart: 8 KiB = 2x D$ */
#define STRIDE 128

static uint8_t g_code[NF * STRIDE] ST_ALIGNED(4096);
static uint64_t g_junk[4096] ST_ALIGNED(4096);

static void emit(int i, int32_t v) {
    uint64_t a = (uint64_t)g_code + (uint64_t)i * STRIDE + (uint64_t)(i & 7) * 2;   /* varying alignment */
    a = st_put_li32(a, 10, v);
    st_put_insn32(a, ENC_RET);
}
static uint64_t call(int i) {
    uint64_t a = (uint64_t)g_code + (uint64_t)i * STRIDE + (uint64_t)(i & 7) * 2;
    return ((uint64_t (*)(void))a)();
}
static void evict_dcache(void) {
    for (unsigned i = 0; i < ST_ARRAY_LEN(g_junk); i += 2) g_junk[i] += 1;
}

int main(void) {
    st_init();
    int32_t val[NF];
    uint64_t bad;
    for (int round = 0; round < 3 * ST_SCALE; round++) {
        st_section("A: code dirty in D$, fence.i, run");
        bad = 0;
        for (int i = 0; i < 16; i++) { val[i] = (int32_t)st_rand(); emit(i, val[i]); }
        st_fence_i();
        for (int i = 0; i < 16; i++) bad += call(i) != (uint64_t)(int64_t)val[i];
        ST_CHECK_EQ("dirty code", bad, 0);

        st_section("B: code evicted to memory by other traffic before fence.i");
        bad = 0;
        for (int i = 0; i < 16; i++) { val[i] = (int32_t)st_rand(); emit(i, val[i]); }
        evict_dcache();
        st_fence_i();
        for (int i = 0; i < 16; i++) bad += call(i) != (uint64_t)(int64_t)val[i];
        ST_CHECK_EQ("evicted code", bad, 0);

        st_section("C: one halfword changed in lines the I$ holds");
        bad = 0;
        for (int i = 0; i < 16; i++) (void)call(i);     /* I$ hot */
        for (int i = 0; i < 16; i++) {
            /* change only the addiw immediate's upper halfword */
            uint64_t a = (uint64_t)g_code + (uint64_t)i * STRIDE + (uint64_t)(i & 7) * 2 + 4;
            uint32_t insn = st_get_insn32(a);
            int32_t lo = (int32_t)st_rand_range(1024);
            insn = (insn & 0x000fffffu) | ((uint32_t)lo << 20);
            *(volatile uint16_t *)(a + 2) = (uint16_t)(insn >> 16);
            uint32_t hi = (((uint32_t)val[i] + 0x800u) >> 12) << 12;
            val[i] = (int32_t)(hi + (uint32_t)lo);
        }
        st_fence_i();
        for (int i = 0; i < 16; i++) bad += call(i) != (uint64_t)(int64_t)val[i];
        ST_CHECK_EQ("halfword patch in hot lines", bad, 0);

        st_section("D: 8 KiB of code (2x D$) written, then one fence.i");
        bad = 0;
        for (int i = 0; i < NF; i++) { val[i] = (int32_t)st_rand(); emit(i, val[i]); }
        st_fence_i();
        for (int k = 0; k < 2; k++)
            for (int i = NF - 1; i >= 0; i--) bad += call(i) != (uint64_t)(int64_t)val[i];
        ST_CHECK_EQ("large region", bad, 0);
    }
    return st_result();
}
