/*
 * stress.h -- shared harness for testcode/stress.
 *
 * Header-only on purpose: every stress test is ONE translation unit, so it
 * builds unchanged through bin/generate_memory_file.py (sim/Makefile), the
 * pin bench (hvl/pin/pin.sh) and fi_always.sh, none of which take extra
 * sources.  Include it exactly once, from the test's .c file:
 *
 *     #include "../lib/stress.h"
 *     int main(void) { st_init(); ... return st_result(); }
 *
 * main() runs in M-mode on bin/startup.s's stack and its return value is the
 * tohost exit code (0 = pass).  Programs are built -march=rv64gc but the chip
 * is RV64IMAC: never use float/double (CI lints the .dis for F/D opcodes).
 *
 * What the testbench can see.  Outside the Linux build, top_tb detects tohost
 * and the console by snooping the RETIRED store's address -- a VIRTUAL address.
 * So console output and the exit must come from M-mode (or through an identity
 * mapping).  This library only prints and exits from M; lower modes reach it
 * through ecall (st_ecall_exit / st_ecall_putc).
 *
 * Build switches (CFLAGS_EXTRA, see sim/Makefile):
 *   -DSEED=n   seeds st_rand(); CI passes one per matrix entry.
 *   -DCOSIM    the test runs under Spike lock-step co-simulation, which cannot
 *              model MMIO: all console output compiles to nothing, failures are
 *              reported only through the exit code (0x10000 + __LINE__ of the
 *              first failing check).
 */
#ifndef STRESS_H
#define STRESS_H

#include <stdint.h>
#include <stddef.h>
#include "amoeba_cfg.h"

#ifndef SEED
#define SEED 1
#endif

/* ======================================================================= */
/*  Basics                                                                  */
/* ======================================================================= */
#define ST_PAGE          4096UL
#define ST_MEGAPAGE      (2UL << 20)
#define ST_GIGAPAGE      (1UL << 30)
#define ST_ALIGNED(n)    __attribute__((aligned(n)))
#define ST_NOINLINE      __attribute__((noinline))
#define ST_USED          __attribute__((used))
#define ST_UNUSED        __attribute__((unused))
#define ST_ARRAY_LEN(a)  (sizeof(a) / sizeof((a)[0]))

#define csr_read(csr)  ({ uint64_t __v; __asm__ volatile ("csrr %0, " #csr : "=r"(__v) :: "memory"); __v; })
#define csr_write(csr, val) __asm__ volatile ("csrw " #csr ", %0" :: "r"((uint64_t)(val)) : "memory")
#define csr_set(csr, val)   __asm__ volatile ("csrs " #csr ", %0" :: "r"((uint64_t)(val)) : "memory")
#define csr_clear(csr, val) __asm__ volatile ("csrc " #csr ", %0" :: "r"((uint64_t)(val)) : "memory")
#define csr_swap(csr, val)  ({ uint64_t __v; __asm__ volatile ("csrrw %0, " #csr ", %1" : "=r"(__v) : "r"((uint64_t)(val)) : "memory"); __v; })

static inline void st_fence(void)   { __asm__ volatile ("fence rw, rw" ::: "memory"); }
static inline void st_fence_io(void){ __asm__ volatile ("fence iorw, iorw" ::: "memory"); }
static inline void st_fence_i(void) { __asm__ volatile ("fence.i" ::: "memory"); }
static inline void st_wfi(void)     { __asm__ volatile ("wfi" ::: "memory"); }
static inline void st_compiler_barrier(void) { __asm__ volatile ("" ::: "memory"); }
/* Hide a value from the optimizer so loops and checks are not folded away. */
#define ST_OPAQUE(x) ({ __typeof__(x) __o = (x); __asm__ volatile ("" : "+r"(__o)); __o; })

/* ---- mstatus / mip / cause encodings ---------------------------------- */
#define MSTATUS_SIE   (1UL << 1)
#define MSTATUS_MIE   (1UL << 3)
#define MSTATUS_SPIE  (1UL << 5)
#define MSTATUS_MPIE  (1UL << 7)
#define MSTATUS_SPP   (1UL << 8)
#define MSTATUS_MPP   (3UL << 11)
#define MSTATUS_MPP_S (1UL << 11)
#define MSTATUS_MPP_M (3UL << 11)
#define MSTATUS_FS    (3UL << 13)
#define MSTATUS_MPRV  (1UL << 17)
#define MSTATUS_SUM   (1UL << 18)
#define MSTATUS_MXR   (1UL << 19)
#define MSTATUS_TVM   (1UL << 20)
#define MSTATUS_TW    (1UL << 21)
#define MSTATUS_TSR   (1UL << 22)

#define MIP_SSIP (1UL << 1)
#define MIP_MSIP (1UL << 3)
#define MIP_STIP (1UL << 5)
#define MIP_MTIP (1UL << 7)
#define MIP_SEIP (1UL << 9)
#define MIP_MEIP (1UL << 11)

#define CAUSE_INTR             (1UL << 63)
#define CAUSE_MISALIGNED_FETCH 0
#define CAUSE_FETCH_ACCESS     1
#define CAUSE_ILLEGAL          2
#define CAUSE_BREAKPOINT       3
#define CAUSE_MISALIGNED_LOAD  4
#define CAUSE_LOAD_ACCESS      5
#define CAUSE_MISALIGNED_STORE 6
#define CAUSE_STORE_ACCESS     7
#define CAUSE_ECALL_U          8
#define CAUSE_ECALL_S          9
#define CAUSE_ECALL_M          11
#define CAUSE_FETCH_PAGE       12
#define CAUSE_LOAD_PAGE        13
#define CAUSE_STORE_PAGE       15
#define IRQ_S_SOFT   1
#define IRQ_M_SOFT   3
#define IRQ_S_TIMER  5
#define IRQ_M_TIMER  7
#define IRQ_S_EXT    9
#define IRQ_M_EXT    11

#define PRV_U 0
#define PRV_S 1
#define PRV_M 3

/* Freestanding mem* (programs link -nostdlib; GCC lowers struct/array
 * initialisers and copies to these).  The optimize attribute stops GCC from
 * turning the loops back into calls to themselves. */
#define ST_NOLIBCALL __attribute__((used, noinline, optimize("no-tree-loop-distribute-patterns")))
ST_NOLIBCALL void *memset(void *d, int c, size_t n) {
    volatile uint8_t *p = (volatile uint8_t *)d;
    while (n--) *p++ = (uint8_t)c;
    return d;
}
ST_NOLIBCALL void *memcpy(void *d, const void *s, size_t n) {
    volatile uint8_t *p = (volatile uint8_t *)d; const volatile uint8_t *q = (const volatile uint8_t *)s;
    while (n--) *p++ = *q++;
    return d;
}
ST_NOLIBCALL void *memmove(void *d, const void *s, size_t n) {
    volatile uint8_t *p = (volatile uint8_t *)d; const volatile uint8_t *q = (const volatile uint8_t *)s;
    if (p < q) { while (n--) *p++ = *q++; }
    else { p += n; q += n; while (n--) *--p = *--q; }
    return d;
}
ST_NOLIBCALL int memcmp(const void *a, const void *b, size_t n) {
    const volatile uint8_t *p = (const volatile uint8_t *)a, *q = (const volatile uint8_t *)b;
    for (; n; n--, p++, q++) if (*p != *q) return *p < *q ? -1 : 1;
    return 0;
}

