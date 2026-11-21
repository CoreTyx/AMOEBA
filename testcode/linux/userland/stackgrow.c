/*
 * stackgrow -- the stack VMA growing by page faults.  A 256-deep recursion
 * with 2 KiB frames (512 KiB) writes a pattern into every frame and checks it
 * on the way back up, then a 320 KiB local array is touched page by page
 * downwards.  Every new stack page is a fault the kernel resolves by expanding
 * the stack VMA.
 */
#include "ustress.h"
#define NAME "stackgrow"

static unsigned long __attribute__((noinline)) dive(int depth, unsigned long seed)
{
    volatile unsigned long frame[256];
    for (int i = 0; i < 256; i++) frame[i] = u_mix(seed + (unsigned long)i);
    unsigned long r = depth ? dive(depth - 1, seed * 3 + 1) : 0;
    for (int i = 0; i < 256; i++) if (frame[i] != u_mix(seed + (unsigned long)i)) return ~0UL;
    return r == ~0UL ? r : r + frame[depth & 255];
}

static unsigned long __attribute__((noinline)) big_local(void)
{
    volatile unsigned char big[320 * 1024];
    for (long off = (long)sizeof big - 1; off >= 0; off -= (long)U_PAGE) big[off] = (unsigned char)off;
    unsigned long s = 0;
    for (long off = (long)sizeof big - 1; off >= 0; off -= (long)U_PAGE) {
        if (big[off] != (unsigned char)off) return ~0UL;
        s += big[off];
    }
    return s;
}

int main(void)
{
    unsigned long a = dive(255, 7);
    if (a == ~0UL) U_FAIL(NAME, "frame corrupted during deep recursion");
    unsigned long b = big_local();
    if (b == ~0UL) U_FAIL(NAME, "large stack array corrupted");
    return prog_pass(NAME, a ^ b);
}
