// @stress tier=pr seeds=2 nightly_seeds=8 weekly_seeds=64 build=no_spike duts=legacy,forte timeout=150000000
//
// st_minikernel -- context-switch storm and spawn/exit churn under a small
// preemptive S-mode kernel.  What Linux does all day, compressed:
//
//   - up to 16 live U processes, 64 spawned in total, 5 kinds of program
//   - every process has its own Sv39 address space with the SAME virtual
//     layout (data, stack, demand-paged heap) and its own ASID drawn from a
//     pool that, for odd seeds, is only 4 wide -- so ASIDs are constantly
//     reused and the kernel must `sfence.vma x0, asid` whenever an ASID
//     changes hands (the Linux ASID-allocator protocol)
//   - preemption by the supervisor timer every 500-2000 cycles through the
//     SBI set_timer path (M forwards MTIP as STIP), plus voluntary yields:
//     thousands of context switches, each one a full 31-register swap plus satp
//   - syscalls (getpid/yield/exit) and demand-paging faults delegated to S
//   - on exit every frame of the process -- tables included -- goes back to a
//     free list and is zeroed and reused by later processes
// Each program verifies its own private memory and returns a value the kernel
// predicts independently, so a leaked translation, a register lost in a
// switch, a stale TLB entry after ASID reuse or a frame recycled without a
// flush shows up as a wrong exit value.
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define NSLOT      16
#define NSPAWN     (64 * ST_SCALE)
#define ASID_POOL  ((SEED & 1) ? 4 : 256)
#define VA_DATA    0xC0000000UL      /* 4 pages, pid-tagged */
#define VA_STACK   0xC0200000UL      /* 2 pages */
#define VA_HEAP    0xC0400000UL      /* 16 pages, demand-paged */
#define HEAP_PAGES 16
#define WORK       400

enum { SYS_GETPID = 1, SYS_YIELD = 2, SYS_EXIT = 3 };
enum { P_FREE = 0, P_RUN = 1 };

typedef struct {
    int state;
    uint64_t pid, type, asid, root;
    st_frame_t frame;
    uint64_t frames[48];
    int nframes;
} proc_t;

static proc_t g_proc[NSLOT];
static int g_cur;
static uint64_t g_kroot;
static uint64_t g_next_pid = 1, g_spawned, g_exited, g_asid_next;
static proc_t *g_asid_owner[257];
static uint64_t g_free[2048];
static int g_nfree;
static volatile uint64_t g_switches, g_ticks, g_syscalls, g_pfaults, g_asid_flushes, g_bad_results, g_killed;
static uint64_t g_usp_top = VA_STACK + 2 * ST_PAGE;

/* ------------------------------------------------------------------ */
/* U programs (run through the U alias; touch only private VAs)        */
/* ------------------------------------------------------------------ */
static inline uint64_t u_sys(uint64_t n, uint64_t a) {
    register uint64_t a0 __asm__("a0") = a, a7 __asm__("a7") = n;
    __asm__ volatile ("ecall" : "+r"(a0) : "r"(a7) : "memory");
    return a0;
}
static inline uint64_t pat(uint64_t pid, uint64_t i) { return (pid << 40) ^ (i * 0x9E3779B97F4A7C15ULL); }

static uint64_t prog_value(uint64_t pid, uint64_t type) {   /* also used by the kernel as the model */
    uint64_t v = pid * 0x100000001ULL + type;
    for (uint64_t i = 0; i < WORK; i++) {
        switch (type) {
        case 0: v = v * 6364136223846793005ULL + i; break;
        case 1: v ^= pat(pid, i); break;
        case 2: v += pid; break;
        case 3: v += (pid ^ (i % HEAP_PAGES)) + i; break;
        default: v += 1; break;
        }
    }
    return v;
}

