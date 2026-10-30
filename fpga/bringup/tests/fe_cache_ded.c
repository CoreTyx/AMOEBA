// fe_cache_ded.c -- uncorrectable cache errors on the chip (CTRL-21,
// docs/impl_plan_fpga_rtl_freeze.md).  Run by fe_cache_ded.cmd.
//
// FI_CONTROL bit 7 alone makes every cache injection event uncorrectable.  An
// event plants one flip pair in the next word written to the cache's data
// array and one in the next tag written (cachefi.sv), so each trial controls
// where they land: the PS pulses fault_inject for one cycle at the cache's
// phase, then the trial's first writes take the flips.
//
// Per trial the PS sends 'g'; the program arms bit 7 and prints "DED GO"; a PL
// trigger on that text makes the pulse; the PS sends 'x' once it is over.
//   T1  D$ data DED on a dirty line, and a tag DED on a clean one: a store hit
//       on dirty line A takes the data flips, a load miss on C the tag flips.
//       Loading A traps (cause 20, mepc the load, mtval its address); A stays
//       in the cache.  fence.i's D$ flush drops it and traps once more (mtval
//       A's line).  D$ DED counter +2.  C's tag no longer matches, so C just
//       misses and is refetched.  Nothing counts it: a tag error is reported
//       only for the way that hits, a way with an uncorrectable tag never
//       hits, and a clean victim's tag is not checked.
// A dirty uncorrectable line cannot be evicted by a miss: the eviction's trap
// is taken at once, its flush aborts the refill, and the line stays, so the
// retried access picks it as victim again, for ever.  The flush path drops
// the line as it traps, so recovery is fence.i.
//   T2  D$ tag DED on a dirty line: a store miss on B takes both.  Loading B
//       traps (mtval its address) and B is dropped.  D$ DED counter +1.
//   T3  I$ DED: the next instruction fill takes both.  The code after the
//       pulse runs twice (the PS sends two 'x'), so whichever line took the
//       flips is fetched again: it misses, as T1's C, and is refetched.  No
//       trap, correct results, and no counter moves: with the scrubber off an
//       I$ DED is never counted.
// Lost lines are rebuilt from a shadow copy.  Every trial: no other trap, no
// other counter moves, results correct.  One line per trial:
//   DED T<n> PASS|FAIL traps <n> d <18 counter deltas>
// Exit code: the number of failed trials.
#include <stdint.h>
#include "../../../testcode/isa_level_testing/test_utils.h"

#define FI_CONTROL      (*(volatile uint8_t *)0x1007000bUL)
#define FAULT_COUNTER   ((volatile uint32_t *)0x10080000UL)
#define COUNTERS        18
#define CACHE_DED_UNIT  0x80
#define CAUSE_CACHE_DED 20
#define DCACHE_DED      7

// D$: 4 ways of 1 KiB, 16-byte lines, so addresses 1 KiB apart share a set.
#define WAY_BYTES       1024
#define LINE_BYTES      16
#define CONFLICTS       8
#define WORD(base, set) ((volatile uint64_t *)((base) + (set) * LINE_BYTES))

// Every line the trials use, each in a set of its own.
__attribute__((used)) uint8_t arena[(CONFLICTS + 1) * WAY_BYTES] __attribute__((aligned(WAY_BYTES)));
#define SET_A    1
#define SET_C    2
#define SET_B    3
#define SET_LOG  32
#define LINE_A   WORD((uintptr_t)arena, SET_A)
#define LINE_C   WORD((uintptr_t)arena, SET_C)
#define LINE_B   WORD((uintptr_t)arena, SET_B)

// The trap log, and the handler's register save area, live in sets of their
// own, so the handler's stores cannot evict a line a trial left uncorrectable.
#define MAX_TRAPS 4
struct trap_log {
    uint64_t count;
    uint64_t resume_pc;
    uint64_t cause[MAX_TRAPS];
    uint64_t epc[MAX_TRAPS];
    uint64_t tval[MAX_TRAPS];
    uint64_t saved[3];
};
#define TRAPS ((volatile struct trap_log *)((uintptr_t)arena + SET_LOG * LINE_BYTES))

