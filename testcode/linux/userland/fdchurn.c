/*
 * fdchurn -- file-descriptor and heap churn: 300 pipe create/write/read/close
 * cycles, 200 open/close of /dev/console, dup3 chains onto high descriptors,
 * and 100 brk grow/shrink cycles that keep the surviving prefix intact.
 */
#include "ustress.h"
#define NAME "fdchurn"

int main(void)
{
    unsigned long sum = 0;
    unsigned char out[64], in[64];
    for (int i = 0; i < 300; i++) {
        int fds[2];
        if (sys_pipe2(fds, 0)) U_FAIL(NAME, "pipe2");
        for (int k = 0; k < 64; k++) out[k] = (unsigned char)(i * 31 + k);
        int wfd = fds[1];
        if (i & 1) { if (sys_dup3(fds[1], 20 + (i % 10), 0) < 0) U_FAIL(NAME, "dup3"); wfd = 20 + (i % 10); }
        if (sys_write(wfd, out, 64) != 64) U_FAIL(NAME, "write");
        if (sys_read(fds[0], in, 64) != 64) U_FAIL(NAME, "read");
        if (memcmp(in, out, 64)) U_FAIL(NAME, "pipe data");
        sys_close(fds[0]); sys_close(fds[1]);
        if (wfd != fds[1]) sys_close(wfd);
        sum += in[i & 63];
    }
    for (int i = 0; i < 200; i++) {
        int fd = sys_openat(AT_FDCWD, "/dev/console", O_RDWR | O_NOCTTY, 0);
        if (fd < 0) U_FAIL(NAME, "open console");
        if (sys_close(fd)) U_FAIL(NAME, "close console");
    }
    unsigned char *base = (unsigned char *)sys_brk(0);
    unsigned long keep = 0;
    for (int i = 0; i < 100; i++) {
        unsigned long grow = 4096 + (u_rand() % 65536);
        unsigned char *top = (unsigned char *)sys_brk(base + keep + grow);
        if (top != base + keep + grow) U_FAIL(NAME, "brk");
        for (unsigned long k = keep; k < keep + grow; k += 64) base[k] = (unsigned char)(k * 7);
        for (unsigned long k = 0; k < keep; k += 64) if (base[k] != (unsigned char)(k * 7)) U_FAIL(NAME, "brk prefix lost");
        keep = (keep + grow) / 2 & ~63UL;
        if ((unsigned char *)sys_brk(base + keep) != base + keep) U_FAIL(NAME, "brk shrink");
        sum += keep;
    }
    sys_brk(base);
    return prog_pass(NAME, sum);
}
