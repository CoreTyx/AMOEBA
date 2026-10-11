/* hvl/pin/tests/uart_echo.c -- both UART directions through the pins.
 * Prints a banner, then echoes received bytes until '.', prefixing each line
 * with "echo:".  Exit code 0 only if it saw exactly "ping\n." -- so a byte
 * the agent corrupted, dropped or duplicated on uart_rx fails the program,
 * and the console pattern in uart_echo.cmd checks the uart_tx direction. */
#include <stdint.h>
#define UART ((volatile uint8_t *)0x10000000UL)
#define LSR_DR   0x01
#define LSR_THRE 0x20

static void putc_(char c) { while (!(UART[5] & LSR_THRE)) ; UART[0] = (uint8_t)c; }
static void puts_(const char *s) { while (*s) putc_(*s++); }
static char getc_(void) { while (!(UART[5] & LSR_DR)) ; return (char)UART[0]; }

int main(void) {
    static const char want[] = "ping\n.";
    int n = 0, bad = 0;
    UART[3] = 0x03;                         /* 8N1, DLAB=0; divisor stays at reset (1) */
    UART[2] = 0x07;                         /* FIFOs on and cleared: the agent sends back to
                                               back, and one holding register overruns while
                                               the previous byte is being echoed */
    puts_("PIN_UART_READY\n");
    puts_("echo:");
    for (;;) {
        char c = getc_();
        if (n < (int)sizeof(want) - 1 && c != want[n]) bad = 1;
        n++;
        if (c == '.') break;
        putc_(c);
        if (c == '\n') puts_("echo:");
    }
    puts_("\nPIN_UART_DONE\n");
    return (bad || n != (int)sizeof(want) - 1) ? 1 : 0;
}
