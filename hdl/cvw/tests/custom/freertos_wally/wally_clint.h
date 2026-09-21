#ifndef WALLY_CLINT_H
#define WALLY_CLINT_H

#include <stdint.h>

/* Matches CLINT_BASE = 64'h02000000 in config.vh */
#define CLINT_BASE      0x02000000UL

/* CLINT register offsets - standard SiFive CLINT layout */
#define CLINT_MSIP      (*(volatile uint32_t *)(CLINT_BASE + 0x0000))    /* M-mode software interrupt */
#define CLINT_MTIMECMP  (*(volatile uint64_t *)(CLINT_BASE + 0x4000))    /* M-mode timer compare */
#define CLINT_MTIME     (*(volatile uint64_t *)(CLINT_BASE + 0xBFF8))    /* M-mode timer */

/* Convenience: read current time */
static inline uint64_t clint_get_time(void) {
    return CLINT_MTIME;
}

/* Set next timer interrupt relative to now */
static inline void clint_set_timer_interval(uint64_t interval) {
    CLINT_MTIMECMP = CLINT_MTIME + interval;
}

/* Advance timer compare by one interval (called from timer ISR) */
static inline void clint_advance_timer(uint64_t interval) {
    CLINT_MTIMECMP += interval;
}

#endif /* WALLY_CLINT_H */
