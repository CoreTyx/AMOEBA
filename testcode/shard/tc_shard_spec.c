// tc_shard_spec.c
//
// Exercises the instruction classes SHARD defers through its queues and the CSR
// state mirror, which the other test tiers barely touch:
//   - store-to-load forwarding out of the store queue (overlapping sub-word stores)
//   - AMOs and LR/SC (their write half goes through the store queue)
//   - signed/unsigned multiplies (mod-3 residue check) and divides
//   - CSR reads/writes of mirrored CSRs, a trap and an mret (CSR state mirror)
//
// Run with the no-Spike simulator (the Spike co-simulation path cannot follow AMOs):
//   make -C sim run_verilator_top_tb_no_spike PROG=../testcode/shard/tc_shard_spec.c
//
// Exit code 0 = pass; otherwise the number of the first failing check.

#include <stdint.h>
#include "../isa_level_testing/test_utils.h"

static volatile uint64_t mem[16] __attribute__((aligned(64)));
static volatile uint64_t trap_cause;
static volatile uint64_t trap_count;

#define CHECK(id, cond) do { if (!(cond)) sim_exit(id); } while (0)

// Trap handler: record mcause, skip the trapping instruction, return.
void trap_entry(void);
__asm__(
    ".align 2\n"
    ".globl trap_entry\n"
    "trap_entry:\n"
    "  csrrw t6, mscratch, t6\n"      // free a register
    "  csrr  t6, mcause\n"
    "  sd    t6, trap_cause, t5\n"
    "  ld    t6, trap_count\n"
    "  addi  t6, t6, 1\n"
    "  sd    t6, trap_count, t5\n"
    "  csrr  t6, mepc\n"
    "  addi  t6, t6, 4\n"
    "  csrw  mepc, t6\n"
    "  csrrw t6, mscratch, t6\n"
    "  mret\n");

#define AMO(name, insn)                                                        \
    static inline uint64_t name(volatile void *p, uint64_t v) {                \
        uint64_t r;                                                            \
        __asm__ volatile (insn " %0, %2, (%1)"                                 \
                          : "=&r"(r) : "r"(p), "r"(v) : "memory");             \
        return r;                                                              \
    }
AMO(amoswap_d, "amoswap.d")
AMO(amoadd_d,  "amoadd.d")
AMO(amoand_d,  "amoand.d")
AMO(amoor_d,   "amoor.d")
AMO(amoxor_d,  "amoxor.d")
AMO(amomin_d,  "amomin.d")
AMO(amomaxu_d, "amomaxu.d")
AMO(amoadd_w,  "amoadd.w")
AMO(amoswap_w, "amoswap.w")
AMO(amomax_w,  "amomax.w")

#define MULOP(name, insn)                                                      \
    static inline uint64_t name(uint64_t a, uint64_t b) {                      \
        uint64_t r;                                                            \
        __asm__ volatile (insn " %0, %1, %2" : "=r"(r) : "r"(a), "r"(b));      \
        return r;                                                              \
    }
MULOP(op_mul,    "mul")
MULOP(op_mulh,   "mulh")
MULOP(op_mulhsu, "mulhsu")
MULOP(op_mulhu,  "mulhu")
MULOP(op_mulw,   "mulw")
MULOP(op_div,    "div")
MULOP(op_rem,    "rem")
MULOP(op_divu,   "divu")

static void test_forwarding(void) {
    volatile uint64_t *p = &mem[0];
    uint64_t a, b, c, d, e;
    // Stores followed at once by loads of the same word: the loads must see every
    // store still sitting in the store queue, byte by byte, newest last.
    __asm__ volatile (
        "sd  %[v0], 0(%[p])\n"
        "sb  %[v1], 3(%[p])\n"
        "ld  %[a], 0(%[p])\n"
        "sh  %[v2], 6(%[p])\n"
        "lw  %[b], 0(%[p])\n"
        "ld  %[c], 0(%[p])\n"
        "sw  %[v3], 4(%[p])\n"
        "lhu %[d], 6(%[p])\n"
        "lbu %[e], 3(%[p])\n"
        : [a]"=&r"(a), [b]"=&r"(b), [c]"=&r"(c), [d]"=&r"(d), [e]"=&r"(e)
        : [p]"r"(p), [v0]"r"(0x1122334455667788UL), [v1]"r"(0xAAUL),
          [v2]"r"(0xBBCCUL), [v3]"r"(0xDEADBEEFUL)
        : "memory");
    CHECK(1, a == 0x11223344AA667788UL);
    CHECK(2, b == 0xFFFFFFFFAA667788UL);
    CHECK(3, c == 0xBBCC3344AA667788UL);
    CHECK(4, d == 0xDEAD);
    CHECK(5, e == 0xAA);
    CHECK(6, mem[0] == 0xDEADBEEFAA667788UL);

    // A run of stores to different words, then read them all back.
    for (int i = 1; i < 16; i++) mem[i] = 0x0101010101010101UL * (uint64_t)i;
    uint64_t sum = 0;
    for (int i = 1; i < 16; i++) sum += mem[i];
    CHECK(7, sum == 0x0101010101010101UL * 120);
}