/* ======================================================================= */
/*  Memory map (pkg/config.vh via amoeba_cfg.h)                             */
/* ======================================================================= */
#define ST_RAM_BASE      0x80000000UL
#define ST_RAM_END       ((uint64_t)AMOEBA_EXT_MEM_END)
/* bin/link.ld: image from 0x80000000, tohost at 0x80800000, stack top
 * 0x8ff00000.  Frames for page tables and test data come from a bump
 * allocator over [FRAME_POOL_BASE, FRAME_POOL_END), clear of all three. */
#define ST_FRAME_POOL_BASE 0x81000000UL
#define ST_FRAME_POOL_END  0x8e000000UL

#define CLINT_BASE      ((uint64_t)AMOEBA_CLINT_BASE)
#define CLINT_MSIP      (*(volatile uint32_t *)(CLINT_BASE + 0x0000))
#define CLINT_MTIMECMP  (*(volatile uint64_t *)(CLINT_BASE + 0x4000))
#define CLINT_MTIMECMP_LO (*(volatile uint32_t *)(CLINT_BASE + 0x4000))
#define CLINT_MTIMECMP_HI (*(volatile uint32_t *)(CLINT_BASE + 0x4004))
#define CLINT_MTIME     (*(volatile uint64_t *)(CLINT_BASE + 0xBFF8))
#define CLINT_MTIME_LO  (*(volatile uint32_t *)(CLINT_BASE + 0xBFF8))
#define CLINT_MTIME_HI  (*(volatile uint32_t *)(CLINT_BASE + 0xBFFC))

#define UART_BASE_ADDR  ((uint64_t)AMOEBA_UART_BASE)
#define UART_REG(off)   (*(volatile uint8_t *)(UART_BASE_ADDR + (off)))
#define UART_RBR 0   /* DLAB=0 read  */
#define UART_THR 0   /* DLAB=0 write */
#define UART_DLL 0   /* DLAB=1 */
#define UART_IER 1
#define UART_DLM 1   /* DLAB=1 */
#define UART_IIR 2   /* read  */
#define UART_FCR 2   /* write */
#define UART_LCR 3
#define UART_MCR 4
#define UART_LSR 5
#define UART_MSR 6
#define UART_SCR 7
#define UART_LSR_DR   0x01
#define UART_LSR_OE   0x02
#define UART_LSR_THRE 0x20
#define UART_LSR_TEMT 0x40

#define PLIC_BASE_ADDR       ((uint64_t)AMOEBA_PLIC_BASE)
#define PLIC_PRIORITY(src)   (*(volatile uint32_t *)(PLIC_BASE_ADDR + 4UL * (src)))
#define PLIC_PENDING0        (*(volatile uint32_t *)(PLIC_BASE_ADDR + 0x1000))
#define PLIC_ENABLE(ctx)     (*(volatile uint32_t *)(PLIC_BASE_ADDR + 0x2000 + 0x80UL * (ctx)))
#define PLIC_THRESHOLD(ctx)  (*(volatile uint32_t *)(PLIC_BASE_ADDR + 0x200000 + 0x1000UL * (ctx)))
#define PLIC_CLAIM(ctx)      (*(volatile uint32_t *)(PLIC_BASE_ADDR + 0x200004 + 0x1000UL * (ctx)))
#define PLIC_CTX_M 0
#define PLIC_CTX_S 1
#define PLIC_SRC_IRQ0 AMOEBA_PLIC_GPIO_ID   /* forte: irq[0] pad */
#define PLIC_SRC_IRQ1 AMOEBA_PLIC_SPI_ID    /* forte: irq[1] pad */
#define PLIC_SRC_UART AMOEBA_PLIC_UART_ID

/* AMOEBA fault-tolerance MMIO (hdl/core/cvw.sv) */
#define FI_CONTROL_ADDR   0x1007000bUL
#define ECC_COUNTER_BASE  0x10080000UL

/* An address no region decodes (adrdecs SelRegions[0]) -> access fault. */
#define ST_HOLE_ADDR      0x40000000UL

/* ======================================================================= */
/*  Exit and console (M-mode only)                                          */
/* ======================================================================= */
extern volatile uint64_t tohost;

static inline void __attribute__((noreturn)) st_m_exit(uint64_t code) {
    tohost = (code << 1) | 1;
    /* fence.i writes the D$ back so a pin-level bench sees the store too. */
    st_fence_i();
    for (;;) __asm__ volatile ("wfi");
}

#ifdef COSIM
static inline void st_putc(char c) { (void)c; }
#else
static inline void st_putc(char c) {
    /* Bounded wait: a dead UART must not turn into a silent hang. */
    for (uint32_t i = 0; i < 100000; i++)
        if (UART_REG(UART_LSR) & UART_LSR_THRE) break;
    UART_REG(UART_THR) = (uint8_t)c;
}
#endif

static inline void st_puts(const char *s) { while (*s) st_putc(*s++); }

static inline void st_puthex(uint64_t v) {
    static const char hex[] = "0123456789abcdef";
    st_putc('0'); st_putc('x');
    for (int i = 60; i >= 0; i -= 4) st_putc(hex[(v >> i) & 0xf]);
}

static inline void st_putdec(uint64_t v) {
    char buf[21]; int i = 20; buf[i] = 0;
    if (!v) { st_putc('0'); return; }
    while (v && i) { buf[--i] = (char)('0' + v % 10); v /= 10; }
    st_puts(&buf[i]);
}

/* ======================================================================= */
/*  Checks                                                                  */
/* ======================================================================= */
static volatile uint32_t g_st_pass, g_st_fail, g_st_first_fail_line;
static const char *volatile g_st_section = "";

static inline void st_section(const char *name) {
    g_st_section = name;
    st_puts("[ST] "); st_puts(name); st_putc('\n');
}

static ST_NOINLINE void st_check_failed(const char *label, uint64_t got, uint64_t exp, int line) {
    if (!g_st_fail) g_st_first_fail_line = (uint32_t)line;
    g_st_fail++;
    st_puts("  FAIL ["); st_puts(g_st_section); st_puts("] "); st_puts(label);
    st_puts(" line "); st_putdec((uint64_t)line);
    st_puts(" got "); st_puthex(got); st_puts(" exp "); st_puthex(exp); st_putc('\n');
}

#define ST_CHECK_EQ(label, got, exp) do { \
        uint64_t __g = (uint64_t)(got), __e = (uint64_t)(exp); \
        if (__g == __e) g_st_pass++; else st_check_failed((label), __g, __e, __LINE__); \
    } while (0)
#define ST_CHECK(label, cond) ST_CHECK_EQ((label), !!(cond), 1)

/* Fail-fast variant for invariants whose violation makes the rest of the
 * test meaningless (corrupted page tables, lost control flow). */
#define ST_ASSERT(label, cond) do { \
        if (!(cond)) { st_check_failed((label), 0, 1, __LINE__); st_m_exit(0x10000u + __LINE__); } \
        g_st_pass++; \
    } while (0)

/* main()'s return value: 0 on pass, 0x10000 + line of the first failure. */
static inline int st_result(void) {
    st_puts("[ST] pass="); st_putdec(g_st_pass);
    st_puts(" fail="); st_putdec(g_st_fail); st_putc('\n');
    return g_st_fail ? (int)(0x10000u + g_st_first_fail_line) : 0;
}