static void __attribute__((noreturn)) u_proc(uint64_t arg) {
    uint64_t pid = arg & 0xffff, type = arg >> 16, v = pid * 0x100000001ULL + type, err = 0;
    volatile uint64_t local[32];
    for (int i = 0; i < 32; i++) local[i] = pid + (uint64_t)i;
    volatile uint64_t *data = (volatile uint64_t *)VA_DATA;
    switch (type) {
    case 0:
        for (uint64_t i = 0; i < WORK; i++) v = v * 6364136223846793005ULL + i;
        break;
    case 1:   /* private memory, same VA in every process */
        for (uint64_t i = 0; i < WORK; i++) { data[(i * 5) % 2048] = pat(pid, i); if ((i & 63) == 63) u_sys(SYS_YIELD, 0); }
        for (uint64_t i = 0; i < WORK; i++) { uint64_t x = data[(i * 5) % 2048]; if (x != pat(pid, i)) err++; v ^= x; }
        break;
    case 2:   /* syscall spam */
        for (uint64_t i = 0; i < WORK; i++) { uint64_t r = u_sys(SYS_GETPID, 0); if (r != pid) err++; v += r; }
        break;
    case 3: { /* demand-paged heap */
        volatile uint64_t *heap = (volatile uint64_t *)VA_HEAP;
        for (uint64_t i = 0; i < WORK; i++) {
            uint64_t pg = i % HEAP_PAGES, idx = pg * 512 + (i / HEAP_PAGES) % 512;
            if (heap[idx] != 0 && i < HEAP_PAGES) err++;            /* fresh pages are zero */
            heap[idx] = (pid ^ pg) + i;
            v += heap[idx];
        }
        break; }
    default:  /* yield storm */
        for (uint64_t i = 0; i < WORK; i++) { u_sys(SYS_YIELD, 0); v += 1; }
        break;
    }
    for (int i = 0; i < 32; i++) if (local[i] != pid + (uint64_t)i) err++;   /* stack survived */
    u_sys(SYS_EXIT, v ^ (err << 56));
    for (;;) ;
}

/* ------------------------------------------------------------------ */
/* kernel                                                             */
/* ------------------------------------------------------------------ */
static uint64_t kalloc(proc_t *p) {
    uint64_t pa = g_nfree ? g_free[--g_nfree] : frame_alloc();
    st_zero_page(pa);
    if (p && p->nframes < 48) p->frames[p->nframes++] = pa;
    return pa;
}
static uint64_t *kslot(proc_t *p, uint64_t root, uint64_t va, int level) {
    uint64_t *t = (uint64_t *)root;
    for (int l = 2; l > level; l--) {
        uint64_t *e = &t[vpn(va, l)];
        if (!(*e & PTE_V)) *e = pte_table(kalloc(p));
        t = (uint64_t *)pte_pa(*e);
    }
    return &t[vpn(va, level)];
}

static void spawn(int slot) {
    proc_t *p = &g_proc[slot];
    p->nframes = 0;
    p->pid = g_next_pid++;
    p->type = p->pid % 5;
    p->root = kalloc(p);
    *kslot(p, p->root, ST_RAM_BASE, 2) = pte_leaf(ST_RAM_BASE, PTE_RWX | PTE_AD);           /* kernel */
    *kslot(p, p->root, 0, 2)           = pte_leaf(0, PTE_R | PTE_W | PTE_AD);                /* MMIO   */
    *kslot(p, p->root, ST_U_ALIAS_VA, 2) = pte_leaf(ST_RAM_BASE, PTE_RWX | PTE_AD | PTE_U);  /* U text */
    for (int i = 0; i < 4; i++) *kslot(p, p->root, VA_DATA + (uint64_t)i * ST_PAGE, 0) = pte_leaf(kalloc(p), PTE_R | PTE_W | PTE_U | PTE_AD);
    for (int i = 0; i < 2; i++) *kslot(p, p->root, VA_STACK + (uint64_t)i * ST_PAGE, 0) = pte_leaf(kalloc(p), PTE_R | PTE_W | PTE_U | PTE_AD);
    (void)kslot(p, p->root, VA_HEAP, 0);              /* heap table exists, leaves fault in */
    p->asid = 1 + (g_asid_next++ % ASID_POOL);
    sfence_asid(p->asid);                             /* a reused ASID may have stale entries */
    g_asid_owner[p->asid] = p;
    for (int i = 0; i < 32; i++) p->frame.x[i] = 0;
    p->frame.x[2]  = g_usp_top;
    p->frame.x[10] = p->pid | (p->type << 16);
    p->frame.epc   = st_u_alias((uint64_t)u_proc);
    p->frame.status = (csr_read(sstatus) & ~(MSTATUS_SPP | MSTATUS_SIE)) | MSTATUS_SPIE;
    p->state = P_RUN;
    g_spawned++;
}

