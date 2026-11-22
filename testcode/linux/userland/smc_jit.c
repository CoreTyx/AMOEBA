/*
 * smc_jit -- self-modifying code the way a JIT does it under Linux.
 *   1. RWX anonymous mapping: write code, riscv_flush_icache(), call -- x200
 *   2. the same with a bare `fence.i` from U-mode instead of the syscall
 *   3. W^X: map RW, write, mprotect(PROT_READ|PROT_EXEC), flush, call
 *   4. a file mapped twice MAP_SHARED: write through the RW view, execute
 *      through the RX view at a different virtual address
 * Code: `lui a0, hi ; addiw a0, a0, lo ; ret`, a fresh constant every time.
 */
#include "ustress.h"
#define NAME "smc_jit"

static void emit(volatile unsigned int *c, int v)
{
    unsigned int hi = ((unsigned)v + 0x800u) >> 12;
    c[0] = ((hi & 0xfffff) << 12) | (10u << 7) | 0x37;
    c[1] = ((unsigned)(v & 0xfff) << 20) | (10u << 15) | (10u << 7) | 0x1b;
    c[2] = 0x00008067;
}
static long call(void *p) { return ((long (*)(void))p)(); }

int main(void)
{
    unsigned long sum = 0;
    char *rwx = (char *)sys_mmap(0, 4 * U_PAGE, PROT_READ | PROT_WRITE | PROT_EXEC, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
    if ((long)rwx < 0 && (long)rwx > -4096) U_FAIL(NAME, "mmap rwx");
    for (int i = 0; i < 200; i++) {
        int v = (int)(u_rand() & 0x7fffffff);
        char *f = rwx + (u_rand() % (4 * U_PAGE / 16 - 1)) * 16;
        emit((volatile unsigned int *)f, v);
        if (i & 1) sys_flush_icache(f, f + 12);
        else __asm__ volatile ("fence.i" ::: "memory");
        if (call(f) != v) U_FAIL(NAME, "rwx jit result");
        sum += (unsigned long)v;
    }
    /* W^X */
    for (int i = 0; i < 20; i++) {
        char *w = (char *)sys_mmap(0, U_PAGE, PROT_READ | PROT_WRITE, MAP_PRIVATE | MAP_ANONYMOUS, -1, 0);
        int v = (int)(u_rand() & 0xffffff);
        emit((volatile unsigned int *)(w + 64), v);
        if (sys_mprotect(w, U_PAGE, PROT_READ | PROT_EXEC)) U_FAIL(NAME, "mprotect rx");
        sys_flush_icache(w, w + U_PAGE);
        if (call(w + 64) != v) U_FAIL(NAME, "w^x result");
        sys_munmap(w, U_PAGE);
        sum += (unsigned long)v;
    }
    /* dual mapping of a shared file */
    int fd = sys_openat(AT_FDCWD, "/jitfile", O_RDWR | O_CREAT | O_TRUNC, 0700);
    if (fd < 0) U_FAIL(NAME, "open /jitfile");
    if (sys_ftruncate(fd, U_PAGE)) U_FAIL(NAME, "ftruncate");
    char *rw = (char *)sys_mmap(0, U_PAGE, PROT_READ | PROT_WRITE, MAP_SHARED, fd, 0);
    char *rx = (char *)sys_mmap(0, U_PAGE, PROT_READ | PROT_EXEC, MAP_SHARED, fd, 0);
    if (((long)rw < 0 && (long)rw > -4096) || ((long)rx < 0 && (long)rx > -4096)) U_FAIL(NAME, "mmap shared");
    if (rw == rx) U_FAIL(NAME, "views not distinct");
    for (int i = 0; i < 50; i++) {
        int v = (int)(u_rand() & 0x7fffff);
        unsigned off = (unsigned)(u_rand() % 200) * 16;
        emit((volatile unsigned int *)(rw + off), v);
        sys_flush_icache(rx + off, rx + off + 12);
        if (call(rx + off) != v) U_FAIL(NAME, "dual-map result");
        sum += (unsigned long)v;
    }
    sys_close(fd);
    return prog_pass(NAME, sum);
}