/* ======================================================================= */
/*  Deterministic PRNG (xorshift64*), seeded by -DSEED                      */
/* ======================================================================= */
static uint64_t g_st_rng = 0x9E3779B97F4A7C15ULL * (uint64_t)(SEED) ^ 0xD1B54A32D192ED03ULL;

static inline uint64_t st_rand(void) {
    uint64_t x = g_st_rng;
    x ^= x >> 12; x ^= x << 25; x ^= x >> 27;
    g_st_rng = x;
    return x * 0x2545F4914F6CDD1DULL;
}
static inline uint64_t st_rand_range(uint64_t n) { return n ? st_rand() % n : 0; }

static inline uint64_t st_mix64(uint64_t x) {   /* splitmix64 finaliser */
    x ^= x >> 30; x *= 0xBF58476D1CE4E5B9ULL;
    x ^= x >> 27; x *= 0x94D049BB133111EBULL;
    return x ^ (x >> 31);
}

/* ======================================================================= */
/*  Software multiply/divide reference (no M ops: independent of the MDU)   */
/* ======================================================================= */
static inline uint64_t st_soft_mul(uint64_t a, uint64_t b) {
    uint64_t r = 0;
    for (int i = 0; i < 64; i++) { if (b & 1) r += a; a <<= 1; b >>= 1; }
    return r;
}

/* ======================================================================= */
/*  M-mode trap handling                                                    */
/* ======================================================================= */
typedef struct st_frame {
    uint64_t x[32];          /* x[2] = interrupted sp */
    uint64_t epc, cause, tval, status;
} st_frame_t;                /* 36 * 8 = 288 bytes, 16-aligned */

/* ecall ABI between lower modes and the M-mode harness: a7 = function. */
#define ST_ECALL_RETURN    0x53540001UL  /* back to run_in_mode's caller, a0 = value */
#define ST_ECALL_EXIT      0x53540002UL  /* st_m_exit(a0)                           */
#define ST_ECALL_PUTC      0x53540003UL  /* st_putc(a0)                             */
#define ST_ECALL_SET_TIMER 0x53540004UL  /* mtimecmp = a0, clear STIP (SBI-like)    */
#define ST_ECALL_SET_SSIP  0x53540005UL  /* mip.SSIP = 1                            */
#define ST_TRAP_ABORTED    0xDEAD0000DEAD0000UL

/* Hooks.  Return nonzero if the trap was handled (the frame may be edited). */
typedef int (*st_hook_t)(st_frame_t *f);
static volatile st_hook_t g_m_hook;       /* any trap, before the defaults below */
static volatile st_hook_t g_m_irq_hook;   /* interrupts only                    */

/* "Expect" state: the next synchronous exception is recorded instead of
 * failing the test.  ST_EXPECT_SKIP resumes after the faulting instruction
 * (g_exp_len bytes, 4 by default -- probes are .option norvc), or at
 * g_exp_resume if set.  ST_EXPECT_ABORT unwinds a run_in_mode() back to its
 * M-mode caller, which then sees ST_TRAP_ABORTED. */
#define ST_EXPECT_NONE  0
#define ST_EXPECT_SKIP  1
#define ST_EXPECT_ABORT 2
static volatile int      g_exp_mode;
static volatile uint64_t g_exp_len = 4, g_exp_resume;
static volatile uint64_t g_trap_cause, g_trap_tval, g_trap_epc, g_trap_status, g_trap_count;
static volatile uint64_t g_irq_count;

static inline void st_expect(int mode) {
    g_trap_cause = ~0UL; g_trap_tval = ~0UL; g_trap_epc = ~0UL;
    g_exp_resume = 0; g_exp_len = 4; g_exp_mode = mode;
}
static inline int st_trapped(void) { return g_trap_cause != ~0UL; }
static inline void st_expect_clear(void) { g_exp_mode = ST_EXPECT_NONE; }

/* Under Sv39 neither S nor M-with-MPRV may execute a U page, and S may never
 * fetch from one, so a test whose S/M code and U programs share the image maps
 * it twice: identity, supervisor-only, and at identity + g_st_u_alias_off with
 * U set.  st_run_in_mode(PRV_U) and st_s_run_user return U through the alias;
 * st_u_alias() converts code/stack/data addresses for U.  0 = no alias. */
ST_USED volatile uint64_t g_st_u_alias_off;
static inline uint64_t st_u_alias(uint64_t a) { return a + g_st_u_alias_off; }
#define ST_U_ALIAS_VA 0x100000000UL   /* vpn[2] = 4: a whole gigapage alias of RAM */

/* M trap stack (also the stack every lower-mode trap starts on). */
#define ST_MSTACK_BYTES 16384
static uint8_t g_st_mstack[ST_MSTACK_BYTES] ST_ALIGNED(16);
/* Default stack for code run in S/U by run_in_mode(). */
#define ST_LSTACK_BYTES 16384
static uint8_t g_st_lstack[ST_LSTACK_BYTES] ST_ALIGNED(16);

extern void st_trap_entry(void);
extern void st_rim_resume(void);
extern void st_rim_trampoline(void);
extern uint64_t st_run_in_mode(uint64_t mode, uint64_t (*fn)(uint64_t), uint64_t arg, uint64_t sp);

/*
 * Trap entry.  Traps from S/U switch to the M stack held in mscratch; traps
 * from M (nested traps, MPRV probes, interrupts in M code) stay on the current
 * stack, so a trap inside a handler never overwrites the frame it interrupted.
 * mscratch always holds the M stack top between traps.
 */