static void test_atomics(void) {
    mem[1] = 100;
    CHECK(10, amoswap_d(&mem[1], 7) == 100 && mem[1] == 7);
    CHECK(11, amoadd_d(&mem[1], 5) == 7 && mem[1] == 12);
    CHECK(12, amoand_d(&mem[1], 0xA) == 12 && mem[1] == 8);
    CHECK(13, amoor_d(&mem[1], 0x30) == 8 && mem[1] == 0x38);
    CHECK(14, amoxor_d(&mem[1], 0xFF) == 0x38 && mem[1] == 0xC7);
    CHECK(15, amomin_d(&mem[1], (uint64_t)-5) == 0xC7 && mem[1] == (uint64_t)-5);
    CHECK(16, amomaxu_d(&mem[1], 9) == (uint64_t)-5 && mem[1] == (uint64_t)-5);

    mem[2] = 0x00000001FFFFFFFFUL;                       // low word = -1
    CHECK(17, amoadd_w(&mem[2], 2) == (uint64_t)-1 && mem[2] == 0x0000000100000001UL);
    CHECK(18, amoswap_w((volatile uint32_t *)&mem[2] + 1, 0x80000000UL) == 1 &&
              mem[2] == 0x8000000000000001UL);
    CHECK(19, amomax_w(&mem[2], (uint64_t)-7) == 1 && mem[2] == 0x8000000000000001UL);

    // Back-to-back AMOs on one word: each must read the previous one's buffered write.
    mem[3] = 0;
    for (int i = 0; i < 20; i++) amoadd_d(&mem[3], (uint64_t)i);
    CHECK(20, mem[3] == 190);

    // LR/SC: success, then an SC with no reservation must fail and leave memory alone.
    uint64_t old, rc, rc2;
    mem[4] = 55;
    __asm__ volatile (
        "lr.d %[old], (%[p])\n"
        "addi %[old], %[old], 1\n"
        "sc.d %[rc], %[old], (%[p])\n"
        "sc.d %[rc2], %[bad], (%[p])\n"
        : [old]"=&r"(old), [rc]"=&r"(rc), [rc2]"=&r"(rc2)
        : [p]"r"(&mem[4]), [bad]"r"(999UL) : "memory");
    CHECK(21, rc == 0 && mem[4] == 56);
    CHECK(22, rc2 != 0 && mem[4] == 56);
    uint32_t oldw;
    __asm__ volatile (
        "lr.w %[old], (%[p])\n"
        "sc.w %[rc], %[v], (%[p])\n"
        : [old]"=&r"(oldw), [rc]"=&r"(rc) : [p]"r"(&mem[4]), [v]"r"(77UL) : "memory");
    CHECK(23, rc == 0 && oldw == 56 && mem[4] == 77);
}

