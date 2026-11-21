// @stress tier=pr build=no_spike duts=legacy timeout=1000000 xfail=mtvec-mode-warl ecc=no dummy=no pin=no
//
// st_mtvec_mode -- KNOWN RTL DEVIATION (xfail): mtvec/stvec.MODE is WARL and
// this configuration has no vectored interrupts (pkg/config.vh:
// VECTORED_INTERRUPTS_SUPPORTED = 0), so writing MODE = 1 must leave a legal
// value (MODE = 0).  CVW stores MODE = 1 anyway (csrs.sv/csrm.sv
// TVECWriteValM), so software that probes for vectored mode -- riscv-tests
// rv64mi-p-illegal does, and then hangs -- believes it is supported while
// traps still enter at the base.  Linux and OpenSBI always use direct mode,
// so the boot is unaffected; the test tracks the deviation until it is fixed.
#include "../lib/stress.h"

int main(void) {
    st_init();
    uint64_t base = csr_read(mtvec) & ~3UL;
    csr_write(mtvec, base | 1);
    uint64_t m = csr_read(mtvec);
    csr_write(mtvec, base);
    ST_CHECK_EQ("mtvec.MODE=1 not retained without vectored interrupts", m & 3, 0);
    csr_write(stvec, base | 1);
    uint64_t s = csr_read(stvec);
    csr_write(stvec, base);
    ST_CHECK_EQ("stvec.MODE=1 not retained without vectored interrupts", s & 3, 0);
    return st_result();
}
