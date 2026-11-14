/*
 * proc: process creation and IPC.
 *
 *  1. fork three children; each checks getppid() is the parent and exits with
 *     a distinct code.  The parent reaps them out of creation order with
 *     wait4() and checks every exit status.  fork duplicates the address
 *     space copy-on-write, so the child's first stores fault and copy.
 *  2. Pipe ping-pong: a fourth child echoes each 8-byte message back
 *     incremented, over a pair of pipes, for a few rounds; then the parent
 *     closes its write end and expects EOF on the reply pipe after the child
 *     exits.  Each round blocks one side in read(), so it exercises sleeping,
 *     wakeup and a context switch per message.
 */
#include "ulib.h"

#define NKIDS   3
#define ROUNDS  4

static const char *const name = "proc";

static int read_full(int fd, void *buf, size_t n)
{
    size_t got = 0;
    while (got < n) {
        ssize_t r = sys_read(fd, (char *)buf + got, n - got);
        if (r <= 0)
            return -1;
        got += r;
    }
    return 0;
}

static int write_full(int fd, const void *buf, size_t n)
{
    size_t put = 0;
    while (put < n) {
        ssize_t r = sys_write(fd, (const char *)buf + put, n - put);
        if (r <= 0)
            return -1;
        put += r;
    }
    return 0;
}

int main(void)
{
    unsigned long sum = 0;
    int me = sys_getpid();
    int pids[NKIDS];

    /* ---- fork / exit / wait4 ---- */
    for (int i = 0; i < NKIDS; i++) {
        int pid = sys_fork();
        if (pid < 0)
            return prog_fail(name, "fork");
        if (pid == 0)
            sys_exit(sys_getppid() == me ? 10 + 7 * i : 99);
        pids[i] = pid;
    }
    for (int i = NKIDS - 1; i >= 0; i--) {
        int status = -1;
        if (sys_wait4(pids[i], &status, 0, 0) != pids[i])
            return prog_fail(name, "wait4");
        if (!WIFEXITED(status) || WEXITSTATUS(status) != 10 + 7 * i)
            return prog_fail(name, "child-exit-status");
        sum = sum * 31 + WEXITSTATUS(status);
    }
    {
        int status;
        if (sys_wait4(-1, &status, 0, 0) != -10 /* -ECHILD */)
            return prog_fail(name, "stray-child");
    }

    /* ---- pipe ping-pong ---- */
    int down[2], up[2];
    if (sys_pipe2(down, 0) != 0 || sys_pipe2(up, 0) != 0)
        return prog_fail(name, "pipe2");

    int pid = sys_fork();
    if (pid < 0)
        return prog_fail(name, "fork-pipe");
    if (pid == 0) {
        sys_close(down[1]);
        sys_close(up[0]);
        unsigned long v;
        int n = 0;
        while (read_full(down[0], &v, sizeof v) == 0) {
            v += 1;
            if (write_full(up[1], &v, sizeof v) != 0)
                sys_exit(2);
            n++;
        }
        sys_exit(n == ROUNDS ? 0 : 3);
    }
    sys_close(down[0]);
    sys_close(up[1]);

    unsigned long v = 0x1234;
    for (int r = 0; r < ROUNDS; r++) {
        unsigned long reply;
        if (write_full(down[1], &v, sizeof v) != 0)
            return prog_fail(name, "pipe-write");
        if (read_full(up[0], &reply, sizeof reply) != 0)
            return prog_fail(name, "pipe-read");
        if (reply != v + 1)
            return prog_fail(name, "pipe-reply");
        sum = sum * 31 + reply;
        v = reply * 3;
    }
    sys_close(down[1]);   /* child sees EOF and exits */

    int status = -1;
    if (sys_wait4(pid, &status, 0, 0) != pid)
        return prog_fail(name, "wait4-pipe");
    if (!WIFEXITED(status) || WEXITSTATUS(status) != 0)
        return prog_fail(name, "pipe-child-status");

    char c;
    if (sys_read(up[0], &c, 1) != 0)
        return prog_fail(name, "pipe-no-eof");
    sys_close(up[0]);

    return prog_pass(name, sum);
}
