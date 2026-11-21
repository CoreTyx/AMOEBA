// @stress tier=pr build=no_spike duts=legacy,forte timeout=10000000 ecc=no
//
// st_fi_ctrl_counters -- the AMOEBA fault-tolerance MMIO as firmware will use
// it, and its protection from the OS.
//   - FI_CONTROL (0x1007000b) is a single byte, resets to 0 on silicon, and
//     holds every value; the 18 fault counters (0x10080000) read as words and,
//     with no faults injected, stay at zero across a burst of real work
//   - OpenSBI-style PMP: a NAPOT entry without permissions over the FT MMIO
//     block makes S/U loads and stores access-fault while M still works, and a
//     LOCKED entry binds M too
#include "../lib/stress.h"

/* Two naturally aligned NAPOT regions (one covering both would have to be
 * 1 MiB from 0x10000000, which includes the UART): */
#define FI_BLOCK      0x10070000UL      /* 64 KiB around FI_CONTROL (0x1007000b) */
#define FI_BLOCK_SIZE 0x10000UL
#define CNT_BLOCK     ECC_COUNTER_BASE  /* 4 KiB of fault counters */
#define CNT_BLOCK_SIZE 0x1000UL
#define NCOUNTERS     18

static volatile uint8_t *const g_fi = (volatile uint8_t *)FI_CONTROL_ADDR;
static uint64_t s_ld_counter(uint64_t i) { return *(volatile uint32_t *)(ECC_COUNTER_BASE + 4 * i); }

int main(void) {
    st_init();

    st_section("FI_CONTROL byte register");
    ST_CHECK_EQ("resets to 0 (silicon value)", *g_fi, 0);
    uint64_t bad = 0;
    for (int v = 0; v < 256; v++) { *g_fi = (uint8_t)v; if (*g_fi != (uint8_t)v) bad++; }
    *g_fi = 0;
    ST_CHECK_EQ("holds all 256 values", bad, 0);

    st_section("fault counters stay zero under real work (no injection)");
    volatile uint64_t buf[512];
    uint64_t acc = 0;
    for (int r = 0; r < 20; r++)
        for (int i = 0; i < 512; i++) { buf[i] = acc * 31 + (uint64_t)i; acc += buf[(i * 7) & 511] / ((uint64_t)i | 1); }
    (void)acc;
    for (uint64_t i = 0; i < NCOUNTERS; i++) {
        uint32_t c = *(volatile uint32_t *)(ECC_COUNTER_BASE + 4 * i);
        if (c != 0) st_check_failed("counter nonzero without injection", i, c, (int)i);
        else g_st_pass++;
    }

    st_section("PMP hides the FT block from S/U");
    pmp_write_addr(0, pmp_napot_addr(FI_BLOCK, FI_BLOCK_SIZE));
    pmp_write_cfg(0, PMP_NAPOT);                    /* no permissions, not locked */
    pmp_write_addr(1, pmp_napot_addr(CNT_BLOCK, CNT_BLOCK_SIZE));
    pmp_write_cfg(1, PMP_NAPOT);
    uint64_t v;
    ST_CHECK_EQ("S load of a counter faults", probe_lw(ECC_COUNTER_BASE, PRV_S, &v), 1);
    ST_CHECK_EQ("  cause", g_trap_cause, CAUSE_LOAD_ACCESS);
    ST_CHECK_EQ("U store to FI_CONTROL faults", probe_sb(FI_CONTROL_ADDR, PRV_U, 0x3f), 1);
    ST_CHECK_EQ("  cause", g_trap_cause, CAUSE_STORE_ACCESS);
    ST_CHECK_EQ("  FI_CONTROL unchanged", *g_fi, 0);
    uint64_t r = st_run_expect_abort(PRV_S, s_ld_counter, 0, (uint64_t)(g_st_lstack + ST_LSTACK_BYTES));
    ST_CHECK_EQ("S code reading a counter traps", r, ST_TRAP_ABORTED);
    ST_CHECK_EQ("M still reads counters", m_try_lw(ECC_COUNTER_BASE, &v), 0);
    *g_fi = 0x5a;
    ST_CHECK_EQ("M still writes FI_CONTROL", *g_fi, 0x5a);
    *g_fi = 0;

    st_section("a LOCKED entry binds M as well (last: lock persists to reset)");
    pmp_write_cfg(0, PMP_NAPOT | PMP_L);
    pmp_write_cfg(1, PMP_NAPOT | PMP_L);
    ST_CHECK_EQ("M store to FI_CONTROL now faults", m_try_sb(FI_CONTROL_ADDR, 0x12), 1);
    ST_CHECK_EQ("  cause", g_trap_cause, CAUSE_STORE_ACCESS);
    ST_CHECK_EQ("M load of a counter now faults", m_try_lw(ECC_COUNTER_BASE, &v), 1);
    pmp_write_cfg(1, PMP_OFF);                      /* ignored: entry is locked */
    ST_CHECK_EQ("locked cfg cannot be cleared", m_try_lw(ECC_COUNTER_BASE, &v), 1);
    ST_CHECK_EQ("the console (UART) is still reachable from M", m_try_lbu(UART_BASE_ADDR + UART_LSR, &v), 0);
    return st_result();
}
