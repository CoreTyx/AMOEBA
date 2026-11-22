// @stress tier=pr build=no_spike duts=legacy,forte timeout=1000000 ecc=no dummy=no pin=no
//
// st_mtvec_mode -- mtvec/stvec.MODE is WARL and this configuration has no
// vectored interrupts (pkg/config.vh: VECTORED_INTERRUPTS_SUPPORTED = 0), so
// writing MODE = 1 must leave a legal value (MODE = 0) and must not disturb
// BASE.  Upstream CVW stored MODE = 1 and cleared BASE[5:2] (csrm.sv/csrs.sv
// TVECWriteValM), so software probing for vectored mode -- riscv-tests
// rv64mi-p-illegal does -- believed it was supported and trapped to the wrong
// address.  Regression test for that fix.
#include "../lib/stress.h"

/* Trap-entry probe.  tv_block is 64-byte aligned; its two entry points 32
 * bytes apart each return their own tag in a0 and resume after the ecall.
 * tv_probe(mtvec_value) installs the value, takes an M-mode ecall, restores
 * mtvec and returns the tag of the entry the trap used (MIE is 0 here). */
uint64_t tv_probe(uint64_t tvec);
__asm__(
    ".section .text\n"
    ".option push\n.option norvc\n"
    ".globl tv_probe\n"
    "tv_probe:\n"
    "  csrr t1, mtvec\n"
    "  csrw mtvec, a0\n"
    "  li a0, 0\n"
    "  ecall\n"
    "  csrw mtvec, t1\n"
    "  ret\n"
    ".balign 64\n"
    "tv_block:\n"
    "  li a0, 0xA0\n"              /* BASE & ~0x3f */
    "  j tv_resume\n"
    ".balign 32\n"
    "tv_block_plus32:\n"
    "  li a0, 0xB0\n"              /* BASE as written */
    "tv_resume:\n"
    "  csrr t2, mepc\n"
    "  addi t2, t2, 4\n"
    "  csrw mepc, t2\n"
    "  mret\n"
    ".option pop\n");
extern char tv_block_plus32[];

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

    /* A synchronous exception enters at BASE in either mode.  With MODE=1
     * illegal here, the write's BASE (4-byte aligned, legal in direct mode)
     * should be used as written; CVW applies the vectored-mode 64-byte
     * alignment (TVECWriteValM zeroes BASE[5:2]) and enters 32 bytes early. */
    uint64_t b = (uint64_t)tv_block_plus32;
    ST_CHECK_EQ("control: MODE=0, ecall enters at BASE", tv_probe(b), 0xB0);
    ST_CHECK_EQ("BASE|1 written: ecall still enters at BASE", tv_probe(b | 1), 0xB0);
    return st_result();
}
