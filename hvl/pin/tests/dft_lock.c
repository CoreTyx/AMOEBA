/* hvl/pin/tests/dft_lock.c -- the DFT lock (hdl/forte_dft_lock.sv) from the pins.
 * Protocol (dft_lock.cmd):
 *   1. unlocked out of reset: print DFT_UNLOCKED; the script runs a real DFT
 *      hold (it must work) and sends 'l'
 *   2. clear the lock, check it reads back 0 and that writing 1 cannot reopen
 *      it, print DFT_LOCKED
 *   3. keep working and printing while the script drives test_mode/scan_en
 *      (dft_locked): the pins must be ignored and the work must stay correct
 * Exit 0 only if every check passed. */
#include "pin_common.h"

#define DFT_LOCK (*(volatile uint64_t *)0x0200F000UL)

static uint64_t work(uint64_t x) {
    for (int i = 0; i < 64; i++) x = x * 6364136223846793005ULL + 1442695040888963407ULL;
    return x;
}

int main(void) {
    uart_init(1);
    int ok = (DFT_LOCK & 1) == 1;                        /* resets unlocked */
    puts_(ok ? "DFT_UNLOCKED\n" : "DFT_BAD_RESET\n");
    while (getc_() != 'l') ;

    DFT_LOCK = 0;
    ok &= (DFT_LOCK & 1) == 0;
    DFT_LOCK = 1;                                        /* sticky: no way back */
    ok &= (DFT_LOCK & 1) == 0;
    puts_(ok ? "DFT_LOCKED\n" : "DFT_LOCK_BAD\n");

    /* Work through the dft_locked window; a hold or a shift would corrupt or
     * stop it.  The reference chain is recomputed and compared at the end. */
    uint64_t x = 0x1234, ref = 0x1234;
    for (uint32_t r = 1; r <= 40; r++) {
        x = work(x);
        puts_("TICK_"); putdec_(r); putc_('\n');
    }
    for (uint32_t r = 1; r <= 40; r++) ref = work(ref);
    ok &= (x == ref) && (DFT_LOCK & 1) == 0;
    puts_(ok ? "DFT_LOCK_DONE\n" : "DFT_LOCK_BAD\n");
    return ok ? 0 : 1;
}