// Logs mcause/mepc/mtval and resumes at resume_pc if a trial set one (the
// faulting load would only trap again), else retries the instruction.
__asm__(
    ".text\n"
    ".align 2\n"
    ".globl ded_trap\n"
    "ded_trap:\n"
    "    csrw mscratch, t0\n"
    "    la t0, arena + 512\n"              // the log: SET_LOG * LINE_BYTES
    "    sd t1, 112(t0)\n"
    "    sd t2, 120(t0)\n"
    "    sd t3, 128(t0)\n"
    "    ld t1, 0(t0)\n"                    // t1 = count
    "    li t2, 4\n"
    "    bgeu t1, t2, 1f\n"
    "    slli t2, t1, 3\n"
    "    add t2, t2, t0\n"
    "    csrr t3, mcause\n    sd t3, 16(t2)\n"
    "    csrr t3, mepc\n      sd t3, 48(t2)\n"
    "    csrr t3, mtval\n     sd t3, 80(t2)\n"
    "1:  addi t1, t1, 1\n"
    "    sd t1, 0(t0)\n"
    "    ld t1, 8(t0)\n"                    // resume_pc
    "    beqz t1, 2f\n"
    "    csrw mepc, t1\n"
    "    sd zero, 8(t0)\n"
    "2:  li t1, 0x1800\n"
    "    csrs mstatus, t1\n"                // MPP = M
    "    ld t1, 112(t0)\n"
    "    ld t2, 120(t0)\n"
    "    ld t3, 128(t0)\n"
    "    csrr t0, mscratch\n"
    "    mret\n"
);
extern void ded_trap(void);
_Static_assert(SET_LOG * LINE_BYTES == 512, "ded_trap addresses the log as arena + 512");
_Static_assert(__builtin_offsetof(struct trap_log, saved) == 112, "ded_trap's save slots");

static volatile uint64_t sink;

static void arm(uint8_t units) {
    FI_CONTROL = units;
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
}

static char get_byte(void) {
    while (!(*(volatile uint8_t *)(UART_BASE + 5) & 1))
        ;
    return (char)*(volatile uint8_t *)UART_BASE;
}

static void read_counters(uint32_t *c) {
    for (int i = 0; i < COUNTERS; i++)
        c[i] = FAULT_COUNTER[i] & 0xffff;
}

static void clear_traps(void) {
    TRAPS->count = 0;
    TRAPS->resume_pc = 0;
}

static void flush_dcache(void) {
    __asm__ volatile ("fence.i" ::: "memory");
}

// Loads from the lines 1..CONFLICTS ways past `line`: enough misses in its
// set to evict whatever the set held.
static void evict_set_of(volatile uint64_t *line) {
    for (int k = 1; k <= CONFLICTS; k++)
        sink = *(volatile uint64_t *)((uintptr_t)line + k * WAY_BYTES);
}

// Waits for the PS's 'x' and disarms.  It opens each trial's asm block, which
// writes nothing to the D$ until the trial's own first store, so no other
// write can take the planted flips.
#define START_AFTER_PULSE                                                     \
    "1:  lbu t0, 5(%[uart])\n"                                                \
    "    andi t0, t0, 1\n"                                                    \
    "    beqz t0, 1b\n"                                                       \
    "    lbu t0, 0(%[uart])\n"                                                \
    "    sb zero, 0(%[fi])\n"                                                 \
    "    fence iorw, iorw\n"

static void announce_pulse(void) {
    while (get_byte() != 'g')
        ;
    arm(CACHE_DED_UNIT);
    uart_puts("DED GO\n");
}

static int report(int trial, int ok, const uint32_t *before, const uint32_t *after) {
    uart_puts("DED T");
    uart_putu64((uint64_t)trial);
    uart_puts(ok ? " PASS traps " : " FAIL traps ");
    uart_putu64(TRAPS->count);
    uart_puts(" d");
    for (int i = 0; i < COUNTERS; i++) {
        uart_puts(" ");
        uart_putu64(after[i] - before[i]);
    }
    uart_puts("\n");
    return ok;
}

static int only_counter_moved(const uint32_t *before, const uint32_t *after, int counter, uint32_t by) {
    for (int i = 0; i < COUNTERS; i++) {
        uint32_t want = i == counter ? by : 0;
        if (after[i] - before[i] != want)
            return 0;
    }
    return 1;
}

static int no_counter_moved(const uint32_t *before, const uint32_t *after) {
    for (int i = 0; i < COUNTERS; i++)
        if (after[i] != before[i])
            return 0;
    return 1;
}

static int trap_is(int n, uint64_t epc, uint64_t tval) {
    return TRAPS->cause[n] == CAUSE_CACHE_DED && (epc == 0 || TRAPS->epc[n] == epc) && TRAPS->tval[n] == tval;
}