static void reap(proc_t *p) {
    csr_write(satp, satp_sv39(0, g_kroot));          /* off the dying address space first */
    sfence_all();
    for (int i = 0; i < p->nframes; i++) if (g_nfree < (int)ST_ARRAY_LEN(g_free)) g_free[g_nfree++] = p->frames[i];
    if (g_asid_owner[p->asid] == p) g_asid_owner[p->asid] = 0;
    p->state = P_FREE;
}

static void load(proc_t *p, st_frame_t *f) {
    *f = p->frame;
    csr_write(satp, satp_sv39(p->asid, p->root));
    if (g_asid_owner[p->asid] != p) { sfence_asid(p->asid); g_asid_owner[p->asid] = p; g_asid_flushes++; }
}

static int pick_next(void) {
    for (int k = 1; k <= NSLOT; k++) { int s = (g_cur + k) % NSLOT; if (g_proc[s].state == P_RUN) return s; }
    return -1;
}

static void switch_from(st_frame_t *f, int save) {
    if (save) g_proc[g_cur].frame = *f;
    int n = pick_next();
    if (n < 0) {                                       /* everyone is done: back to kmain */
        csr_write(satp, satp_sv39(0, g_kroot));
        sfence_all();
        f->x[10] = 0;
        f->epc = (uint64_t)st_s_rim_resume;
        f->status = (f->status | MSTATUS_SPP) & ~MSTATUS_SPIE;
        return;
    }
    g_cur = n;
    g_switches++;
    load(&g_proc[n], f);
}

static void do_exit(st_frame_t *f, uint64_t code) {
    proc_t *p = &g_proc[g_cur];
    if (code != prog_value(p->pid, p->type)) {
        g_bad_results++;
        if (g_bad_results < 4) { st_puts("[ST] bad exit pid "); st_putdec(p->pid); st_puts(" type "); st_putdec(p->type);
                                 st_puts(" got "); st_puthex(code); st_puts(" want "); st_puthex(prog_value(p->pid, p->type)); st_putc('\n'); }
    }
    g_exited++;
    reap(p);
    if (g_spawned < NSPAWN) spawn(g_cur);
    switch_from(f, 0);
}

