// tc_page_deny.c
// Accesses a leaf page-table entry refuses: that each one page-faults with the
// right cause, address and pc, and that it has no effect -- a refused store
// changes neither the cache nor memory nor a device register, a refused load
// returns nothing, a refused fetch does not execute.  The lines are brought
// into the cache first, so a refused store is a cache hit, and every access
// is made twice: the first misses the TLB and is refused after the walk, the
// second is refused from the TLB entry the walk left.
//
// tc_hptw_fault.c covers walks that end in a fault, tc_pmp_deny.c what the PMP
// refuses; this one covers what a valid leaf entry refuses.
//
// Sv39, set up from M-mode:
//   root[2]                    0x0_8000_0000  1 GiB identity leaf (the program)
//   root[3] -> l1[0] -> l0[i]  0x0_C000_0000 + i * 4 KiB, the pages below
// Loads and stores are made from M-mode with mstatus.MPRV and MPP = S (SUM and
// MXR clear), fetches by returning into S-mode.

#include "test_utils.h"

#define PTE_V 0x01UL
#define PTE_R 0x02UL
#define PTE_W 0x04UL
#define PTE_X 0x08UL
#define PTE_U 0x10UL
#define PTE_A 0x40UL
#define PTE_D 0x80UL

#define CAUSE_ECALL_S     9
#define CAUSE_INSTR_PAGE  12
#define CAUSE_LOAD_PAGE   13
#define CAUSE_STORE_PAGE  15
#define NO_TRAP           (~0UL)

#define SENTINEL   0x5e5e5e5e5e5e5e5eUL
#define VA_BASE    0x0C0000000UL
#define VA(page, off)  (VA_BASE + (uint64_t)(page) * 4096 + (off))
#define MTIMECMP   0x02004000UL

// What virtual page i is, and what refuses it.
enum { PG_GOOD, PG_READONLY, PG_CLEAN, PG_NOT_ACCESSED, PG_EXEC_ONLY, PG_USER, PG_INVALID,
       PG_DEVICE, PG_CODE_NOEXEC, PG_CODE, NPAGES };
#define NDATA PG_DEVICE         // pages 0 .. NDATA-1 are backed by `pages`

static uint64_t root_table[512] __attribute__((aligned(4096)));
static uint64_t l1_table[512]   __attribute__((aligned(4096)));
static uint64_t l0_table[512]   __attribute__((aligned(4096)));
static volatile uint64_t pages[NDATA][512] __attribute__((aligned(4096)));

volatile uint64_t trap_cause, trap_epc, trap_tval, trap_count;
volatile uint64_t resume_pc, expect_pc;

// Records the trap and resumes at resume_pc in M-mode with MPRV off.  Only
// reached from the probes below, which treat t0 and t1 as clobbered.
__asm__ (
    ".text\n"
    ".align 2\n"
    ".globl page_trap\n"
    "page_trap:\n"
    "    csrr t0, mcause\n    la t1, trap_cause\n    sd t0, 0(t1)\n"
    "    csrr t0, mepc\n      la t1, trap_epc\n      sd t0, 0(t1)\n"
    "    csrr t0, mtval\n     la t1, trap_tval\n     sd t0, 0(t1)\n"
    "    la t1, trap_count\n  ld t0, 0(t1)\n  addi t0, t0, 1\n  sd t0, 0(t1)\n"
    "    la t1, resume_pc\n   ld t0, 0(t1)\n  csrw mepc, t0\n"
    "    li t0, 0x20000\n     csrc mstatus, t0\n"      // MPRV off
    "    li t0, 0x1800\n      csrs mstatus, t0\n"      // MPP = M
    "    mret\n"
    ".align 2\n"
    ".globl page_stub\n"
    "page_stub:\n"
    "    ecall\n"
);
extern void page_trap(void);
extern void page_stub(void);
#define STUB_OFF ((uint64_t)page_stub & 0xfff)

static void clear_trap(void) { trap_cause = NO_TRAP; trap_epc = NO_TRAP; trap_tval = NO_TRAP; }

#define SET_RESUME "la t0, 1f\n la t1, resume_pc\n sd t0, 0(t1)\n"
#define SET_EXPECT "la t0, 2f\n la t1, expect_pc\n sd t0, 0(t1)\n"
#define MPRV_ON    "li t0, 0x1800\n csrc mstatus, t0\n li t0, 0x20800\n csrs mstatus, t0\n"   // MPRV, MPP = S
#define MPRV_OFF   "li t0, 0x20000\n csrc mstatus, t0\n"
#define RESUME     ".align 2\n1:\n"

