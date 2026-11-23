/*
 * upriv -- U-mode privilege semantics, seen through Linux.
 *   1. every S/M CSR, xRET, sfence.vma, H and F/D instruction executed from U
 *      raises SIGILL (ILL_ILLOPC) at exactly that instruction; ebreak and
 *      c.ebreak raise SIGTRAP; wfi either returns or raises SIGILL
 *   2. loads, stores and fetches at kernel and non-canonical Sv39 addresses
 *      raise SIGSEGV with si_addr the full 64-bit address
 *   3. permission faults: fetch from a non-X page, load from PROT_NONE, store
 *      to text, AMO and SC to read-only pages, LR from PROT_NONE -- SIGSEGV
 *      SEGV_ACCERR at the exact address; AMO to an unmapped page SEGV_MAPERR
 *   4. ecall: an unknown number returns -ENOSYS; a syscall preserves every
 *      register but a0
 */
#include "ustress.h"
#define NAME "upriv"

struct insn { const char *what; unsigned word; };

static const struct insn privileged[] = {
    { "csrr sstatus",    0x10002573 }, { "csrw sstatus",   0x10001073 },
    { "csrr x0 sstatus", 0x10002073 }, { "csrr sie",       0x10402573 },
    { "csrr stvec",      0x10502573 }, { "csrr scounteren", 0x10602573 },
    { "csrr senvcfg",    0x10a02573 }, { "csrr sscratch",  0x14002573 },
    { "csrr sepc",       0x14102573 }, { "csrr scause",    0x14202573 },
    { "csrr stval",      0x14302573 }, { "csrr sip",       0x14402573 },
    { "csrr satp",       0x18002573 }, { "csrw satp",      0x18001073 },
    { "csrr mstatus",    0x30002573 }, { "csrr misa",      0x30102573 },
    { "csrr mtvec",      0x30502573 }, { "csrr mepc",      0x34102573 },
    { "csrr mcause",     0x34202573 }, { "csrr pmpcfg0",   0x3a002573 },
    { "csrr pmpaddr0",   0x3b002573 }, { "csrr mcycle",    0xb0002573 },
    { "csrr mvendorid",  0xf1102573 }, { "csrr mhartid",   0xf1402573 },
    { "csrr 0x7c0",      0x7c002573 }, { "sret",           0x10200073 },
    { "mret",            0x30200073 }, { "sfence.vma",     0x12000073 },
    { "hfence.vvma",     0x22000073 }, { "csrr fcsr",      0x00302573 },
    { "fadd.d",          0x02007053 }, { "fld",            0x00013007 },
    { "fsd",             0x00013027 }, { "all ones",       0xffffffff },
};

#define RET   0x00008067u    /* jalr x0, 0(ra) */
#define C_RET 0x8082u        /* c.jr ra */

static unsigned *code_page;

static void place(unsigned word)
{
    code_page[0] = word;
    code_page[1] = RET;
    sys_flush_icache(code_page, code_page + 2);
}

static long run_code(long arg) { return ((long (*)(long))code_page)(arg); }
static long load_at(long a)    { return *(volatile long *)a; }
static long store_at(long a)   { *(volatile long *)a = 0x5a; return 0; }
static long fetch_at(long a)   { return ((long (*)(long))a)(0); }
static long amo_at(long a)
{
    long old;
    __asm__ volatile ("amoadd.d %0, %1, (%2)" : "=r"(old) : "r"(1L), "r"(a) : "memory");
    return old;
}
static long lr_at(long a)
{
    long v;
    __asm__ volatile ("lr.d %0, (%1)" : "=r"(v) : "r"(a) : "memory");
    return v;
}
/* LR succeeds on a readable page; the SC that follows would succeed, so it
 * must take the store fault rather than quietly fail. */
static long lr_sc_at(long a)
{
    long v, fail;
    __asm__ volatile ("lr.d %0, (%2)\n sc.d %1, %0, (%2)" : "=&r"(v), "=&r"(fail) : "r"(a) : "memory");
    return fail;
}

