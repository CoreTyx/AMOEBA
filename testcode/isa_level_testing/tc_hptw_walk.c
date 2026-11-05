// tc_hptw_walk.c
// Three-level Sv39 page walks, many of them: 4 KiB pages, more of them than
// either TLB holds, so loads, stores and fetches keep missing and the walker
// keeps running between ordinary accesses.  tc_hptw_fault.c covers walks that
// end in a fault; this one covers walks that succeed and checks that what is
// read, written and executed afterwards is the right page.
//
//   root[2]                    0x0_8000_0000  1 GiB identity leaf (the program)
//   root[3] -> l1[0] -> l0[i]  0x0_C000_0000 + i * 4 KiB, i = 0 .. NPAGES-1
//       even i: data page i/2 of `pages`, in reverse order
//       odd  i: the page of code holding s_mode_ecall, executable
// Loads and stores are made from M-mode with mstatus.MPRV and MPP = S; fetches
// by returning into S-mode, where the ecall brings control back.

#include "test_utils.h"

#define PTE_V 0x01UL
#define PTE_R 0x02UL
#define PTE_W 0x04UL
#define PTE_X 0x08UL
#define PTE_A 0x40UL
#define PTE_D 0x80UL
#define LEAF_RW  (PTE_D | PTE_A | PTE_W | PTE_R | PTE_V)
#define LEAF_RX  (PTE_A | PTE_X | PTE_R | PTE_V)
#define LEAF_RWX (LEAF_RW | PTE_X)

#define VA_BASE     0x0C0000000UL
#define NPAGES      40                  // virtual pages; each TLB holds 8
#define NDATA       (NPAGES / 2)
#define CAUSE_ECALL_S 9

static uint64_t root_table[512] __attribute__((aligned(4096)));
static uint64_t l1_table[512]   __attribute__((aligned(4096)));
static uint64_t l0_table[512]   __attribute__((aligned(4096)));
static uint64_t pages[NDATA][512] __attribute__((aligned(4096)));

volatile uint64_t trap_cause, trap_epc, trap_count;
volatile uint64_t resume_pc;

// Records the trap and resumes at resume_pc in M-mode with MPRV off.
__asm__ (
    ".text\n"
    ".align 2\n"
    ".globl walk_trap\n"
    "walk_trap:\n"
    "    csrr t0, mcause\n    la t1, trap_cause\n    sd t0, 0(t1)\n"
    "    csrr t0, mepc\n      la t1, trap_epc\n      sd t0, 0(t1)\n"
    "    la t1, trap_count\n  ld t0, 0(t1)\n  addi t0, t0, 1\n  sd t0, 0(t1)\n"
    "    la t1, resume_pc\n   ld t0, 0(t1)\n  csrw mepc, t0\n"
    "    li t0, 0x20000\n     csrc mstatus, t0\n"
    "    li t0, 0x1800\n      csrs mstatus, t0\n"
    "    mret\n"
    ".align 2\n"
    ".globl s_mode_ecall\n"
    "s_mode_ecall:\n"
    "    ecall\n"
);
extern void walk_trap(void);
extern void s_mode_ecall(void);

#define MPRV_ON  "li t0, 0x1800\n csrc mstatus, t0\n li t0, 0x20800\n csrs mstatus, t0\n"
#define MPRV_OFF "li t0, 0x20000\n csrc mstatus, t0\n"

// A trap inside one of these resumes after it; the callers check trap_count.
static uint64_t __attribute__((noinline)) vload(uint64_t va) {
    uint64_t d = 0;
    __asm__ volatile ("la t0, 1f\n la t1, resume_pc\n sd t0, 0(t1)\n"
                      MPRV_ON "ld %0, 0(%1)\n" MPRV_OFF ".align 2\n1:\n"
                      : "+r"(d) : "r"(va) : "t0", "t1", "memory");
    return d;
}
static void __attribute__((noinline)) vstore(uint64_t va, uint64_t d) {
    __asm__ volatile ("la t0, 1f\n la t1, resume_pc\n sd t0, 0(t1)\n"
                      MPRV_ON "sd %1, 0(%0)\n" MPRV_OFF ".align 2\n1:\n"
                      : : "r"(va), "r"(d) : "t0", "t1", "memory");
}
static void __attribute__((noinline)) vfetch(uint64_t va) {
    trap_cause = ~0UL; trap_epc = ~0UL;
    __asm__ volatile ("la t0, 1f\n la t1, resume_pc\n sd t0, 0(t1)\n"
                      "csrw mepc, %0\n"
                      "li t0, 0x1800\n csrc mstatus, t0\n li t0, 0x0800\n csrs mstatus, t0\n"
                      "mret\n.align 2\n1:\n"
                      : : "r"(va) : "t0", "t1", "memory");
}

