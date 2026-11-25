// @stress tier=pr seeds=2 nightly_seeds=8 build=no_spike duts=legacy,forte timeout=30000000
//
// st_asid_switch -- the same virtual addresses in 8 address spaces, switched
// with satp alone (no sfence), as Linux does on every context switch when the
// ASID allocator has a live ASID for the next mm.
//
// With 8-entry TLBs shared by all address spaces, entries from several ASIDs
// are resident at once.  A TLB that ignores the ASID tag, or matches it with
// the wrong width (ASID_BITS = 16), hands one process another's pages -- the
// worst possible post-tapeout bug, because nothing crashes.  Also covered:
//   - global (G) mappings are shared across ASIDs and survive ASID switches
//   - reusing an ASID for a NEW address space after `sfence.vma x0, asid`
//   - ASIDs that differ only in their top bit (catches a truncated compare)
//   - instruction fetch per address space (ITLB tagging), from U
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif
#define NSPACES  8
#define NPAGES   6
#define VA_DATA  0xC0000000UL
#define VA_CODE  0xC4000000UL
#define VA_GLOB  0xC8000000UL
#define SWITCHES (600 * ST_SCALE)

static uint64_t g_root[NSPACES], g_asid[NSPACES], g_frame[NSPACES][NPAGES];
static uint64_t g_gframe;

static inline uint64_t mark(int s, int p, uint64_t gen) { return st_mix64(((uint64_t)s << 40) ^ ((uint64_t)p << 20) ^ gen); }

static void write_code(uint64_t pa, uint32_t val) {
    volatile uint32_t *c = (volatile uint32_t *)pa;
    c[0] = ((val + 0x800) & 0xfffff000u) | (10u << 7) | 0x37;
    c[1] = ((val & 0xfff) << 20) | (10u << 15) | (10u << 7) | 0x1b;
    c[2] = 0x00008067;
}

static uint64_t g_gen[NSPACES];

static void build_space(int s, uint64_t asid) {
    g_root[s] = pt_new_identity_root(0);
    map_giga(g_root[s], ST_U_ALIAS_VA, ST_RAM_BASE, PTE_RWX | PTE_AD | PTE_U);
    g_asid[s] = asid;
    for (int p = 0; p < NPAGES; p++) {
        g_frame[s][p] = frame_alloc();
        map_page(g_root[s], VA_DATA + (uint64_t)p * ST_PAGE, g_frame[s][p], PTE_R | PTE_W | PTE_AD);
        *(volatile uint64_t *)(g_frame[s][p] + 8 * (uint64_t)p) = mark(s, p, g_gen[s]);
    }
    uint64_t code = frame_alloc();
    write_code(code, 0x100000u + (uint32_t)s * 0x1111u + (uint32_t)(g_gen[s] & 0xff));
    map_page(g_root[s], VA_CODE, code, PTE_R | PTE_X | PTE_U | PTE_A);
    map_page(g_root[s], VA_GLOB, g_gframe, PTE_R | PTE_W | PTE_AD | PTE_G);
}

int main(void) {
    st_init();
    g_st_u_alias_off = ST_U_ALIAS_VA - ST_RAM_BASE;
    uint64_t usp = st_u_alias((uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    g_gframe = frame_alloc();

    st_section("build 8 address spaces (ASIDs differ in high bits too)");
    static const uint64_t asids[NSPACES] = { 1, 2, 0x8001, 0x8002, 0x4001, 0x0100, 0xffff, 0x7fff };
    for (int s = 0; s < NSPACES; s++) build_space(s, asids[s]);
    st_fence_i();
    sfence_all();

    st_section("random satp switches without sfence");
    uint64_t bad_data = 0, bad_code = 0, bad_glob = 0, glob = 0;
    for (int i = 0; i < SWITCHES; i++) {
        int s = (int)st_rand_range(NSPACES);
        csr_write(satp, satp_sv39(g_asid[s], g_root[s]));
        int p = (int)st_rand_range(NPAGES);
        uint64_t v = 0;
        if (probe_ld(VA_DATA + (uint64_t)p * ST_PAGE + 8 * (uint64_t)p, PRV_S, &v) || v != mark(s, p, g_gen[s])) {
            bad_data++;
            if (bad_data < 4) st_check_failed("data from another address space", v, mark(s, p, g_gen[s]), __LINE__);
        }
        if ((i & 7) == 0) {
            uint64_t want = (uint64_t)(0x100000u + (uint32_t)s * 0x1111u + (uint32_t)(g_gen[s] & 0xff));
            uint64_t r = st_run_in_mode(PRV_U, (uint64_t (*)(uint64_t))VA_CODE, 0, usp);
            if (r != want) { bad_code++; if (bad_code < 4) st_check_failed("code from another address space", r, want, __LINE__); }
        }
        if ((i & 3) == 0) {   /* global page: shared, written through any ASID */
            (void)probe_sd(VA_GLOB, PRV_S, ++glob);
            (void)probe_ld(VA_GLOB, PRV_S, &v);
            if (v != glob) bad_glob++;
        }
        /* occasionally retire an ASID and reuse it for a fresh address space */
        if ((i % 97) == 96) {
            int t = (int)st_rand_range(NSPACES);
            g_gen[t]++;
            build_space(t, g_asid[t]);
            st_fence_i();
            sfence_asid(g_asid[t]);      /* the only fence Linux issues on ASID reuse */
        }
    }
    ST_CHECK_EQ("no cross-ASID data", bad_data, 0);
    ST_CHECK_EQ("no cross-ASID code", bad_code, 0);
    ST_CHECK_EQ("global page coherent across ASIDs", bad_glob, 0);

    st_section("ASID reuse without a flush of the OLD ASID must not leak");
    /* Space 0 is rebuilt under ASID 2's number after `sfence.vma x0, 2`. */
    csr_write(satp, satp_sv39(g_asid[1], g_root[1]));
    uint64_t v = 0;
    (void)probe_ld(VA_DATA, PRV_S, &v);                    /* warm ASID 2 */
    g_gen[1] += 100;
    build_space(1, g_asid[1]);
    st_fence_i();
    sfence_asid(g_asid[1]);
    csr_write(satp, satp_sv39(g_asid[1], g_root[1]));
    (void)probe_ld(VA_DATA, PRV_S, &v);
    ST_CHECK_EQ("reused ASID sees the new space", v, mark(1, 0, g_gen[1]));

    csr_write(satp, 0);
    sfence_all();
    return st_result();
}
