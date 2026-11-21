/*
 * sleep -- the timer path end to end: nanosleep arms an hrtimer/tick, the
 * kernel programs SBI set_timer, OpenSBI writes mtimecmp, MTIP becomes STIP,
 * and the sleeper must wake no earlier than asked.  Plus clock_gettime
 * monotonicity (time read through OpenSBI's rdtime emulation or the vDSO).
 */
#include "ustress.h"
#define NAME "sleep"

int main(void)
{
    long last = u_now_ns(), back = 0;
    for (int i = 0; i < 2000; i++) { long t = u_now_ns(); if (t < last) back++; last = t; }
    if (back) U_FAIL(NAME, "CLOCK_MONOTONIC went backwards");
    struct timespec z = { 0, 0 };
    if (sys_nanosleep(&z, 0)) U_FAIL(NAME, "nanosleep(0)");
    static const long req_ns[] = { 1000000, 5000000, 10000000, 15000000, 20000000, 30000000 };
    unsigned long total = 0;
    for (unsigned i = 0; i < sizeof req_ns / sizeof req_ns[0]; i++) {
        struct timespec r = { 0, req_ns[i] };
        long t0 = u_now_ns();
        int rc = sys_nanosleep(&r, 0);
        long dt = u_now_ns() - t0;
        if (rc) U_FAIL(NAME, "nanosleep rc");
        if (dt < req_ns[i]) U_FAIL(NAME, "woke early");
        total += (unsigned long)dt;
    }
    return prog_pass(NAME, total > 0);
}
