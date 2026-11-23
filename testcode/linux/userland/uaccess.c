/*
 * uaccess -- the kernel touching user memory: S-mode loads and stores with
 * sstatus.SUM set, and the page faults they take.
 *   1. user pointers to kernel, unmapped and PROT_NONE memory: -EFAULT, not an
 *      oops; a read() into a read-only page fails and leaves the data queued
 *   2. a read() into a page never touched (demand-zero fault in S-mode) and
 *      into a copy-on-write page after fork (S-mode store fault, COW in the
 *      kernel): the reader sees the data, the other process keeps its own
 *   3. a write() from a buffer running into a PROT_NONE page: -EFAULT or a
 *      short count, and what arrived is the buffer's prefix
 *   4. a path string ending on the last byte of a page, followed by PROT_NONE:
 *      found; the same string without its NUL: -EFAULT
 *   5. kernel copies at every source and destination misalignment 0..15 and
 *      lengths 1..72, through a pipe, checked byte for byte
 *   6. MADV_DONTNEED behind a write() source between rounds: the kernel
 *      refaults the zero page and sends zeros
 */
#include "ustress.h"
#define NAME "uaccess"

#define KERNEL_ADDR ((void *)0xffffffff80000000UL)
#define UNMAPPED    ((void *)0x3000UL)

static int fds[2];

static int drain(void *buf, int want)
{
    int got = 0;
    while (got < want) {
        long n = sys_read(fds[0], (char *)buf + got, (size_t)(want - got));
        if (n <= 0)
            return -1;
        got += (int)n;
    }
    return got;
}

