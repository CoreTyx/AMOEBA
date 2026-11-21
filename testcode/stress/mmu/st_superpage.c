// @stress tier=pr build=no_spike duts=legacy,forte timeout=20000000
//
// st_superpage -- 2 MiB (megapage) and 1 GiB (gigapage) leaves.
//
// The Linux kernel maps its own image and the linear map with superpages, so
// every kernel access goes through one; userland gets them via THP.  The TLB
// must match a superpage entry for EVERY address inside it, keep its PPN
// bits from the VA for the levels below the leaf, invalidate it on an sfence.vma
// naming ANY address inside it, and refuse a misaligned superpage (low PPN bits
// set) with a page fault.  4 KiB tests never exercise any of that.
#include "../lib/stress.h"

#define VA_MEGA   0xC0200000UL       /* 2 MiB aligned */
#define VA_MEGA2  0xC0600000UL
#define VA_GIGA   0x140000000UL      /* vpn[2] = 5 */
#define VA_SMALL  0xC1000000UL
#define VA_BAD    0xC0A00000UL
#define VA_UCODE  0xC0E00000UL

static void fill_marks(uint64_t pa, uint64_t span, uint64_t stride, uint64_t salt) {
    for (uint64_t o = 0; o < span; o += stride) *(volatile uint64_t *)(pa + o) = st_mix64(pa + o + salt);
}
static int check_marks(uint64_t va, uint64_t pa, uint64_t span, uint64_t stride, uint64_t salt, uint64_t prv) {
    int bad = 0;
    for (uint64_t o = 0; o < span; o += stride) {
        uint64_t v = 0;
        if (probe_ld(va + o, prv, &v) || v != st_mix64(pa + o + salt)) bad++;
    }
    return bad;
}

