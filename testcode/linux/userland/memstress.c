/*
 * memstress -- userland memory traffic: memcpy/memmove at every alignment
 * and many lengths (overlapping and not), a random read-modify-write walk
 * over 1 MiB of brk memory (far beyond the D$ and the TLB reach), and D$
 * set-conflict strides.  All results checked against computed values.
 */
#include "ustress.h"
#define NAME "memstress"

static void ref_move(unsigned char *d, const unsigned char *s, unsigned long n)
{
    if (d < s) for (unsigned long i = 0; i < n; i++) d[i] = s[i];
    else for (unsigned long i = n; i; i--) d[i - 1] = s[i - 1];
}
static void word_move(unsigned char *d, const unsigned char *s, unsigned long n)
{   /* a different implementation: dword-at-a-time when both aligned */
    if (d < s && !(((unsigned long)d | (unsigned long)s) & 7)) {
        unsigned long i = 0;
        for (; i + 8 <= n; i += 8) *(unsigned long *)(d + i) = *(const unsigned long *)(s + i);
        for (; i < n; i++) d[i] = s[i];
    } else ref_move(d, s, n);
}

/* Big enough for every window below and no bigger: refilling and comparing
 * cost is per combination (2816 of them), on a core with a 65-cycle multiply. */
#define BUF 512
static unsigned char A[BUF], B[BUF];

int main(void)
{
    unsigned long sum = 0;
    for (int sa = 0; sa < 16; sa++)
        for (int da = 0; da < 16; da++)
            for (int len = 0; len < 72; len += 7) {
                unsigned char seed = (unsigned char)(sa * 13 + da * 7 + len);
                for (int i = 0; i < BUF; i++) A[i] = B[i] = (unsigned char)(seed + i * 37);
                memcpy(A + 64 + da, A + 256 + sa, (size_t)len);
                ref_move(B + 64 + da, B + 256 + sa, (unsigned long)len);
                if (memcmp(A, B, BUF)) U_FAIL(NAME, "memcpy");
                word_move(A + 100 + da, A + 100 + sa, (unsigned long)len + 64);   /* overlapping */
                ref_move(B + 100 + da, B + 100 + sa, (unsigned long)len + 64);
                if (memcmp(A, B, BUF)) U_FAIL(NAME, "overlapping move");
                sum += A[64 + da];
            }
    /* 1 MiB of brk */
    unsigned char *cur = (unsigned char *)sys_brk(0);
    unsigned char *top = (unsigned char *)sys_brk(cur + (1 << 20));
    if (top < cur + (1 << 20)) U_FAIL(NAME, "brk grow");
    volatile unsigned long *w = (volatile unsigned long *)(((unsigned long)cur + 7) & ~7UL);
    unsigned long nw = ((1 << 20) - 8) / 8;
    for (unsigned long i = 0; i < nw; i += 7) w[i] = u_mix(i);
    for (int k = 0; k < 20000; k++) {
        unsigned long i = (u_rand() % (nw / 7)) * 7;
        if (w[i] != u_mix(i) && w[i] != u_mix(i) + 1) U_FAIL(NAME, "brk walk");
        if (w[i] == u_mix(i)) w[i] = u_mix(i) + 1; else w[i] = u_mix(i);
    }
    /* set-conflict strides: 1 KiB apart */
    for (int r = 0; r < 200; r++)
        for (unsigned long j = 0; j < 12; j++) {
            volatile unsigned long *p = (volatile unsigned long *)((unsigned long)w + j * 1024 + (unsigned long)(r % 64) * 16);
            *p += j;
            sum += *p;
        }
    sys_brk(cur);
    return prog_pass(NAME, sum);
}