__asm__ (
    ".text\n"
    ".option push\n"
    ".option norvc\n"
    ".balign 4\n"
    ".globl st_trap_entry\n"
    "st_trap_entry:\n"
    "    csrrw sp, mscratch, sp\n"          /* sp = M stack top, mscratch = interrupted sp */
    "    sd    t0, -8(sp)\n"
    "    csrr  t0, mstatus\n"
    "    srli  t0, t0, 11\n"
    "    andi  t0, t0, 3\n"
    "    xori  t0, t0, 3\n"
    "    beqz  t0, 1f\n"
    /* from S/U: frame on the M stack */
    "    ld    t0, -8(sp)\n"
    "    addi  sp, sp, -304\n"              /* 16 bytes scratch + 288 frame */
    "    sd    t0, 40(sp)\n"
    "    csrr  t0, mscratch\n"
    "    sd    t0, 16(sp)\n"
    "    addi  t0, sp, 304\n"
    "    csrw  mscratch, t0\n"
    "    j     2f\n"
    /* from M: frame on the interrupted stack */
    "1:  ld    t0, -8(sp)\n"
    "    csrrw sp, mscratch, sp\n"          /* sp = interrupted sp, mscratch = top */
    "    addi  sp, sp, -288\n"
    "    sd    t0, 40(sp)\n"
    "    addi  t0, sp, 288\n"
    "    sd    t0, 16(sp)\n"
    "2:  sd x1, 8(sp)\n   sd x3, 24(sp)\n  sd x4, 32(sp)\n"
    "    sd x6, 48(sp)\n  sd x7, 56(sp)\n  sd x8, 64(sp)\n  sd x9, 72(sp)\n"
    "    sd x10, 80(sp)\n sd x11, 88(sp)\n sd x12, 96(sp)\n sd x13, 104(sp)\n"
    "    sd x14, 112(sp)\n sd x15, 120(sp)\n sd x16, 128(sp)\n sd x17, 136(sp)\n"
    "    sd x18, 144(sp)\n sd x19, 152(sp)\n sd x20, 160(sp)\n sd x21, 168(sp)\n"
    "    sd x22, 176(sp)\n sd x23, 184(sp)\n sd x24, 192(sp)\n sd x25, 200(sp)\n"
    "    sd x26, 208(sp)\n sd x27, 216(sp)\n sd x28, 224(sp)\n sd x29, 232(sp)\n"
    "    sd x30, 240(sp)\n sd x31, 248(sp)\n"
    "    csrr t0, mepc\n    sd t0, 256(sp)\n"
    "    csrr t0, mcause\n  sd t0, 264(sp)\n"
    "    csrr t0, mtval\n   sd t0, 272(sp)\n"
    "    csrr t0, mstatus\n sd t0, 280(sp)\n"
    "    mv   a0, sp\n"
    "    call st_trap_dispatch\n"
    "    ld t0, 256(sp)\n   csrw mepc, t0\n"
    "    ld t0, 280(sp)\n   csrw mstatus, t0\n"
    "    ld x1, 8(sp)\n   ld x3, 24(sp)\n  ld x4, 32(sp)\n  ld x5, 40(sp)\n"
    "    ld x6, 48(sp)\n  ld x7, 56(sp)\n  ld x8, 64(sp)\n  ld x9, 72(sp)\n"
    "    ld x10, 80(sp)\n ld x11, 88(sp)\n ld x12, 96(sp)\n ld x13, 104(sp)\n"
    "    ld x14, 112(sp)\n ld x15, 120(sp)\n ld x16, 128(sp)\n ld x17, 136(sp)\n"
    "    ld x18, 144(sp)\n ld x19, 152(sp)\n ld x20, 160(sp)\n ld x21, 168(sp)\n"
    "    ld x22, 176(sp)\n ld x23, 184(sp)\n ld x24, 192(sp)\n ld x25, 200(sp)\n"
    "    ld x26, 208(sp)\n ld x27, 216(sp)\n ld x28, 224(sp)\n ld x29, 232(sp)\n"
    "    ld x30, 240(sp)\n ld x31, 248(sp)\n"
    "    ld x2, 16(sp)\n"
    "    mret\n"
    /*
     * uint64_t st_run_in_mode(mode, fn, arg, sp): run fn(arg) in S (mode 1) or
     * U (mode 0) and return its result.  fn returns into st_rim_trampoline,
     * which ecalls back; the dispatcher resumes M at st_rim_resume.  Callee-
     * saved state lives on the caller's M stack; one level only.
     */
    ".balign 4\n"
    ".globl st_run_in_mode\n"
    "st_run_in_mode:\n"
    "    addi sp, sp, -112\n"
    "    sd ra, 0(sp)\n   sd s0, 8(sp)\n   sd s1, 16(sp)\n  sd s2, 24(sp)\n"
    "    sd s3, 32(sp)\n  sd s4, 40(sp)\n  sd s5, 48(sp)\n  sd s6, 56(sp)\n"
    "    sd s7, 64(sp)\n  sd s8, 72(sp)\n  sd s9, 80(sp)\n  sd s10, 88(sp)\n"
    "    sd s11, 96(sp)\n sd gp, 104(sp)\n"
    "    la   t0, g_st_rim_sp\n"
    "    sd   sp, 0(t0)\n"
    "    li   t0, 0x1800\n"
    "    csrc mstatus, t0\n"
    "    slli t1, a0, 11\n"
    "    csrs mstatus, t1\n"
    "    csrw mepc, a1\n"
    "    la   ra, st_rim_trampoline\n"
    "    bnez a0, 4f\n"                    /* U: return through the U alias */
    "    la   t0, g_st_u_alias_off\n"
    "    ld   t0, 0(t0)\n"
    "    add  ra, ra, t0\n"
    "4:  mv   a0, a2\n"
    "    mv   sp, a3\n"
    "    mret\n"
    ".balign 4\n"
    ".globl st_rim_trampoline\n"
    "st_rim_trampoline:\n"
    "    li   a7, 0x53540001\n"
    "    ecall\n"
    "3:  j 3b\n"
    ".balign 4\n"
    ".globl st_rim_resume\n"
    "st_rim_resume:\n"
    "    la   t0, g_st_rim_sp\n"
    "    ld   sp, 0(t0)\n"
    "    ld ra, 0(sp)\n   ld s0, 8(sp)\n   ld s1, 16(sp)\n  ld s2, 24(sp)\n"
    "    ld s3, 32(sp)\n  ld s4, 40(sp)\n  ld s5, 48(sp)\n  ld s6, 56(sp)\n"
    "    ld s7, 64(sp)\n  ld s8, 72(sp)\n  ld s9, 80(sp)\n  ld s10, 88(sp)\n"
    "    ld s11, 96(sp)\n ld gp, 104(sp)\n"
    "    addi sp, sp, 112\n"
    "    ret\n"
    ".option pop\n"
);

ST_USED volatile uint64_t g_st_rim_sp;   /* named from asm: must not be static (LTO renames statics) */

static inline void st_set_mpp(st_frame_t *f, uint64_t prv) {
    f->status = (f->status & ~MSTATUS_MPP) | (prv << 11);
}

static inline uint64_t st_irq_bit(uint64_t cause) { return cause & ~CAUSE_INTR; }

ST_USED ST_NOINLINE void st_trap_dispatch(st_frame_t *f) {
    uint64_t cause = f->cause;
    g_trap_count++;

    /* ---- harness ecalls from any mode ---------------------------------- */
    if (cause == CAUSE_ECALL_U || cause == CAUSE_ECALL_S || cause == CAUSE_ECALL_M) {
        uint64_t fn = f->x[17];
        if (fn == ST_ECALL_RETURN) {
            /* MPIE cleared: the caller resumes with MIE = 0 whatever MIE was
             * while the lower mode ran (mret would otherwise restore it). */
            f->epc = (uint64_t)st_rim_resume;
            f->status &= ~(MSTATUS_MPRV | MSTATUS_MPIE);
            st_set_mpp(f, PRV_M);
            return;
        }
        if (fn == ST_ECALL_EXIT)  st_m_exit(f->x[10]);
        if (fn == ST_ECALL_PUTC)  { st_putc((char)f->x[10]); f->epc += 4; return; }
        if (fn == ST_ECALL_SET_TIMER) {
            CLINT_MTIMECMP = f->x[10];
            csr_clear(mip, MIP_STIP);
            csr_set(mie, MIP_MTIP);
            f->epc += 4; return;
        }
        if (fn == ST_ECALL_SET_SSIP) { csr_set(mip, MIP_SSIP); f->epc += 4; return; }
    }

    if (g_m_hook && g_m_hook(f)) return;

    if (cause & CAUSE_INTR) {
        g_irq_count++;
        if (g_m_irq_hook && g_m_irq_hook(f)) return;
        st_puts("[ST] unexpected interrupt "); st_puthex(cause);
        st_puts(" epc "); st_puthex(f->epc); st_putc('\n');
        st_m_exit(0x600 | (cause & 0xff));
    }

    if (g_exp_mode != ST_EXPECT_NONE) {
        int mode = g_exp_mode;
        g_exp_mode = ST_EXPECT_NONE;
        g_trap_cause = cause; g_trap_tval = f->tval; g_trap_epc = f->epc;
        g_trap_status = f->status;
        if (mode == ST_EXPECT_ABORT) {
            f->x[10] = ST_TRAP_ABORTED;
            f->epc = (uint64_t)st_rim_resume;
            f->status &= ~(MSTATUS_MPRV | MSTATUS_MPIE);
            st_set_mpp(f, PRV_M);
        } else {
            f->epc = g_exp_resume ? g_exp_resume : f->epc + g_exp_len;
        }
        return;
    }

    st_puts("[ST] unexpected trap cause "); st_puthex(cause);
    st_puts(" epc "); st_puthex(f->epc);
    st_puts(" tval "); st_puthex(f->tval);
    st_puts(" mstatus "); st_puthex(f->status); st_putc('\n');
    st_m_exit(0x400 | (cause & 0x3ff));
}