int main(void) {
    st_init();
    uint64_t root = pt_new_identity_root(0);
    st_map_u_alias(root);
    uint64_t usp = st_u_alias((uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    uint64_t mpa0 = frame_alloc_aligned(ST_MEGAPAGE);
    g_next_frame = mpa0 + ST_MEGAPAGE;
    uint64_t mpa1 = frame_alloc_aligned(ST_MEGAPAGE);
    g_next_frame = mpa1 + ST_MEGAPAGE;
    /* stride walks every 4 KiB page of the megapage at a varying offset */
    fill_marks(mpa0, ST_MEGAPAGE, ST_PAGE + 8, 1);
    fill_marks(mpa1, ST_MEGAPAGE, ST_PAGE + 8, 2);
    csr_write(satp, satp_sv39(3, root));

    st_section("megapage: every 4K slice translates");
    map_mega(root, VA_MEGA, mpa0, PTE_R | PTE_W | PTE_AD);
    sfence_all();
    ST_CHECK_EQ("S reads through megapage", check_marks(VA_MEGA, mpa0, ST_MEGAPAGE, ST_PAGE + 8, 1, PRV_S), 0);
    ST_CHECK_EQ("store through megapage", probe_sd(VA_MEGA + 0x1ffff8, PRV_S, 0xfeedface), 0);
    ST_CHECK_EQ("  lands at PA + offset", *(volatile uint64_t *)(mpa0 + 0x1ffff8), 0xfeedface);

    st_section("sfence.vma on an INTERIOR address drops the megapage");
    map_mega(root, VA_MEGA, mpa1, PTE_R | PTE_W | PTE_AD);
    sfence_va(VA_MEGA + 0x12345 * 8);
    ST_CHECK_EQ("new megapage visible at every slice", check_marks(VA_MEGA, mpa1, ST_MEGAPAGE, ST_PAGE + 8, 2, PRV_S), 0);
    map_mega(root, VA_MEGA, mpa0, PTE_R | PTE_W | PTE_AD);
    sfence_va_asid(VA_MEGA + 0x1ff000, 3);
    ST_CHECK_EQ("va,asid form on last 4K slice", check_marks(VA_MEGA, mpa0, ST_MEGAPAGE, 3 * ST_PAGE + 8, 1, PRV_S), 0);

    st_section("gigapage over all of RAM");
    map_giga(root, VA_GIGA, ST_RAM_BASE, PTE_R | PTE_W | PTE_AD);
    sfence_all();
    ST_CHECK_EQ("gigapage reaches megapage frames", check_marks(VA_GIGA + (mpa0 - ST_RAM_BASE), mpa0, ST_MEGAPAGE, 7 * ST_PAGE + 8, 1, PRV_S), 0);
    uint64_t v = 0;
    ST_CHECK_EQ("gigapage reads image text", probe_ld((VA_GIGA + ((uint64_t)(void *)main - ST_RAM_BASE)) & ~7UL, PRV_S, &v), 0);
    ST_CHECK_EQ("  same bytes as identity", v, *(volatile uint64_t *)(((uint64_t)(void *)main) & ~7UL));

    st_section("mixed page sizes resident together");
    uint64_t small = frame_alloc();
    *(volatile uint64_t *)small = 0x5a11UL;
    map_page(root, VA_SMALL, small, PTE_R | PTE_W | PTE_AD);
    map_mega(root, VA_MEGA2, mpa1, PTE_R | PTE_AD);
    sfence_all();
    int bad = 0;
    for (int i = 0; i < 64; i++) {
        switch (i % 4) {
        case 0: (void)probe_ld(VA_SMALL, PRV_S, &v); bad += v != 0x5a11UL; break;
        case 1: (void)probe_ld(VA_MEGA + (uint64_t)(i * 4104 % 0x1fff8 & ~7), PRV_S, &v); bad += v != *(volatile uint64_t *)(mpa0 + (uint64_t)(i * 4104 % 0x1fff8 & ~7)); break;
        case 2: (void)probe_ld(VA_MEGA2 + (uint64_t)(i * 8200 % 0x1fff8 & ~7), PRV_S, &v); bad += v != *(volatile uint64_t *)(mpa1 + (uint64_t)(i * 8200 % 0x1fff8 & ~7)); break;
        default: (void)probe_ld(VA_GIGA + 0x800000, PRV_S, &v); bad += v != *(volatile uint64_t *)(ST_RAM_BASE + 0x800000); break;
        }
    }
    ST_CHECK_EQ("interleaved 4K/2M/2M/1G lookups", bad, 0);

    st_section("superpage permissions and Svade A/D");
    ST_CHECK_EQ("store to RO megapage faults", probe_sd(VA_MEGA2 + 64, PRV_S, 1), 1);
    ST_CHECK_EQ("  cause", g_trap_cause, CAUSE_STORE_PAGE);
    ST_CHECK_EQ("  tval", g_trap_tval, VA_MEGA2 + 64);
    map_mega(root, VA_MEGA2, mpa1, PTE_R | PTE_W | PTE_A);     /* D = 0 */
    sfence_va(VA_MEGA2);
    ST_CHECK_EQ("store to D=0 megapage faults (no Svadu)", probe_sd(VA_MEGA2 + 0x100008, PRV_S, 1), 1);
    ST_CHECK_EQ("  cause", g_trap_cause, CAUSE_STORE_PAGE);
    map_mega(root, VA_MEGA2, mpa1, PTE_R | PTE_W | PTE_D);     /* A = 0 */
    sfence_va(VA_MEGA2 + 0x40000);
    ST_CHECK_EQ("load from A=0 megapage faults", probe_ld(VA_MEGA2 + 0x1f0000, PRV_S, &v), 1);
    ST_CHECK_EQ("  cause", g_trap_cause, CAUSE_LOAD_PAGE);
    ST_CHECK_EQ("U access to S megapage faults", probe_ld(VA_MEGA + 8, PRV_U, &v), 1);
    ST_CHECK_EQ("  cause", g_trap_cause, CAUSE_LOAD_PAGE);

    st_section("misaligned superpages fault");
    map_mega(root, VA_BAD, mpa0 + ST_PAGE, PTE_R | PTE_W | PTE_AD);     /* ppn[0] != 0 */
    sfence_all();
    ST_CHECK_EQ("misaligned megapage load", probe_ld(VA_BAD, PRV_S, &v), 1);
    ST_CHECK_EQ("  cause", g_trap_cause, CAUSE_LOAD_PAGE);
    ST_CHECK_EQ("  tval", g_trap_tval, VA_BAD);
    uint64_t before = *(volatile uint64_t *)(mpa0 + 2 * ST_PAGE);
    ST_CHECK_EQ("misaligned megapage store", probe_sd(VA_BAD + 0x1000, PRV_S, 0xbad0bad0UL), 1);
    ST_CHECK_EQ("  cause", g_trap_cause, CAUSE_STORE_PAGE);
    ST_CHECK_EQ("  frame untouched", *(volatile uint64_t *)(mpa0 + 2 * ST_PAGE), before);
    map_giga(root, VA_GIGA, ST_RAM_BASE + ST_MEGAPAGE, PTE_R | PTE_W | PTE_AD);   /* ppn[1] != 0 */
    sfence_va(VA_GIGA);
    ST_CHECK_EQ("misaligned gigapage load", probe_ld(VA_GIGA + 0x800000, PRV_S, &v), 1);
    ST_CHECK_EQ("  cause", g_trap_cause, CAUSE_LOAD_PAGE);

    st_section("execute from a megapage in U");
    uint64_t cpa = frame_alloc_aligned(ST_MEGAPAGE);
    g_next_frame = cpa + ST_MEGAPAGE;
    for (uint64_t off = 0; off < ST_MEGAPAGE; off += 0x40000) {
        volatile uint32_t *c = (volatile uint32_t *)(cpa + off);
        uint32_t val = (uint32_t)(off >> 12) + 7;
        c[0] = (val << 20) | (10u << 7) | 0x13;          /* addi a0, x0, val */
        c[1] = 0x00008067;
    }
    st_fence_i();
    map_mega(root, VA_UCODE, cpa, PTE_R | PTE_X | PTE_U | PTE_A);
    sfence_all();
    bad = 0;
    for (uint64_t off = 0; off < ST_MEGAPAGE; off += 0x40000) {
        uint64_t r = st_run_in_mode(PRV_U, (uint64_t (*)(uint64_t))(VA_UCODE + off), 0, usp);
        bad += r != (off >> 12) + 7;
    }
    ST_CHECK_EQ("8 entry points across the megapage", bad, 0);

    csr_write(satp, 0);
    sfence_all();
    return st_result();
}
