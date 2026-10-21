/* hvl/pin/tests/uart_lsr.c -- LSR[7], "error in receiver FIFO" (16550 8.6.3).
 * The bench sends one byte with a framing error (uart_lsr.cmd).  With the FIFO
 * holding an errored byte, LSR[7] must be 1 and LSR[3] (framing error) must
 * be set.  uartPC16550D built LSR[7] from a mask of the FIFO's EMPTY slots, so
 * a real error in an occupied slot was missed -- and in 4-state simulation the
 * never-written slots made LSR X.  LSR[7] must also clear on an LSR read once
 * the errored byte is gone (it used to stay set until reset). */
#include <stdint.h>
#define UART ((volatile uint8_t *)0x10000000UL)

static void putc_(char c) { while (!(UART[5] & 0x20)) ; UART[0] = (uint8_t)c; }
static void puts_(const char *s) { while (*s) putc_(*s++); }
static void puthex(uint8_t v) { const char *h = "0123456789abcdef"; putc_(h[v >> 4]); putc_(h[v & 15]); }

int main(void) {
    uint8_t lsr = 0;
    UART[3] = 0x03;                       /* 8N1 */
    UART[2] = 0x07;                       /* FIFOs on and cleared */
    puts_("PIN_LSR_READY\n");
    while (!(UART[5] & 0x01)) ;           /* the errored byte has arrived */
    for (volatile int i = 0; i < 200; i++) ;   /* let LSR settle a few cycles */
    lsr = UART[5];                        /* the first read; reading also squashes LSR[4:1] */
    puts_("LSR=");
    puthex(lsr);
    /* LSR[7] clears on an LSR read once no errored character remains in the
     * FIFO (16550 8.6.3): pop the byte, then the next LSR read still reports
     * the error and the one after it must not. */
    (void)UART[0];                        /* RBR: pop the errored byte */
    uint8_t lsr2 = UART[5], lsr3 = UART[5];
    puts_(" LSR2=");
    puthex(lsr2);
    puts_(" LSR3=");
    puthex(lsr3);
    puts_("\nPIN_LSR_DONE\n");
    return ((lsr & 0x80) && (lsr & 0x08) && (lsr2 & 0x80) && !(lsr3 & 0x80)) ? 0 : 1;
}
