/*
 * sys: basic process-identity and time syscalls.
 *
 *  1. getpid()/getppid(): this program is exec'd by a child /init forked, so
 *     the parent must be PID 1 and our own PID something larger.
 *  2. uname(): sysname "Linux", release "6.6...", machine "riscv64".
 *  3. clock_gettime(CLOCK_MONOTONIC) before and after a short busy loop must
 *     strictly increase, and by a plausible amount.  That reads the timer CSR
 *     the CLINT drives, through the kernel's clocksource.
 */
#include "ulib.h"

static const char *const name = "sys";

static long ts_ns(const struct timespec *t)
{
    return t->tv_sec * 1000000000L + t->tv_nsec;
}

int main(void)
{
    unsigned sum = 0;

    int pid = sys_getpid(), ppid = sys_getppid();
    if (ppid != 1)
        return prog_fail(name, "ppid-not-init");
    if (pid <= 1)
        return prog_fail(name, "pid");

    struct utsname u;
    memset(&u, 0, sizeof u);
    if (sys_uname(&u) != 0)
        return prog_fail(name, "uname");
    if (strcmp(u.sysname, "Linux") != 0)
        return prog_fail(name, "uname-sysname");
    if (strncmp(u.release, "6.6", 3) != 0)
        return prog_fail(name, "uname-release");
    if (strcmp(u.machine, "riscv64") != 0)
        return prog_fail(name, "uname-machine");
    sum = crc32_update(sum, u.sysname, strlen(u.sysname));
    sum = crc32_update(sum, u.machine, strlen(u.machine));

    struct timespec t0, t1;
    if (sys_clock_gettime(CLOCK_MONOTONIC, &t0) != 0)
        return prog_fail(name, "clock_gettime");
    if (t0.tv_nsec < 0 || t0.tv_nsec >= 1000000000L)
        return prog_fail(name, "clock-nsec-range");

    /* ~20k iterations: a few hundred microseconds of 100 MHz time. */
    unsigned long acc = 0;
    for (unsigned long i = 0; i < 20000; i++)
        acc += opaque(i);

    if (sys_clock_gettime(CLOCK_MONOTONIC, &t1) != 0)
        return prog_fail(name, "clock_gettime-2");
    long dt = ts_ns(&t1) - ts_ns(&t0);
    if (dt <= 0)
        return prog_fail(name, "clock-not-monotonic");
    if (dt > 10L * 1000000000L)
        return prog_fail(name, "clock-jump");
    if (acc != 20000UL * 19999UL / 2)
        return prog_fail(name, "busy-loop");

    return prog_pass(name, sum);
}
