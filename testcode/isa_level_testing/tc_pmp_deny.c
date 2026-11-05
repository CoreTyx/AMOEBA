// tc_pmp_deny.c
// Accesses the PMP refuses: that each one traps with the right cause, address
// and pc, and that it has no effect -- a refused load returns nothing, a
// refused store changes neither the cache nor memory nor a device register,
// and a refused fetch does not execute, also when the line is already in the
// cache.  Around every refusal there is an access one step outside the region
// that has to go through.
//
// tc_hptw_fault.c covers the PMP refusing the page walker's own accesses; this
// one covers the instruction's access.  No address translation (satp = 0).
// Loads and stores are made from M-mode with mstatus.MPRV and MPP = S, fetches
// by returning into S-mode.
//
//   entries 0-2  set up per case
//   entry 7      everything, RWX (left out where "no entry matches" is the case)

#include "test_utils.h"

#define PMP_R     0x01UL
#define PMP_W     0x02UL
#define PMP_X     0x04UL
#define PMP_TOR   0x08UL
#define PMP_NA4   0x10UL
#define PMP_NAPOT 0x18UL
#define PMP_L     0x80UL

#define CAUSE_INSTR_ACCESS  1
#define CAUSE_LOAD_ACCESS   5
#define CAUSE_STORE_ACCESS  7
#define CAUSE_ECALL_S       9
#define NO_TRAP             (~0UL)

#define SENTINEL   0x5e5e5e5e5e5e5e5eUL
#define MTIMECMP   0x02004000UL
#define CLINT_BASE 0x02000000UL

// Three pages; the middle one is what the PMP entries are put on.
static volatile uint64_t zone[3 * 512] __attribute__((aligned(4096)));
#define Z(off)   ((uint64_t)zone + (off))
#define ZW(off)  zone[(off) / 8]
// An M-mode read: the word's line is in the cache afterwards.  A refused store
// is the dangerous one when it hits, so each is made to a line read just before.
#define IN_CACHE(off) ((void)ZW(off))

volatile uint64_t trap_cause, trap_epc, trap_tval, trap_count;
volatile uint64_t resume_pc, expect_pc;

// Records the trap and resumes at resume_pc in M-mode with MPRV off.  Only
// reached from the probes below, which treat t0 and t1 as clobbered.
__asm__ (
    ".text\n"
    ".align 2\n"
    ".globl pmp_trap\n"
    "pmp_trap:\n"
    "    csrr t0, mcause\n    la t1, trap_cause\n    sd t0, 0(t1)\n"
    "    csrr t0, mepc\n      la t1, trap_epc\n      sd t0, 0(t1)\n"
    "    csrr t0, mtval\n     la t1, trap_tval\n     sd t0, 0(t1)\n"
    "    la t1, trap_count\n  ld t0, 0(t1)\n  addi t0, t0, 1\n  sd t0, 0(t1)\n"
    "    la t1, resume_pc\n   ld t0, 0(t1)\n  csrw mepc, t0\n"
    "    li t0, 0x20000\n     csrc mstatus, t0\n"      // MPRV off
    "    li t0, 0x1800\n      csrs mstatus, t0\n"      // MPP = M
    "    mret\n"
    // Two full-size instructions in one 8-byte block, so that an entry can
    // cover both or exactly one of them.
    ".option push\n"
    ".option norvc\n"
    ".align 3\n"
    ".globl pmp_stub\n"
    "pmp_stub:\n"
    "    nop\n"
    "    ecall\n"
    ".option pop\n"
);
extern void pmp_trap(void);
extern void pmp_stub(void);
#define STUB ((uint64_t)pmp_stub)

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
// The same two without MPRV: M-mode's own accesses, for the locked entry.
static uint64_t __attribute__((noinline)) probe_load_m(uint64_t va) {
    uint64_t d = SENTINEL;
    clear_trap();
    __asm__ volatile (SET_RESUME SET_EXPECT "2: ld %0, 0(%1)\n" RESUME
                      : "+r"(d) : "r"(va) : "t0", "t1", "memory");
    return d;
}
static void __attribute__((noinline)) probe_store_m(uint64_t va, uint64_t d) {
    clear_trap();
    __asm__ volatile (SET_RESUME SET_EXPECT "2: sd %1, 0(%0)\n" RESUME
                      : : "r"(va), "r"(d) : "t0", "t1", "memory");
}
// Three accesses in consecutive instructions; the middle one is the one
// expected to trap (expect_pc), the third must then not happen.
static uint64_t __attribute__((noinline)) probe_ld_ld_sd(uint64_t a, uint64_t b, uint64_t c, uint64_t d) {
    uint64_t first = SENTINEL, second = SENTINEL;
    clear_trap();
    __asm__ volatile (SET_RESUME SET_EXPECT MPRV_ON
                      "ld %0, 0(%2)\n" "2: ld %1, 0(%3)\n" "sd %5, 0(%4)\n" MPRV_OFF RESUME
                      : "+r"(first), "+r"(second) : "r"(a), "r"(b), "r"(c), "r"(d) : "t0", "t1", "memory");
    return (second == SENTINEL) ? first : ~first;
}
static void __attribute__((noinline)) probe_sd_sd_sd(uint64_t a, uint64_t b, uint64_t c, uint64_t d) {
    clear_trap();
    __asm__ volatile (SET_RESUME SET_EXPECT MPRV_ON
                      "sd %3, 0(%0)\n" "2: sd %3, 0(%1)\n" "sd %3, 0(%2)\n" MPRV_OFF RESUME
                      : : "r"(a), "r"(b), "r"(c), "r"(d) : "t0", "t1", "memory");
}
// Fetch at va in S-mode.  Always comes back through the trap handler.
static void __attribute__((noinline)) probe_fetch(uint64_t va) {
    clear_trap();
    __asm__ volatile (SET_RESUME "csrw mepc, %0\n"
                      "li t0, 0x1800\n csrc mstatus, t0\n li t0, 0x0800\n csrs mstatus, t0\n"   // MPP = S
                      "mret\n" RESUME
                      : : "r"(va) : "t0", "t1", "memory");
}