// Load as S-mode would.  A load that traps leaves SENTINEL in the register.
static uint64_t __attribute__((noinline)) probe_load(uint64_t va) {
    uint64_t d = SENTINEL;
    clear_trap();
    __asm__ volatile (SET_RESUME SET_EXPECT MPRV_ON "2: ld %0, 0(%1)\n" MPRV_OFF RESUME
                      : "+r"(d) : "r"(va) : "t0", "t1", "memory");
    return d;
}
static void __attribute__((noinline)) probe_store(uint64_t va, uint64_t d) {
    clear_trap();
    __asm__ volatile (SET_RESUME SET_EXPECT MPRV_ON "2: sd %1, 0(%0)\n" MPRV_OFF RESUME
                      : : "r"(va), "r"(d) : "t0", "t1", "memory");
}
// Fetch at va in S-mode.  Always comes back through the trap handler.
static void __attribute__((noinline)) probe_fetch(uint64_t va) {
    clear_trap();
    __asm__ volatile (SET_RESUME "csrw mepc, %0\n"
                      "li t0, 0x1800\n csrc mstatus, t0\n li t0, 0x0800\n csrs mstatus, t0\n"   // MPP = S
                      "mret\n" RESUME
                      : : "r"(va) : "t0", "t1", "memory");
}

static uint64_t pattern(int page, uint64_t off) { return 0x9e3779b97f4a7c15UL * ((uint64_t)page * 4096 + off + 8); }
static uint64_t leaf(uint64_t pa, uint64_t bits) { return ((pa >> 12) << 10) | bits | PTE_V; }

// A store the entry refuses, twice (TLB miss, then TLB hit), into words that
// are in the cache.  Counts what went wrong.
static uint64_t refused_stores(int page) {
    uint64_t bad = 0;
    for (int i = 0; i < 2; i++) {
        uint64_t off = 0x100 + 0x208 * (uint64_t)i;
        uint64_t before = pages[page][off / 8];                 // also brings the line into the cache
        probe_store(VA(page, off), 0xbad0000000000000UL + off);
        if (trap_cause != CAUSE_STORE_PAGE || trap_tval != VA(page, off) || trap_epc != expect_pc) bad++;
        if (pages[page][off / 8] != before) bad += 0x100;       // the store landed
    }
    return bad;
}
static uint64_t refused_loads(int page) {
    uint64_t bad = 0;
    for (int i = 0; i < 2; i++) {
        uint64_t off = 0x300 + 0x208 * (uint64_t)i;
        (void)pages[page][off / 8];
        if (probe_load(VA(page, off)) != SENTINEL) bad += 0x100; // something was loaded
        if (trap_cause != CAUSE_LOAD_PAGE || trap_tval != VA(page, off) || trap_epc != expect_pc) bad++;
    }
    return bad;
}

