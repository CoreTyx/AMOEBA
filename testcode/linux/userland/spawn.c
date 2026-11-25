/*
 * spawn -- fork + execve storm.  120 children, 8 alive at a time, each one a
 * full execve of /bin/child (new mm, new page tables, new ASID on the core)
 * with its own argv/envp, reaped out of order with wait4(-1).  Every exit code
 * must match its argument; nothing may be lost or reaped twice.
 */
#include "ustress.h"
#define NAME   "spawn"
#define TOTAL  120
#define LIVE   8

static void itoa_(long v, char *b) { char t[24]; int n = 0; do { t[n++] = (char)('0' + v % 10); v /= 10; } while (v); while (n) *b++ = t[--n]; *b = 0; }

int main(void)
{
    static int pid_of[TOTAL];
    static unsigned char reaped[TOTAL];
    int started = 0, done = 0, live = 0;
    unsigned long sum = 0;
    while (done < TOTAL) {
        while (live < LIVE && started < TOTAL) {
            int n = started;
            int pid = sys_fork();
            if (pid == 0) {
                char a1[24], env[40] = "SPAWN_ENV=";
                itoa_(n, a1);
                itoa_(n, env + 10);
                char *argv[] = { "/bin/child", a1, "AMOEBA", 0 };
                char *envp[] = { env, "OTHER=1", 0 };
                sys_execve("/bin/child", argv, envp);
                sys_exit(249);
            }
            if (pid < 0) U_FAIL(NAME, "fork");
            pid_of[n] = pid;
            started++; live++;
        }
        int st = 0;
        int pid = sys_wait4(-1, &st, 0, 0);
        if (pid <= 0) U_FAIL(NAME, "wait4");
        int n = -1;
        for (int i = 0; i < started; i++) if (pid_of[i] == pid && !reaped[i]) { n = i; break; }
        if (n < 0) U_FAIL(NAME, "unknown or double reap");
        reaped[n] = 1;
        if (!WIFEXITED(st) || WEXITSTATUS(st) != ((n * 7) & 0xff)) U_FAIL(NAME, "child exit code");
        sum += (unsigned long)WEXITSTATUS(st);
        done++; live--;
    }
    if (sys_wait4(-1, 0, 0, 0) != -10 /* -ECHILD */) U_FAIL(NAME, "stray child");
    return prog_pass(NAME, sum);
}