static int s_trap(st_frame_t *f) {
    if (f->cause == (CAUSE_INTR | IRQ_S_TIMER)) {
        g_ticks++;
        switch_from(f, 1);
        /* Arm the next slice AFTER the switch, so it is measured from the
         * return to U.  Measured (legacy, GCC 14): tick + SBI round trip +
         * switch costs ~6.5k cycles; armed first and only 500-2000 cycles
         * out, STIP was already pending at every sret, and 256 ticks / 255
         * switches ran 0 syscalls, 0 page faults, 0 exits -- no process ever
         * got past its first loop (CI: timeout on legacy and forte). */
        st_ecall(ST_ECALL_SET_TIMER, st_mtime() + 3000 + st_rand_range(5000));
        return 1;
    }
    if (f->cause == CAUSE_ECALL_U) {
        g_syscalls++;
        f->epc += 4;
        switch (f->x[17]) {
        case SYS_GETPID: f->x[10] = g_proc[g_cur].pid; return 1;
        case SYS_YIELD:  switch_from(f, 1); return 1;
        case SYS_EXIT:   do_exit(f, f->x[10]); return 1;
        default: return 0;
        }
    }
    if (f->cause == CAUSE_LOAD_PAGE || f->cause == CAUSE_STORE_PAGE) {
        proc_t *p = &g_proc[g_cur];
        if (f->tval >= VA_HEAP && f->tval < VA_HEAP + HEAP_PAGES * ST_PAGE) {
            uint64_t va = f->tval & ~(ST_PAGE - 1);
            *kslot(p, p->root, va, 0) = pte_leaf(kalloc(p), PTE_R | PTE_W | PTE_U | PTE_AD);
            sfence_va_asid(va, p->asid);
            g_pfaults++;
            return 1;
        }
        g_killed++;                                    /* wild access: kill the process */
        do_exit(f, ~0UL);
        return 1;
    }
    return 0;
}

static uint8_t g_boot_ustack[1024] ST_ALIGNED(16);

static uint64_t kmain(uint64_t a) {
    (void)a;
    st_s_init();
    g_s_hook = s_trap;
    g_kroot = pt_new_identity_root(0);
    g_st_u_alias_off = ST_U_ALIAS_VA - ST_RAM_BASE;
    for (int s = 0; s < NSLOT; s++) spawn(s);
    csr_set(sie, MIP_STIP);
    st_ecall(ST_ECALL_SET_TIMER, st_mtime() + 1000);
    /* enter process 0; its frame is captured on its first trap */
    g_cur = 0;
    proc_t *p = &g_proc[0];
    csr_write(satp, satp_sv39(p->asid, p->root));
    g_asid_owner[p->asid] = p;
    (void)g_boot_ustack;
    uint64_t r = st_s_run_user((uint64_t (*)(uint64_t))p->frame.epc, p->frame.x[10], p->frame.x[2]);
    st_ecall(ST_ECALL_SET_TIMER, ~0UL);
    csr_clear(sie, MIP_STIP);
    g_s_hook = 0;
    return r;
}

int main(void) {
    st_init();
    g_m_irq_hook = st_sbi_timer_hook;
    csr_write(mideleg, MIP_STIP | MIP_SSIP);
    csr_write(medeleg, (1UL << CAUSE_ECALL_U) | (1UL << CAUSE_LOAD_PAGE) | (1UL << CAUSE_STORE_PAGE));
    st_section("preemptive multi-process kernel");
    (void)st_run(PRV_S, kmain, 0);
    csr_write(medeleg, 0);
    csr_write(mideleg, 0);
    st_timer_off();
    csr_write(satp, 0);
    sfence_all();

    st_puts("[ST] spawned "); st_putdec(g_spawned); st_puts(" exited "); st_putdec(g_exited);
    st_puts(" switches "); st_putdec(g_switches); st_puts(" ticks "); st_putdec(g_ticks);
    st_puts(" syscalls "); st_putdec(g_syscalls); st_puts(" heap faults "); st_putdec(g_pfaults);
    st_puts(" asid flushes "); st_putdec(g_asid_flushes); st_puts(" asid pool "); st_putdec(ASID_POOL); st_putc('\n');
    ST_CHECK_EQ("every process spawned", g_spawned, NSPAWN);
    ST_CHECK_EQ("every process exited", g_exited, NSPAWN);
    ST_CHECK_EQ("every exit value matched the model", g_bad_results, 0);
    ST_CHECK_EQ("no process was killed for a wild access", g_killed, 0);
    ST_CHECK("thousands of context switches", g_switches >= 1000);
    ST_CHECK("preemption happened", g_ticks > 20);
    ST_CHECK("demand paging happened", g_pfaults > 0);
    if (ASID_POOL < NSLOT) ST_CHECK("ASIDs were reused under contention", g_asid_flushes > 0);
    return st_result();
}