static long ecall_unknown(void)
{
    register long a0 __asm__("a0") = 0;
    register long a7 __asm__("a7") = 9999;
    __asm__ volatile ("ecall" : "+r"(a0) : "r"(a7) : "memory");
    return a0;
}

/* Sets every register a syscall may not touch to a pattern, makes getpid,
 * and returns the number of the first register that changed (0: none). */
extern long u_ecall_keeps_regs(void);
__asm__ (
".text\n.globl u_ecall_keeps_regs\nu_ecall_keeps_regs:\n"
"  addi sp, sp, -128\n"
"  sd ra, 0(sp)\n  sd s0, 8(sp)\n  sd s1, 16(sp)\n  sd s2, 24(sp)\n  sd s3, 32(sp)\n  sd s4, 40(sp)\n"
"  sd s5, 48(sp)\n  sd s6, 56(sp)\n  sd s7, 64(sp)\n  sd s8, 72(sp)\n  sd s9, 80(sp)\n  sd s10, 88(sp)\n"
"  sd s11, 96(sp)\n  sd gp, 104(sp)\n  sd tp, 112(sp)\n"
"  li x1, 0x6b010101\n  li x3, 0x6b030303\n  li x4, 0x6b040404\n"
"  li x5, 0x6b050505\n  li x6, 0x6b060606\n  li x7, 0x6b070707\n  li x8, 0x6b080808\n"
"  li x9, 0x6b090909\n  li x11, 0x6b0b0b0b\n  li x12, 0x6b0c0c0c\n  li x13, 0x6b0d0d0d\n"
"  li x14, 0x6b0e0e0e\n  li x15, 0x6b0f0f0f\n  li x16, 0x6b101010\n  li x18, 0x6b121212\n"
"  li x19, 0x6b131313\n  li x20, 0x6b141414\n  li x21, 0x6b151515\n  li x22, 0x6b161616\n"
"  li x23, 0x6b171717\n  li x24, 0x6b181818\n  li x25, 0x6b191919\n  li x26, 0x6b1a1a1a\n"
"  li x27, 0x6b1b1b1b\n  li x28, 0x6b1c1c1c\n  li x29, 0x6b1d1d1d\n  li x30, 0x6b1e1e1e\n"
"  li x31, 0x6b1f1f1f\n"
"  li a7, 172\n  ecall\n"
"  li a0, 0\n"
"  li a7, 0x6b010101\n  li a0, 1\n  bne x1, a7, 9f\n"
"  li a7, 0x6b030303\n  li a0, 3\n  bne x3, a7, 9f\n"
"  li a7, 0x6b040404\n  li a0, 4\n  bne x4, a7, 9f\n"
"  li a7, 0x6b050505\n  li a0, 5\n  bne x5, a7, 9f\n"
"  li a7, 0x6b060606\n  li a0, 6\n  bne x6, a7, 9f\n"
"  li a7, 0x6b070707\n  li a0, 7\n  bne x7, a7, 9f\n"
"  li a7, 0x6b080808\n  li a0, 8\n  bne x8, a7, 9f\n"
"  li a7, 0x6b090909\n  li a0, 9\n  bne x9, a7, 9f\n"
"  li a7, 0x6b0b0b0b\n  li a0, 11\n  bne x11, a7, 9f\n"
"  li a7, 0x6b0c0c0c\n  li a0, 12\n  bne x12, a7, 9f\n"
"  li a7, 0x6b0d0d0d\n  li a0, 13\n  bne x13, a7, 9f\n"
"  li a7, 0x6b0e0e0e\n  li a0, 14\n  bne x14, a7, 9f\n"
"  li a7, 0x6b0f0f0f\n  li a0, 15\n  bne x15, a7, 9f\n"
"  li a7, 0x6b101010\n  li a0, 16\n  bne x16, a7, 9f\n"
"  li a7, 0x6b121212\n  li a0, 18\n  bne x18, a7, 9f\n"
"  li a7, 0x6b131313\n  li a0, 19\n  bne x19, a7, 9f\n"
"  li a7, 0x6b141414\n  li a0, 20\n  bne x20, a7, 9f\n"
"  li a7, 0x6b151515\n  li a0, 21\n  bne x21, a7, 9f\n"
"  li a7, 0x6b161616\n  li a0, 22\n  bne x22, a7, 9f\n"
"  li a7, 0x6b171717\n  li a0, 23\n  bne x23, a7, 9f\n"
"  li a7, 0x6b181818\n  li a0, 24\n  bne x24, a7, 9f\n"
"  li a7, 0x6b191919\n  li a0, 25\n  bne x25, a7, 9f\n"
"  li a7, 0x6b1a1a1a\n  li a0, 26\n  bne x26, a7, 9f\n"
"  li a7, 0x6b1b1b1b\n  li a0, 27\n  bne x27, a7, 9f\n"
"  li a7, 0x6b1c1c1c\n  li a0, 28\n  bne x28, a7, 9f\n"
"  li a7, 0x6b1d1d1d\n  li a0, 29\n  bne x29, a7, 9f\n"
"  li a7, 0x6b1e1e1e\n  li a0, 30\n  bne x30, a7, 9f\n"
"  li a7, 0x6b1f1f1f\n  li a0, 31\n  bne x31, a7, 9f\n"
"  li a0, 0\n"
"9:\n"
"  ld ra, 0(sp)\n  ld s0, 8(sp)\n  ld s1, 16(sp)\n  ld s2, 24(sp)\n  ld s3, 32(sp)\n  ld s4, 40(sp)\n"
"  ld s5, 48(sp)\n  ld s6, 56(sp)\n  ld s7, 64(sp)\n  ld s8, 72(sp)\n  ld s9, 80(sp)\n  ld s10, 88(sp)\n"
"  ld s11, 96(sp)\n  ld gp, 104(sp)\n  ld tp, 112(sp)\n"
"  addi sp, sp, 128\n  ret\n"
);

