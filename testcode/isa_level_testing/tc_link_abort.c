///////////////////////////////////////////
// tc_link_abort.c
//
// TC_INDIRECT_STORM  - data-dependent indirect calls into a table of 64
//                      functions whose code exceeds the I-cache, so line
//                      fills are constantly in flight when the predictor is
//                      wrong and the fetch is flushed: every one of those is
//                      an off-chip burst the link bridge must finish after the
//                      core has abandoned it.
// TC_FENCEI_STORM    - fence.i between mispredicted branches: the I-cache is
//                      invalidated while a fill may be outstanding.
// TC_WRITEBACK_MIX   - a buffer larger than the D-cache written and read back
//                      so write-back bursts interleave with the fetch traffic.
//
// No hardware counters (the tapeout config has ZICNTR=0), no B/K extensions.
// The testbench prints the link's abort count at the end of the run; the
// pass criterion here is only correctness, the abort count is checked by
// the caller (see sim/Makefile link_abort target).
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////

#include "test_utils.h"

// 64 real functions, each padded to ~100 bytes so the table spans ~7 KiB
// against an 8 KiB I-cache.
#define PAD() __asm__ volatile(".rept 40\n\tnop\n\t.endr")
#define FN(k) \
    __attribute__((noinline)) static uint64_t fn_##k(uint64_t x) { PAD(); return x * (k + 1) + k; }

FN(0)  FN(1)  FN(2)  FN(3)  FN(4)  FN(5)  FN(6)  FN(7)
FN(8)  FN(9)  FN(10) FN(11) FN(12) FN(13) FN(14) FN(15)
FN(16) FN(17) FN(18) FN(19) FN(20) FN(21) FN(22) FN(23)
FN(24) FN(25) FN(26) FN(27) FN(28) FN(29) FN(30) FN(31)
FN(32) FN(33) FN(34) FN(35) FN(36) FN(37) FN(38) FN(39)
FN(40) FN(41) FN(42) FN(43) FN(44) FN(45) FN(46) FN(47)
FN(48) FN(49) FN(50) FN(51) FN(52) FN(53) FN(54) FN(55)
FN(56) FN(57) FN(58) FN(59) FN(60) FN(61) FN(62) FN(63)

typedef uint64_t (*fn_t)(uint64_t);
static fn_t tbl[64] = {
    fn_0,  fn_1,  fn_2,  fn_3,  fn_4,  fn_5,  fn_6,  fn_7,
    fn_8,  fn_9,  fn_10, fn_11, fn_12, fn_13, fn_14, fn_15,
    fn_16, fn_17, fn_18, fn_19, fn_20, fn_21, fn_22, fn_23,
    fn_24, fn_25, fn_26, fn_27, fn_28, fn_29, fn_30, fn_31,
    fn_32, fn_33, fn_34, fn_35, fn_36, fn_37, fn_38, fn_39,
    fn_40, fn_41, fn_42, fn_43, fn_44, fn_45, fn_46, fn_47,
    fn_48, fn_49, fn_50, fn_51, fn_52, fn_53, fn_54, fn_55,
    fn_56, fn_57, fn_58, fn_59, fn_60, fn_61, fn_62, fn_63,
};

static inline uint32_t lfsr_step(uint32_t s) {
    return (s >> 1) ^ (-(s & 1u) & 0xD0000001u);
}

__attribute__((noinline, optimize("O1")))
static void tc_indirect_storm(void) {
    test_begin("TC_INDIRECT_STORM");
    uint32_t s = 0xACE1u;
    uint64_t acc = 0, exp = 0;
    for (uint64_t i = 0; i < 2048; i++) {
        s = lfsr_step(s);
        uint64_t k = s & 63u;
        acc += tbl[k](i);
        exp += i * (k + 1) + k;
        // a data-dependent forward branch the 2-bit predictor cannot learn
        if (s & 0x100u) acc ^= 0x5A5Au; else exp ^= 0;
        if (s & 0x100u) exp ^= 0x5A5Au;
    }
    check("indirect storm checksum", acc, exp);
}

__attribute__((noinline, optimize("O1")))
static void tc_fencei_storm(void) {
    test_begin("TC_FENCEI_STORM");
    uint32_t s = 0xBEEFu;
    uint64_t acc = 0, exp = 0;
    for (uint64_t i = 0; i < 256; i++) {
        s = lfsr_step(s);
        uint64_t k = s & 63u;
        __asm__ volatile("fence.i" ::: "memory");
        acc += tbl[k](i ^ 7);
        exp += (i ^ 7) * (k + 1) + k;
        if (s & 0x40u) { __asm__ volatile("fence.i" ::: "memory"); acc += 1; exp += 1; }
    }
    check("fence.i storm checksum", acc, exp);
}

static uint64_t buf[2048];   // 16 KiB, twice the D-cache

__attribute__((noinline, optimize("O1")))
static void tc_writeback_mix(void) {
    test_begin("TC_WRITEBACK_MIX");
    uint32_t s = 0xC0DEu;
    for (uint64_t i = 0; i < 2048; i++) buf[i] = (i * 0x9E3779B97F4A7C15ull) ^ i;
    uint64_t bad = 0, calls = 0, exp_calls = 0;
    for (uint64_t r = 0; r < 4; r++) {
        for (uint64_t i = 0; i < 2048; i += 3) {
            s = lfsr_step(s);
            if (buf[i] != ((i * 0x9E3779B97F4A7C15ull) ^ i)) bad++;
            buf[i] += r;                       // dirty the line: write-back later
            buf[i] -= r;
            if (s & 1u) { calls += tbl[s & 63u](i); exp_calls += i * ((s & 63u) + 1) + (s & 63u); }
        }
    }
    check("buffer intact across write-backs", bad, 0);
    check("interleaved calls checksum", calls, exp_calls);
}

int main(void) {
    tc_indirect_storm();
    tc_fencei_storm();
    tc_writeback_mix();
    test_finish();
}
