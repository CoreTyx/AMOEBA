/* Minimal <string.h> for building riscv-tests' env/v with a bare-metal
 * toolchain that ships no libc headers (Ubuntu's gcc-riscv64-unknown-elf).
 * The definitions are in third_party/riscv-tests/env/v/string.c. */
#ifndef AMOEBA_RT_STRING_H
#define AMOEBA_RT_STRING_H
#include <stddef.h>
void  *memcpy(void *d, const void *s, size_t n);
void  *memset(void *d, int c, size_t n);
int    memcmp(const void *a, const void *b, size_t n);
size_t strlen(const char *s);
int    strcmp(const char *a, const char *b);
char  *strcpy(char *d, const char *s);
long   atol(const char *s);
#endif
