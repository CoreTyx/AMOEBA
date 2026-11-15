// tc_cow_fault.c
// Demand paging and copy-on-write, as Linux does them for userland/mem.c.
//
// A U-mode body touches Sv39 pages whose leaf entries start out invalid; an
// M-mode trap handler plays the kernel.  A load fault maps the shared zero page
// read-only, a store fault on an invalid entry maps a fresh zeroed frame, and a
// store fault on the zero page copies on write: fresh frame, entry cleared,
// sfence.vma va,asid, new writable entry, sfence.vma va.  Each fault returns to
// the faulting store, whose fetch then misses the ITLB.
//
// The fill loops are placed by hand so the faulting sd sits at offset 0xc
// (fill_c, as in Linux's mem binary) or 0xe (fill_e, spills) of a 16-byte I$
// line: a fetch there predicts the next PC in the next line.  The I$ used to
// read that line's set during the ITLB miss and then take it for a hit on the
// faulting PC, so the store was replaced by the instruction one line on, and
// every page lost its first word.
//
// Sv39, ASID 1:
//   root[2]                    0x0_8000_0000  1 GiB identity leaf, U (program, stack)
//   root[3] -> l1[0] -> l0[i]  0x0_C000_0000 + i * 4 KiB, demand-paged

#include "test_utils.h"

#define PTE_V 0x01UL
#define PTE_R 0x02UL
#define PTE_W 0x04UL
#define PTE_X 0x08UL
#define PTE_U 0x10UL
#define PTE_A 0x40UL
#define PTE_D 0x80UL

#define CAUSE_ECALL_U     8
#define CAUSE_LOAD_PAGE   13
#define CAUSE_STORE_PAGE  15

#define PAGE      4096UL
#define VA_BASE   0x0C0000000UL
#define ZERO_PA   0x081000000UL
#define POOL_PA   0x081001000UL
#define ASID      1UL

#define NPG_MMAP  4
#define NPG_BRK   2
#define PG_BRK    0
#define PG_MMAP0  (PG_BRK + NPG_BRK)
#define PG_MMAP1  (PG_MMAP0 + NPG_MMAP)
#define NL0       (PG_MMAP1 + NPG_MMAP)

static uint64_t root_table[512] __attribute__((aligned(4096)));
static uint64_t l1_table[512]   __attribute__((aligned(4096)));
static uint64_t l0_table[512]   __attribute__((aligned(4096)));
static uint64_t m_stack[1024]   __attribute__((aligned(16)));

volatile uint64_t next_frame;
volatile uint64_t n_zero_maps, n_anon_maps, n_cow, n_spurious, n_bad_trap;
volatile uint64_t bad_cause, bad_tval, bad_epc;
volatile uint64_t saved_ctx[16];

volatile uint64_t r_notzero[2];
volatile uint64_t r_bad[3], r_first[3], r_got[3], r_reread[3];
volatile uint64_t r_badpages[3];

static uint64_t leaf(uint64_t pa, uint64_t bits) { return ((pa >> 12) << 10) | bits | PTE_V; }
static uint64_t pte_pa(uint64_t pte) { return (pte >> 10) << 12; }

static void zero_frame(uint64_t pa) {
    volatile uint64_t *p = (volatile uint64_t *)pa;
    for (unsigned i = 0; i < PAGE / 8; i++)
        p[i] = 0;
}

static uint64_t alloc_zeroed(void) {
    uint64_t pa = next_frame;
    next_frame = pa + PAGE;
    zero_frame(pa);
    return pa;
}

static inline void sfence_va(uint64_t va) { __asm__ volatile ("sfence.vma %0" : : "r"(va) : "memory"); }
static inline void sfence_va_asid(uint64_t va) { __asm__ volatile ("sfence.vma %0, %1" : : "r"(va), "r"(ASID) : "memory"); }

extern void user_return(void);

__attribute__((used, noinline)) void handle_trap(uint64_t cause, uint64_t tval, uint64_t epc) {
    uint64_t pg = (tval - VA_BASE) / PAGE;
    uint64_t va = tval & ~(PAGE - 1);

    if (cause == CAUSE_ECALL_U) {
        __asm__ volatile ("csrw mepc, %0" : : "r"((uint64_t)user_return));
        __asm__ volatile ("csrs mstatus, %0" : : "r"(0x1800UL));
        return;
    }
    if ((cause == CAUSE_LOAD_PAGE || cause == CAUSE_STORE_PAGE) && tval >= VA_BASE && pg < NL0) {
        uint64_t pte = l0_table[pg];
        if (!(pte & PTE_V)) {
            if (cause == CAUSE_LOAD_PAGE) {
                l0_table[pg] = leaf(ZERO_PA, PTE_A | PTE_U | PTE_R);
                n_zero_maps++;
            } else {
                l0_table[pg] = leaf(alloc_zeroed(), PTE_D | PTE_A | PTE_U | PTE_W | PTE_R);
                n_anon_maps++;
            }
            sfence_va(va);
            return;
        }
        if (cause == CAUSE_STORE_PAGE && pte_pa(pte) == ZERO_PA) {
            uint64_t frame = alloc_zeroed();
            l0_table[pg] = 0;
            sfence_va_asid(va);
            l0_table[pg] = leaf(frame, PTE_D | PTE_A | PTE_U | PTE_W | PTE_R);
            sfence_va(va);
            n_cow++;
            return;
        }
        n_spurious++;
        sfence_va(va);
        if (n_spurious < 1000)
            return;
    }
    n_bad_trap++;
    bad_cause = cause;
    bad_tval = tval;
    bad_epc = epc;
    __asm__ volatile ("csrw mepc, %0" : : "r"((uint64_t)user_return));
    __asm__ volatile ("csrs mstatus, %0" : : "r"(0x1800UL));
}