int main(void)
{
    unsigned long sum = 0;
    char buf[256];
    u_probe_install();
    if (sys_pipe2(fds, 0)) U_FAIL(NAME, "pipe2");

    char *ro = u_map(U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
    char *none = u_map(U_PAGE, PROT_NONE, MAP_PRIVATE);
    if (!ro || !none) U_FAIL(NAME, "mmap");
    ro[0] = 1;
    sys_mprotect(ro, U_PAGE, PROT_READ);

    /* 1 */
    void *bad[] = { KERNEL_ADDR, UNMAPPED, none };
    for (unsigned i = 0; i < 3; i++) {
        if (sys_write(fds[1], bad[i], 8) != -EFAULT) U_FAIL(NAME, "write from a bad pointer");
        if (sys_write(fds[1], "abcdefgh", 8) != 8) U_FAIL(NAME, "write");
        if (sys_read(fds[0], bad[i], 8) != -EFAULT) U_FAIL(NAME, "read into a bad pointer");
        if (sys_read(fds[0], ro + 64, 8) != -EFAULT) U_FAIL(NAME, "read into a read-only page");
        if (drain(buf, 8) != 8 || memcmp(buf, "abcdefgh", 8)) U_FAIL(NAME, "data lost by a failed read");
    }
    struct timespec ts = { 0, 1 };
    if (sys_uname(UNMAPPED) != -EFAULT) U_FAIL(NAME, "uname to an unmapped buffer");
    if (sys_uname(KERNEL_ADDR) != -EFAULT) U_FAIL(NAME, "uname to a kernel address");
    if (sys_clock_gettime(CLOCK_MONOTONIC, (void *)ro) != -EFAULT) U_FAIL(NAME, "clock_gettime into a read-only page");
    if (sys_nanosleep(UNMAPPED, 0) != -EFAULT) U_FAIL(NAME, "nanosleep from an unmapped request");
    if (sys_nanosleep(&ts, KERNEL_ADDR) != 0) U_FAIL(NAME, "nanosleep");
    if (sys_openat(AT_FDCWD, UNMAPPED, O_RDONLY, 0) != -EFAULT) U_FAIL(NAME, "openat with an unmapped path");

    /* 2: demand-zero page filled by the kernel */
    for (int round = 0; round < 8; round++) {
        char *fresh = u_map(2 * U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
        if (!fresh) U_FAIL(NAME, "mmap");
        for (int i = 0; i < 64; i++) buf[i] = (char)(round * 64 + i);
        sys_write(fds[1], buf, 64);
        char *dst = fresh + U_PAGE - 32 + round;       /* straddles the two pages */
        if (drain(dst, 64) != 64 || memcmp(dst, buf, 64)) U_FAIL(NAME, "read into an untouched page");
        if (fresh[0] != 0 || fresh[2 * U_PAGE - 1] != 0) U_FAIL(NAME, "demand-zero page not zero");
        sum = u_mix(sum + crc32(dst, 64));
        sys_munmap(fresh, 2 * U_PAGE);
    }

    /* 2: copy-on-write page written by the kernel, in the child, then in the parent */
    char *cow = u_map(U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
    if (!cow) U_FAIL(NAME, "mmap");
    for (int round = 0; round < 6; round++) {
        memset(cow, 0x11 + round, U_PAGE);
        int pid = sys_fork();
        if (pid < 0) U_FAIL(NAME, "fork");
        int kernel_writes_child = round & 1;
        if (pid == 0) {
            if (kernel_writes_child) {
                if (drain(cow + 100, 16) != 16) sys_exit(2);
                for (int i = 0; i < 16; i++) if (cow[100 + i] != (char)(0x70 + i)) sys_exit(3);
            }
            for (int i = 0; i < 100; i++) if (cow[i] != (char)(0x11 + round)) sys_exit(4);
            if (!kernel_writes_child)
                for (int i = 100; i < 116; i++) if (cow[i] != (char)(0x11 + round)) sys_exit(5);
            sys_exit(0);
        }
        for (int i = 0; i < 16; i++) buf[i] = (char)(0x70 + i);
        if (kernel_writes_child) {
            sys_write(fds[1], buf, 16);
        } else {
            sys_write(fds[1], buf, 16);
            if (drain(cow + 100, 16) != 16) U_FAIL(NAME, "read into a COW page");
        }
        int st = 0;
        if (sys_wait4(pid, &st, 0, 0) != pid || !WIFEXITED(st) || WEXITSTATUS(st)) U_FAIL(NAME, "child saw the wrong COW data");
        for (int i = 100; i < 116; i++) {
            char want = kernel_writes_child ? (char)(0x11 + round) : (char)(0x70 + i - 100);
            if (cow[i] != want) U_FAIL(NAME, "parent saw the wrong COW data");
        }
        sum = u_mix(sum + (unsigned char)cow[100]);
    }

    /* 3: a write source running into PROT_NONE */
    char *pair = u_map(2 * U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
    if (!pair) U_FAIL(NAME, "mmap");
    for (unsigned i = 0; i < U_PAGE; i++) pair[i] = (char)(i * 7);
    sys_mprotect(pair + U_PAGE, U_PAGE, PROT_NONE);
    for (int before = 1; before <= 24; before += 7) {
        long n = sys_write(fds[1], pair + U_PAGE - before, 32);
        if (n != -EFAULT && (n <= 0 || n > before)) U_FAIL(NAME, "write across a PROT_NONE page");
        if (n > 0) {
            if (drain(buf, (int)n) != n || memcmp(buf, pair + U_PAGE - before, (size_t)n)) U_FAIL(NAME, "short write data");
            sum = u_mix(sum + (unsigned long)n);
        }
    }

    /* 4: a path ending on the last byte of a page */
    static const char path[] = "/dev/console";
    char *end = pair + U_PAGE - sizeof path;
    memcpy(end, path, sizeof path);
    int fd = sys_openat(AT_FDCWD, end, O_RDONLY | O_NOCTTY, 0);
    if (fd < 0) U_FAIL(NAME, "openat with a path at the end of a page");
    sys_close(fd);
    memcpy(end + 1, path, sizeof path - 1);           /* no NUL before PROT_NONE */
    if (sys_openat(AT_FDCWD, end + 1, O_RDONLY | O_NOCTTY, 0) != -EFAULT) U_FAIL(NAME, "unterminated path into PROT_NONE");

    /* 5: misaligned kernel copies */
    static char src[160], dst[160];
    for (int i = 0; i < 160; i++) src[i] = (char)u_rand();
    for (int s = 0; s < 16; s++)
        for (int d = 0; d < 16; d++) {
            int len = 1 + (s * 16 + d) % 72;
            memset(dst, 0, sizeof dst);
            if (sys_write(fds[1], src + s, (size_t)len) != len) U_FAIL(NAME, "misaligned write");
            if (drain(dst + d, len) != len) U_FAIL(NAME, "misaligned read");
            if (memcmp(dst + d, src + s, (size_t)len)) U_FAIL(NAME, "misaligned kernel copy corrupted data");
            for (int i = 0; i < d; i++) if (dst[i]) U_FAIL(NAME, "kernel copy wrote before its buffer");
            if (dst[d + len]) U_FAIL(NAME, "kernel copy wrote past its buffer");
        }
    sum = u_mix(sum + crc32(src, sizeof src));

    /* 6: the zero page behind a write source */
    char *dz = u_map(4 * U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE);
    if (!dz) U_FAIL(NAME, "mmap");
    static char got[4 * 4096];
    for (int round = 0; round < 4; round++) {
        memset(dz, 0x5c, 4 * U_PAGE);
        sys_madvise(dz + (unsigned long)round * U_PAGE, U_PAGE, MADV_DONTNEED);
        if (sys_write(fds[1], dz, 4 * U_PAGE) != (long)(4 * U_PAGE)) U_FAIL(NAME, "write of 16 KiB");
        if (drain(got, 4 * U_PAGE) != (int)(4 * U_PAGE)) U_FAIL(NAME, "read of 16 KiB");
        for (unsigned i = 0; i < 4 * U_PAGE; i++) {
            char want = i / U_PAGE == (unsigned)round ? 0 : 0x5c;
            if (got[i] != want) U_FAIL(NAME, "MADV_DONTNEED page sent the wrong data");
        }
    }
    return prog_pass(NAME, sum);
}
