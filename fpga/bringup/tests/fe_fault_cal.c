// fe_fault_cal.c -- the chip side of fault_inject phase calibration
// (docs/impl_plan_fpga_rtl_freeze.md CTRL-12b, the calibrate_phase command).
//
// The PS sweeps a one-cycle pin pulse over the 512 phases of the chip's fault
// counter.  Each round it sends a unit digit; the program arms that unit,
// prints "CAL GO" (a PL trigger on it starts the pulse pattern) and runs a
// kernel until the PS sends 'x', then prints
//   CAL d <detect counter delta> f <other counters' delta>
// 'q' ends the program, exit code 0.
#include <stdint.h>
#include "../../../testcode/isa_level_testing/test_utils.h"

#define FI_CONTROL     (*(volatile uint8_t *)0x1007000bUL)
#define FAULT_COUNTER  ((volatile uint32_t *)0x10080000UL)
#define UART           ((volatile uint8_t *)0x10000000UL)
#define LSR_DR         0x01
#define COUNTERS       18
#define UNITS          7

// As fe_fault_pin.c: each unit's detect counter, and the counters it may also move.
static const int detect_counter[UNITS] = {8, 10, 12, 14, 0, 2, 6};
static const uint32_t unit_counters[UNITS] = {
    1u << 9, 1u << 11, 1u << 13, 1u << 15, 1u << 1,
    (1u << 0) | (1u << 1) | (1u << 3), (1u << 4) | (1u << 5) | (1u << 7),
};

static volatile uint64_t seed = 0x0123456789abcdefULL;
static volatile uint64_t sink;

static void arm(uint8_t units) {
    FI_CONTROL = units;
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
}

static int byte_waiting(void) {
    return UART[5] & LSR_DR;
}

static char get_byte(void) {
    while (!byte_waiting())
        ;
    return (char)UART[0];
}

static void read_counters(uint32_t *c) {
    for (int i = 0; i < COUNTERS; i++)
        c[i] = FAULT_COUNTER[i] & 0xffff;
}

// Single-cycle operations only.  A register-file fault counts only if the read
// it corrupts enters Execute that cycle, and a multiply or divide would stall
// the pipeline through most of the sweep's one-cycle pulses.
static uint64_t __attribute__((noinline)) kernel_until_byte(void) {
    uint64_t x = seed;
    uint64_t y = ~seed;
    uint64_t count = 0;
    while (!byte_waiting()) {
        x = (x ^ (y << 7)) + (y >> 3);
        y = y - (x >> 11);
        if ((int64_t)x < (int64_t)y)
            count += 1;
        __asm__ volatile ("" : "+r"(x), "+r"(y), "+r"(count));
    }
    return x ^ y ^ count;
}

static void round_for(int unit) {
    uint32_t before[COUNTERS];
    uint32_t after[COUNTERS];
    uint32_t detected;
    uint32_t others = 0;

    read_counters(before);
    arm((uint8_t)(1u << unit));
    uart_puts("CAL GO\n");
    sink = kernel_until_byte();
    get_byte();
    arm(0);
    read_counters(after);

    detected = after[detect_counter[unit]] - before[detect_counter[unit]];
    for (int i = 0; i < COUNTERS; i++) {
        int mine = i == detect_counter[unit] || ((unit_counters[unit] >> i) & 1);
        if (!mine)
            others += after[i] - before[i];
    }
    uart_puts("CAL d ");
    uart_putu64(detected);
    uart_puts(" f ");
    uart_putu64(others);
    uart_puts("\n");
}

int main(void) {
    uart_puts("CAL READY\n");
    for (;;) {
        char c = get_byte();
        if (c == 'q')
            break;
        if (c >= '0' && c < '0' + UNITS)
            round_for(c - '0');
    }
    uart_puts("CAL DONE\n");
    sim_exit(0);
}
