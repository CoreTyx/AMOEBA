// tc_hptw_fault.c
// Faults found by the hardware page-table walker itself, as opposed to faults
// the TLB reports for a translation it holds:
//   - a non-leaf PTE with a reserved bit set  -> page fault
//   - a page-table page the PMP does not allow -> access fault
// each of them for an instruction fetch, a load and a store, next to a fetch
// and a load that walk the same root table and succeed.
//
// The walker ends such a walk in its FAULT state and the access has to finish
// "with a fault" although the TLB still misses.  Nothing else in the
// regressions reaches that state: Linux only takes page faults on leaf PTEs,
// which the walker writes into the TLB like any other entry.
//
// Sv39, set up from M-mode:
//   root[2]  0x0_8000_0000  1 GiB identity leaf (the program itself), no U bit
//   root[3]  0x0_C000_0000  pointer with the A bit set (reserved in a non-leaf)
//   root[4]  0x1_0000_0000  pointer to a table in a page PMP entry 0 denies
// Loads and stores are done from M-mode with mstatus.MPRV and MPP = S; fetches
// by returning into S-mode at the address.  Every access traps (the good fetch
// lands on an ecall) and the handler resumes the test in M-mode.

#include "test_utils.h"

#define PTE_V 0x01UL
#define PTE_R 0x02UL
#define PTE_W 0x04UL
#define PTE_X 0x08UL
#define PTE_A 0x40UL
#define PTE_D 0x80UL

#define VA_GOOD_DATA   ((uint64_t)&good_word)
#define VA_RESERVED    0x0C0000000UL
#define VA_PMP_DENIED  0x100000000UL

#define CAUSE_INSTR_ACCESS  1
#define CAUSE_LOAD_ACCESS   5
#define CAUSE_STORE_ACCESS  7
#define CAUSE_ECALL_S       9
#define CAUSE_INSTR_PAGE    12
#define CAUSE_LOAD_PAGE     13
#define CAUSE_STORE_PAGE    15

static uint64_t root_table[512]   __attribute__((aligned(4096)));
static uint64_t denied_table[512] __attribute__((aligned(4096)));
static volatile uint64_t good_word = 0x0123456789abcdefUL;

// Written by the trap handler.
volatile uint64_t trap_cause, trap_epc, trap_tval, trap_count;
volatile uint64_t resume_pc;

// Records the trap and resumes at resume_pc in M-mode with MPRV off.  Only
// reached from the probes below, which treat t0 and t1 as clobbered.
__asm__ (
    ".text\n"
    ".align 2\n"
    ".globl hptw_trap\n"
    "hptw_trap:\n"
    "    csrr t0, mcause\n    la t1, trap_cause\n    sd t0, 0(t1)\n"
    "    csrr t0, mepc\n      la t1, trap_epc\n      sd t0, 0(t1)\n"
    "    csrr t0, mtval\n     la t1, trap_tval\n     sd t0, 0(t1)\n"
    "    la t1, trap_count\n  ld t0, 0(t1)\n  addi t0, t0, 1\n  sd t0, 0(t1)\n"
    "    la t1, resume_pc\n   ld t0, 0(t1)\n  csrw mepc, t0\n"
    "    li t0, 0x20000\n     csrc mstatus, t0\n"      // MPRV off
    "    li t0, 0x1800\n      csrs mstatus, t0\n"      // MPP = M
    "    mret\n"
    ".align 2\n"
    ".globl s_mode_ecall\n"
    "s_mode_ecall:\n"
    "    ecall\n"
);
extern void hptw_trap(void);
extern void s_mode_ecall(void);

static void clear_trap(void) { trap_cause = ~0UL; trap_epc = ~0UL; trap_tval = ~0UL; }

// Load from va as S-mode would.  Returns the data, or 0 if the load trapped.
static uint64_t __attribute__((noinline)) probe_load(uint64_t va) {
    uint64_t data = 0;
    clear_trap();
    __asm__ volatile (
        "la t0, 1f\n          la t1, resume_pc\n  sd t0, 0(t1)\n"
        "li t0, 0x1800\n      csrc mstatus, t0\n"
        "li t0, 0x20800\n     csrs mstatus, t0\n"      // MPRV on, MPP = S
        "ld %0, 0(%1)\n"
        "li t0, 0x20000\n     csrc mstatus, t0\n"
        ".align 2\n"
        "1:\n"
        : "+r"(data) : "r"(va) : "t0", "t1", "memory");
    return data;
}

static void __attribute__((noinline)) probe_store(uint64_t va, uint64_t data) {
    clear_trap();
    __asm__ volatile (
        "la t0, 1f\n          la t1, resume_pc\n  sd t0, 0(t1)\n"
        "li t0, 0x1800\n      csrc mstatus, t0\n"
        "li t0, 0x20800\n     csrs mstatus, t0\n"
        "sd %1, 0(%0)\n"
        "li t0, 0x20000\n     csrc mstatus, t0\n"
        ".align 2\n"
        "1:\n"
        : : "r"(va), "r"(data) : "t0", "t1", "memory");
}

