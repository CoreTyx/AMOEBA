// @stress tier=pr seeds=2 build=no_spike duts=legacy,forte timeout=30000000
//
// st_plic_uart -- the on-chip peripherals: PLIC + 16550 UART.
//
// GPIO, SPI and SDC are disabled in pkg/config.vh, so the UART is the only
// interrupt source inside the chip (PLIC source 10; sources 3 and 6 are the
// irq pads, exercised by the pin bench).  Linux's DTS has no PLIC node today,
// but anything that enables UART interrupts later goes through exactly this:
//   PLIC: priority/threshold gating (strictly greater), pending bit, claim
//         returns the source and clears pending, completion re-arms a source
//         that is still asserted, context 0 -> MEIP, context 1 -> SEIP
//   delivery: machine external interrupt in M; supervisor external interrupt
//         in S via mideleg[9], claimed from context 1
//   UART: THRE interrupt; RX through MCR loopback -- interrupt-driven receive,
//         16-byte FIFO bursts, overrun (LSR.OE), 5/6/7/8-bit word lengths
// No console output while loopback is on (st_putc would feed the receiver).
#include "../lib/stress.h"

#define SRC PLIC_SRC_UART

static inline void uart_wr(int r, uint8_t v) { UART_REG(r) = v; }
static inline uint8_t uart_rd(int r) { return UART_REG(r); }

static void uart_setup(uint8_t lcr, uint8_t fcr) {
    uart_wr(UART_LCR, 0x80);
    uart_wr(UART_DLL, 1);
    uart_wr(UART_DLM, 0);
    uart_wr(UART_LCR, lcr);
    uart_wr(UART_FCR, fcr);
    uart_wr(UART_MCR, 0x10);             /* loopback */
}
static void uart_restore(void) {
    uart_wr(UART_IER, 0);
    uart_wr(UART_MCR, 0);
    uart_wr(UART_FCR, 0);
    uart_wr(UART_LCR, 0x03);
    while (uart_rd(UART_LSR) & UART_LSR_DR) (void)uart_rd(UART_RBR);
    (void)uart_rd(UART_LSR);
}
static int wait_lsr(uint8_t bits, uint32_t spins) {
    while (spins--) if ((uart_rd(UART_LSR) & bits) == bits) return 1;
    return 0;
}

static void plic_reset(void) {
    for (int c = 0; c < 2; c++) { PLIC_ENABLE(c) = 0; PLIC_THRESHOLD(c) = 0; }
    PLIC_PRIORITY(SRC) = 0;
    for (int i = 0; i < 4; i++) { uint32_t id = PLIC_CLAIM(0); if (id) PLIC_CLAIM(0) = id; id = PLIC_CLAIM(1); if (id) PLIC_CLAIM(1) = id; }
}

/* ---- M external interrupt handler ---- */
static volatile uint64_t g_mei, g_mei_id, g_rx_n;
static volatile uint8_t g_rx[64];
static volatile int g_mode;   /* 0 = THRE test, 1 = RX test */
static int m_irq(st_frame_t *f) {
    if (f->cause != (CAUSE_INTR | IRQ_M_EXT)) return 0;
    uint32_t id = PLIC_CLAIM(PLIC_CTX_M);
    g_mei++; g_mei_id = id;
    if (id == SRC) {
        if (g_mode == 0) uart_wr(UART_IER, 0);
        else while (uart_rd(UART_LSR) & UART_LSR_DR) { uint8_t c = uart_rd(UART_RBR); if (g_rx_n < 64) g_rx[g_rx_n] = c; g_rx_n++; }
    }
    PLIC_CLAIM(PLIC_CTX_M) = id;
    return 1;
}

/* ---- S external interrupt handler (context 1) ---- */
static volatile uint64_t g_sei, g_sei_id;
static int s_irq(st_frame_t *f) {
    if (f->cause != (CAUSE_INTR | IRQ_S_EXT)) return 0;
    uint32_t id = PLIC_CLAIM(PLIC_CTX_S);
    g_sei++; g_sei_id = id;
    uart_wr(UART_IER, 0);
    PLIC_CLAIM(PLIC_CTX_S) = id;
    return 1;
}
static uint64_t s_main(uint64_t a) {
    (void)a;
    st_s_init();
    g_s_irq_hook = s_irq;
    csr_set(sie, MIP_SEIP);
    uart_wr(UART_IER, 0x02);              /* THRE interrupt -> source 10 -> ctx 1 */
    csr_set(sstatus, MSTATUS_SIE);
    for (int i = 0; i < 2000 && !g_sei; i++) __asm__ volatile ("nop");
    csr_clear(sstatus, MSTATUS_SIE);
    csr_clear(sie, MIP_SEIP);
    return g_sei;
}

