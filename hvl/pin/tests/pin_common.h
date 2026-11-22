/* hvl/pin/tests/pin_common.h -- console + PLIC helpers for pin-bench programs.
 * The pin bench drives forte_top through its pads, so the console is the real
 * serial line: programs set DLL to match the script's `uart_div`. */
#ifndef PIN_COMMON_H
#define PIN_COMMON_H
#include <stdint.h>
#define UART   ((volatile uint8_t  *)0x10000000UL)
#define PRIO   ((volatile uint32_t *)0x0C000000UL)
#define PEND   (*(volatile uint32_t *)0x0C001000UL)
#define EN(c)  (*(volatile uint32_t *)(0x0C002000UL + 0x80UL * (c)))
#define THR(c) (*(volatile uint32_t *)(0x0C200000UL + 0x1000UL * (c)))
#define CLM(c) (*(volatile uint32_t *)(0x0C200004UL + 0x1000UL * (c)))
#define MTIME    (*(volatile uint64_t *)0x0200BFF8UL)
#define MTIMECMP (*(volatile uint64_t *)0x02004000UL)
static void uart_init(uint8_t div) {
    UART[3] = 0x80; UART[0] = div; UART[1] = 0; UART[3] = 0x03;
    UART[2] = 0x07;                     /* FIFOs on, cleared */
}
static void putc_(char c) { while (!(UART[5] & 0x20)) ; UART[0] = (uint8_t)c; }
static void puts_(const char *s) { while (*s) putc_(*s++); }
static void putdec_(uint32_t v) { char b[11]; int i = 10; b[i] = 0; do { b[--i] = (char)('0' + v % 10); v /= 10; } while (v); puts_(&b[i]); }
static int  getc_nb(void) { return (UART[5] & 1) ? UART[0] : -1; }
static char getc_(void) { int c; while ((c = getc_nb()) < 0) ; return (char)c; }
#endif