// Fetch at va in S-mode.  Always comes back through the trap handler.
static void __attribute__((noinline)) probe_fetch(uint64_t va) {
    clear_trap();
    __asm__ volatile (
        "la t0, 1f\n          la t1, resume_pc\n  sd t0, 0(t1)\n"
        "csrw mepc, %0\n"
        "li t0, 0x1800\n      csrc mstatus, t0\n"
        "li t0, 0x0800\n      csrs mstatus, t0\n"      // MPP = S
        "mret\n"
        ".align 2\n"
        "1:\n"
        : : "r"(va) : "t0", "t1", "memory");
}

static void expect_trap(const char *what, uint64_t cause, uint64_t epc_or_none, uint64_t tval) {
    test_begin(what);
    check("mcause", trap_cause, cause);
    if (epc_or_none != ~0UL) check("mepc", trap_epc, epc_or_none);
    check("mtval", trap_tval, tval);
}

int main(void) {
    uint64_t before, data;

    // Page tables.
    root_table[2] = (0x80000UL << 10) | PTE_D | PTE_A | PTE_X | PTE_W | PTE_R | PTE_V;
    root_table[3] = (((uint64_t)denied_table >> 12) << 10) | PTE_A | PTE_V;
    root_table[4] = (((uint64_t)denied_table >> 12) << 10) | PTE_V;

    // PMP: entry 0 takes the one page of denied_table away from S and U mode,
    // entry 1 gives them everything else.
    __asm__ volatile ("csrw pmpaddr0, %0" : : "r"((((uint64_t)denied_table) >> 2) | 0x1ffUL));
    __asm__ volatile ("csrw pmpaddr1, %0" : : "r"(~0UL));
    __asm__ volatile ("csrw pmpcfg0, %0"  : : "r"(0x1f18UL));

    __asm__ volatile ("csrw mtvec, %0" : : "r"((uint64_t)hptw_trap));
    __asm__ volatile ("csrw satp, %0"  : : "r"((8UL << 60) | ((uint64_t)root_table >> 12)));
    __asm__ volatile ("sfence.vma");

    // Walks that succeed.
    test_begin("load through a good walk");
    before = trap_count;
    data = probe_load(VA_GOOD_DATA);
    check("data", data, 0x0123456789abcdefUL);
    check("no trap", trap_count, before);

    probe_fetch((uint64_t)s_mode_ecall);
    expect_trap("fetch through a good walk reaches the ecall", CAUSE_ECALL_S, (uint64_t)s_mode_ecall, 0);

    // Reserved bit in a non-leaf PTE: page faults.
    probe_fetch(VA_RESERVED);
    expect_trap("fetch, reserved bit in non-leaf PTE", CAUSE_INSTR_PAGE, VA_RESERVED, VA_RESERVED);
    probe_load(VA_RESERVED + 0x18);
    expect_trap("load, reserved bit in non-leaf PTE", CAUSE_LOAD_PAGE, ~0UL, VA_RESERVED + 0x18);
    probe_store(VA_RESERVED + 0x20, 1);
    expect_trap("store, reserved bit in non-leaf PTE", CAUSE_STORE_PAGE, ~0UL, VA_RESERVED + 0x20);

    // Page-table page the PMP denies: access faults.
    probe_fetch(VA_PMP_DENIED);
    expect_trap("fetch, page table behind PMP", CAUSE_INSTR_ACCESS, VA_PMP_DENIED, VA_PMP_DENIED);
    probe_load(VA_PMP_DENIED + 0x28);
    expect_trap("load, page table behind PMP", CAUSE_LOAD_ACCESS, ~0UL, VA_PMP_DENIED + 0x28);
    probe_store(VA_PMP_DENIED + 0x30, 1);
    expect_trap("store, page table behind PMP", CAUSE_STORE_ACCESS, ~0UL, VA_PMP_DENIED + 0x30);

    // The good walks still work afterwards, back to back with the bad ones.
    test_begin("load through a good walk, again");
    before = trap_count;
    __asm__ volatile ("sfence.vma");
    data = probe_load(VA_GOOD_DATA);
    check("data", data, 0x0123456789abcdefUL);
    check("no trap", trap_count, before);
    probe_fetch((uint64_t)s_mode_ecall);
    expect_trap("fetch through a good walk, again", CAUSE_ECALL_S, (uint64_t)s_mode_ecall, 0);

    __asm__ volatile ("csrw satp, zero");
    __asm__ volatile ("sfence.vma");
    print_summary();
    test_finish();
}