/* Sv39: user space is the low 256 GiB; bits 63..39 must copy bit 38. */
static const unsigned long kernel_or_noncanonical[] = {
    0xffffffff80000000UL,   /* kernel image */
    0xffffffd800000000UL,   /* linear map */
    0xffffffc000000000UL,   /* lowest canonical upper-half address */
    0x0000004000000000UL,   /* bit 38 set, upper bits clear */
    0x0000008000000000UL,   /* bit 39 only */
    0x7fffffffff000000UL,   /* bit 63 clear, bit 38 set */
    0x8000000000000000UL,   /* bit 63 only */
    0xffffffbffffff000UL,   /* upper bits set, bit 38 clear */
    0x0000003ffffff000UL,   /* last user page, unmapped */
};

int main(void)
{
    unsigned long sum = 0;
    u_probe_install();
    code_page = u_map(U_PAGE, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE);
    if (!code_page) U_FAIL(NAME, "mmap RWX");

    for (unsigned i = 0; i < sizeof privileged / sizeof privileged[0]; i++) {
        place(privileged[i].word);
        if (u_probe(run_code, 0) == 0) {
            out_str("upriv: executed from U: "); out_str(privileged[i].what); out_str("\n");
            U_FAIL(NAME, "privileged instruction executed from U");
        }
        if (!u_faulted(SIGILL, ILL_ILLOPC, code_page)) {
            out_str("upriv: wrong signal for "); out_str(privileged[i].what); out_str("\n");
            U_FAIL(NAME, "SIGILL info");
        }
        sum = u_mix(sum + i);
    }

    place(0x00100073);                                   /* ebreak */
    if (u_probe(run_code, 0) != SIGTRAP || !u_faulted(SIGTRAP, TRAP_BRKPT, code_page)) U_FAIL(NAME, "ebreak");
    ((unsigned short *)code_page)[0] = 0x9002;           /* c.ebreak */
    ((unsigned short *)code_page)[1] = C_RET;
    sys_flush_icache(code_page, code_page + 1);
    if (u_probe(run_code, 0) != SIGTRAP || !u_faulted(SIGTRAP, TRAP_BRKPT, code_page)) U_FAIL(NAME, "c.ebreak");

    place(0x10500073);                                   /* wfi: may complete, or trap */
    int wfi_sig = u_probe(run_code, 0);
    if (wfi_sig != 0 && !u_faulted(SIGILL, ILL_ILLOPC, code_page)) U_FAIL(NAME, "wfi from U");
    out_str(wfi_sig ? "upriv: wfi from U traps\n" : "upriv: wfi from U returns\n");

    for (unsigned i = 0; i < sizeof kernel_or_noncanonical / sizeof kernel_or_noncanonical[0]; i++) {
        unsigned long a = kernel_or_noncanonical[i];
        if (u_probe(load_at, a) != SIGSEGV || !u_faulted(SIGSEGV, -1, (void *)a)) {
            out_str("upriv: load at "); out_hex(a); out_str("\n");
            U_FAIL(NAME, "load from a kernel or non-canonical address");
        }
        if (u_probe(store_at, a) != SIGSEGV || !u_faulted(SIGSEGV, -1, (void *)a)) {
            out_str("upriv: store at "); out_hex(a); out_str("\n");
            U_FAIL(NAME, "store to a kernel or non-canonical address");
        }
        if (u_probe(fetch_at, a) != SIGSEGV || !u_faulted(SIGSEGV, -1, (void *)a)) {
            out_str("upriv: fetch at "); out_hex(a); out_str("\n");
            U_FAIL(NAME, "fetch from a kernel or non-canonical address");
        }
        sum = u_mix(sum ^ a);
    }

    unsigned *rw = u_map(U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
    long *ro = u_map(U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
    long *none = u_map(U_PAGE, PROT_NONE, MAP_PRIVATE);
    if (!rw || !ro || !none) U_FAIL(NAME, "mmap");
    rw[0] = RET;
    ro[3] = 41;
    if (sys_mprotect(ro, U_PAGE, PROT_READ)) U_FAIL(NAME, "mprotect");

    if (u_probe(fetch_at, (long)rw) != SIGSEGV || !u_faulted(SIGSEGV, SEGV_ACCERR, rw)) U_FAIL(NAME, "fetch from a non-X page");
    if (u_probe(load_at, (long)(none + 5)) != SIGSEGV || !u_faulted(SIGSEGV, SEGV_ACCERR, none + 5)) U_FAIL(NAME, "load from PROT_NONE");
    if (u_probe(store_at, (long)main) != SIGSEGV || !u_faulted(SIGSEGV, SEGV_ACCERR, (void *)main)) U_FAIL(NAME, "store to text");
    if (u_probe(amo_at, (long)(ro + 3)) != SIGSEGV || !u_faulted(SIGSEGV, SEGV_ACCERR, ro + 3)) U_FAIL(NAME, "AMO to a read-only page");
    if (u_probe(amo_at, (long)main) != SIGSEGV || !u_faulted(SIGSEGV, SEGV_ACCERR, (void *)main)) U_FAIL(NAME, "AMO to text");
    if (u_probe(amo_at, 0x2000) != SIGSEGV || !u_faulted(SIGSEGV, SEGV_MAPERR, (void *)0x2000)) U_FAIL(NAME, "AMO to an unmapped page");
    if (u_probe(lr_at, (long)(none + 2)) != SIGSEGV || !u_faulted(SIGSEGV, SEGV_ACCERR, none + 2)) U_FAIL(NAME, "LR from PROT_NONE");
    if (u_probe(lr_sc_at, (long)(ro + 3)) != SIGSEGV || !u_faulted(SIGSEGV, SEGV_ACCERR, ro + 3)) U_FAIL(NAME, "SC to a read-only page");
    if (ro[3] != 41) U_FAIL(NAME, "a faulting AMO or SC changed memory");

    if (ecall_unknown() != -ENOSYS) U_FAIL(NAME, "unknown syscall number");
    for (int i = 0; i < 20; i++) {
        long bad = u_ecall_keeps_regs();
        if (bad) {
            out_str("upriv: register x"); out_dec(bad); out_str(" changed by a syscall\n");
            U_FAIL(NAME, "syscall changed a register");
        }
    }
    return prog_pass(NAME, sum);
}
