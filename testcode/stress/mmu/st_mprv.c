// @stress tier=pr build=no_spike duts=legacy,forte timeout=20000000
//
// st_mprv -- M-mode loads/stores with MPRV, the mechanism OpenSBI uses to read
// and write S/U memory (misaligned-access emulation, SBI calls taking pointers).
//
// For every combination of {MPP = S, U} x {SUM} x {MXR} x {page: U/S x RW/RO/X}
// x {load, store}, the outcome must match the spec's permission rules exactly.
// Also: MPRV must not affect M's own instruction fetches; MPRV with MPP = M is
// untranslated; an mret to a lower mode clears MPRV.
#include "../lib/stress.h"

#define VA 0xC0000000UL

typedef struct { const char *name; uint64_t bits; } pg_t;
static const pg_t g_pages[] = {
    { "U RW", PTE_U | PTE_R | PTE_W }, { "U RO", PTE_U | PTE_R }, { "U X", PTE_U | PTE_X },
    { "S RW", PTE_R | PTE_W },         { "S RO", PTE_R },         { "S X", PTE_X },
    { "U RX", PTE_U | PTE_R | PTE_X },
};

static int model_allows(uint64_t bits, uint64_t prv, int sum, int mxr, int store) {
    int u = !!(bits & PTE_U);
    if (prv == PRV_U && !u) return 0;
    if (prv == PRV_S && u && !sum) return 0;
    if (store) return !!(bits & PTE_W);
    return (bits & PTE_R) || (mxr && (bits & PTE_X));
}

static volatile uint64_t g_mprv_seen = ~0UL;
static int m_hook(st_frame_t *f) {
    if (f->cause == CAUSE_ECALL_S && f->x[17] == 0x4d505256UL) {
        g_mprv_seen = (f->status & MSTATUS_MPRV) ? 1 : 0;
        f->epc += 4;
        return 1;
    }
    return 0;
}
static uint64_t s_report(uint64_t a) { (void)a; st_ecall(0x4d505256UL, 0); return 0; }

int main(void) {
    st_init();
    g_m_hook = m_hook;
    uint64_t root = pt_new_identity_root(0);
    uint64_t frame = frame_alloc();
    *(volatile uint64_t *)frame = 0x0123456789abcdefUL;
    for (unsigned i = 0; i < ST_ARRAY_LEN(g_pages); i++)
        map_page(root, VA + i * ST_PAGE, frame, g_pages[i].bits | PTE_AD);
    csr_write(satp, satp_sv39(7, root));
    sfence_all();

    st_section("permission matrix");
    uint64_t mism = 0, cases = 0;
    for (uint64_t prv = PRV_U; prv <= PRV_S; prv++)
        for (int sum = 0; sum < 2; sum++)
            for (int mxr = 0; mxr < 2; mxr++)
                for (unsigned i = 0; i < ST_ARRAY_LEN(g_pages); i++)
                    for (int store = 0; store < 2; store++) {
                        csr_clear(mstatus, MSTATUS_SUM | MSTATUS_MXR);
                        if (sum) csr_set(mstatus, MSTATUS_SUM);
                        if (mxr) csr_set(mstatus, MSTATUS_MXR);
                        uint64_t va = VA + i * ST_PAGE;
                        uint64_t v = 0;
                        int trapped = store ? probe_sd(va + 8, prv, 0x5555) : probe_ld(va, prv, &v);
                        int allowed = model_allows(g_pages[i].bits, prv, sum, mxr, store);
                        cases++;
                        int ok = allowed ? (!trapped && (store || v == 0x0123456789abcdefUL))
                                         : (trapped && g_trap_cause == (store ? CAUSE_STORE_PAGE : CAUSE_LOAD_PAGE));
                        if (!ok) {
                            mism++;
                            if (mism < 8) st_check_failed(g_pages[i].name,
                                (prv << 12) | ((uint64_t)sum << 8) | ((uint64_t)mxr << 4) | (uint64_t)store, allowed, __LINE__);
                        }
                    }
    csr_clear(mstatus, MSTATUS_SUM | MSTATUS_MXR);
    ST_CHECK_EQ("all matrix cases match the spec model", mism, 0);
    st_puts("[ST] cases: "); st_putdec(cases); st_putc('\n');

    st_section("MPRV with MPP = M is untranslated");
    uint64_t v = 0;
    ST_CHECK_EQ("physical read with MPP=M", probe_ld(frame, PRV_M, &v), 0);
    ST_CHECK_EQ("  value", v, 0x0123456789abcdefUL);
    ST_CHECK_EQ("VA is not mapped as PA with MPP=M", probe_ld(VA, PRV_M, &v), 1);
    ST_CHECK_EQ("  (VA 0xC0000000 is a PMA hole)", g_trap_cause, CAUSE_LOAD_ACCESS);

    st_section("mret to S clears MPRV");
    csr_set(mstatus, MSTATUS_MPRV);
    (void)st_run(PRV_S, s_report, 0);     /* st_run sets MPP=S; MPRV stays 1 into the mret */
    ST_CHECK_EQ("MPRV was 0 while S ran", g_mprv_seen, 0);
    csr_clear(mstatus, MSTATUS_MPRV);

    csr_write(satp, 0);
    sfence_all();
    return st_result();
}
