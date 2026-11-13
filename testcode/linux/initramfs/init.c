/*
 * PID 1 for the boot test.
 *
 * Prints AMOEBA_LINUX_BOOT_OK first -- unchanged from the original init.S, so
 * the boot nightly's milestone means exactly what it did -- then runs each
 * userland test program (testcode/linux/userland/) in turn:
 *
 *     fork -> execve("/bin/<name>") -> wait4
 *
 * and prints `PROG_EXIT <name> <code>` for each.  When all have run it prints
 * AMOEBA_LINUX_PROGS_OK if every one exited 0, else AMOEBA_PROG_FAIL <name>
 * for the first that did not.  The CI tier matches on those two strings.
 *
 * Freestanding C against the raw syscall ABI (userland/syscall.h) with the
 * shared crt0, so the bare-metal-capable cross compiler is all that is needed.
 *
 * init must not return -- a PID 1 that exits panics the kernel, which would
 * turn a passing run into a confusing failure.  The final loop is safe because
 * ECE411_LINUX stops the testbench treating `j .` as a halt instruction.
 */
#include "ulib.h"

/* AMOEBA_PROGS is supplied by the Makefile from its PROGS list, as a
 * comma-terminated list of string literals. */
#ifndef AMOEBA_PROGS
#error "build with -DAMOEBA_PROGS='\"prog\",...'"
#endif
static const char *const progs[] = { AMOEBA_PROGS };
#define NPROGS (sizeof progs / sizeof progs[0])

static void console_setup(void)
{
    /* The kernel opens /dev/console as fds 0/1/2 for init, but only if the
     * node exists in the initramfs (see initramfs.spec).  Do not rely on it:
     * open the console explicitly and make it 0/1/2.  If that fails, fall
     * back to whatever fd 1 the kernel gave us. */
    int fd = sys_openat(AT_FDCWD, "/dev/console", O_RDWR | O_NOCTTY, 0);
    if (fd < 0)
        return;
    for (int i = 0; i < 3; i++)
        if (fd != i)
            sys_dup3(fd, i, 0);
    if (fd > 2)
        sys_close(fd);
}

static int run(const char *prog)
{
    char path[64] = "/bin/";
    size_t n = strlen(path);
    for (const char *s = prog; *s && n < sizeof path - 1; s++)
        path[n++] = *s;
    path[n] = 0;

    char *argv[] = { path, 0 };
    char *envp[] = { 0 };

    int pid = sys_fork();
    if (pid == 0) {
        int err = sys_execve(path, argv, envp);
        out_str("PROG ");
        out_str(prog);
        out_str(" FAIL execve ");
        out_dec(err);
        out_str("\n");
        sys_exit(127);
    }
    if (pid < 0) {
        out_str("PROG ");
        out_str(prog);
        out_str(" FAIL fork ");
        out_dec(pid);
        out_str("\n");
        return -1;
    }

    int status = 0;
    long r;
    do {
        r = sys_wait4(pid, &status, 0, 0);
    } while (r == -4 /* -EINTR */);

    out_str("PROG_EXIT ");
    out_str(prog);
    if (r != pid) {
        out_str(" wait4 ");
        out_dec(r);
        out_str("\n");
        return -1;
    }
    if (WIFEXITED(status)) {
        out_str(" ");
        out_dec(WEXITSTATUS(status));
        out_str("\n");
        return WEXITSTATUS(status);
    }
    out_str(" signal ");
    out_dec(WTERMSIG(status));
    out_str("\n");
    return -1;
}

int main(void)
{
    console_setup();
    out_str("AMOEBA_LINUX_BOOT_OK\n");

    const char *failed = 0;
    for (unsigned i = 0; i < NPROGS; i++)
        if (run(progs[i]) != 0 && !failed)
            failed = progs[i];

    if (failed) {
        out_str("AMOEBA_PROG_FAIL ");
        out_str(failed);
        out_str("\n");
    } else {
        out_str("AMOEBA_LINUX_PROGS_OK\n");
    }

    for (;;)
        ;   /* never exit: PID 1 returning is a panic */
}