__asm__ (
    ".text\n"
    ".align 2\n"
    ".globl trap_entry\n"
    "trap_entry:\n"
    "    csrrw sp, mscratch, sp\n"
    "    addi sp, sp, -256\n"
    "    sd x1, 8(sp)\n   sd x3, 24(sp)\n  sd x4, 32(sp)\n  sd x5, 40(sp)\n"
    "    sd x6, 48(sp)\n  sd x7, 56(sp)\n  sd x8, 64(sp)\n  sd x9, 72(sp)\n"
    "    sd x10, 80(sp)\n sd x11, 88(sp)\n sd x12, 96(sp)\n sd x13, 104(sp)\n"
    "    sd x14, 112(sp)\n sd x15, 120(sp)\n sd x16, 128(sp)\n sd x17, 136(sp)\n"
    "    sd x18, 144(sp)\n sd x19, 152(sp)\n sd x20, 160(sp)\n sd x21, 168(sp)\n"
    "    sd x22, 176(sp)\n sd x23, 184(sp)\n sd x24, 192(sp)\n sd x25, 200(sp)\n"
    "    sd x26, 208(sp)\n sd x27, 216(sp)\n sd x28, 224(sp)\n sd x29, 232(sp)\n"
    "    sd x30, 240(sp)\n sd x31, 248(sp)\n"
    "    csrr a0, mcause\n  csrr a1, mtval\n  csrr a2, mepc\n"
    "    call handle_trap\n"
    "    ld x1, 8(sp)\n   ld x3, 24(sp)\n  ld x4, 32(sp)\n  ld x5, 40(sp)\n"
    "    ld x6, 48(sp)\n  ld x7, 56(sp)\n  ld x8, 64(sp)\n  ld x9, 72(sp)\n"
    "    ld x10, 80(sp)\n ld x11, 88(sp)\n ld x12, 96(sp)\n ld x13, 104(sp)\n"
    "    ld x14, 112(sp)\n ld x15, 120(sp)\n ld x16, 128(sp)\n ld x17, 136(sp)\n"
    "    ld x18, 144(sp)\n ld x19, 152(sp)\n ld x20, 160(sp)\n ld x21, 168(sp)\n"
    "    ld x22, 176(sp)\n ld x23, 184(sp)\n ld x24, 192(sp)\n ld x25, 200(sp)\n"
    "    ld x26, 208(sp)\n ld x27, 216(sp)\n ld x28, 224(sp)\n ld x29, 232(sp)\n"
    "    ld x30, 240(sp)\n ld x31, 248(sp)\n"
    "    addi sp, sp, 256\n"
    "    csrrw sp, mscratch, sp\n"
    "    mret\n"
    ".align 2\n"
    ".globl run_user\n"
    "run_user:\n"
    "    la t0, saved_ctx\n"
    "    sd ra, 0(t0)\n  sd sp, 8(t0)\n  sd s0, 16(t0)\n  sd s1, 24(t0)\n"
    "    sd s2, 32(t0)\n sd s3, 40(t0)\n sd s4, 48(t0)\n sd s5, 56(t0)\n"
    "    sd s6, 64(t0)\n sd s7, 72(t0)\n sd s8, 80(t0)\n sd s9, 88(t0)\n"
    "    sd s10, 96(t0)\n sd s11, 104(t0)\n"
    "    csrw mepc, a0\n"
    "    li t0, 0x1800\n  csrc mstatus, t0\n"
    "    la ra, user_exit\n"
    "    mret\n"
    ".align 2\n"
    "user_exit:\n"
    "    ecall\n"
    ".align 2\n"
    ".globl user_return\n"
    "user_return:\n"
    "    la t0, saved_ctx\n"
    "    ld ra, 0(t0)\n  ld sp, 8(t0)\n  ld s0, 16(t0)\n  ld s1, 24(t0)\n"
    "    ld s2, 32(t0)\n ld s3, 40(t0)\n ld s4, 48(t0)\n ld s5, 56(t0)\n"
    "    ld s6, 64(t0)\n ld s7, 72(t0)\n ld s8, 80(t0)\n ld s9, 88(t0)\n"
    "    ld s10, 96(t0)\n ld s11, 104(t0)\n"
    "    ret\n"
);
extern void trap_entry(void);
extern void run_user(void (*fn)(void));

// ---- U-mode ----

