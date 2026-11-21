/* Hold/resume workload: dirty cache lines, integer multiply/divide, and CSRs.
 * No timer-dependent output: reference and held runs must have identical I/O.
 */
#include <stdint.h>

static volatile uint64_t data[256];

int main(void) {
    for (unsigned round = 1; round <= 16; ++round) {
        uint64_t csr = 0x1234567800000000ULL | round, got;
        __asm__ volatile ("csrw mscratch, %0\ncsrr %1, mscratch"
                          : "+r"(csr), "=r"(got) : : "memory");
        if (got != csr) return 1;
        __asm__ volatile ("csrw mepc, %0\ncsrr %1, mepc"
                          : "+r"(csr), "=r"(got) : : "memory");
        if (got != (csr & ~1ULL)) return 2;
        for (unsigned i = 0; i < 256; ++i) {
            uint64_t a = ((uint64_t)round << 32) + i * 65537ULL;
            volatile uint64_t b = (i % 31) + 1;
            uint64_t q = a / b, r = a % b;
            if (q * b + r != a || r >= b) return 3;
            data[i] = a ^ csr;
        }
        for (unsigned i = 0; i < 256; ++i) {
            uint64_t a = ((uint64_t)round << 32) + i * 65537ULL;
            if (data[i] != (a ^ csr)) return 4;
        }
    }
    return 0;
}