/* Lower-mode helpers (callable from S or U). */
static inline uint64_t st_ecall(uint64_t fn, uint64_t a0) {
    register uint64_t r_a0 __asm__("a0") = a0;
    register uint64_t r_a7 __asm__("a7") = fn;
    __asm__ volatile ("ecall" : "+r"(r_a0) : "r"(r_a7) : "memory");
    return r_a0;
}
static inline void __attribute__((noreturn)) st_ecall_exit(uint64_t code) {
    st_ecall(ST_ECALL_EXIT, code);
    for (;;) ;
}
static inline void st_ecall_putc(char c) { st_ecall(ST_ECALL_PUTC, (uint64_t)c); }

static inline uint64_t st_run(uint64_t prv, uint64_t (*fn)(uint64_t), uint64_t arg) {
    return st_run_in_mode(prv, fn, arg, (uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
}

/* ======================================================================= */
/*  PMP                                                                     */
/* ======================================================================= */
#define PMP_R     0x01
#define PMP_W     0x02
#define PMP_X     0x04
#define PMP_OFF   0x00
#define PMP_TOR   0x08
#define PMP_NA4   0x10
#define PMP_NAPOT 0x18
#define PMP_L     0x80

static inline uint64_t pmp_napot_addr(uint64_t base, uint64_t size) {
    return (base >> 2) | ((size >> 3) - 1);
}

/* pmpaddrN / pmpcfg are not indexable at run time: switch over the index. */
static ST_NOINLINE void pmp_write_addr(int i, uint64_t v) {
    switch (i) {
    case 0: csr_write(pmpaddr0, v); break;   case 1: csr_write(pmpaddr1, v); break;
    case 2: csr_write(pmpaddr2, v); break;   case 3: csr_write(pmpaddr3, v); break;
    case 4: csr_write(pmpaddr4, v); break;   case 5: csr_write(pmpaddr5, v); break;
    case 6: csr_write(pmpaddr6, v); break;   case 7: csr_write(pmpaddr7, v); break;
    case 8: csr_write(pmpaddr8, v); break;   case 9: csr_write(pmpaddr9, v); break;
    case 10: csr_write(pmpaddr10, v); break; case 11: csr_write(pmpaddr11, v); break;
    case 12: csr_write(pmpaddr12, v); break; case 13: csr_write(pmpaddr13, v); break;
    case 14: csr_write(pmpaddr14, v); break; case 15: csr_write(pmpaddr15, v); break;
    default: break;
    }
}
static ST_NOINLINE uint64_t pmp_read_addr(int i) {
    switch (i) {
    case 0: return csr_read(pmpaddr0);   case 1: return csr_read(pmpaddr1);
    case 2: return csr_read(pmpaddr2);   case 3: return csr_read(pmpaddr3);
    case 4: return csr_read(pmpaddr4);   case 5: return csr_read(pmpaddr5);
    case 6: return csr_read(pmpaddr6);   case 7: return csr_read(pmpaddr7);
    case 8: return csr_read(pmpaddr8);   case 9: return csr_read(pmpaddr9);
    case 10: return csr_read(pmpaddr10); case 11: return csr_read(pmpaddr11);
    case 12: return csr_read(pmpaddr12); case 13: return csr_read(pmpaddr13);
    case 14: return csr_read(pmpaddr14); case 15: return csr_read(pmpaddr15);
    default: return 0;
    }
}
/* Set the 8-bit config of entry i (RV64: pmpcfg0 holds 0-7, pmpcfg2 8-15). */
static ST_NOINLINE void pmp_write_cfg(int i, uint8_t cfg) {
    uint64_t shift = (uint64_t)(i & 7) * 8;
    uint64_t mask = 0xffUL << shift, val = (uint64_t)cfg << shift;
    if (i < 8) { uint64_t c = csr_read(pmpcfg0); csr_write(pmpcfg0, (c & ~mask) | val); }
    else       { uint64_t c = csr_read(pmpcfg2); csr_write(pmpcfg2, (c & ~mask) | val); }
}
static inline void pmp_clear_all(void) {
    csr_write(pmpcfg0, 0); csr_write(pmpcfg2, 0);
    for (int i = 0; i < AMOEBA_PMP_ENTRIES; i++) pmp_write_addr(i, 0);
}
/* Lowest-priority catch-all granting S/U full access (the last entry). */
static inline void pmp_allow_all(void) {
    int last = AMOEBA_PMP_ENTRIES - 1;
    pmp_write_addr(last, ~0UL >> 10);
    pmp_write_cfg(last, PMP_NAPOT | PMP_R | PMP_W | PMP_X);
    __asm__ volatile ("sfence.vma" ::: "memory");
}

/* ======================================================================= */
/*  Sv39                                                                    */
/* ======================================================================= */
#define PTE_V 0x001UL
#define PTE_R 0x002UL
#define PTE_W 0x004UL
#define PTE_X 0x008UL
#define PTE_U 0x010UL
#define PTE_G 0x020UL
#define PTE_A 0x040UL
#define PTE_D 0x080UL
#define PTE_RWX  (PTE_R | PTE_W | PTE_X)
#define PTE_AD   (PTE_A | PTE_D)
#define SATP_SV39 (8UL << 60)

static inline uint64_t pte_leaf(uint64_t pa, uint64_t bits) { return ((pa >> 12) << 10) | bits | PTE_V; }
static inline uint64_t pte_table(uint64_t pa) { return ((pa >> 12) << 10) | PTE_V; }
static inline uint64_t pte_pa(uint64_t pte) { return (pte >> 10) << 12; }
static inline uint64_t vpn(uint64_t va, int level) { return (va >> (12 + 9 * level)) & 0x1ff; }
static inline uint64_t satp_sv39(uint64_t asid, uint64_t root_pa) {
    return SATP_SV39 | ((asid & 0xffffUL) << 44) | (root_pa >> 12);
}

static volatile uint64_t g_next_frame = ST_FRAME_POOL_BASE;

static inline void st_zero_page(uint64_t pa) {
    volatile uint64_t *p = (volatile uint64_t *)pa;
    for (unsigned i = 0; i < ST_PAGE / 8; i++) p[i] = 0;
}
/* Untouched simulator memory may read X: every frame is zeroed on allocation. */
static inline uint64_t frame_alloc(void) {
    uint64_t pa = g_next_frame;
    if (pa + ST_PAGE > ST_FRAME_POOL_END) { st_puts("[ST] frame pool exhausted\n"); st_m_exit(0x7ff); }
    g_next_frame = pa + ST_PAGE;
    st_zero_page(pa);
    return pa;
}
static inline uint64_t frame_alloc_aligned(uint64_t align) {
    uint64_t pa = (g_next_frame + align - 1) & ~(align - 1);
    g_next_frame = pa;
    return frame_alloc();
}

static inline void sfence_all(void) { __asm__ volatile ("sfence.vma" ::: "memory"); }
static inline void sfence_va(uint64_t va) { __asm__ volatile ("sfence.vma %0, zero" :: "r"(va) : "memory"); }
static inline void sfence_asid(uint64_t asid) { __asm__ volatile ("sfence.vma zero, %0" :: "r"(asid) : "memory"); }
static inline void sfence_va_asid(uint64_t va, uint64_t asid) { __asm__ volatile ("sfence.vma %0, %1" :: "r"(va), "r"(asid) : "memory"); }

/* Pointer to the PTE that maps va at `level` (2 = 1 GiB, 1 = 2 MiB, 0 = 4 KiB),
 * allocating intermediate tables as needed. */
static uint64_t *pt_slot(uint64_t root, uint64_t va, int level) {
    uint64_t *table = (uint64_t *)root;
    for (int l = 2; l > level; l--) {
        uint64_t *e = &table[vpn(va, l)];
        if (!(*e & PTE_V) || (*e & PTE_RWX)) *e = pte_table(frame_alloc());
        table = (uint64_t *)pte_pa(*e);
    }
    return &table[vpn(va, level)];
}
static inline void map_page(uint64_t root, uint64_t va, uint64_t pa, uint64_t bits) { *pt_slot(root, va, 0) = pte_leaf(pa, bits); }
static inline void map_mega(uint64_t root, uint64_t va, uint64_t pa, uint64_t bits) { *pt_slot(root, va, 1) = pte_leaf(pa, bits); }
static inline void map_giga(uint64_t root, uint64_t va, uint64_t pa, uint64_t bits) { *pt_slot(root, va, 2) = pte_leaf(pa, bits); }

/* A root that maps the RAM gigapage (0x80000000) identity -- code, data, stacks,
 * tohost -- and the MMIO gigapage (0x0) identity, both supervisor-only unless
 * `user`.  Test mappings go above 0xC0000000 (root[3]) or elsewhere. */
static inline uint64_t pt_new_identity_root(int user) {
    uint64_t root = frame_alloc();
    uint64_t u = user ? PTE_U : 0;
    map_giga(root, 0x80000000UL, 0x80000000UL, PTE_RWX | PTE_AD | u);
    map_giga(root, 0x00000000UL, 0x00000000UL, PTE_R | PTE_W | PTE_AD);
    return root;
}

static inline void st_map_u_alias(uint64_t root) {
    map_giga(root, ST_U_ALIAS_VA, ST_RAM_BASE, PTE_RWX | PTE_AD | PTE_U);
    g_st_u_alias_off = ST_U_ALIAS_VA - ST_RAM_BASE;
}

/* ---- MPRV probes: access va from M with the translation/permissions of
 * privilege `prv` (MPRV=1, MPP=prv).  Return 1 if the access trapped; the trap
 * is in g_trap_cause / g_trap_tval. ----------------------------------- */
#define ST_DEF_PROBE_LD(name, insn, type) \
static ST_NOINLINE int name(uint64_t va, uint64_t prv, uint64_t *out) { \
    uint64_t v = 0x5a5a5a5a5a5a5a5aUL; \
    csr_clear(mstatus, MSTATUS_MPP); csr_set(mstatus, prv << 11); \
    st_expect(ST_EXPECT_SKIP); \
    __asm__ volatile (".option push\n.option norvc\n" \
                      "csrs mstatus, %[m]\n" insn " %[v], 0(%[a])\n" "csrc mstatus, %[m]\n" \
                      ".option pop\n" : [v] "+&r"(v) : [a] "r"(va), [m] "r"(MSTATUS_MPRV) : "memory"); \
    st_expect_clear(); \
    csr_clear(mstatus, MSTATUS_MPP); csr_set(mstatus, MSTATUS_MPP_M); \
    if (out) *out = (uint64_t)(type)v; \
    return st_trapped(); \
}
#define ST_DEF_PROBE_ST(name, insn) \
static ST_NOINLINE int name(uint64_t va, uint64_t prv, uint64_t val) { \
    csr_clear(mstatus, MSTATUS_MPP); csr_set(mstatus, prv << 11); \
    st_expect(ST_EXPECT_SKIP); \
    __asm__ volatile (".option push\n.option norvc\n" \
                      "csrs mstatus, %[m]\n" insn " %[v], 0(%[a])\n" "csrc mstatus, %[m]\n" \
                      ".option pop\n" :: [v] "r"(val), [a] "r"(va), [m] "r"(MSTATUS_MPRV) : "memory"); \
    st_expect_clear(); \
    csr_clear(mstatus, MSTATUS_MPP); csr_set(mstatus, MSTATUS_MPP_M); \
    return st_trapped(); \
}
ST_DEF_PROBE_LD(probe_ld,  "ld",  uint64_t)
ST_DEF_PROBE_LD(probe_lw,  "lw",  int32_t)
ST_DEF_PROBE_LD(probe_lwu, "lwu", uint32_t)
ST_DEF_PROBE_LD(probe_lh,  "lh",  int16_t)
ST_DEF_PROBE_LD(probe_lhu, "lhu", uint16_t)
ST_DEF_PROBE_LD(probe_lb,  "lb",  int8_t)
ST_DEF_PROBE_LD(probe_lbu, "lbu", uint8_t)
ST_DEF_PROBE_ST(probe_sd, "sd")
ST_DEF_PROBE_ST(probe_sw, "sw")
ST_DEF_PROBE_ST(probe_sh, "sh")
ST_DEF_PROBE_ST(probe_sb, "sb")

/* Plain M-mode (physical) accesses that may fault, e.g. PMA holes. */
#define ST_DEF_MACC_LD(name, insn) \
static ST_NOINLINE int name(uint64_t pa, uint64_t *out) { \
    uint64_t v = 0x5a5a5a5a5a5a5a5aUL; \
    st_expect(ST_EXPECT_SKIP); \
    __asm__ volatile (".option push\n.option norvc\n" insn " %[v], 0(%[a])\n.option pop\n" \
                      : [v] "+&r"(v) : [a] "r"(pa) : "memory"); \
    st_expect_clear(); \
    if (out) *out = v; \
    return st_trapped(); \
}
#define ST_DEF_MACC_ST(name, insn) \
static ST_NOINLINE int name(uint64_t pa, uint64_t val) { \
    st_expect(ST_EXPECT_SKIP); \
    __asm__ volatile (".option push\n.option norvc\n" insn " %[v], 0(%[a])\n.option pop\n" \
                      :: [v] "r"(val), [a] "r"(pa) : "memory"); \
    st_expect_clear(); \
    return st_trapped(); \
}
ST_DEF_MACC_LD(m_try_ld, "ld")
ST_DEF_MACC_LD(m_try_lw, "lw")
ST_DEF_MACC_LD(m_try_lh, "lh")
ST_DEF_MACC_LD(m_try_lb, "lb")
ST_DEF_MACC_LD(m_try_lbu, "lbu")
ST_DEF_MACC_ST(m_try_sd, "sd")
ST_DEF_MACC_ST(m_try_sw, "sw")
ST_DEF_MACC_ST(m_try_sh, "sh")
ST_DEF_MACC_ST(m_try_sb, "sb")

/* Run fn at its (possibly virtual) address in `prv`; returns ST_TRAP_ABORTED
 * if a synchronous exception occurred (details in g_trap_*), else fn's value. */
static inline uint64_t st_run_expect_abort(uint64_t prv, uint64_t (*fn)(uint64_t), uint64_t arg, uint64_t sp) {
    st_expect(ST_EXPECT_ABORT);
    uint64_t r = st_run_in_mode(prv, fn, arg, sp);
    st_expect_clear();
    return r;
}

/* ======================================================================= */
/*  CLINT / timer                                                           */
/* ======================================================================= */
static inline uint64_t st_mtime(void) { return CLINT_MTIME; }
static inline void st_set_mtimecmp(uint64_t v) { CLINT_MTIMECMP = v; }
static inline void st_timer_off(void) { CLINT_MTIMECMP = ~0UL; }

/* ======================================================================= */
/*  S-mode trap handling (delegated traps)                                  */
/* ======================================================================= */
/* Same frame layout as M: epc/cause/tval/status hold sepc/scause/stval/
 * sstatus.  S code must run bare or through an identity mapping of RAM (and
 * of MMIO, to print), supervisor pages, with medeleg/mideleg set by M. */
#define ST_ECALL_SRETURN 0x53540011UL   /* U -> S: back to st_s_run_user's caller */

static volatile st_hook_t g_s_hook;
static volatile st_hook_t g_s_irq_hook;
static volatile int      g_s_exp_mode;
static volatile uint64_t g_s_exp_len = 4;
static volatile uint64_t g_s_trap_cause, g_s_trap_tval, g_s_trap_epc, g_s_trap_count;

static inline void st_s_expect(int mode) {
    g_s_trap_cause = ~0UL; g_s_trap_tval = ~0UL; g_s_trap_epc = ~0UL;
    g_s_exp_len = 4; g_s_exp_mode = mode;
}
static inline int st_s_trapped(void) { return g_s_trap_cause != ~0UL; }

#define ST_SSTACK_BYTES 16384
static uint8_t g_st_sstack[ST_SSTACK_BYTES] ST_ALIGNED(16);
ST_USED volatile uint64_t g_st_srim_sp;   /* named from asm: must not be static */
/* Under Sv39 S can never execute a U page, so a test whose S kernel and U
 * programs share the image maps it twice: identity, supervisor-only (for S)
 * and at identity + g_st_u_alias_off with U set (for U).  st_s_run_user
 * returns U through the alias; st_u_alias() converts code/stack addresses. */


extern void st_s_trap_entry(void);
extern void st_s_rim_resume(void);
extern uint64_t st_s_run_user(uint64_t (*fn)(uint64_t), uint64_t arg, uint64_t sp);

__asm__ (
    ".text\n"
    ".option push\n"
    ".option norvc\n"
    ".balign 4\n"
    ".globl st_s_trap_entry\n"
    "st_s_trap_entry:\n"
    "    csrrw sp, sscratch, sp\n"
    "    sd    t0, -8(sp)\n"
    "    csrr  t0, sstatus\n"
    "    andi  t0, t0, 0x100\n"            /* SPP: 1 = from S */
    "    bnez  t0, 1f\n"
    "    ld    t0, -8(sp)\n"
    "    addi  sp, sp, -304\n"
    "    sd    t0, 40(sp)\n"
    "    csrr  t0, sscratch\n"
    "    sd    t0, 16(sp)\n"
    "    addi  t0, sp, 304\n"
    "    csrw  sscratch, t0\n"
    "    j     2f\n"
    "1:  ld    t0, -8(sp)\n"
    "    csrrw sp, sscratch, sp\n"
    "    addi  sp, sp, -288\n"
    "    sd    t0, 40(sp)\n"
    "    addi  t0, sp, 288\n"
    "    sd    t0, 16(sp)\n"
    "2:  sd x1, 8(sp)\n   sd x3, 24(sp)\n  sd x4, 32(sp)\n"
    "    sd x6, 48(sp)\n  sd x7, 56(sp)\n  sd x8, 64(sp)\n  sd x9, 72(sp)\n"
    "    sd x10, 80(sp)\n sd x11, 88(sp)\n sd x12, 96(sp)\n sd x13, 104(sp)\n"
    "    sd x14, 112(sp)\n sd x15, 120(sp)\n sd x16, 128(sp)\n sd x17, 136(sp)\n"
    "    sd x18, 144(sp)\n sd x19, 152(sp)\n sd x20, 160(sp)\n sd x21, 168(sp)\n"
    "    sd x22, 176(sp)\n sd x23, 184(sp)\n sd x24, 192(sp)\n sd x25, 200(sp)\n"
    "    sd x26, 208(sp)\n sd x27, 216(sp)\n sd x28, 224(sp)\n sd x29, 232(sp)\n"
    "    sd x30, 240(sp)\n sd x31, 248(sp)\n"
    "    csrr t0, sepc\n    sd t0, 256(sp)\n"
    "    csrr t0, scause\n  sd t0, 264(sp)\n"
    "    csrr t0, stval\n   sd t0, 272(sp)\n"
    "    csrr t0, sstatus\n sd t0, 280(sp)\n"
    "    mv   a0, sp\n"
    "    call st_s_trap_dispatch\n"
    "    ld t0, 256(sp)\n   csrw sepc, t0\n"
    "    ld t0, 280(sp)\n   csrw sstatus, t0\n"
    "    ld x1, 8(sp)\n   ld x3, 24(sp)\n  ld x4, 32(sp)\n  ld x5, 40(sp)\n"
    "    ld x6, 48(sp)\n  ld x7, 56(sp)\n  ld x8, 64(sp)\n  ld x9, 72(sp)\n"
    "    ld x10, 80(sp)\n ld x11, 88(sp)\n ld x12, 96(sp)\n ld x13, 104(sp)\n"
    "    ld x14, 112(sp)\n ld x15, 120(sp)\n ld x16, 128(sp)\n ld x17, 136(sp)\n"
    "    ld x18, 144(sp)\n ld x19, 152(sp)\n ld x20, 160(sp)\n ld x21, 168(sp)\n"
    "    ld x22, 176(sp)\n ld x23, 184(sp)\n ld x24, 192(sp)\n ld x25, 200(sp)\n"
    "    ld x26, 208(sp)\n ld x27, 216(sp)\n ld x28, 224(sp)\n ld x29, 232(sp)\n"
    "    ld x30, 240(sp)\n ld x31, 248(sp)\n"
    "    ld x2, 16(sp)\n"
    "    sret\n"
    /* uint64_t st_s_run_user(fn, arg, sp): from S, run fn(arg) in U. */
    ".balign 4\n"
    ".globl st_s_run_user\n"
    "st_s_run_user:\n"
    "    addi sp, sp, -112\n"
    "    sd ra, 0(sp)\n   sd s0, 8(sp)\n   sd s1, 16(sp)\n  sd s2, 24(sp)\n"
    "    sd s3, 32(sp)\n  sd s4, 40(sp)\n  sd s5, 48(sp)\n  sd s6, 56(sp)\n"
    "    sd s7, 64(sp)\n  sd s8, 72(sp)\n  sd s9, 80(sp)\n  sd s10, 88(sp)\n"
    "    sd s11, 96(sp)\n sd gp, 104(sp)\n"
    "    la   t0, g_st_srim_sp\n"
    "    sd   sp, 0(t0)\n"
    "    li   t0, 0x100\n"
    "    csrc sstatus, t0\n"               /* SPP = U */
    "    csrw sepc, a0\n"
    "    mv   a0, a1\n"
    "    mv   sp, a2\n"
    "    la   ra, st_s_rim_trampoline\n"
    "    la   t0, g_st_u_alias_off\n"
    "    ld   t0, 0(t0)\n"
    "    add  ra, ra, t0\n"               /* U runs the image through its U alias */
    "    sret\n"
    ".balign 4\n"
    ".globl st_s_rim_trampoline\n"
    "st_s_rim_trampoline:\n"
    "    li   a7, 0x53540011\n"
    "    ecall\n"
    "3:  j 3b\n"
    ".balign 4\n"
    ".globl st_s_rim_resume\n"
    "st_s_rim_resume:\n"
    "    la   t0, g_st_srim_sp\n"
    "    ld   sp, 0(t0)\n"
    "    ld ra, 0(sp)\n   ld s0, 8(sp)\n   ld s1, 16(sp)\n  ld s2, 24(sp)\n"
    "    ld s3, 32(sp)\n  ld s4, 40(sp)\n  ld s5, 48(sp)\n  ld s6, 56(sp)\n"
    "    ld s7, 64(sp)\n  ld s8, 72(sp)\n  ld s9, 80(sp)\n  ld s10, 88(sp)\n"
    "    ld s11, 96(sp)\n ld gp, 104(sp)\n"
    "    addi sp, sp, 112\n"
    "    ret\n"
    ".option pop\n"
);

ST_USED ST_NOINLINE void st_s_trap_dispatch(st_frame_t *f) {
    uint64_t cause = f->cause;
    g_s_trap_count++;
    if (cause == CAUSE_ECALL_U && f->x[17] == ST_ECALL_SRETURN) {
        f->epc = (uint64_t)st_s_rim_resume;     /* resumes S with SIE = 0 */
        f->status = (f->status | MSTATUS_SPP) & ~MSTATUS_SPIE;
        return;
    }
    if (g_s_hook && g_s_hook(f)) return;
    if (cause & CAUSE_INTR) {
        if (g_s_irq_hook && g_s_irq_hook(f)) return;
        st_ecall_exit(0x680 | (cause & 0xff));
    }
    if (g_s_exp_mode != ST_EXPECT_NONE) {
        int mode = g_s_exp_mode;
        g_s_exp_mode = ST_EXPECT_NONE;
        g_s_trap_cause = cause; g_s_trap_tval = f->tval; g_s_trap_epc = f->epc;
        if (mode == ST_EXPECT_ABORT) {
            f->x[10] = ST_TRAP_ABORTED;
            f->epc = (uint64_t)st_s_rim_resume;
            f->status = (f->status | MSTATUS_SPP) & ~MSTATUS_SPIE;
        } else {
            f->epc += g_s_exp_len;
        }
        return;
    }
    st_ecall_exit(0x500 | (cause & 0xff));
}

/* Called in S: install the S trap vector and stack. */
static inline void st_s_init(void) {
    csr_write(stvec, (uint64_t)st_s_trap_entry);
    csr_write(sscratch, (uint64_t)(g_st_sstack + ST_SSTACK_BYTES));
}

/* SBI-style timer forwarding (what OpenSBI does for Linux): S asks for a
 * timer via ST_ECALL_SET_TIMER; when MTIP fires, M disarms it and raises
 * STIP, which S sees as a supervisor timer interrupt (mideleg[5]).  Install
 * with g_m_irq_hook = st_sbi_timer_hook. */
static int st_sbi_timer_hook(st_frame_t *f) {
    if (f->cause == (CAUSE_INTR | IRQ_M_TIMER)) {
        CLINT_MTIMECMP = ~0UL;
        csr_clear(mie, MIP_MTIP);
        csr_set(mip, MIP_STIP);
        return 1;
    }
    return 0;
}

/* ======================================================================= */
/*  Instruction encoders (code generation for SMC / JIT tests)              */
/* ======================================================================= */
static inline uint32_t enc_r(uint32_t f7, uint32_t rs2, uint32_t rs1, uint32_t f3, uint32_t rd, uint32_t op) {
    return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op;
}
static inline uint32_t enc_i(int32_t imm, uint32_t rs1, uint32_t f3, uint32_t rd, uint32_t op) {
    return ((uint32_t)(imm & 0xfff) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op;
}
static inline uint32_t enc_s(int32_t imm, uint32_t rs2, uint32_t rs1, uint32_t f3, uint32_t op) {
    return ((uint32_t)((imm >> 5) & 0x7f) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((uint32_t)(imm & 0x1f) << 7) | op;
}
static inline uint32_t enc_u(uint32_t imm20, uint32_t rd, uint32_t op) { return (imm20 << 12) | (rd << 7) | op; }
#define ENC_ADDI(rd, rs1, imm) enc_i((imm), (rs1), 0, (rd), 0x13)
#define ENC_RET                0x00008067u
#define ENC_NOP                0x00000013u
#define ENC_C_NOP              0x0001u

/* Store an instruction at any 2-byte-aligned address with halfword stores
 * (a 4-byte store to a 2-mod-4 address would itself be misaligned). */
static inline void st_put_insn32(uint64_t a, uint32_t insn) {
    *(volatile uint16_t *)a = (uint16_t)insn;
    *(volatile uint16_t *)(a + 2) = (uint16_t)(insn >> 16);
}
static inline uint32_t st_get_insn32(uint64_t a) {
    return *(volatile uint16_t *)a | ((uint32_t)*(volatile uint16_t *)(a + 2) << 16);
}
/* `li rd, imm32` as lui + addiw (2 instructions, 8 bytes). */
static inline uint64_t st_put_li32(uint64_t a, uint32_t rd, int32_t imm) {
    uint32_t hi = ((uint32_t)imm + 0x800u) >> 12;
    st_put_insn32(a, enc_u(hi & 0xfffff, rd, 0x37));
    st_put_insn32(a + 4, enc_i(imm & 0xfff, rd, 0, rd, 0x1b));
    return a + 8;
}

/* ======================================================================= */
/*  Init                                                                    */
/* ======================================================================= */
static inline void st_init(void) {
    csr_write(mtvec, (uint64_t)st_trap_entry);
    csr_write(mscratch, (uint64_t)(g_st_mstack + ST_MSTACK_BYTES));
    csr_write(mie, 0);
    csr_clear(mstatus, MSTATUS_MIE | MSTATUS_SIE | MSTATUS_MPRV | MSTATUS_SUM | MSTATUS_MXR |
                       MSTATUS_TVM | MSTATUS_TW | MSTATUS_TSR);
    csr_write(medeleg, 0);
    csr_write(mideleg, 0);
    csr_write(satp, 0);
    pmp_allow_all();
    sfence_all();
#ifdef ST_DUMMY_INSERT
    /* CI variant: AMOEBA random dummy-instruction insertion (custom CSR 0x7c1)
     * under the whole test.  Dummies are architecturally invisible, so every
     * result must be unchanged. */
    csr_write(0x7c1, (uint64_t)(ST_DUMMY_INSERT));
#endif
    st_puts("[ST] seed "); st_putdec((uint64_t)SEED); st_putc('\n');
}

#endif /* STRESS_H */