int main(void) {
    uint64_t before, code_pa = (uint64_t)page_stub & ~0xfffUL;

    for (int p = 0; p < NDATA; p++)
        for (uint64_t off = 0; off < 4096; off += 8) pages[p][off / 8] = pattern(p, off);

    root_table[2] = leaf(0x80000000UL, PTE_D | PTE_A | PTE_X | PTE_W | PTE_R);
    root_table[3] = ((uint64_t)l1_table >> 12) << 10 | PTE_V;
    l1_table[0]   = ((uint64_t)l0_table >> 12) << 10 | PTE_V;
    l0_table[PG_GOOD]         = leaf((uint64_t)pages[PG_GOOD],         PTE_D | PTE_A | PTE_W | PTE_R);
    l0_table[PG_READONLY]     = leaf((uint64_t)pages[PG_READONLY],     PTE_D | PTE_A | PTE_R);
    l0_table[PG_CLEAN]        = leaf((uint64_t)pages[PG_CLEAN],        PTE_A | PTE_W | PTE_R);
    l0_table[PG_NOT_ACCESSED] = leaf((uint64_t)pages[PG_NOT_ACCESSED], PTE_D | PTE_W | PTE_R);
    l0_table[PG_EXEC_ONLY]    = leaf((uint64_t)pages[PG_EXEC_ONLY],    PTE_A | PTE_X);
    l0_table[PG_USER]         = leaf((uint64_t)pages[PG_USER],         PTE_D | PTE_A | PTE_U | PTE_W | PTE_R);
    l0_table[PG_INVALID]      = leaf((uint64_t)pages[PG_INVALID],      PTE_D | PTE_A | PTE_W | PTE_R) & ~PTE_V;
    l0_table[PG_DEVICE]       = leaf(MTIMECMP,                         PTE_D | PTE_A | PTE_R);
    l0_table[PG_CODE_NOEXEC]  = leaf(code_pa,                          PTE_A | PTE_R);
    l0_table[PG_CODE]         = leaf(code_pa,                          PTE_A | PTE_X | PTE_R);

    __asm__ volatile ("csrw pmpaddr0, %0" : : "r"(~0UL));
    __asm__ volatile ("csrw pmpcfg0, %0"  : : "r"(0x1fUL));
    __asm__ volatile ("csrw mtvec, %0" : : "r"((uint64_t)page_trap));
    __asm__ volatile ("csrw satp, %0"  : : "r"((8UL << 60) | ((uint64_t)root_table >> 12)));
    __asm__ volatile ("sfence.vma");

    test_begin("a page that allows everything");
    check("load", probe_load(VA(PG_GOOD, 0x40)), pattern(PG_GOOD, 0x40));
    check("no trap", trap_cause, NO_TRAP);
    probe_store(VA(PG_GOOD, 0x48), 0x1234);
    check("no trap", trap_cause, NO_TRAP);
    check("store landed", pages[PG_GOOD][0x48 / 8], 0x1234);

    test_begin("read-only page");
    check("stores refused, memory unchanged", refused_stores(PG_READONLY), 0);
    check("load", probe_load(VA(PG_READONLY, 0x50)), pattern(PG_READONLY, 0x50));
    check("no trap", trap_cause, NO_TRAP);

    test_begin("writable page with the dirty bit clear");
    check("stores refused, memory unchanged", refused_stores(PG_CLEAN), 0);
    check("load", probe_load(VA(PG_CLEAN, 0x58)), pattern(PG_CLEAN, 0x58));
    check("no trap", trap_cause, NO_TRAP);

    test_begin("page with the accessed bit clear");
    check("stores refused, memory unchanged", refused_stores(PG_NOT_ACCESSED), 0);
    check("loads refused, nothing loaded", refused_loads(PG_NOT_ACCESSED), 0);

    test_begin("execute-only page");
    check("stores refused, memory unchanged", refused_stores(PG_EXEC_ONLY), 0);
    check("loads refused, nothing loaded", refused_loads(PG_EXEC_ONLY), 0);

    test_begin("user page, from supervisor mode");
    check("stores refused, memory unchanged", refused_stores(PG_USER), 0);
    check("loads refused, nothing loaded", refused_loads(PG_USER), 0);

    test_begin("invalid entry");
    check("stores refused, memory unchanged", refused_stores(PG_INVALID), 0);
    check("loads refused, nothing loaded", refused_loads(PG_INVALID), 0);

    // A device register behind a read-only entry: a refused store must not
    // reach the bus.  Then the same store through a writable entry, to show
    // that the mapping does reach the register.
    test_begin("device register behind a read-only page");
    before = *(volatile uint64_t *)MTIMECMP;
    for (int i = 0; i < 2; i++) {
        probe_store(VA(PG_DEVICE, 0), 0x7fffffffffff0000UL);
        check("mcause", trap_cause, CAUSE_STORE_PAGE);
        check("mtval", trap_tval, VA(PG_DEVICE, 0));
        check("register unchanged", *(volatile uint64_t *)MTIMECMP, before);
    }
    l0_table[PG_DEVICE] = leaf(MTIMECMP, PTE_D | PTE_A | PTE_W | PTE_R);
    __asm__ volatile ("sfence.vma");
    probe_store(VA(PG_DEVICE, 0), 0x7fffffffffff0000UL);
    check("no trap once it is writable", trap_cause, NO_TRAP);
    check("register written", *(volatile uint64_t *)MTIMECMP, 0x7fffffffffff0000UL);
    *(volatile uint64_t *)MTIMECMP = before;

    // Fetches.  The executable mapping goes first, so the stub's line is in
    // the cache when the mapping that is not executable is tried.
    test_begin("fetch from an executable page reaches the ecall");
    probe_fetch(VA(PG_CODE, STUB_OFF));
    check("mcause", trap_cause, CAUSE_ECALL_S);
    check("mepc", trap_epc, VA(PG_CODE, STUB_OFF));
    test_begin("fetch from a page that is not executable");
    for (int i = 0; i < 2; i++) {
        probe_fetch(VA(PG_CODE_NOEXEC, STUB_OFF));
        check("mcause", trap_cause, CAUSE_INSTR_PAGE);
        check("mepc", trap_epc, VA(PG_CODE_NOEXEC, STUB_OFF));
        check("mtval", trap_tval, VA(PG_CODE_NOEXEC, STUB_OFF));
    }
    test_begin("fetch from a data page");
    probe_fetch(VA(PG_GOOD, 0));
    check("mcause", trap_cause, CAUSE_INSTR_PAGE);
    check("mtval", trap_tval, VA(PG_GOOD, 0));

    // The page that allows everything still does, and nothing above leaked
    // into it.
    test_begin("the good page afterwards");
    check("load", probe_load(VA(PG_GOOD, 0x40)), pattern(PG_GOOD, 0x40));
    check("earlier store", probe_load(VA(PG_GOOD, 0x48)), 0x1234);
    check("no trap", trap_cause, NO_TRAP);

    __asm__ volatile ("csrw satp, zero");
    __asm__ volatile ("sfence.vma");
    print_summary();
    test_finish();
}