static void test_muldiv(void) {
    volatile uint64_t m1 = (uint64_t)-1, m3 = (uint64_t)-3, five = 5;
    volatile uint64_t big = 0x8000000000000000UL, x = 0x123456789ABCDEF1UL, y = 0xFEDCBA9876543211UL;
    CHECK(40, op_mul(m3, five) == (uint64_t)-15);
    CHECK(41, op_mulh(m3, five) == (uint64_t)-1);
    CHECK(42, op_mulhu(m1, m1) == 0xFFFFFFFFFFFFFFFEUL);
    CHECK(43, op_mulhsu(m1, m1) == (uint64_t)-1);
    CHECK(44, op_mulhsu(five, m1) == 4);
    CHECK(45, op_mulh(big, big) == 0x4000000000000000UL);
    CHECK(46, op_mulh(big, m1) == 0);
    CHECK(47, op_mulhu(big, m1) == 0x7FFFFFFFFFFFFFFFUL);
    CHECK(48, op_mulw(0x7FFFFFFF, 2) == (uint64_t)-2);
    CHECK(49, op_mul(x, y) == x * y);
    CHECK(50, op_mulhu(x, y) == (uint64_t)(((unsigned __int128)x * y) >> 64));
    CHECK(51, op_mulh(x, y) == (uint64_t)(((__int128)(int64_t)x * (int64_t)y) >> 64));
    CHECK(52, op_mulhsu(y, x) == (uint64_t)(((__int128)(int64_t)y * (unsigned __int128)x) >> 64));
    CHECK(53, op_div(100, 7) == 14 && op_rem(100, 7) == 2);
    CHECK(54, op_div((uint64_t)-100, 7) == (uint64_t)-14 && op_divu(m1, 2) == 0x7FFFFFFFFFFFFFFFUL);
}

static void test_csr(void) {
    uint64_t a, b, c, d, old_tvec, ms0, ms1, ms2;
    __asm__ volatile ("csrr %0, mtvec" : "=r"(old_tvec));
    __asm__ volatile ("csrw mtvec, %0" :: "r"((uint64_t)&trap_entry));
    __asm__ volatile ("csrr %0, mtvec" : "=r"(a));
    CHECK(70, a == (uint64_t)&trap_entry);

    __asm__ volatile (
        "csrw  mscratch, %[v]\n"
        "csrr  %[a], mscratch\n"
        "csrrs %[b], mscratch, %[s]\n"
        "csrrc %[c], mscratch, %[k]\n"
        "csrrw %[d], mscratch, x0\n"
        : [a]"=&r"(a), [b]"=&r"(b), [c]"=&r"(c), [d]"=&r"(d)
        : [v]"r"(0x00FF00FF00FF00FFUL), [s]"r"(0xF000UL), [k]"r"(0xFFUL));
    CHECK(71, a == 0x00FF00FF00FF00FFUL);
    CHECK(72, b == 0x00FF00FF00FF00FFUL);
    CHECK(73, c == 0x00FF00FF00FFF0FFUL);
    CHECK(74, d == 0x00FF00FF00FFF000UL);

    __asm__ volatile ("csrw mepc, %1\n csrr %0, mepc" : "=&r"(a) : "r"(0x80001237UL));
    CHECK(75, a == 0x80001236UL);                        // bit 0 is not writable

    // mstatus.MIE set and clear (no interrupt source is enabled in mie)
    __asm__ volatile (
        "csrr  %[m0], mstatus\n"
        "csrsi mstatus, 8\n"
        "csrr  %[m1], mstatus\n"
        "csrci mstatus, 8\n"
        "csrr  %[m2], mstatus\n"
        : [m0]"=&r"(ms0), [m1]"=&r"(ms1), [m2]"=&r"(ms2));
    CHECK(76, (ms1 & 8) == 8 && (ms2 & 8) == 0 && ((ms0 ^ ms2) & ~8UL) == 0);

    // Trap and return: ecall from M-mode, the handler skips it and mrets.
    trap_cause = 0; trap_count = 0;
    __asm__ volatile ("ecall" ::: "memory");
    __asm__ volatile ("ecall" ::: "memory");
    CHECK(77, trap_count == 2 && trap_cause == 11);
    __asm__ volatile ("csrr %0, mcause" : "=r"(a));
    CHECK(78, a == 11);
    __asm__ volatile ("csrr %0, mstatus" : "=r"(a));
    CHECK(79, ((a >> 11) & 3) == 0 && (a & 0x80));       // after mret: MPP = U, MPIE = 1

    __asm__ volatile ("csrw mtvec, %0" :: "r"(old_tvec));
}

int main(void) {
    test_forwarding();
    test_atomics();
    test_muldiv();
    test_csr();
    // Again, so every path also runs warm (caches filled, predictors trained).
    test_forwarding();
    test_atomics();
    test_muldiv();
    sim_exit(0);
}
