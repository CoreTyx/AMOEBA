/*
 * Minimal support library for the freestanding boot-test userland.
 *
 * Output is line-buffered and each line goes out in a single write(), so a
 * parent and child printing concurrently cannot interleave mid-line on the
 * console the testbench pattern-matches against.
 */
#ifndef AMOEBA_ULIB_H
#define AMOEBA_ULIB_H

#include "syscall.h"

/* GCC may emit calls to these for struct copies and zeroing loops even with
 * -ffreestanding, so they must exist as real symbols. */
void  *memset(void *d, int c, size_t n);
void  *memcpy(void *d, const void *s, size_t n);
int    memcmp(const void *a, const void *b, size_t n);
size_t strlen(const char *s);
int    strcmp(const char *a, const char *b);
int    strncmp(const char *a, const char *b, size_t n);

/* Line-buffered stdout.  out_flush() is implied by a '\n' in out_str(). */
void out_str(const char *s);
void out_hex(unsigned long v);
void out_dec(long v);
void out_flush(void);

/* Bitwise CRC-32 (IEEE 802.3, reflected, as zlib's crc32()). */
unsigned crc32_update(unsigned crc, const void *buf, size_t n);
static inline unsigned crc32(const void *buf, size_t n)
{
    return crc32_update(0, buf, n);
}

/* Result lines in the format the CI tier greps for.  prog_fail returns 1 so
 * a test can `return prog_fail(...)` straight out of main. */
int prog_pass(const char *name, unsigned long checksum);
int prog_fail(const char *name, const char *reason);

/* Hides a value from the optimiser so a computation on it is really executed
 * at run time rather than folded at compile time. */
static inline unsigned long opaque(unsigned long x)
{
    __asm__ volatile ("" : "+r"(x));
    return x;
}

#endif /* AMOEBA_ULIB_H */
