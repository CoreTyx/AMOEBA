/* hvl/pin/tests/wfi_wake.c -- WFI with MIE = 0 woken by an irq pad (Linux's
 * idle path), four times at different delays chosen by the script, then once
 * by the timer.  WFI must return; no trap may be taken (MIE = 0). */
#include "pin_common.h"
static volatile uint32_t traps;
void __attribute__((interrupt("machine"), aligned(4))) handler(void) { traps++; MTIMECMP = ~0ULL; }
int main(void) {
    uart_init(1);
    PRIO[3] = 1; THR(0) = 0; EN(0) = 1u << 3;
    asm volatile("csrw mtvec, %0" :: "r"(handler));
    asm volatile("csrs mie, %0" :: "r"((1u << 11) | (1u << 7)));
    for (int i = 1; i <= 4; i++) {
        puts_("SLEEP_"); putdec_((uint32_t)i); putc_('\n');
        while (!(UART[5] & 0x40)) ;
        asm volatile("wfi");
        uint32_t id = CLM(0);                        /* the pad that woke us */
        puts_("WOKE_"); putdec_(id); putc_('\n');
        if (id) { EN(0) = 0; CLM(0) = id; }
        while (getc_() != 'n') ;                     /* script dropped the pad */
        /* the source re-pended when its claim completed with the pad still
         * high: unmask, drain that stale claim (pad is low now), then sleep */
        EN(0) = 1u << 3;
        uint32_t st;
        while ((st = CLM(0)) != 0) CLM(0) = st;
    }
    puts_("TIMER\n");
    while (!(UART[5] & 0x40)) ;
    MTIMECMP = MTIME + 3000;
    asm volatile("wfi");
    uint64_t mip; asm volatile("csrr %0, mip" : "=r"(mip));
    int ok = (mip & (1u << 7)) && traps == 0;
    MTIMECMP = ~0ULL;
    puts_(ok ? "PIN_WFI_DONE\n" : "PIN_WFI_BAD\n");
    return ok ? 0 : 1;
}
