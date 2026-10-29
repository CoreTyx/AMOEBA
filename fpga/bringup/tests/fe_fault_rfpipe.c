// fe_fault_rfpipe.c -- register-file ECC and pipeline-register ECC armed
// together (docs/impl_plan_fpga_rtl_freeze.md s5.4.2).
//
// Both injectors fire at fault-counter phase 0x1FF, and the pipeline mask also
// flips RD1E/RD2E, the registers that carry register-file operands into
// Execute.  Armed together, one operand can take both flips in the same cycle:
// a double error (DED, counters 1/3), or two flips of the same bit that cancel.
// This runs the same kernel with FI_CONTROL = 0x10, 0x20 and 0x30 and prints
// counters 0-3 for each:
//   RFPIPE mask <m> <result ok|WRONG> d <c0> <c1> <c2> <c3>
// Exit code: the number of rounds whose result was wrong or whose DED counters
// (1, 3) moved.
#include "../../../testcode/isa_level_testing/test_utils.h"

#define FI_CONTROL     (*(volatile uint8_t *)0x1007000bUL)
#define FAULT_COUNTER  ((volatile uint32_t *)0x10080000UL)

static volatile uint64_t seed = 0x0123456789abcdefULL;
static volatile uint64_t sink;

static void arm(uint8_t units) {
    FI_CONTROL = units;
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
}

static uint64_t __attribute__((noinline)) kernel(int n) {
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

static int round_with(uint8_t mask, uint64_t golden) {
    uint32_t before[4];
    uint32_t after[4];
    uint64_t got;
    for (int i = 0; i < 4; i++)
        before[i] = FAULT_COUNTER[i] & 0xffff;
    arm(mask);
    got = kernel(12000);
    arm(0);
    for (int i = 0; i < 4; i++)
        after[i] = FAULT_COUNTER[i] & 0xffff;
    sink = got;
    uart_puts("RFPIPE mask ");
    uart_puthex64(mask);
    uart_puts(got == golden ? " result ok d" : " result WRONG d");
    for (int i = 0; i < 4; i++) {
        uart_puts(" ");
        uart_putu64(after[i] - before[i]);
    }
    uart_puts("\n");
    return got == golden && after[1] == before[1] && after[3] == before[3];
}

int main(void) {
    int failures = 0;
    uint64_t golden;
    arm(0);
    golden = kernel(12000);
    failures += !round_with(0x10, golden);
    failures += !round_with(0x20, golden);
    failures += !round_with(0x30, golden);
    uart_puts("RFPIPE DONE\n");
    sim_exit((uint64_t)failures);
}
