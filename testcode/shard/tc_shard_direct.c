// tc_shard_direct.c
//
// Exercises the memory and floating-point instructions SHARD does not defer: they wait
// in the Memory stage until the shadow is quiescent, are checked there, and then act
// directly.
//   - misaligned loads and stores, inside a doubleword, across doublewords and across
//     a cache line
//   - floating point, including fused multiply-add (FMA residue check), FP load/store,
//     FP divide and FP-to-integer conversion
//
// The riscv-formal RVFI monitor models a misaligned access as a trap, so this test
// must run in a simulator built without it:
//   make -C sim run_verilator_top_tb_no_spike NO_SPIKE_DIR=build_no_spike_norvfi \
//        EXTRA_DEFINES=+define+ECE411_NO_RVFI PROG=../testcode/shard/tc_shard_direct.c
//
// Exit code 0 = pass; otherwise the number of the first failing check.

#include <stdint.h>
#include "../isa_level_testing/test_utils.h"

static volatile uint64_t mem[16] __attribute__((aligned(64)));

#define CHECK(id, cond) do { if (!(cond)) sim_exit(id); } while (0)

static void test_misaligned(void) {
    volatile uint8_t *b = (volatile uint8_t *)&mem[8];   // start of a 64-byte cache line
    uint64_t r0, r1, r2, r3;
    mem[8] = 0; mem[9] = 0; mem[7] = 0;
    __asm__ volatile (
        "sw  %[v0], 1(%[b])\n"          // misaligned inside one doubleword
        "lw  %[r0], 1(%[b])\n"
        "sd  %[v1], 5(%[b])\n"          // crosses a doubleword
        "ld  %[r1], 5(%[b])\n"
        "sd  %[v2], -3(%[b])\n"         // crosses a cache line
        "ld  %[r2], -3(%[b])\n"
        "lhu %[r3], 7(%[b])\n"          // crosses a doubleword
        : [r0]"=&r"(r0), [r1]"=&r"(r1), [r2]"=&r"(r2), [r3]"=&r"(r3)
        : [b]"r"(b), [v0]"r"(0x11223344UL), [v1]"r"(0x0102030405060708UL),
          [v2]"r"(0xA1A2A3A4A5A6A7A8UL)
        : "memory");
    CHECK(30, r0 == 0x11223344);
    CHECK(31, r1 == 0x0102030405060708UL);
    CHECK(32, r2 == 0xA1A2A3A4A5A6A7A8UL);
    CHECK(33, r3 == 0x0506);
    CHECK(34, mem[7] == 0xA6A7A80000000000UL);
    CHECK(35, mem[8] == 0x060708A1A2A3A4A5UL);
    CHECK(36, mem[9] == 0x0000000102030405UL);
}

static void test_fp(void) {
    uint64_t r0, r1, r2, r3, r4, r5;
    __asm__ volatile ("li t0, 0x2000\n csrs mstatus, t0" ::: "t0");    // FS = initial
    __asm__ volatile (
        "fmv.d.x ft0, %[a]\n"
        "fmv.d.x ft1, %[b]\n"
        "fmv.d.x ft2, %[c]\n"
        "fmadd.d ft3, ft0, ft1, ft2\n"    // 3*5+1 = 16
        "fmv.x.d %[r0], ft3\n"
        "fmul.d  ft4, ft0, ft1\n"         // 15
        "fmv.x.d %[r1], ft4\n"
        "fmsub.d ft5, ft3, ft4, ft0\n"    // 16*15-3 = 237
        "fmv.x.d %[r2], ft5\n"
        "fadd.d  ft6, ft5, ft2\n"         // 238
        "fmv.x.d %[r3], ft6\n"
        "fsd     ft6, 0(%[p])\n"          // FP store, then integer and FP loads
        "ld      %[r4], 0(%[p])\n"
        "fld     ft7, 0(%[p])\n"
        "fdiv.d  ft7, ft7, ft1\n"         // 238/5 = 47.6
        "fcvt.l.d %[r5], ft7, rtz\n"      // 47
        : [r0]"=&r"(r0), [r1]"=&r"(r1), [r2]"=&r"(r2), [r3]"=&r"(r3), [r4]"=&r"(r4), [r5]"=&r"(r5)
        : [a]"r"(0x4008000000000000UL), [b]"r"(0x4014000000000000UL),
          [c]"r"(0x3FF0000000000000UL), [p]"r"(&mem[10])
        : "ft0", "ft1", "ft2", "ft3", "ft4", "ft5", "ft6", "ft7", "memory");
    CHECK(60, r0 == 0x4030000000000000UL);
    CHECK(61, r1 == 0x402E000000000000UL);
    CHECK(62, r2 == 0x406DA00000000000UL);
    CHECK(63, r3 == 0x406DC00000000000UL);
    CHECK(64, r4 == 0x406DC00000000000UL);
    CHECK(65, r5 == 47);
}

int main(void) {
    test_misaligned();
    test_fp();
    // Again, so every path also runs warm (caches filled, predictors trained).
    test_misaligned();
    test_fp();
    sim_exit(0);
}