__asm__ (
    ".text\n"
    ".option push\n"
    ".option norvc\n"
    ".balign 16\n"
    ".globl fill_c\n"
    "fill_c:\n"
    "    nop\n"
    "    nop\n"
    "1:  xor t0, a0, a2\n"
    "    sd t0, 0(a0)\n"
    "    addi a0, a0, 8\n"
    "    bltu a0, a1, 1b\n"
    "    ret\n"
    ".balign 16\n"
    ".globl fill_e\n"
    "fill_e:\n"
    "    nop\n"
    "    nop\n"
    ".option rvc\n"
    "    c.nop\n"
    ".option norvc\n"
    "2:  xor t0, a0, a2\n"
    "    sd t0, 0(a0)\n"
    "    addi a0, a0, 8\n"
    "    bltu a0, a1, 2b\n"
    "    ret\n"
    ".option pop\n"
);
extern void fill_c(uint64_t base, uint64_t end, uint64_t seed);
extern void fill_e(uint64_t base, uint64_t end, uint64_t seed);

static void check_region(int r, uint64_t base, uint64_t npages, uint64_t seed) {
    volatile uint64_t *p = (volatile uint64_t *)base;
    uint64_t n = npages * PAGE / 8, bad = 0;
    for (uint64_t i = 0; i < n; i++) {
        uint64_t v = p[i];
        if (v != ((base + 8 * i) ^ seed)) {
            if (!bad++) {
                r_first[r] = i;
                r_got[r] = v;
            }
            r_badpages[r] |= 1UL << (i * 8 / PAGE);
        }
    }
    r_bad[r] = bad;
    if (bad)
        r_reread[r] = p[r_first[r]];
}

static void user_body(void) {
    uint64_t b = VA_BASE + PG_BRK * PAGE;
    fill_c(b, b + NPG_BRK * PAGE, 0x1111);
    check_region(0, b, NPG_BRK, 0x1111);
    for (int round = 0; round < 2; round++) {
        uint64_t base = VA_BASE + (round ? PG_MMAP1 : PG_MMAP0) * PAGE;
        for (uint64_t off = 0; off < NPG_MMAP * PAGE; off += PAGE)
            if (*(volatile uint64_t *)(base + off) != 0)
                r_notzero[round]++;
        (round ? fill_e : fill_c)(base, base + NPG_MMAP * PAGE, 0x2222 + round);
        check_region(1 + round, base, NPG_MMAP, 0x2222 + round);
    }
}

// ---- M-mode ----

int main(void) {
    for (int i = 0; i < 512; i++) {
        root_table[i] = 0;
        l1_table[i] = 0;
        l0_table[i] = 0;
    }
    zero_frame(ZERO_PA);
    next_frame = POOL_PA;

    root_table[2] = leaf(0x80000000UL, PTE_D | PTE_A | PTE_U | PTE_X | PTE_W | PTE_R);
    root_table[3] = ((uint64_t)l1_table >> 12) << 10 | PTE_V;
    l1_table[0]   = ((uint64_t)l0_table >> 12) << 10 | PTE_V;

    __asm__ volatile ("csrw pmpaddr0, %0" : : "r"(~0UL));
    __asm__ volatile ("csrw pmpcfg0, %0"  : : "r"(0x1fUL));
    __asm__ volatile ("csrw mscratch, %0" : : "r"((uint64_t)&m_stack[1024]));
    __asm__ volatile ("csrw mtvec, %0" : : "r"((uint64_t)trap_entry));
    __asm__ volatile ("csrw satp, %0"  : : "r"((8UL << 60) | (ASID << 44) | ((uint64_t)root_table >> 12)));
    __asm__ volatile ("sfence.vma");

    run_user(user_body);

    __asm__ volatile ("csrw satp, zero");
    __asm__ volatile ("sfence.vma");

    static const char *const names[3] = { "brk (store first)", "mmap, COW store at line offset 0xc",
                                          "mmap, COW store at line offset 0xe (spill)" };
    test_begin("kernel side");
    check("no unexpected trap", n_bad_trap, 0);
    if (n_bad_trap) {
        uart_puts("    cause "); uart_puthex64(bad_cause);
        uart_puts(" tval "); uart_puthex64(bad_tval);
        uart_puts(" epc "); uart_puthex64(bad_epc); uart_puts("\n");
    }
    check("zero-page maps", n_zero_maps, 2 * NPG_MMAP);
    check("anon maps", n_anon_maps, NPG_BRK);
    check("cow faults", n_cow, 2 * NPG_MMAP);
    check("spurious faults", n_spurious, 0);
    for (int r = 0; r < 3; r++) {
        test_begin(names[r]);
        if (r)
            check("first reads were zero", r_notzero[r - 1], 0);
        check("bad words", r_bad[r], 0);
        if (r_bad[r]) {
            uart_puts("    first "); uart_putu64(r_first[r]);
            uart_puts(" got "); uart_puthex64(r_got[r]);
            uart_puts(" reread "); uart_puthex64(r_reread[r]);
            uart_puts(" bad pages "); uart_puthex64(r_badpages[r]); uart_puts("\n");
        }
    }
    print_summary();
    test_finish();
}