int main(void) {
    st_init();
    g_m_irq_hook = m_irq;
    st_section("PLIC gating with the UART THRE interrupt (polled)");
    plic_reset();
    uart_wr(UART_IER, 0x02);
    for (int i = 0; i < 100; i++) __asm__ volatile ("nop");
    PLIC_PRIORITY(SRC) = 5;
    ST_CHECK("pending bit set", (PLIC_PENDING0 >> SRC) & 1);
    ST_CHECK_EQ("not enabled -> no MEIP", csr_read(mip) & MIP_MEIP, 0);
    PLIC_ENABLE(PLIC_CTX_M) = 1u << SRC;
    PLIC_THRESHOLD(PLIC_CTX_M) = 5;
    ST_CHECK_EQ("priority == threshold -> no MEIP", csr_read(mip) & MIP_MEIP, 0);
    PLIC_THRESHOLD(PLIC_CTX_M) = 4;
    ST_CHECK("priority > threshold -> MEIP", csr_read(mip) & MIP_MEIP);
    ST_CHECK_EQ("ctx 1 not enabled -> no SEIP", csr_read(mip) & MIP_SEIP, 0);
    PLIC_PRIORITY(SRC) = 0;
    ST_CHECK_EQ("priority 0 never interrupts", csr_read(mip) & MIP_MEIP, 0);
    PLIC_PRIORITY(SRC) = 7;
    uint32_t id = PLIC_CLAIM(PLIC_CTX_M);
    ST_CHECK_EQ("claim returns the UART source", id, SRC);
    ST_CHECK_EQ("claimed -> MEIP drops", csr_read(mip) & MIP_MEIP, 0);
    ST_CHECK_EQ("second claim returns 0", PLIC_CLAIM(PLIC_CTX_M), 0);
    PLIC_CLAIM(PLIC_CTX_M) = id;                  /* complete, source still asserted */
    for (int i = 0; i < 20; i++) __asm__ volatile ("nop");
    ST_CHECK("level source re-pends after completion", csr_read(mip) & MIP_MEIP);
    id = PLIC_CLAIM(PLIC_CTX_M);
    uart_wr(UART_IER, 0);
    PLIC_CLAIM(PLIC_CTX_M) = id;
    for (int i = 0; i < 20; i++) __asm__ volatile ("nop");
    ST_CHECK_EQ("source dropped -> stays quiet", csr_read(mip) & MIP_MEIP, 0);

    st_section("machine external interrupt delivery");
    csr_set(mie, MIP_MEIP);
    csr_set(mstatus, MSTATUS_MIE);
    g_mode = 0;
    for (int k = 0; k < 10; k++) {
        uint64_t n = g_mei;
        uart_wr(UART_IER, 0x02);
        for (int i = 0; i < 2000 && g_mei == n; i++) __asm__ volatile ("nop");
        ST_CHECK_EQ("one MEI per arming", g_mei, n + 1);
        ST_CHECK_EQ("  claimed id", g_mei_id, SRC);
    }
    csr_clear(mstatus, MSTATUS_MIE);
    csr_clear(mie, MIP_MEIP);

    st_section("supervisor external interrupt via context 1");
    plic_reset();
    PLIC_PRIORITY(SRC) = 3;
    PLIC_ENABLE(PLIC_CTX_S) = 1u << SRC;
    PLIC_THRESHOLD(PLIC_CTX_S) = 0;
    csr_write(mideleg, MIP_SEIP);
    ST_CHECK_EQ("S handler took the SEI", st_run(PRV_S, s_main, 0), 1);
    ST_CHECK_EQ("  claimed from context 1", g_sei_id, SRC);
    ST_CHECK_EQ("M context untouched", csr_read(mip) & MIP_MEIP, 0);
    csr_write(mideleg, 0);
    plic_reset();

    st_section("UART loopback RX (no console output from here)");
    uint64_t bad = 0;
    /* polled, FIFO off, one byte at a time */
    uart_setup(0x03, 0x00);
    while (uart_rd(UART_LSR) & UART_LSR_DR) (void)uart_rd(UART_RBR);
    for (int i = 0; i < 24; i++) {
        uint8_t c = (uint8_t)st_rand();
        if (!wait_lsr(UART_LSR_THRE, 100000)) bad++;
        uart_wr(UART_THR, c);
        if (!wait_lsr(UART_LSR_DR, 100000)) { bad++; continue; }
        if (uart_rd(UART_RBR) != c) bad++;
    }
    uint64_t polled_bad = bad;

    /* interrupt-driven receive through the PLIC */
    bad = 0;
    PLIC_PRIORITY(SRC) = 2;
    PLIC_ENABLE(PLIC_CTX_M) = 1u << SRC;
    g_mode = 1; g_rx_n = 0;
    uart_wr(UART_IER, 0x01);                       /* RX data available */
    csr_set(mie, MIP_MEIP);
    csr_set(mstatus, MSTATUS_MIE);
    uint8_t sent[32];
    for (int i = 0; i < 32; i++) {
        sent[i] = (uint8_t)st_rand();
        if (!wait_lsr(UART_LSR_TEMT, 100000)) bad++;
        uart_wr(UART_THR, sent[i]);
        for (int s = 0; s < 100000 && g_rx_n <= (uint64_t)i; s++) ;
    }
    csr_clear(mstatus, MSTATUS_MIE);
    csr_clear(mie, MIP_MEIP);
    uart_wr(UART_IER, 0);
    if (g_rx_n != 32) bad += 100;
    for (int i = 0; i < 32 && i < (int)g_rx_n; i++) if (g_rx[i] != sent[i]) bad++;
    uint64_t irq_bad = bad;
    plic_reset();

    /* FIFO burst: 16 bytes into the TX FIFO back to back */
    bad = 0;
    uart_setup(0x03, 0x07);
    uint8_t burst[16];
    for (int i = 0; i < 16; i++) { burst[i] = (uint8_t)(0xA0 + i * 3); uart_wr(UART_THR, burst[i]); }
    for (int i = 0; i < 16; i++) {
        if (!wait_lsr(UART_LSR_DR, 200000)) { bad += 100; break; }
        if (uart_rd(UART_RBR) != burst[i]) bad++;
    }
    uint64_t fifo_bad = bad;

    /* overrun: FIFO off, two bytes, read neither until both arrived */
    uart_setup(0x03, 0x00);
    while (uart_rd(UART_LSR) & UART_LSR_DR) (void)uart_rd(UART_RBR);
    (void)uart_rd(UART_LSR);
    uart_wr(UART_THR, 0x11);
    wait_lsr(UART_LSR_TEMT, 100000);
    uart_wr(UART_THR, 0x22);
    wait_lsr(UART_LSR_TEMT, 100000);
    for (int i = 0; i < 2000; i++) __asm__ volatile ("nop");
    uint8_t lsr = uart_rd(UART_LSR);
    uint8_t lsr2 = uart_rd(UART_LSR);
    (void)uart_rd(UART_RBR);

    /* word lengths with parity: 5..8 bits */
    uint64_t wl_bad = 0;
    for (int wl = 0; wl < 4; wl++) {
        uart_setup((uint8_t)(0x08 | 0x10 | wl), 0x00);       /* PEN + even parity */
        while (uart_rd(UART_LSR) & UART_LSR_DR) (void)uart_rd(UART_RBR);
        uint8_t c = 0xff ^ (uint8_t)(wl * 0x11);
        uart_wr(UART_THR, c);
        if (!wait_lsr(UART_LSR_DR, 100000)) { wl_bad += 10; continue; }
        uint8_t got = uart_rd(UART_RBR), mask = (uint8_t)((1u << (5 + wl)) - 1);
        if ((got & mask) != (c & mask)) wl_bad++;
    }
    uart_restore();

    /* console is ours again */
    ST_CHECK_EQ("polled loopback bytes", polled_bad, 0);
    ST_CHECK_EQ("interrupt-driven RX bytes, in order", irq_bad, 0);
    ST_CHECK_EQ("FIFO burst", fifo_bad, 0);
    ST_CHECK("overrun flagged in LSR.OE", lsr & UART_LSR_OE);
    ST_CHECK_EQ("OE clears on LSR read", lsr2 & UART_LSR_OE, 0);
    ST_CHECK_EQ("5/6/7/8-bit word lengths", wl_bad, 0);
    return st_result();
}