// Entries 0-2 as given (configuration bytes packed, entry 0 lowest), entry 7
// everything or off.  The entries are off while their addresses change.
static void pmp_set(uint64_t a0, uint64_t a1, uint64_t a2, uint64_t cfg, int rest_allowed) {
    __asm__ volatile ("csrw pmpcfg0, zero");
    __asm__ volatile ("csrw pmpaddr0, %0" : : "r"(a0));
    __asm__ volatile ("csrw pmpaddr1, %0" : : "r"(a1));
    __asm__ volatile ("csrw pmpaddr2, %0" : : "r"(a2));
    __asm__ volatile ("csrw pmpaddr7, %0" : : "r"(~0UL));
    if (rest_allowed) cfg |= (PMP_NAPOT | PMP_X | PMP_W | PMP_R) << 56;
    __asm__ volatile ("csrw pmpcfg0, %0" : : "r"(cfg));
}
static uint64_t napot(uint64_t base, uint64_t size) { return (base >> 2) | ((size >> 3) - 1); }   // size >= 8

static void refused(const char *what, uint64_t cause, uint64_t va) {
    test_begin(what);
    check("mcause", trap_cause, cause);
    check("mtval", trap_tval, va);
    check("mepc", trap_epc, (cause == CAUSE_INSTR_ACCESS) ? va : expect_pc);
}
static void went_through(const char *what, uint64_t got, uint64_t want) {
    test_begin(what);
    check("no trap", trap_cause, NO_TRAP);
    check("data", got, want);
}
static uint64_t pattern(uint64_t off) { return 0x9e3779b97f4a7c15UL * (off + 8); }

