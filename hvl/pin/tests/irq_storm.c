/* hvl/pin/tests/irq_storm.c -- many rounds on the irq[1:0] pads (PLIC sources
 * 3 and 6), with priorities, a threshold sweep and both pads raised together.
 * Protocol per round (irq_storm.cmd): the script raises a pad; the handler
 * claims, acks "A<src>_<n>" and masks the source; the script drops the pad and
 * sends 'r'; main drains any stale claim, unmasks and acks "R_<n>".  Both pads
 * together must be claimed in priority order (6 above 3). */
#include "pin_common.h"
static volatile uint32_t n3, n6, nspur, order[2], norder;
void __attribute__((interrupt("machine"), aligned(4))) handler(void) {
    uint32_t id = CLM(0);
    if (id == 3)      { n3++; puts_("A3_"); putdec_(n3); putc_('\n'); }
    else if (id == 6) { n6++; puts_("A6_"); putdec_(n6); putc_('\n'); }
    else if (id)      nspur++;
    if (norder < 2 && id) order[norder++] = id;
    if (id) { EN(0) &= ~(1u << id); CLM(0) = id; }
}
int main(void) {
    uart_init(1);
    PRIO[3] = 2; PRIO[6] = 5;
    THR(0) = 0;
    EN(0) = (1u << 3) | (1u << 6);
    asm volatile("csrw mtvec, %0" :: "r"(handler));
    asm volatile("csrs mie, %0" :: "r"(1u << 11));
    asm volatile("csrs mstatus, %0" :: "r"(1u << 3));
    puts_("PIN_STORM_ARMED\n");
    uint32_t rounds = 0;
    for (;;) {
        char c = getc_();
        if (c == 'r') {
            asm volatile("csrc mstatus, %0" :: "r"(1u << 3));
            /* A level source whose claim completed while its pad was still
             * high is pending again (latched until claimed, as the PLIC spec
             * allows), even though the pad is low now.  Unmask with MIE off,
             * claim and complete whatever is stale, then take interrupts. */
            uint32_t id;
            EN(0) = (1u << 3) | (1u << 6);
            while ((id = CLM(0)) != 0) CLM(0) = id;
            asm volatile("csrs mstatus, %0" :: "r"(1u << 3));
            rounds++;
            puts_("R_"); putdec_(rounds); putc_('\n');
        } else if (c == 'b') {                           /* both pads next: record order */
            norder = 0;
            puts_("B_READY\n");
        } else if (c == 't') {                           /* threshold above source 3 */
            THR(0) = 3;
            puts_("T_SET\n");
        } else if (c == 'q') break;
    }
    asm volatile("csrc mstatus, %0" :: "r"(1u << 3));
    puts_("ORDER "); putdec_(order[0]); putc_(' '); putdec_(order[1]); putc_('\n');
    int ok = nspur == 0 && order[0] == 6 && order[1] == 3;
    puts_(ok ? "PIN_STORM_DONE\n" : "PIN_STORM_BAD\n");
    return ok ? 0 : 1;
}
