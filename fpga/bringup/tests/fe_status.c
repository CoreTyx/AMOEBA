// fe_status.c -- holds the link in one condition while the PS measures the
// status pin (docs/impl_plan_fpga_rtl_freeze.md STAT-01, STAT-02).
//
// The PS sends a mode byte and the program acknowledges it, then holds that
// mode until the PS sends 'x':
//   'a'  active: streams through 64 KiB, far more than the D$, so link
//        transactions complete continuously       -> "ST ACTIVE"
//   'q'  quiet: spins in a cached loop that polls only the on-chip UART, so
//        the link sees nothing                      -> "ST QUIET"
// 'd' ends the program, exit code 0.
#include <stdint.h>
#include "../../../testcode/isa_level_testing/test_utils.h"

#define UART    ((volatile uint8_t *)0x10000000UL)
#define LSR_DR  0x01
#define STREAM_WORDS (64 * 1024 / 8)

static volatile uint64_t stream[STREAM_WORDS];
static volatile uint64_t sink;

static int byte_waiting(void) {
    return UART[5] & LSR_DR;
}

static char get_byte(void) {
    while (!byte_waiting())
        ;
    return (char)UART[0];
}

static void hold_active(void) {
    uint64_t sum = 0;
    uint64_t pass = 0;
    while (!byte_waiting()) {
        for (int i = 0; i < STREAM_WORDS && !byte_waiting(); i += 2) {
            stream[i] = pass + (uint64_t)i;
            sum += stream[i + 1];
        }
        pass++;
    }
    sink = sum;
}

static void hold_quiet(void) {
    while (!byte_waiting())
        ;
}

int main(void) {
    UART[2] = 0x07;   // FIFOs on and cleared: the PS sends 'x' and the next mode back to back
    uart_puts("ST READY\n");
    for (;;) {
        char c = get_byte();
        if (c == 'd')
            break;
        if (c == 'a') {
            uart_puts("ST ACTIVE\n");
            hold_active();
            get_byte();
        } else if (c == 'q') {
            uart_puts("ST QUIET\n");
            hold_quiet();
            get_byte();
        }
    }
    uart_puts("ST DONE\n");
    sim_exit(0);
}
