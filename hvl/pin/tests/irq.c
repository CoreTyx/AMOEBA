/* hvl/pin/tests/irq.c -- the irq[1:0] pins through the on-chip PLIC.
 * irq[0] is PLIC source 3 and irq[1] source 6 (docs/memory_map.md).  The
 * handler claims, reports the ID on the console, masks the source (the pins
 * are level-sensitive and the script drops them only after it has seen the
 * report) and completes.  Exit 0 once both arrived, each exactly once. */
#include <stdint.h>
#define UART  ((volatile uint8_t  *)0x10000000UL)
#define PRIO  ((volatile uint32_t *)0x0C000000UL)   /* + source */
#define EN0   (*(volatile uint32_t *)0x0C002000UL)   /* context 0 (M) enables */
#define THR0  (*(volatile uint32_t *)0x0C200000UL)
#define CLM0  (*(volatile uint32_t *)0x0C200004UL)

static void putc_(char c) { while (!(UART[5] & 0x20)) ; UART[0] = (uint8_t)c; }
static void puts_(const char *s) { while (*s) putc_(*s++); }

static volatile int seen3, seen6, spurious;

void __attribute__((interrupt("machine"), aligned(4))) handler(void) {
    uint32_t id = CLM0;
    if (id == 3)      { seen3++; puts_("IRQ3\n"); }
    else if (id == 6) { seen6++; puts_("IRQ6\n"); }
    else              { spurious++; }
    EN0 &= ~(1u << id);
    CLM0 = id;
}

int main(void) {
    UART[3] = 0x03;
    PRIO[3] = 1; PRIO[6] = 1;
    THR0 = 0;
    EN0 = (1u << 3) | (1u << 6);
    asm volatile("csrw mtvec, %0" :: "r"(handler));
    asm volatile("csrs mie, %0" :: "r"(1u << 11));      /* MEIE */
    asm volatile("csrs mstatus, %0" :: "r"(1u << 3));   /* MIE  */
    puts_("PIN_IRQ_ARMED\n");
    while (!(seen3 && seen6)) asm volatile("wfi");
    asm volatile("csrc mstatus, %0" :: "r"(1u << 3));
    puts_("PIN_IRQ_DONE\n");
    return (seen3 == 1 && seen6 == 1 && spurious == 0) ? 0 : 1;
}
