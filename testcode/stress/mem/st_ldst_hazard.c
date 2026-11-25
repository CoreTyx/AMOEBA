// @stress tier=pr seeds=2 nightly_seeds=8 build=spike duts=legacy timeout=20000000
// @stress-variant build=no_spike duts=forte
//
// st_ldst_hazard -- store immediately followed by an overlapping load.
//
// Every store width (sb/sh/sw/sd) x every load width and signedness
// (lb/lbu/lh/lhu/lw/lwu/ld) x every naturally-aligned offset pair inside a
// dword, back to back with nothing in between, so the load must see a
// partially-written dword: store-to-load forwarding / bypass, byte-enable
// merging, and sign extension all at once.  Each pattern runs on a hot line and
// on a line that is cold (miss on the store, then the load).  Expected values
// are computed byte-wise in C; under Spike co-simulation each load is also
// checked at retirement.
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define REPS (3 * ST_SCALE)

static uint64_t ldst_sb_lb(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sb %[v], 0(%[sa])\n\tlb %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sb_lbu(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sb %[v], 0(%[sa])\n\tlbu %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sb_lh(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sb %[v], 0(%[sa])\n\tlh %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sb_lhu(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sb %[v], 0(%[sa])\n\tlhu %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sb_lw(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sb %[v], 0(%[sa])\n\tlw %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sb_lwu(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sb %[v], 0(%[sa])\n\tlwu %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sb_ld(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sb %[v], 0(%[sa])\n\tld %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sh_lb(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sh %[v], 0(%[sa])\n\tlb %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sh_lbu(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sh %[v], 0(%[sa])\n\tlbu %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sh_lh(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sh %[v], 0(%[sa])\n\tlh %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sh_lhu(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sh %[v], 0(%[sa])\n\tlhu %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sh_lw(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sh %[v], 0(%[sa])\n\tlw %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sh_lwu(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sh %[v], 0(%[sa])\n\tlwu %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sh_ld(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sh %[v], 0(%[sa])\n\tld %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sw_lb(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sw %[v], 0(%[sa])\n\tlb %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sw_lbu(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sw %[v], 0(%[sa])\n\tlbu %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sw_lh(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sw %[v], 0(%[sa])\n\tlh %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sw_lhu(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sw %[v], 0(%[sa])\n\tlhu %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sw_lw(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sw %[v], 0(%[sa])\n\tlw %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sw_lwu(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sw %[v], 0(%[sa])\n\tlwu %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sw_ld(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sw %[v], 0(%[sa])\n\tld %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sd_lb(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sd %[v], 0(%[sa])\n\tlb %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sd_lbu(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sd %[v], 0(%[sa])\n\tlbu %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sd_lh(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sd %[v], 0(%[sa])\n\tlh %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sd_lhu(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sd %[v], 0(%[sa])\n\tlhu %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sd_lw(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sd %[v], 0(%[sa])\n\tlw %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sd_lwu(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sd %[v], 0(%[sa])\n\tlwu %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}
static uint64_t ldst_sd_ld(uint64_t sa, uint64_t la, uint64_t v) {
    uint64_t r;
    __asm__ volatile ("sd %[v], 0(%[sa])\n\tld %[r], 0(%[la])" : [r] "=&r"(r) : [v] "r"(v), [sa] "r"(sa), [la] "r"(la) : "memory");
    return r;
}

typedef struct { uint64_t (*fn)(uint64_t, uint64_t, uint64_t); int ss, ls, sgn; const char *name; } combo_t;
static const combo_t g_combo[] = {
    { ldst_sb_lb, 1, 1, 1, "sb->lb" },
    { ldst_sb_lbu, 1, 1, 0, "sb->lbu" },
    { ldst_sb_lh, 1, 2, 1, "sb->lh" },
    { ldst_sb_lhu, 1, 2, 0, "sb->lhu" },
    { ldst_sb_lw, 1, 4, 1, "sb->lw" },
    { ldst_sb_lwu, 1, 4, 0, "sb->lwu" },
    { ldst_sb_ld, 1, 8, 0, "sb->ld" },
    { ldst_sh_lb, 2, 1, 1, "sh->lb" },
    { ldst_sh_lbu, 2, 1, 0, "sh->lbu" },
    { ldst_sh_lh, 2, 2, 1, "sh->lh" },
    { ldst_sh_lhu, 2, 2, 0, "sh->lhu" },
    { ldst_sh_lw, 2, 4, 1, "sh->lw" },
    { ldst_sh_lwu, 2, 4, 0, "sh->lwu" },
    { ldst_sh_ld, 2, 8, 0, "sh->ld" },
    { ldst_sw_lb, 4, 1, 1, "sw->lb" },
    { ldst_sw_lbu, 4, 1, 0, "sw->lbu" },
    { ldst_sw_lh, 4, 2, 1, "sw->lh" },
    { ldst_sw_lhu, 4, 2, 0, "sw->lhu" },
    { ldst_sw_lw, 4, 4, 1, "sw->lw" },
    { ldst_sw_lwu, 4, 4, 0, "sw->lwu" },
    { ldst_sw_ld, 4, 8, 0, "sw->ld" },
    { ldst_sd_lb, 8, 1, 1, "sd->lb" },
    { ldst_sd_lbu, 8, 1, 0, "sd->lbu" },
    { ldst_sd_lh, 8, 2, 1, "sd->lh" },
    { ldst_sd_lhu, 8, 2, 0, "sd->lhu" },
    { ldst_sd_lw, 8, 4, 1, "sd->lw" },
    { ldst_sd_lwu, 8, 4, 0, "sd->lwu" },
    { ldst_sd_ld, 8, 8, 0, "sd->ld" },
};

static uint8_t g_cold[1 << 18] ST_ALIGNED(4096);

static uint64_t expect(uint64_t init, int so, int ss, uint64_t v, int lo, int ls, int sgn) {
    uint8_t b[8];
    for (int i = 0; i < 8; i++) b[i] = (uint8_t)(init >> (8 * i));
    for (int i = 0; i < ss; i++) b[so + i] = (uint8_t)(v >> (8 * i));
    uint64_t r = 0;
    for (int i = ls - 1; i >= 0; i--) r = (r << 8) | b[lo + i];
    if (sgn && ls < 8) { int sh = 64 - 8 * ls; r = (uint64_t)(((int64_t)(r << sh)) >> sh); }
    return r;
}

int main(void) {
    st_init();
    st_section("store -> overlapping load, all widths/offsets");
    uint64_t bad = 0, n = 0, cold = 0;
    static volatile uint64_t hot[4] ST_ALIGNED(64);
    for (int rep = 0; rep < REPS; rep++)
        for (unsigned c = 0; c < ST_ARRAY_LEN(g_combo); c++) {
            const combo_t *k = &g_combo[c];
            for (int so = 0; so + k->ss <= 8; so += k->ss)
                for (int lo = 0; lo + k->ls <= 8; lo += k->ls) {
                    uint64_t init = st_rand(), v = st_rand();
                    volatile uint64_t *cell;
                    uint64_t coff = 0;
                    if (n & 1) cell = &hot[n & 3];
                    else { coff = (cold++ * 1040) % (sizeof g_cold - 8) & ~7UL; cell = (volatile uint64_t *)(g_cold + coff); }
                    *cell = init;
                    if (!(n & 1)) {
                        /* push the cold cell out again: WAYS+1 other lines of the
                         * same set, all inside the zero-initialised .bss buffer
                         * (co-sim must never read memory the program did not set) */
                        for (uint64_t e = 1; e <= AMOEBA_DCACHE_NUMWAYS + 1; e++)
                            (void)*(volatile uint64_t *)(g_cold + (coff + e * AMOEBA_DCACHE_WAYSIZEINBYTES * 3) % (sizeof g_cold - 8));
                    }
                    uint64_t r = k->fn((uint64_t)cell + (uint64_t)so, (uint64_t)cell + (uint64_t)lo, v);
                    if (r != expect(init, so, k->ss, v, lo, k->ls, k->sgn)) {
                        bad++;
                        if (bad < 6) st_check_failed(k->name, r, expect(init, so, k->ss, v, lo, k->ls, k->sgn), so * 8 + lo);
                    }
                    n++;
                }
        }
    ST_CHECK_EQ("all store->load hazards", bad, 0);
    st_puts("[ST] cases: "); st_putdec(n); st_putc('\n');
    return st_result();
}