static uint64_t data_va(int n)  { return VA_BASE + (uint64_t)(2 * n) * 4096; }      // data page n
static uint64_t code_va(int n)  { return VA_BASE + (uint64_t)(2 * n + 1) * 4096 + ((uint64_t)s_mode_ecall & 0xfff); }
static uint64_t pattern(int n, int w) { return 0x9e3779b97f4a7c15UL * (uint64_t)(n * 512 + w + 1); }

int main(void) {
    uint64_t bad;

    for (int n = 0; n < NDATA; n++)
        for (int w = 0; w < 512; w += 37) pages[n][w] = pattern(n, w);

    root_table[2] = (0x80000UL << 10) | LEAF_RWX;
    root_table[3] = (((uint64_t)l1_table >> 12) << 10) | PTE_V;
    l1_table[0]   = (((uint64_t)l0_table >> 12) << 10) | PTE_V;
    for (int n = 0; n < NDATA; n++) {
        l0_table[2 * n]     = (((uint64_t)pages[NDATA - 1 - n] >> 12) << 10) | LEAF_RW;
        l0_table[2 * n + 1] = (((uint64_t)s_mode_ecall >> 12) << 10) | LEAF_RX;
    }

    __asm__ volatile ("csrw pmpaddr0, %0" : : "r"(~0UL));
    __asm__ volatile ("csrw pmpcfg0, %0"  : : "r"(0x1fUL));
    __asm__ volatile ("csrw mtvec, %0" : : "r"((uint64_t)walk_trap));
    __asm__ volatile ("csrw satp, %0"  : : "r"((8UL << 60) | ((uint64_t)root_table >> 12)));
    __asm__ volatile ("sfence.vma");

    // Two passes over every data page: the second finds the early pages
    // evicted again.  Virtual page n is physical page NDATA-1-n.
    test_begin("loads through three-level walks");
    bad = 0;
    for (int pass = 0; pass < 2; pass++)
        for (int n = 0; n < NDATA; n++)
            for (int w = 0; w < 512; w += 185)
                if (vload(data_va(n) + 8 * (uint64_t)w) != pattern(NDATA - 1 - n, w)) bad++;
    check("wrong data", bad, 0);
    check("traps", trap_count, 0);

    test_begin("stores through three-level walks");
    for (int n = 0; n < NDATA; n++) vstore(data_va(n) + 8 * 3, 0xd00d000000000000UL + (uint64_t)n);
    bad = 0;
    for (int n = 0; n < NDATA; n++) {
        if (pages[NDATA - 1 - n][3] != 0xd00d000000000000UL + (uint64_t)n) bad++;      // landed in the right physical page
        if (vload(data_va(n) + 8 * 3) != 0xd00d000000000000UL + (uint64_t)n) bad++;    // and reads back through the TLB
        if (pages[NDATA - 1 - n][37] != pattern(NDATA - 1 - n, 37)) bad++;             // neighbours untouched
    }
    check("wrong data", bad, 0);
    check("traps", trap_count, 0);

    // Fetches: every odd page is the same code, so each fetch is a new page for
    // the ITLB and lands on the ecall.  Data walks are interleaved with them.
    test_begin("fetches through three-level walks");
    bad = 0;
    for (int pass = 0; pass < 2; pass++)
        for (int n = 0; n < NDATA; n++) {
            vfetch(code_va(n));
            if (trap_cause != CAUSE_ECALL_S || trap_epc != code_va(n)) bad++;
            if (vload(data_va((n * 7) % NDATA)) != pattern(NDATA - 1 - (n * 7) % NDATA, 0)) bad++;
        }
    check("wrong trap or data", bad, 0);
    check("traps", trap_count, 2UL * NDATA);

    __asm__ volatile ("csrw satp, zero");
    __asm__ volatile ("sfence.vma");
    print_summary();
    test_finish();
}
