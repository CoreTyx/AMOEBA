// @stress tier=pr seeds=2 build=no_spike duts=legacy,forte timeout=20000000
//
// st_mmio_order -- uncached MMIO interleaved with cached traffic, and the PMA
// rules for every peripheral region.
//
// Drivers depend on MMIO being uncached, ordered, and read-after-write exact
// even while the D$ is busy with misses and write-backs around it.  And the
// PMA checker must refuse every access type a peripheral does not support:
// UART is byte-only, PLIC and the ECC counters word-only, FI_CONTROL a single
// byte; nothing in MMIO is executable or atomic; addresses between regions
// are holes.  A refused access must fault and must not reach the device.
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif

static uint64_t g_buf[8192] ST_ALIGNED(4096);   /* 64 KiB: 16x the D$ */

static void churn(int i) {
    /* cached traffic that misses and writes back around the MMIO accesses */
    volatile uint64_t *p = &g_buf[(uint64_t)(i * 131 * 16) % ST_ARRAY_LEN(g_buf)];
    *p = *p + (uint64_t)i;
    (void)g_buf[(uint64_t)(i * 977 * 16 + 8) % ST_ARRAY_LEN(g_buf)];
}

int main(void) {
    st_init();

    st_section("CLINT mtimecmp read-after-write, 64- and 32-bit, amid cache misses");
    uint64_t bad = 0;
    for (int i = 0; i < 400 * ST_SCALE; i++) {
        uint64_t v = st_rand() | (1UL << 62);           /* far future: never fires */
        switch (i % 3) {
        case 0: CLINT_MTIMECMP = v; churn(i); if (CLINT_MTIMECMP != v) bad++; break;
        case 1: CLINT_MTIMECMP_LO = (uint32_t)v; CLINT_MTIMECMP_HI = (uint32_t)(v >> 32);
                churn(i); if (CLINT_MTIMECMP_LO != (uint32_t)v || CLINT_MTIMECMP_HI != (uint32_t)(v >> 32)) bad++; break;
        default: CLINT_MTIMECMP = v; if (CLINT_MTIMECMP != v) bad++; churn(i); break;
        }
    }
    ST_CHECK_EQ("every mtimecmp read returned the last write", bad, 0);
    st_timer_off();

    st_section("byte writes to mtimecmp merge");
    CLINT_MTIMECMP = 0x1122334455667788UL;
    *(volatile uint8_t *)(CLINT_BASE + 0x4003) = 0xab;
    *(volatile uint16_t *)(CLINT_BASE + 0x4006) = 0xcdef;
    ST_CHECK_EQ("partial writes merge", CLINT_MTIMECMP, 0xcdef3344ab667788UL);
    st_timer_off();

    st_section("mtime is monotonic across cached traffic");
    uint64_t last = st_mtime(), nonmono = 0;
    for (int i = 0; i < 300; i++) {
        churn(i);
        uint64_t t = (i & 1) ? st_mtime() : ((uint64_t)CLINT_MTIME_HI << 32 | CLINT_MTIME_LO);
        if ((i & 1) && t < last) nonmono++;
        if (i & 1) last = t;
    }
    ST_CHECK_EQ("64-bit mtime never goes backwards", nonmono, 0);

    st_section("MSIP toggles");
    for (int i = 0; i < 32; i++) {
        CLINT_MSIP = (uint32_t)(i & 1);
        churn(i);
        if ((CLINT_MSIP & 1) != (uint32_t)(i & 1)) bad++;
        if (!!(csr_read(mip) & MIP_MSIP) != (i & 1)) bad++;
    }
    CLINT_MSIP = 0;
    ST_CHECK_EQ("MSIP register and mip.MSIP track writes", bad, 0);

    st_section("UART scratch register read-after-write");
    for (int i = 0; i < 256; i++) {
        UART_REG(UART_SCR) = (uint8_t)i;
        churn(i);
        if (UART_REG(UART_SCR) != (uint8_t)i) bad++;
    }
    ST_CHECK_EQ("SCR holds every byte value", bad, 0);

    st_section("PLIC priority read-after-write");
    for (int i = 0; i < 64; i++) {
        uint32_t p = (uint32_t)(i & 7);
        PLIC_PRIORITY(PLIC_SRC_UART) = p;
        churn(i);
        if (PLIC_PRIORITY(PLIC_SRC_UART) != p) bad++;
    }
    PLIC_PRIORITY(PLIC_SRC_UART) = 0;
    ST_CHECK_EQ("priority register (3 bits)", bad, 0);

    st_section("PMA: unsupported widths are refused and never reach the device");
    uint64_t v;
    UART_REG(UART_SCR) = 0x5a;
    ST_CHECK_EQ("UART 16-bit load faults", m_try_lh(UART_BASE_ADDR + 6, &v), 1);
    ST_CHECK_EQ("  cause", g_trap_cause, CAUSE_LOAD_ACCESS);
    ST_CHECK_EQ("UART 32-bit store faults", m_try_sw(UART_BASE_ADDR + 4, 0xffffffff), 1);
    ST_CHECK_EQ("  cause", g_trap_cause, CAUSE_STORE_ACCESS);
    ST_CHECK_EQ("UART 64-bit load faults", m_try_ld(UART_BASE_ADDR, &v), 1);
    ST_CHECK_EQ("  SCR untouched by refused accesses", UART_REG(UART_SCR), 0x5a);
    PLIC_PRIORITY(PLIC_SRC_UART) = 3;
    ST_CHECK_EQ("PLIC byte store faults", m_try_sb(PLIC_BASE_ADDR + 4 * PLIC_SRC_UART, 7), 1);
    ST_CHECK_EQ("PLIC 64-bit load faults", m_try_ld(PLIC_BASE_ADDR, &v), 1);
    ST_CHECK_EQ("PLIC halfword load faults", m_try_lh(PLIC_BASE_ADDR + 4 * PLIC_SRC_UART, &v), 1);
    ST_CHECK_EQ("  priority untouched", PLIC_PRIORITY(PLIC_SRC_UART), 3);
    PLIC_PRIORITY(PLIC_SRC_UART) = 0;
    ST_CHECK_EQ("FI_CONTROL word store faults", m_try_sw(FI_CONTROL_ADDR & ~3UL, 0), 1);
    ST_CHECK_EQ("ECC counter byte load faults", m_try_lb(ECC_COUNTER_BASE, &v), 1);
    ST_CHECK_EQ("ECC counter word load ok", m_try_lw(ECC_COUNTER_BASE, &v), 0);

    st_section("holes between and past the peripheral regions");
    static const uint64_t holes[] = {
        UART_BASE_ADDR + 8, UART_BASE_ADDR + 0x100, CLINT_BASE + 0x10000, CLINT_BASE - 8,
        PLIC_BASE_ADDR + 0x4000000, PLIC_BASE_ADDR - 4, 0x10060000UL /* GPIO: disabled */,
        0x10040000UL /* SPI: disabled */, 0x00013000UL /* SDC: disabled */, 0x00001000UL /* no boot ROM */,
        ST_RAM_END, 0x7ffffff8UL };
    for (unsigned i = 0; i < ST_ARRAY_LEN(holes); i++) {
        int t = m_try_lw(holes[i], &v);
        if (!t || g_trap_cause != CAUSE_LOAD_ACCESS) st_check_failed("hole load must access-fault", holes[i], CAUSE_LOAD_ACCESS, (int)i);
        else g_st_pass++;
        t = m_try_sw(holes[i], 0);
        if (!t || g_trap_cause != CAUSE_STORE_ACCESS) st_check_failed("hole store must access-fault", holes[i], CAUSE_STORE_ACCESS, (int)i);
        else g_st_pass++;
    }

    st_section("MMIO is never executable");
    static const uint64_t nx[] = { CLINT_BASE, UART_BASE_ADDR, PLIC_BASE_ADDR, ECC_COUNTER_BASE };
    for (unsigned i = 0; i < ST_ARRAY_LEN(nx); i++) {
        st_expect(ST_EXPECT_SKIP);
        __asm__ volatile (".option push\n.option norvc\nla t0, 1f\nsd t0, 0(%0)\njalr zero, 0(%1)\n1:\n.option pop"
                          :: "r"(&g_exp_resume), "r"(nx[i]) : "t0", "memory");
        st_expect_clear();
        if (g_trap_cause != CAUSE_FETCH_ACCESS) st_check_failed("fetch from MMIO", nx[i], CAUSE_FETCH_ACCESS, (int)i);
        else g_st_pass++;
    }
    return st_result();
}
