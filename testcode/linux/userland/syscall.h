/*
 * Raw RISC-V Linux syscall wrappers for the freestanding boot-test userland.
 *
 * ABI: number in a7, arguments in a0..a5, `ecall`, result in a0.  A result in
 * [-4095, -1] is -errno; there is no errno variable and nothing translates it.
 *
 * RISC-V uses the asm-generic syscall table, which has no fork, pipe, dup2,
 * open or waitpid.  The wrappers below spell those the way libc does: clone
 * with SIGCHLD, pipe2, dup3, openat and wait4.
 */
#ifndef AMOEBA_SYSCALL_H
#define AMOEBA_SYSCALL_H

#define __NR_dup3            24
#define __NR_openat          56
#define __NR_close           57
#define __NR_pipe2           59
#define __NR_read            63
#define __NR_write           64
#define __NR_exit_group      94
#define __NR_clock_gettime  113
#define __NR_sched_yield    124
#define __NR_uname          160
#define __NR_getpid         172
#define __NR_getppid        173
#define __NR_brk            214
#define __NR_munmap         215
#define __NR_clone          220
#define __NR_execve         221
#define __NR_mmap           222
#define __NR_wait4          260

#define AT_FDCWD        (-100)
#define O_RDONLY        0
#define O_WRONLY        1
#define O_RDWR          2
#define O_NOCTTY        0400

#define SIGCHLD         17

#define PROT_READ       1
#define PROT_WRITE      2
#define MAP_PRIVATE     0x02
#define MAP_ANONYMOUS   0x20

#define CLOCK_REALTIME  0
#define CLOCK_MONOTONIC 1

#define WIFEXITED(s)    (((s) & 0x7f) == 0)
#define WEXITSTATUS(s)  (((s) >> 8) & 0xff)
#define WTERMSIG(s)     ((s) & 0x7f)

typedef unsigned long size_t;
typedef long          ssize_t;

struct timespec {
    long tv_sec;
    long tv_nsec;
};

struct utsname {
    char sysname[65];
    char nodename[65];
    char release[65];
    char version[65];
    char machine[65];
    char domainname[65];
};

static inline long __syscall6(long n, long a, long b, long c, long d, long e, long f)
{
    register long a7 __asm__("a7") = n;
    register long a0 __asm__("a0") = a;
    register long a1 __asm__("a1") = b;
    register long a2 __asm__("a2") = c;
    register long a3 __asm__("a3") = d;
    register long a4 __asm__("a4") = e;
    register long a5 __asm__("a5") = f;
    __asm__ volatile ("ecall"
                      : "+r"(a0)
                      : "r"(a7), "r"(a1), "r"(a2), "r"(a3), "r"(a4), "r"(a5)
                      : "memory");
    return a0;
}

#define SYS0(n)                 __syscall6((n), 0, 0, 0, 0, 0, 0)
#define SYS1(n, a)              __syscall6((n), (long)(a), 0, 0, 0, 0, 0)
#define SYS2(n, a, b)           __syscall6((n), (long)(a), (long)(b), 0, 0, 0, 0)
#define SYS3(n, a, b, c)        __syscall6((n), (long)(a), (long)(b), (long)(c), 0, 0, 0)
#define SYS4(n, a, b, c, d)     __syscall6((n), (long)(a), (long)(b), (long)(c), (long)(d), 0, 0)
#define SYS6(n, a, b, c, d, e, f) \
    __syscall6((n), (long)(a), (long)(b), (long)(c), (long)(d), (long)(e), (long)(f))

static inline ssize_t sys_read(int fd, void *buf, size_t n)        { return SYS3(__NR_read, fd, buf, n); }
static inline ssize_t sys_write(int fd, const void *buf, size_t n) { return SYS3(__NR_write, fd, buf, n); }
static inline int  sys_openat(int dfd, const char *p, int fl, int mode) { return SYS4(__NR_openat, dfd, p, fl, mode); }
static inline int  sys_close(int fd)                   { return SYS1(__NR_close, fd); }
static inline int  sys_dup3(int old, int new_, int fl) { return SYS3(__NR_dup3, old, new_, fl); }
static inline int  sys_pipe2(int fds[2], int fl)       { return SYS2(__NR_pipe2, fds, fl); }
static inline int  sys_getpid(void)                    { return SYS0(__NR_getpid); }
static inline int  sys_getppid(void)                   { return SYS0(__NR_getppid); }
static inline int  sys_sched_yield(void)               { return SYS0(__NR_sched_yield); }
static inline int  sys_uname(struct utsname *u)        { return SYS1(__NR_uname, u); }
static inline int  sys_clock_gettime(int clk, struct timespec *ts) { return SYS2(__NR_clock_gettime, clk, ts); }
static inline long sys_brk(void *addr)                 { return SYS1(__NR_brk, addr); }
static inline long sys_mmap(void *addr, size_t len, int prot, int flags, int fd, long off)
{
    return SYS6(__NR_mmap, addr, len, prot, flags, fd, off);
}
static inline int  sys_munmap(void *addr, size_t len)  { return SYS2(__NR_munmap, addr, len); }
static inline int  sys_execve(const char *path, char *const argv[], char *const envp[])
{
    return SYS3(__NR_execve, path, argv, envp);
}
static inline int  sys_wait4(int pid, int *status, int options, void *rusage)
{
    return SYS4(__NR_wait4, pid, status, options, rusage);
}

/* fork() == clone(SIGCHLD, 0, ...): no new stack, so the child resumes on a
 * copy-on-write image of the parent's, exactly as fork does. */
static inline int sys_fork(void) { return SYS2(__NR_clone, SIGCHLD, 0); }

static inline __attribute__((noreturn)) void sys_exit(int code)
{
    SYS1(__NR_exit_group, code);
    for (;;)
        ;
}

#endif /* AMOEBA_SYSCALL_H */
