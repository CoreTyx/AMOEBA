// @stress tier=pr build=no_spike duts=legacy,forte timeout=2000000
//
// st_warl -- the WARL / read-only CSR fields Linux and OpenSBI depend on.
//
// OpenSBI probes misa, medeleg/mideleg and satp modes at boot and configures
// itself from what it reads back.  A field that accepts an illegal value (a
// satp mode the MMU cannot walk, a delegation bit for a cause that must stay in
// M, an FS field on a core with no FPU) makes software believe in hardware that
// is not there.  Every expectation below is derived from pkg/config.vh via
// amoeba_cfg.h and the privileged spec.
#include "../lib/stress.h"

int main(void) {
    st_init();

    st_section("misa");
    uint64_t misa = csr_read(misa);
    ST_CHECK_EQ("MXL = 2 (RV64)", misa >> 62, 2);
    ST_CHECK_EQ("extensions match config (IMAC+S+U)", misa & 0x3ffffff, AMOEBA_MISA_EXT_BITS);
    csr_write(misa, 0);
    ST_CHECK_EQ("misa is hardwired (write 0 ignored)", csr_read(misa), misa);
    csr_write(misa, ~0UL);
    ST_CHECK_EQ("misa is hardwired (write ~0 ignored)", csr_read(misa), misa);

    st_section("mstatus");
    uint64_t ms0 = csr_read(mstatus);
    ST_CHECK_EQ("UXL = 2", (ms0 >> 32) & 3, 2);
    ST_CHECK_EQ("SXL = 2", (ms0 >> 34) & 3, 2);
    csr_set(mstatus, MSTATUS_FS);
    ST_CHECK_EQ("FS stays 0 without an FPU", csr_read(mstatus) & MSTATUS_FS, 0);
    ST_CHECK_EQ("SD stays 0", csr_read(mstatus) >> 63, 0);
    csr_set(mstatus, 3UL << 9);   /* VS */
    ST_CHECK_EQ("VS stays 0 without V", (csr_read(mstatus) >> 9) & 3, 0);
    /* MPP is WARL: the reserved encoding 2 (H) must read back as a legal mode. */
    csr_clear(mstatus, MSTATUS_MPP);
    csr_set(mstatus, 2UL << 11);
    uint64_t mpp = (csr_read(mstatus) >> 11) & 3;
    ST_CHECK("MPP never reads 2", mpp != 2);
    csr_clear(mstatus, MSTATUS_MPP);
    csr_set(mstatus, MSTATUS_MPP_M);
    /* Fields that must be writable for Linux. */
    uint64_t want = MSTATUS_SUM | MSTATUS_MXR | MSTATUS_TVM | MSTATUS_TW | MSTATUS_TSR;
    csr_set(mstatus, want);
    ST_CHECK_EQ("SUM/MXR/TVM/TW/TSR writable", csr_read(mstatus) & want, want);
    csr_clear(mstatus, want);
    ST_CHECK_EQ("SUM/MXR/TVM/TW/TSR clearable", csr_read(mstatus) & want, 0);

    st_section("sstatus is a restricted view of mstatus");
    csr_set(mstatus, MSTATUS_MIE);
    csr_set(sstatus, MSTATUS_SUM);
    ST_CHECK("sstatus.SUM -> mstatus.SUM", csr_read(mstatus) & MSTATUS_SUM);
    ST_CHECK_EQ("mstatus.MIE invisible in sstatus", csr_read(sstatus) & MSTATUS_MIE, 0);
    ST_CHECK_EQ("mstatus.MPP invisible in sstatus", csr_read(sstatus) & MSTATUS_MPP, 0);
    csr_clear(sstatus, MSTATUS_SUM);
    ST_CHECK_EQ("sstatus clear SUM", csr_read(mstatus) & MSTATUS_SUM, 0);
    csr_clear(mstatus, MSTATUS_MIE);

    st_section("medeleg / mideleg");
    csr_write(medeleg, ~0UL);
    uint64_t med = csr_read(medeleg);
    ST_CHECK_EQ("ecall-from-M (11) never delegable", (med >> 11) & 1, 0);
    uint64_t linux_deleg = (1UL << CAUSE_MISALIGNED_FETCH) | (1UL << CAUSE_BREAKPOINT) |
                           (1UL << CAUSE_ECALL_U) | (1UL << CAUSE_FETCH_PAGE) |
                           (1UL << CAUSE_LOAD_PAGE) | (1UL << CAUSE_STORE_PAGE);
    /* misaligned-fetch cannot occur with C, so it may be read-only zero */
    ST_CHECK_EQ("the causes OpenSBI delegates are writable",
                med & (linux_deleg & ~1UL), linux_deleg & ~1UL);
    csr_write(medeleg, 0);
    ST_CHECK_EQ("medeleg clears", csr_read(medeleg), 0);

    csr_write(mideleg, ~0UL);
    uint64_t mid = csr_read(mideleg);
    ST_CHECK_EQ("only S interrupts (SSIP/STIP/SEIP) delegable", mid, MIP_SSIP | MIP_STIP | MIP_SEIP);
    csr_write(mideleg, 0);

    st_section("mie / mip");
    csr_write(mie, ~0UL);
    ST_CHECK_EQ("mie implements exactly the 6 standard bits", csr_read(mie),
                MIP_SSIP | MIP_MSIP | MIP_STIP | MIP_MTIP | MIP_SEIP | MIP_MEIP);
    csr_write(mie, 0);
    csr_set(mip, MIP_SSIP | MIP_STIP | MIP_SEIP);
    ST_CHECK_EQ("M can set SSIP/STIP/SEIP", csr_read(mip) & (MIP_SSIP | MIP_STIP | MIP_SEIP),
                MIP_SSIP | MIP_STIP | MIP_SEIP);
    csr_clear(mip, MIP_SSIP | MIP_STIP | MIP_SEIP);
    ST_CHECK_EQ("M can clear SSIP/STIP/SEIP", csr_read(mip) & (MIP_SSIP | MIP_STIP | MIP_SEIP), 0);
    csr_set(mip, MIP_MTIP | MIP_MSIP | MIP_MEIP);
    ST_CHECK_EQ("MTIP/MSIP/MEIP not software-writable", csr_read(mip) & (MIP_MTIP | MIP_MSIP | MIP_MEIP), 0);

    st_section("sie / sip track mideleg");
    csr_write(mideleg, MIP_SSIP | MIP_STIP | MIP_SEIP);
    csr_write(mie, MIP_SSIP | MIP_MTIP);
    ST_CHECK_EQ("sie shows only delegated bits", csr_read(sie), MIP_SSIP);
    csr_write(sie, MIP_STIP);
    ST_CHECK_EQ("sie write reaches mie.STIE", csr_read(mie) & MIP_STIP, MIP_STIP);
    ST_CHECK_EQ("sie write leaves mie.MTIE", csr_read(mie) & MIP_MTIP, MIP_MTIP);
    csr_write(mie, 0);
    csr_write(mideleg, 0);

    st_section("satp: only Bare and Sv39");
    uint64_t root = frame_alloc();
    csr_write(satp, satp_sv39(0xffff, root));
    uint64_t sv = csr_read(satp);
    ST_CHECK_EQ("Sv39 mode accepted", sv >> 60, 8);
    ST_CHECK_EQ("16 ASID bits", (sv >> 44) & 0xffff, 0xffff);
    ST_CHECK_EQ("PPN preserved", sv & ((1UL << 44) - 1), root >> 12);
    csr_write(satp, (9UL << 60) | (root >> 12));
    ST_CHECK_EQ("Sv48 write ignored entirely", csr_read(satp), sv);
    csr_write(satp, (10UL << 60) | (root >> 12));
    ST_CHECK_EQ("Sv57 write ignored entirely", csr_read(satp), sv);
    csr_write(satp, (1UL << 60));
    ST_CHECK_EQ("reserved mode 1 ignored", csr_read(satp), sv);
    csr_write(satp, 0);
    ST_CHECK_EQ("Bare accepted", csr_read(satp), 0);
    sfence_all();

    st_section("mepc / sepc alignment (IALIGN=16)");
    csr_write(mepc, ~0UL);
    ST_CHECK_EQ("mepc[0] reads 0", csr_read(mepc) & 1, 0);
    ST_CHECK_EQ("mepc[1] writable (C present)", csr_read(mepc) & 2, 2);
    csr_write(sepc, ~0UL);
    ST_CHECK_EQ("sepc[0] reads 0", csr_read(sepc) & 1, 0);

    st_section("scratch / tval / identity CSRs");
    csr_write(sscratch, 0x0123456789abcdefUL);
    ST_CHECK_EQ("sscratch holds 64 bits", csr_read(sscratch), 0x0123456789abcdefUL);
    ST_CHECK_EQ("mhartid = 0", csr_read(mhartid), 0);

    st_section("pmpaddr width");
    int e = AMOEBA_PMP_ENTRIES - 2;
    pmp_write_addr(e, ~0UL);
    uint64_t pa = pmp_read_addr(e);
    ST_CHECK_EQ("pmpaddr holds PA_BITS-2 bits (low G read 0 when OFF)", pa,
                ((1UL << (AMOEBA_PA_BITS - 2)) - 1) & ~((1UL << AMOEBA_PMP_G) - 1));
    pmp_write_addr(e, 0);

    return st_result();
}
