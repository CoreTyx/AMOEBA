// FI_CONTROL byte reads/writes through the core's normal load/store path.
// Run with the default simulator (fault_inject master pin low).
#include "test_utils.h"

#define FI_CONTROL (*(volatile uint8_t *)0x1007000bUL)
#define FI_UNIT_MASK 0x3fu

static void write_mask(uint8_t value) {
    FI_CONTROL = value;
    __asm__ volatile ("fence iorw, iorw" ::: "memory");
}

int main(void) {
    test_begin("FI_CONTROL");
    check("reset enables all six units", FI_CONTROL, FI_UNIT_MASK);

    write_mask(0);
    check("disable all units", FI_CONTROL, 0);
    for (unsigned bit = 0; bit < 6; ++bit) {
        unsigned mask = 1u << bit;
        write_mask(mask);
        check("enable one unit", FI_CONTROL, mask);
        write_mask(FI_UNIT_MASK ^ mask);
        check("disable one unit", FI_CONTROL, FI_UNIT_MASK ^ mask);
    }

    // Sweep every input byte, including reserved bits 7:6. Repeated reads
    // must preserve the mask even though the external master pin is low.
    int patterns_ok = 1;
    for (unsigned value = 0; value < 256; ++value) {
        write_mask(value);
        unsigned first = FI_CONTROL;
        unsigned second = FI_CONTROL;
        if (first != (value & FI_UNIT_MASK) || second != first) {
            check("pattern readback", first, value & FI_UNIT_MASK);
            check("read preserves mask", second, first);
            patterns_ok = 0;
            break;
        }
    }
    check_bool("all 256 byte patterns and repeated reads", patterns_ok);

    write_mask(0);
    check("disable after rewriting", FI_CONTROL, 0);
    write_mask(FI_UNIT_MASK);
    check("restore reset mask", FI_CONTROL, FI_UNIT_MASK);
    print_summary();
    test_finish();
}
