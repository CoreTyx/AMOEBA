/*
 * ctxsw -- context-switch storm.
 *   1. a 16-process token ring over pipes, 60 laps: every hop blocks one
 *      process in read() and wakes the next (~1000 switches)
 *   2. a sched_yield storm: 4 processes x 300 yields
 *   3. preemption: two CPU-bound processes that never block must both make
 *      progress, and their run intervals must overlap (timer preemption at
 *      HZ = 100 interleaves them; run back to back they would not)
 */
#include "ustress.h"
#define NAME  "ctxsw"
#define RING  16
#define LAPS  60

static int run_ring(void)
{
    int fds[RING][2];
    for (int i = 0; i < RING; i++) if (sys_pipe2(fds[i], 0)) return -1;
    int pids[RING];
    for (int i = 1; i < RING; i++) {
        int pid = sys_fork();
        if (pid == 0) {
            for (int lap = 0; lap < LAPS; lap++) {
                unsigned long tok;
                if (sys_read(fds[i - 1][0], &tok, 8) != 8) sys_exit(20);
                tok++;
                if (sys_write(fds[i][1], &tok, 8) != 8) sys_exit(21);
            }
            sys_exit(0);
        }
        pids[i] = pid;
    }
    unsigned long tok = 0;
    for (int lap = 0; lap < LAPS; lap++) {
        tok++;                                    /* parent is ring member 0 */
        if (sys_write(fds[0][1], &tok, 8) != 8) return -2;
        if (sys_read(fds[RING - 1][0], &tok, 8) != 8) return -3;
    }
    for (int i = 1; i < RING; i++) {
        int st;
        if (sys_wait4(pids[i], &st, 0, 0) != pids[i] || !WIFEXITED(st) || WEXITSTATUS(st)) return -4;
    }
    for (int i = 0; i < RING; i++) { sys_close(fds[i][0]); sys_close(fds[i][1]); }
    return tok == (unsigned long)RING * LAPS ? 0 : -5;
}

int main(void)
{
    if (run_ring()) U_FAIL(NAME, "token ring");
    /* yield storm */
    int pids[4];
    for (int i = 0; i < 4; i++) {
        int pid = sys_fork();
        if (pid == 0) { for (int k = 0; k < 300; k++) sys_sched_yield(); sys_exit(0); }
        pids[i] = pid;
    }
    for (int i = 0; i < 4; i++) { int st; if (sys_wait4(pids[i], &st, 0, 0) != pids[i] || WEXITSTATUS(st)) U_FAIL(NAME, "yielders"); }
    /* preemption: shared page records each spinner's [start, end] */
    volatile long *shm = (volatile long *)sys_mmap(0, U_PAGE, PROT_READ | PROT_WRITE, MAP_SHARED | MAP_ANONYMOUS, -1, 0);
    if ((long)shm < 0 && (long)shm > -4096) U_FAIL(NAME, "shm");
    for (int i = 0; i < 2; i++) {
        int pid = sys_fork();
        if (pid == 0) {
            shm[2 * i] = u_now_ns();
            volatile unsigned long x = 0;
            /* > 3 ticks of pure computation, never blocking */
            for (unsigned long k = 0; k < 1500000; k++) x += k ^ (x >> 3);
            shm[2 * i + 1] = u_now_ns();
            sys_exit(0);
        }
        pids[i] = pid;
    }
    for (int i = 0; i < 2; i++) { int st; sys_wait4(pids[i], &st, 0, 0); }
    long s0 = shm[0], e0 = shm[1], s1 = shm[2], e1 = shm[3];
    if (!(s0 < e1 && s1 < e0)) U_FAIL(NAME, "CPU-bound processes were not interleaved");
    return prog_pass(NAME, (unsigned long)RING * LAPS);
}
