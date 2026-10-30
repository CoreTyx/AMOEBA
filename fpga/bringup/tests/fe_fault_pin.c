// fe_fault_pin.c -- does each fault-tolerance unit tolerate the faults the
// fault_inject pin lets through? (docs/impl_plan_fpga_rtl_freeze.md, CTRL-10)
//
// For FI_CONTROL bits 0..6, one at a time: run that unit's kernel disarmed
// (the golden result), arm the unit, print "FI GO", run the kernel again,
// disarm.  While armed, the FPGA holds fault_inject in a pattern (a PL trigger
// on "FI GO" starts it; in the pin bench the pin is simply high).
//
// Each round passes when the result equals the golden one, the unit's
// detect counter rose, its unresolved/uncorrectable counters did not, and no
// other unit's counter moved.  Built with FI_PIN_PATTERNED (fe_fault_burst.c)
// the detect counter may stay still: the pin then lets through only what the
// PS chose, and the PS bounds the counts itself.  The pipeline mask also flips RD1E/RD2E, whose
// checks are the register-file counters, so pipeline ECC owns counters 0-3.  One line per round for the PS:
//   FI unit <u> <PASS|FAIL> d <18 counter deltas>
// Exit code: the number of failed rounds.  Bit 7 (cache DED) traps on a dirty
// line and is CTRL-21's, not this program's.
#include "../../../testcode/isa_level_testing/test_utils.h"

#define FI_CONTROL     (*(volatile uint8_t *)0x1007000bUL)
#define FAULT_COUNTER  ((volatile uint32_t *)0x10080000UL)
#define COUNTERS       18
#define UNITS          7

#ifdef FI_PIN_PATTERNED
#define DETECT_REQUIRED 0
#else
#define DETECT_REQUIRED 1
#endif

// faultcount_apb.sv: 0/1 RF SEC/DED, 2/3 pipe SEC/DED, 4/5 I$ SEC/DED,
// 6/7 D$ SEC/DED, 8/9 ALU, 10/11 CMP, 12/13 MUL, 14/15 DIV (detect,
// unresolved), 16/17 privilege-mode TMR.
static const int detect_counter[UNITS] = {8, 10, 12, 14, 0, 2, 6};
// Counters each unit may move: its detect counter, plus these.
static const uint32_t unit_counters[UNITS] = {
    1u << 9, 1u << 11, 1u << 13, 1u << 15, 1u << 1,
    (1u << 0) | (1u << 1) | (1u << 3), (1u << 4) | (1u << 5) | (1u << 7),
};
// Counters that must not move however the unit fares: unresolved and uncorrectable.
static const uint32_t must_stay_zero = (1u << 1) | (1u << 3) | (1u << 5) | (1u << 7) |
                                       (1u << 9) | (1u << 11) | (1u << 13) | (1u << 15) | (1u << 17);
static const char *unit_name[UNITS] = {"alu", "cmp", "mul", "div", "rf_ecc", "pipe_ecc", "cache_sec"};

static volatile uint64_t seed = 0x0123456789abcdefULL;
static volatile uint64_t sink;
static uint64_t sweep[4096];

static void arm(uint8_t units) {
    FI_CONTROL = units;
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
}

static void read_counters(uint32_t *c) {
    for (int i = 0; i < COUNTERS; i++)
        c[i] = FAULT_COUNTER[i] & 0xffff;
}

static uint64_t __attribute__((noinline)) kernel_alu(int n) {
    uint64_t x = seed;
    uint64_t y = ~seed;
    for (int i = 0; i < n; i++) {
        x = (x ^ (y << 7)) + (y >> 3);
        y = y - (x >> 11);
        x = x | (y & 0xff00);
        y = (y << 13) ^ (x >> 5) ^ (uint64_t)i;
        __asm__ volatile ("" : "+r"(x), "+r"(y));
    }
    return x ^ y;
}

static uint64_t __attribute__((noinline)) kernel_cmp(int n) {
    uint64_t a = seed;
    uint64_t b = seed * 3 + 1;
    uint64_t count = 0;
    for (int i = 0; i < n; i++) {
        a = a * 6364136223846793005ULL + 1442695040888963407ULL;
        b = b * 2862933555777941757ULL + 3037000493ULL;
        __asm__ volatile ("" : "+r"(a), "+r"(b));
        if ((int64_t)a < (int64_t)b)
            count += 1;
        if (a < b)
            count += 3;
        if ((a >> 60) == (b >> 60))
            count += 7;
    }
    return count ^ a;
}