int main(void) {
    uint64_t before, bad, d;

    for (uint64_t off = 0; off < 3 * 4096; off += 8) ZW(off) = pattern(off);
    __asm__ volatile ("csrw satp, zero");
    __asm__ volatile ("csrw mtvec, %0" : : "r"((uint64_t)pmp_trap));

    // ---- A region with no permissions: the middle page.
    pmp_set(napot(Z(0x1000), 4096), 0, 0, PMP_NAPOT, 1);

    went_through("load below the refused page", probe_load(Z(0x0ff8)), pattern(0x0ff8));
    d = probe_load(Z(0x1000));
    refused("load, first word of the refused page", CAUSE_LOAD_ACCESS, Z(0x1000));
    check("nothing loaded", d, SENTINEL);
    d = probe_load(Z(0x1ff8));
    refused("load, last word of the refused page", CAUSE_LOAD_ACCESS, Z(0x1ff8));
    check("nothing loaded", d, SENTINEL);
    went_through("load above the refused page", probe_load(Z(0x2000)), pattern(0x2000));

    IN_CACHE(0x1008);
    probe_store(Z(0x1008), 0x1111);
    refused("store into the refused page", CAUSE_STORE_ACCESS, Z(0x1008));
    check("memory unchanged", ZW(0x1008), pattern(0x1008));
    probe_store(Z(0x0ff0), 0x2222);
    went_through("store below the refused page", ZW(0x0ff0), 0x2222);
    probe_store(Z(0x2008), 0x3333);
    went_through("store above the refused page", ZW(0x2008), 0x3333);

    // ---- The refused access between two allowed ones, back to back.
    d = probe_ld_ld_sd(Z(0x0ff8), Z(0x1000), Z(0x2010), 0x4444);
    refused("load, load (refused), store", CAUSE_LOAD_ACCESS, Z(0x1000));
    check("the load before it completed", d, pattern(0x0ff8));
    check("the store after it did not happen", ZW(0x2010), pattern(0x2010));

    IN_CACHE(0x1010);
    probe_sd_sd_sd(Z(0x0fe8), Z(0x1010), Z(0x2018), 0x5555);
    refused("store, store (refused), store", CAUSE_STORE_ACCESS, Z(0x1010));
    check("the store before it landed", ZW(0x0fe8), 0x5555);
    check("the refused store did not", ZW(0x1010), pattern(0x1010));
    check("nor the one after it", ZW(0x2018), pattern(0x2018));

    // ---- Read-only region.
    pmp_set(napot(Z(0x1000), 4096), 0, 0, PMP_NAPOT | PMP_R, 1);
    went_through("load from a read-only page", probe_load(Z(0x1020)), pattern(0x1020));
    IN_CACHE(0x1020);
    probe_store(Z(0x1020), 0x6666);
    refused("store into a read-only page", CAUSE_STORE_ACCESS, Z(0x1020));
    check("memory unchanged", ZW(0x1020), pattern(0x1020));

    // ---- Top-of-range regions with no permissions, [lo, hi): the words on
    // either side of each bound.
    {
        static const uint64_t bounds[][2] = { {0x1008, 0x1100}, {0x1200, 0x1ff8}, {0x0ff8, 0x2008}, {0x1400, 0x1408} };
        test_begin("top-of-range regions");
        before = trap_count; bad = 0;
        for (unsigned i = 0; i < sizeof bounds / sizeof bounds[0]; i++) {
            uint64_t lo = bounds[i][0], hi = bounds[i][1];
            pmp_set(Z(lo) >> 2, Z(hi) >> 2, 0, PMP_TOR << 8, 1);
            if (probe_load(Z(lo - 8)) != ZW(lo - 8) || trap_cause != NO_TRAP) bad++;
            if (probe_load(Z(lo)) != SENTINEL || trap_cause != CAUSE_LOAD_ACCESS || trap_tval != Z(lo)) bad++;
            if (probe_load(Z(hi - 8)) != SENTINEL || trap_cause != CAUSE_LOAD_ACCESS || trap_tval != Z(hi - 8)) bad++;
            if (probe_load(Z(hi)) != ZW(hi) || trap_cause != NO_TRAP) bad++;
            IN_CACHE(hi - 8);
            probe_store(Z(hi - 8), 0x7777);
            if (trap_cause != CAUSE_STORE_ACCESS || ZW(hi - 8) == 0x7777) bad++;
        }
        check("wrong outcome", bad, 0);
        check("traps", trap_count - before, 3 * (sizeof bounds / sizeof bounds[0]));
    }
    // Entry 0 as top of range: everything below the bound, here read-only.
    pmp_set(Z(0x1000) >> 2, 0, 0, PMP_TOR | PMP_R, 1);
    went_through("load below a read-only bound", probe_load(Z(0x0ff8)), pattern(0x0ff8));
    IN_CACHE(0x0ff8);
    probe_store(Z(0x0ff8), 0x8888);
    refused("store below a read-only bound", CAUSE_STORE_ACCESS, Z(0x0ff8));
    check("memory unchanged", ZW(0x0ff8), pattern(0x0ff8));
    probe_store(Z(0x1000), 0x9999);
    went_through("store at the bound", ZW(0x1000), 0x9999);

    // ---- The lowest-numbered matching entry decides.
    pmp_set(napot(Z(0x1800), 8), napot(Z(0x1000), 4096), 0, (PMP_NAPOT | PMP_W | PMP_R) | (PMP_NAPOT << 8), 1);
    went_through("allowed word inside a refused page", probe_load(Z(0x1800)), pattern(0x1800));
    probe_load(Z(0x17f8));
    refused("the word before it", CAUSE_LOAD_ACCESS, Z(0x17f8));
    probe_load(Z(0x1808));
    refused("the word after it", CAUSE_LOAD_ACCESS, Z(0x1808));
    pmp_set(napot(Z(0x1000), 4096), napot(Z(0x1800), 8), 0, PMP_NAPOT | ((PMP_NAPOT | PMP_W | PMP_R) << 8), 1);
    probe_load(Z(0x1800));
    refused("the same word, entries the other way round", CAUSE_LOAD_ACCESS, Z(0x1800));

    // ---- No entry matches: refused below M-mode.
    pmp_set(napot(Z(0x0000), 4096), 0, 0, PMP_NAPOT | PMP_W | PMP_R, 0);
    went_through("load from the only region there is", probe_load(Z(0x0008)), pattern(0x0008));
    probe_load(Z(0x1028));
    refused("load matching no entry", CAUSE_LOAD_ACCESS, Z(0x1028));
    IN_CACHE(0x2020);
    probe_store(Z(0x2020), 0xaaaa);
    refused("store matching no entry", CAUSE_STORE_ACCESS, Z(0x2020));
    check("memory unchanged", ZW(0x2020), pattern(0x2020));

    // ---- Fetches.  The first one brings the stub's line into the cache; the
    // refused ones after it are cache hits.
    pmp_set(napot(STUB, 8), 0, 0, PMP_NAPOT | PMP_X, 1);
    probe_fetch(STUB);
    test_begin("fetch from an execute-only block reaches the ecall");
    check("mcause", trap_cause, CAUSE_ECALL_S);
    check("mepc", trap_epc, STUB + 4);
    probe_load(STUB);
    refused("load from an execute-only block", CAUSE_LOAD_ACCESS, STUB);

    pmp_set(STUB >> 2, (STUB + 4) >> 2, 0, (PMP_NA4 | PMP_X) | ((PMP_NA4 | PMP_R) << 8), 1);
    probe_fetch(STUB);
    refused("fetch running on into a block that is not executable", CAUSE_INSTR_ACCESS, STUB + 4);

    pmp_set(napot(STUB, 8), 0, 0, PMP_NAPOT | PMP_R, 1);
    probe_fetch(STUB);
    refused("fetch from a read-only block", CAUSE_INSTR_ACCESS, STUB);

    pmp_set(napot(STUB, 8), 0, 0, PMP_NAPOT | PMP_X, 1);
    probe_fetch(STUB);
    test_begin("fetch from the block again once it is executable");
    check("mcause", trap_cause, CAUSE_ECALL_S);
    check("mepc", trap_epc, STUB + 4);

    // ---- A device register: a refused store must not reach the bus.
    before = *(volatile uint64_t *)MTIMECMP;
    pmp_set(napot(CLINT_BASE, 0x10000), 0, 0, PMP_NAPOT, 1);
    probe_store(MTIMECMP, 0x7fffffffffff0000UL);
    refused("store to a device the PMP refuses", CAUSE_STORE_ACCESS, MTIMECMP);
    check("register unchanged", *(volatile uint64_t *)MTIMECMP, before);
    pmp_set(napot(CLINT_BASE, 0x10000), 0, 0, PMP_NAPOT | PMP_W | PMP_R, 1);
    probe_store(MTIMECMP, 0x7fffffffffff0000UL);
    went_through("the same store once it is allowed", *(volatile uint64_t *)MTIMECMP, 0x7fffffffffff0000UL);
    *(volatile uint64_t *)MTIMECMP = before;

    // ---- A locked entry binds M-mode too.  It stays until reset, so this
    // is the last case; nothing after it writes the page.
    pmp_set(napot(Z(0x1000), 4096), 0, 0, PMP_L | PMP_NAPOT | PMP_R, 1);
    went_through("M-mode load from a locked read-only page", probe_load_m(Z(0x1030)), pattern(0x1030));
    IN_CACHE(0x1030);
    probe_store_m(Z(0x1030), 0xbbbb);
    refused("M-mode store into a locked read-only page", CAUSE_STORE_ACCESS, Z(0x1030));
    check("memory unchanged", ZW(0x1030), pattern(0x1030));

    print_summary();
    test_finish();
}
