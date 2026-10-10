///////////////////////////////////////////
// tc_amo.c
//
// TC_AMO - AMOADD.W/D, AMOSWAP.D, LR.D/SC.D through the D$: the returned old value and the
//          following plain load, on cold and warm lines.
//          Includes OpenSBI's spin_lock sequence (ticket lock: amoadd.w then lw), which hangs
//          the Linux boot if an AMO returns its own result instead of the old value.
//
// SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
///////////////////////////////////////////
#include "test_utils.h"

static volatile uint32_t lockw[16] __attribute__((aligned(64)));
static volatile uint64_t dw[16]    __attribute__((aligned(64)));

static inline uint32_t amoadd_w(volatile uint32_t *p, uint32_t v) {
    uint32_t r; __asm__ volatile ("amoadd.w.aqrl %0, %2, (%1)" : "=r"(r) : "r"(p), "r"(v) : "memory"); return r;
}
static inline uint64_t amoadd_d(volatile uint64_t *p, uint64_t v) {
    uint64_t r; __asm__ volatile ("amoadd.d.aqrl %0, %2, (%1)" : "=r"(r) : "r"(p), "r"(v) : "memory"); return r;
}
static inline uint64_t amoswap_d(volatile uint64_t *p, uint64_t v) {
    uint64_t r; __asm__ volatile ("amoswap.d.aqrl %0, %2, (%1)" : "=r"(r) : "r"(p), "r"(v) : "memory"); return r;
}
static inline uint64_t lrsc_inc(volatile uint64_t *p, uint64_t *sc_fail) {
    uint64_t old, f;
    __asm__ volatile ("lr.d.aq %0, (%2)\n addi t0, %0, 1\n sc.d.rl %1, t0, (%2)"
                      : "=&r"(old), "=&r"(f) : "r"(p) : "t0", "memory");
    *sc_fail = f; return old;
}

static void run(const char *name, int warm) {
    test_begin(name);
    lockw[0] = 0x00000000;           // ticket lock word: [31:16] next, [15:0] owner
    dw[0] = 100; dw[8] = 7; dw[4] = 40;
    if (warm) { (void)lockw[0]; (void)dw[0]; (void)dw[8]; (void)dw[4]; } // make sure lines are resident
    else __asm__ volatile ("fence rw,rw");

    uint32_t old = amoadd_w(&lockw[0], 0x10000);
    check("amoadd.w returns old value", old, 0x00000000);
    check("lw after amoadd.w sees new value", lockw[0], 0x00010000);
    check("ticket == owner (spin_lock would proceed)", (old >> 16) & 0xffff, old & 0xffff);
    lockw[0] = lockw[0] + 1;          // spin_unlock: owner++
    check("store after amo, then load", lockw[0], 0x00010001);

    check("amoadd.d returns old", amoadd_d(&dw[0], 5), 100);
    check("ld after amoadd.d", dw[0], 105);
    check("amoswap.d returns old", amoswap_d(&dw[8], 99), 7);
    check("ld after amoswap.d", dw[8], 99);
    uint64_t f; uint64_t o = lrsc_inc(&dw[4], &f);
    check("lr.d returns value", o, 40);
    check("sc.d succeeded", f, 0);
    check("ld after sc.d", dw[4], 41);
}

int main(void) {
    run("atomics, cold lines", 0);
    run("atomics, warm lines", 1);
    test_finish();
}
