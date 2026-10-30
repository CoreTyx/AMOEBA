// fe_fault_site.c -- is each fault site checked on its own?
// (docs/impl_plan_fpga_rtl_freeze.md CTRL-22, the target_site command)
//
// Each round the PS sends a unit digit (FI_CONTROL bit, as fe_fault_pin.c);
// the program arms that whole unit, prints "SITE GO" (a PL trigger on it starts
// a PHASE pattern that lets through only the events of the site the PS chose)
// and repeats the unit's kernel until the PS sends 'x', then prints
//   SITE d <18 counter deltas> w <kernel results that differed from golden>
// 'q' ends the program, exit code 0.  The cache round also runs straight-line
// code twice the I$'s size, so both caches refill while armed.
#define FI_KERNELS_ONLY
#include "fe_fault_pin.c"

#define UART    ((volatile uint8_t *)0x10000000UL)
#define LSR_DR  0x01

static int byte_waiting(void) {
    return UART[5] & LSR_DR;
}

static char get_byte(void) {
    while (!byte_waiting())
        ;
    return (char)UART[0];
}

static void __attribute__((noinline)) icache_sweep(void) {
    __asm__ volatile (".rept 1024\n .4byte 0x00000013\n .endr");
}

static uint64_t site_kernel(int unit) {
    switch (unit) {
        case 0:  return kernel_alu(1000);
        case 1:  return kernel_cmp(500);
        case 2:  return kernel_mul(1000);
        case 3:  return kernel_div(300);
        case 6:  icache_sweep(); return kernel_cache(1);
        default: return kernel_alu(1000);
    }
}

static void round_for(int unit) {
    uint32_t before[COUNTERS];
    uint32_t after[COUNTERS];
    uint64_t golden;
    uint64_t wrong = 0;

    arm(0);
    golden = site_kernel(unit);
    read_counters(before);
    arm((uint8_t)(1u << unit));
    uart_puts("SITE GO\n");
    while (!byte_waiting()) {
        if (site_kernel(unit) != golden)
            wrong++;
    }
    get_byte();
    arm(0);
    read_counters(after);

    uart_puts("SITE d");
    for (int i = 0; i < COUNTERS; i++) {
        uart_puts(" ");
        uart_putu64(after[i] - before[i]);
    }
    uart_puts(" w ");
    uart_putu64(wrong);
    uart_puts("\n");
}

int main(void) {
    uart_puts("SITE READY\n");
    for (;;) {
        char c = get_byte();
        if (c == 'q')
            break;
        if (c >= '0' && c < '0' + UNITS)
            round_for(c - '0');
    }
    uart_puts("SITE DONE\n");
    sim_exit(0);
}
