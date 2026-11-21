// @stress tier=pr seeds=2 nightly_seeds=8 build=spike duts=legacy timeout=30000000
// @stress-variant build=no_spike duts=forte
//
// st_smc_lines -- self-modifying code at every alignment, then fence.i.
//
// With the C extension a 32-bit instruction can start at any 2-byte boundary,
// so it can straddle two 16-byte I$ lines (offset 14) or two fetch blocks.
// For every start offset 0..30 the test executes `addi a0, a0, IMM ; ret`,
// rewrites the immediate (halfword stores: a word store at 2 mod 4 would
// itself be misaligned), executes fence.i, and requires the new value -- the
// I$ must have dropped BOTH lines a straddling instruction came from, and the
// D$ must have written the patch back before the refill.  Compressed patches
// (c.addi replacing c.nop in the padding) are interleaved.  Under Spike
// lock-step co-simulation every executed encoding is checked as well.
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define ROUNDS (12 * ST_SCALE)

static uint8_t g_code[8192] ST_ALIGNED(4096);

/* code at base: k x c.nop, addi a0,a0,imm, ret */
static uint64_t build(uint64_t base, int k, int32_t imm) {
    for (int i = 0; i < k; i++) *(volatile uint16_t *)(base + 2 * (uint64_t)i) = ENC_C_NOP;
    uint64_t at = base + 2 * (uint64_t)k;
    st_put_insn32(at, ENC_ADDI(10, 10, imm));
    st_put_insn32(at + 4, ENC_RET);
    return at;
}

int main(void) {
    st_init();
    st_section("patch a 32-bit addi at every 2-byte offset");
    uint64_t bad = 0, runs = 0;
    for (int r = 0; r < ROUNDS; r++) {
        for (int k = 0; k < 16; k++) {
            uint64_t base = (uint64_t)g_code + (uint64_t)((r * 512) % 4096) + 32 * (uint64_t)(k & 7);
            int32_t i0 = (int32_t)st_rand_range(2047), i1 = (int32_t)st_rand_range(2047) - 1024;
            uint64_t at = build(base, k, i0);
            st_fence_i();
            uint64_t (*fn)(uint64_t) = (uint64_t (*)(uint64_t))base;
            if (fn(1000) != (uint64_t)(1000 + i0)) bad++;
            /* patch only the immediate's halfword(s), sometimes just the top half */
            uint32_t ni = ENC_ADDI(10, 10, i1);
            if (r & 1) st_put_insn32(at, ni);
            else *(volatile uint16_t *)(at + 2) = (uint16_t)(ni >> 16);
            if ((r & 1) == 0 && ((ni ^ ENC_ADDI(10, 10, i0)) & 0xffff)) st_put_insn32(at, ni);
            st_fence_i();
            if (fn(1000) != (uint64_t)(int64_t)(1000 + i1)) bad++;
            /* compressed patch: turn the first c.nop into c.addi a0, 3 */
            if (k > 0) {
                *(volatile uint16_t *)base = 0x050d;      /* c.addi a0, 3 */
                st_fence_i();
                if (fn(1000) != (uint64_t)(int64_t)(1003 + i1)) bad++;
            }
            runs++;
        }
    }
    ST_CHECK_EQ("every patched instruction took effect after fence.i", bad, 0);
    ST_CHECK_EQ("runs", runs, (uint64_t)ROUNDS * 16);

    st_section("patch the instruction after the one being returned to");
    /* fn: addi a0,a0,1 ; addi a0,a0,X ; ret -- execute, patch slot 2, fence.i, run */
    uint64_t f2 = (uint64_t)g_code + 4096 + 14;          /* first insn straddles */
    for (int i = 0; i < 64 * ST_SCALE; i++) {
        int32_t x = (int32_t)st_rand_range(1000);
        st_put_insn32(f2, ENC_ADDI(10, 10, 1));
        st_put_insn32(f2 + 4, ENC_ADDI(10, 10, x));
        st_put_insn32(f2 + 8, ENC_RET);
        st_fence_i();
        uint64_t (*fn)(uint64_t) = (uint64_t (*)(uint64_t))f2;
        ST_CHECK_EQ("chain", fn(0), (uint64_t)(1 + x));
    }
    return st_result();
}