static uint64_t __attribute__((noinline)) kernel_mul(int n) {
    uint64_t x = seed;
    uint64_t acc = 0;
    for (int i = 0; i < n; i++) {
        unsigned __int128 p = (unsigned __int128)x * 0x9E3779B97F4A7C15ULL;
        x = (uint64_t)p + (uint64_t)i;
        acc ^= (uint64_t)(p >> 64);
        __asm__ volatile ("" : "+r"(x), "+r"(acc));
    }
    return x ^ acc;
}

// The divider is checked only in the cycle a divide completes, and its
// injector fires in one cycle of every 512, so a fault is seen only when the
// two coincide.  A strictly periodic loop can keep them apart forever; the
// spin (from the LCG's well-mixed high bits; its low bits repeat every 16
// steps) moves the completion through the phases, and the odd one-cycle nop
// breaks the parity: the spin costs an even number of cycles, and with it alone
// every divide completed on an odd counter value while the injector's phase,
// 0x15E, is even.
static uint64_t __attribute__((noinline)) kernel_div(int n) {
    uint64_t x = seed | (1ULL << 63);
    uint64_t acc = 0;
    for (int i = 0; i < n; i++) {
        uint64_t d = (x >> 40) | 3;
        acc += x / d + x % (d >> 7 | 1);
        x = x * 2862933555777941757ULL + 3037000493ULL;
        for (uint64_t spin = x >> 59; spin != 0; spin--)
            __asm__ volatile ("" : "+r"(spin));
        if (x & (1ULL << 58))
            __asm__ volatile ("nop");
        __asm__ volatile ("" : "+r"(x), "+r"(acc));
    }
    return acc;
}

static uint64_t __attribute__((noinline)) kernel_cache(int passes) {
    uint64_t x = seed;
    uint64_t sum = 0;
    for (int p = 0; p < passes; p++) {
        for (int i = 0; i < 4096; i++) {
            sweep[i] = x ^ (uint64_t)(i * p);
            x = (x << 1) | (x >> 63);
        }
        for (int i = 0; i < 4096; i++)
            sum += sweep[(i * 7) & 4095];
        __asm__ volatile ("" : "+r"(x), "+r"(sum) :: "memory");
    }
    return sum;
}

// fe_fault_site.c takes the kernels above and runs its own rounds.
#ifndef FI_KERNELS_ONLY
static uint64_t run_kernel(int unit) {
    switch (unit) {
        case 0:  return kernel_alu(12000);
        case 1:  return kernel_cmp(6000);
        case 2:  return kernel_mul(8000);
        case 3:  return kernel_div(6000);
        case 4:  return kernel_alu(12000);
        case 5:  return kernel_alu(12000);
        default: return kernel_cache(4);
    }
}

static int round_for(int unit) {
    uint32_t before[COUNTERS];
    uint32_t after[COUNTERS];
    uint32_t delta[COUNTERS];
    uint64_t golden;
    uint64_t got;
    int ok = 1;

    arm(0);
    golden = run_kernel(unit);
    read_counters(before);
    arm((uint8_t)(1u << unit));
    uart_puts("FI GO ");
    uart_puts(unit_name[unit]);
    uart_puts("\n");
    got = run_kernel(unit);
    arm(0);
    read_counters(after);
    sink = got;

    for (int i = 0; i < COUNTERS; i++)
        delta[i] = after[i] - before[i];
    if (got != golden)
        ok = 0;
    if (DETECT_REQUIRED && delta[detect_counter[unit]] == 0)
        ok = 0;
    for (int i = 0; i < COUNTERS; i++) {
        int mine = i == detect_counter[unit] || ((unit_counters[unit] >> i) & 1);
        if (delta[i] != 0 && (!mine || ((must_stay_zero >> i) & 1)))
            ok = 0;
    }

    uart_puts("FI unit ");
    uart_putu64((uint64_t)unit);
    uart_puts(ok ? " PASS d" : " FAIL d");
    for (int i = 0; i < COUNTERS; i++) {
        uart_puts(" ");
        uart_putu64(delta[i]);
    }
    uart_puts(got == golden ? " result ok\n" : " result WRONG\n");
    return ok;
}

int main(void) {
    int failures = 0;
    uart_puts("FI READY\n");
    for (int unit = 0; unit < UNITS; unit++)
        failures += !round_for(unit);
    arm(0);
    uart_puts("FI ALL DONE\n");
    sim_exit((uint64_t)failures);
}
#endif