static int trial_dirty_data(void) {
    uint32_t before[COUNTERS];
    uint32_t after[COUNTERS];
    const uint64_t a0 = 0xA0A0A0A0A0A0A0A0ULL;
    const uint64_t a1 = 0xA1A1A1A1A1A1A1A1ULL;
    const uint64_t a_new = 0xA2A2A2A2A2A2A2A2ULL;
    const uint64_t c0 = 0xC0C0C0C0C0C0C0C0ULL;
    uint64_t load_pc;
    uint64_t got_a;
    uint64_t got_c;
    int ok = 1;

    LINE_C[0] = c0;
    evict_set_of(LINE_C);
    LINE_A[0] = a0;
    LINE_A[1] = a1;
    clear_traps();
    read_counters(before);
    announce_pulse();
    __asm__ volatile (
        "    la t0, 3f\n"
        "    sd t0, 8(%[log])\n"            // resume after the load of A; written before the pulse
        START_AFTER_PULSE
        "    sd %[a_new], 0(%[a])\n"        // store hit, dirty A: the data flips
        "    ld t0, 0(%[c])\n"              // load miss, clean C: the tag flips
        "2:  ld t0, 0(%[a])\n"              // traps
        "3:  la %[pc], 2b\n"
        : [pc] "=&r"(load_pc)
        : [uart] "r"(UART_BASE), [fi] "r"(&FI_CONTROL), [log] "r"(TRAPS),
          [a] "r"(LINE_A), [c] "r"(LINE_C), [a_new] "r"(a_new)
        : "t0", "memory");
    if (TRAPS->count != 1 || !trap_is(0, load_pc, (uint64_t)LINE_A))
        ok = 0;
    flush_dcache();
    if (TRAPS->count != 2 || !trap_is(1, 0, (uint64_t)LINE_A))
        ok = 0;
    LINE_A[0] = a_new;
    LINE_A[1] = a1;
    got_a = LINE_A[0] ^ LINE_A[1];
    got_c = LINE_C[0];
    read_counters(after);
    if (got_a != (a_new ^ a1) || got_c != c0)
        ok = 0;
    if (!only_counter_moved(before, after, DCACHE_DED, 2))
        ok = 0;
    return report(1, ok, before, after);
}

static int trial_dirty_tag(void) {
    uint32_t before[COUNTERS];
    uint32_t after[COUNTERS];
    const uint64_t b0 = 0xB0B0B0B0B0B0B0B0ULL;
    const uint64_t b1 = 0xB1B1B1B1B1B1B1B1ULL;
    uint64_t load_pc;
    int ok = 1;

    LINE_B[0] = b0;
    LINE_B[1] = b1;
    evict_set_of(LINE_B);
    clear_traps();
    read_counters(before);
    announce_pulse();
    __asm__ volatile (
        "    la t0, 3f\n"
        "    sd t0, 8(%[log])\n"            // written before the pulse
        START_AFTER_PULSE
        "    sd %[b0], 0(%[b])\n"           // store miss: the fill takes tag and data flips
        "2:  ld t0, 0(%[b])\n"              // traps: a dirty line lost its tag
        "3:  la %[pc], 2b\n"
        : [pc] "=&r"(load_pc)
        : [uart] "r"(UART_BASE), [fi] "r"(&FI_CONTROL), [log] "r"(TRAPS),
          [b] "r"(LINE_B), [b0] "r"(b0)
        : "t0", "memory");
    if (TRAPS->count != 1 || !trap_is(0, load_pc, (uint64_t)LINE_B))
        ok = 0;
    LINE_B[0] = b0;
    LINE_B[1] = b1;
    if ((LINE_B[0] ^ LINE_B[1]) != (b0 ^ b1))
        ok = 0;
    read_counters(after);
    if (!only_counter_moved(before, after, DCACHE_DED, 1))
        ok = 0;
    return report(2, ok, before, after);
}

static uint64_t __attribute__((noinline)) icache_work(uint64_t x) {
    return (x ^ 0x5555) * 3 + 7;
}

static void __attribute__((noinline)) wait_for_release(void) {
    __asm__ volatile (START_AFTER_PULSE : : [uart] "r"(UART_BASE), [fi] "r"(&FI_CONTROL) : "t0", "memory");
}

static int trial_icache(void) {
    uint32_t before[COUNTERS];
    uint32_t after[COUNTERS];
    uint64_t result[2];
    int ok = 1;

    clear_traps();
    read_counters(before);
    announce_pulse();
    for (int pass = 0; pass < 2; pass++) {
        wait_for_release();
        result[pass] = icache_work(41);
    }
    read_counters(after);
    if (result[0] != result[1] || result[0] != ((41 ^ 0x5555) * 3 + 7) || TRAPS->count != 0)
        ok = 0;
    if (!no_counter_moved(before, after))
        ok = 0;
    return report(3, ok, before, after);
}

int main(void) {
    int failures = 0;
    *(volatile uint8_t *)(UART_BASE + 2) = 0x07;   // FIFOs on: T3's two 'x' arrive back to back
    __asm__ volatile ("csrw mtvec, %0" : : "r"((uint64_t)ded_trap));
    uart_puts("DED READY\n");
    failures += !trial_dirty_data();
    failures += !trial_dirty_tag();
    failures += !trial_icache();
    arm(0);
    uart_puts("DED DONE\n");
    sim_exit((uint64_t)failures);
}
