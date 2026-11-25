/* hvl/pin/tests/uart_full.c -- the UART through the real pads.
 *   1. echo, upper-cased, a line from the pin UART agent (RX FIFO, polled)
 *   2. switch divisor (DLL 1 -> 2) mid-run; the script follows with uart_div 2
 *   3. receive interrupt (IER.ERBFI) through PLIC source 10 to M
 *   4. overrun: FIFOs off, the agent sends a burst nobody reads -> LSR.OE */
#include "pin_common.h"
static volatile uint32_t rx_irq; static volatile char rx_buf[64]; static volatile uint32_t rx_n;
void __attribute__((interrupt("machine"), aligned(4))) handler(void) {
    uint32_t id = CLM(0);
    if (id == 10) { int c; while ((c = getc_nb()) >= 0) if (rx_n < 64) rx_buf[rx_n++] = (char)c; rx_irq++; }
    if (id) CLM(0) = id;
}
static void echo_line(void) {
    char c;
    puts_("echo:");
    while ((c = getc_()) != '\n') putc_((c >= 'a' && c <= 'z') ? (char)(c - 32) : c);
    putc_('\n');
}
int main(void) {
    uart_init(1);
    puts_("PIN_UART_READY\n");
    echo_line();
    /* divisor switch: announce at the old rate, then change */
    puts_("DIV2\n");
    while (!(UART[5] & 0x40)) ;                      /* TEMT: last bit out */
    uart_init(2);
    puts_("AT_DIV2\n");
    echo_line();
    /* interrupt-driven receive */
    PRIO[10] = 1; THR(0) = 0; EN(0) = 1u << 10;
    asm volatile("csrw mtvec, %0" :: "r"(handler));
    asm volatile("csrs mie, %0" :: "r"(1u << 11));
    UART[1] = 0x01;                                  /* ERBFI */
    asm volatile("csrs mstatus, %0" :: "r"(1u << 3));
    puts_("IRQ_RX\n");
    while (rx_n < 6) ;
    asm volatile("csrc mstatus, %0" :: "r"(1u << 3));
    UART[1] = 0;
    int ok_irq = rx_irq > 0 && rx_buf[0] == 'h' && rx_buf[5] == '!';
    /* overrun */
    UART[2] = 0x00;                                  /* FIFOs off */
    while (getc_nb() >= 0) ;
    (void)UART[5];
    puts_("FLOOD\n");
    for (volatile uint32_t i = 0; i < 60000; i++) ;  /* let the burst arrive unread */
    uint8_t lsr = UART[5];
    while (getc_nb() >= 0) ;
    int ok_oe = (lsr & 0x02) != 0;
    UART[2] = 0x07;
    puts_(ok_irq ? "IRQ_OK\n" : "IRQ_BAD\n");
    puts_(ok_oe ? "OE_OK\n" : "OE_BAD\n");
    puts_((ok_irq && ok_oe) ? "PIN_UART_FULL_DONE\n" : "PIN_UART_FULL_BAD\n");
    return (ok_irq && ok_oe) ? 0 : 1;
}
