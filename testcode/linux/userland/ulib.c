#include "ulib.h"

void *memset(void *d, int c, size_t n)
{
    unsigned char *p = d;
    while (n--)
        *p++ = (unsigned char)c;
    return d;
}

void *memcpy(void *d, const void *s, size_t n)
{
    unsigned char *dp = d;
    const unsigned char *sp = s;
    while (n--)
        *dp++ = *sp++;
    return d;
}

int memcmp(const void *a, const void *b, size_t n)
{
    const unsigned char *x = a, *y = b;
    for (; n; n--, x++, y++)
        if (*x != *y)
            return *x - *y;
    return 0;
}

size_t strlen(const char *s)
{
    const char *p = s;
    while (*p)
        p++;
    return p - s;
}

int strcmp(const char *a, const char *b)
{
    while (*a && *a == *b)
        a++, b++;
    return (unsigned char)*a - (unsigned char)*b;
}

int strncmp(const char *a, const char *b, size_t n)
{
    for (; n; n--, a++, b++) {
        if (*a != *b)
            return (unsigned char)*a - (unsigned char)*b;
        if (!*a)
            break;
    }
    return 0;
}

static char   obuf[256];
static size_t olen;

void out_flush(void)
{
    size_t off = 0;
    while (off < olen) {
        ssize_t r = sys_write(1, obuf + off, olen - off);
        if (r <= 0)
            break;
        off += r;
    }
    olen = 0;
}

static void out_ch(char c)
{
    if (olen == sizeof obuf)
        out_flush();
    obuf[olen++] = c;
    if (c == '\n')
        out_flush();
}

void out_str(const char *s)
{
    while (*s)
        out_ch(*s++);
}

void out_hex(unsigned long v)
{
    static const char digits[] = "0123456789abcdef";
    char tmp[16];
    int n = 0;
    do {
        tmp[n++] = digits[v & 15];
        v >>= 4;
    } while (v);
    while (n)
        out_ch(tmp[--n]);
}

void out_dec(long v)
{
    char tmp[20];
    int n = 0;
    unsigned long u = v < 0 ? -(unsigned long)v : (unsigned long)v;
    if (v < 0)
        out_ch('-');
    do {
        tmp[n++] = '0' + u % 10;
        u /= 10;
    } while (u);
    while (n)
        out_ch(tmp[--n]);
}

unsigned crc32_update(unsigned crc, const void *buf, size_t n)
{
    const unsigned char *p = buf;
    crc = ~crc;
    while (n--) {
        crc ^= *p++;
        for (int k = 0; k < 8; k++)
            crc = (crc >> 1) ^ (0xEDB88320u & -(crc & 1));
    }
    return ~crc;
}

int prog_pass(const char *name, unsigned long checksum)
{
    out_str("PROG ");
    out_str(name);
    out_str(" PASS ");
    out_hex(checksum);
    out_str("\n");
    return 0;
}

int prog_fail(const char *name, const char *reason)
{
    out_str("PROG ");
    out_str(name);
    out_str(" FAIL ");
    out_str(reason);
    out_str("\n");
    return 1;
}
