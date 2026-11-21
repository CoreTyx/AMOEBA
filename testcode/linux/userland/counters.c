/*
 * counters -- rdcycle / rdtime / rdinstret from userland on a core with no
 * Zicntr (pkg/config.vh: COUNTERS = 0).  The hardware traps all three.
 * OpenSBI emulates `time` from the CLINT; for cycle/instret there is no
 * mcycle to read.  Whatever the stack decides, the outcome must be a value
 * or a SIGILL -- NEVER an SBI panic, a kernel oops or a hang, because any
 * program built for a generic RISC-V target may execute these.  rdtime, if it
 * works, must be monotonic.  The program reports what it saw.
 */
#include "ustress.h"
#define NAME "counters"

static u_jmpbuf jb;
static volatile int g_sig;
static void on_sig(int sig, void *i, void *u) { (void)i; (void)u; g_sig = sig; u_longjmp(jb, 1); }

static int try_csr(int which, unsigned long *out)
{
    g_sig = 0;
    if (u_setjmp(jb) == 0) {
        unsigned long v;
        if (which == 0) __asm__ volatile ("rdcycle %0" : "=r"(v));
        else if (which == 1) __asm__ volatile ("rdtime %0" : "=r"(v));
        else __asm__ volatile ("rdinstret %0" : "=r"(v));
        *out = v;
        return 1;
    }
    return 0;
}

int main(void)
{
    static const char *const nm[3] = { "cycle", "time", "instret" };
    u_signal(SIGILL, on_sig);
    unsigned long sum = 0;
    for (int w = 0; w < 3; w++) {
        unsigned long v = 0, prev = 0;
        int ok = 0, sig = 0;
        for (int k = 0; k < 20; k++) {
            if (try_csr(w, &v)) {
                ok++;
                if (w == 1 && k && v < prev) U_FAIL(NAME, "rdtime went backwards");
                prev = v;
            } else if (g_sig == SIGILL) sig++;
            else U_FAIL(NAME, "unexpected signal");
        }
        out_str("COUNTER ");
        out_str(nm[w]);
        out_str(ok ? " value " : " SIGILL ");
        out_hex(ok ? v : (unsigned long)sig);
        out_str("\n");
        if (ok && sig) U_FAIL(NAME, "inconsistent: sometimes a value, sometimes SIGILL");
        sum += (unsigned long)ok;
    }
    return prog_pass(NAME, sum);
}
