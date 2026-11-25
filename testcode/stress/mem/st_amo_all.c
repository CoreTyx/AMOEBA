// @stress tier=pr seeds=2 build=no_spike duts=legacy,forte timeout=30000000
//
// st_amo_all -- every AMO, every width, every ordering suffix, edge values.
//
// Linux's atomics (atomic_t, bitops, refcounts, the ticket spinlock OpenSBI
// uses) compile to all nine AMO operations in both widths with aq/rl variants.
// For each: the old value is returned in rd (sign-extended for .w), memory gets
// op(old, rs2) computed on the right width with the right signedness, the
// neighbouring word of a .w is untouched, and it works on a cold line, a hot
// clean line and a dirty line.  Then the illegal cases: AMO to a read-only
// page (store page fault), to a hole and to MMIO (no atomic PMA: store access
// fault), with memory unchanged.
#include "../lib/stress.h"

#ifndef ST_SCALE
#define ST_SCALE 1
#endif

static uint64_t amo_swap_w(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoswap.w %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_swap_w_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoswap.w.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_swap_w_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoswap.w.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_swap_w_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoswap.w.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_add_w(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoadd.w %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_add_w_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoadd.w.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_add_w_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoadd.w.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_add_w_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoadd.w.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_xor_w(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoxor.w %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_xor_w_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoxor.w.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_xor_w_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoxor.w.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_xor_w_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoxor.w.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_and_w(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoand.w %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_and_w_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoand.w.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_and_w_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoand.w.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_and_w_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoand.w.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_or_w(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoor.w %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_or_w_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoor.w.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_or_w_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoor.w.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_or_w_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoor.w.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_min_w(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomin.w %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_min_w_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomin.w.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_min_w_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomin.w.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_min_w_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomin.w.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_max_w(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomax.w %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_max_w_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomax.w.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_max_w_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomax.w.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_max_w_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomax.w.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_minu_w(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amominu.w %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_minu_w_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amominu.w.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_minu_w_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amominu.w.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_minu_w_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amominu.w.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_maxu_w(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomaxu.w %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_maxu_w_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomaxu.w.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_maxu_w_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomaxu.w.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_maxu_w_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomaxu.w.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_swap_d(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoswap.d %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_swap_d_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoswap.d.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_swap_d_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoswap.d.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_swap_d_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoswap.d.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_add_d(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoadd.d %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_add_d_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoadd.d.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_add_d_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoadd.d.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_add_d_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoadd.d.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_xor_d(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoxor.d %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_xor_d_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoxor.d.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_xor_d_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoxor.d.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_xor_d_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoxor.d.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_and_d(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoand.d %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_and_d_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoand.d.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_and_d_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoand.d.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_and_d_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoand.d.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_or_d(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoor.d %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_or_d_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoor.d.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_or_d_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoor.d.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_or_d_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amoor.d.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_min_d(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomin.d %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_min_d_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomin.d.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_min_d_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomin.d.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_min_d_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomin.d.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_max_d(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomax.d %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_max_d_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomax.d.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_max_d_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomax.d.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_max_d_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomax.d.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_minu_d(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amominu.d %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_minu_d_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amominu.d.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_minu_d_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amominu.d.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_minu_d_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amominu.d.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_maxu_d(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomaxu.d %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_maxu_d_aq(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomaxu.d.aq %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_maxu_d_rl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomaxu.d.rl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }
static uint64_t amo_maxu_d_aqrl(uint64_t a, uint64_t b) { uint64_t r; __asm__ volatile ("amomaxu.d.aqrl %0, %2, (%1)" : "=r"(r) : "r"(a), "r"(b) : "memory"); return r; }

enum { OP_SWAP, OP_ADD, OP_XOR, OP_AND, OP_OR, OP_MIN, OP_MAX, OP_MINU, OP_MAXU };
typedef struct { uint64_t (*fn)(uint64_t, uint64_t); int op; int sz; const char *name; } amo_t;
static const amo_t g_amo[] = {
    { amo_swap_w, 0, 4, "amoswap.w" },
    { amo_swap_w_aq, 0, 4, "amoswap.w.aq" },
    { amo_swap_w_rl, 0, 4, "amoswap.w.rl" },
    { amo_swap_w_aqrl, 0, 4, "amoswap.w.aqrl" },
    { amo_add_w, 1, 4, "amoadd.w" },
    { amo_add_w_aq, 1, 4, "amoadd.w.aq" },
    { amo_add_w_rl, 1, 4, "amoadd.w.rl" },
    { amo_add_w_aqrl, 1, 4, "amoadd.w.aqrl" },
    { amo_xor_w, 2, 4, "amoxor.w" },
    { amo_xor_w_aq, 2, 4, "amoxor.w.aq" },
    { amo_xor_w_rl, 2, 4, "amoxor.w.rl" },
    { amo_xor_w_aqrl, 2, 4, "amoxor.w.aqrl" },
    { amo_and_w, 3, 4, "amoand.w" },
    { amo_and_w_aq, 3, 4, "amoand.w.aq" },
    { amo_and_w_rl, 3, 4, "amoand.w.rl" },
    { amo_and_w_aqrl, 3, 4, "amoand.w.aqrl" },
    { amo_or_w, 4, 4, "amoor.w" },
    { amo_or_w_aq, 4, 4, "amoor.w.aq" },
    { amo_or_w_rl, 4, 4, "amoor.w.rl" },
    { amo_or_w_aqrl, 4, 4, "amoor.w.aqrl" },
    { amo_min_w, 5, 4, "amomin.w" },
    { amo_min_w_aq, 5, 4, "amomin.w.aq" },
    { amo_min_w_rl, 5, 4, "amomin.w.rl" },
    { amo_min_w_aqrl, 5, 4, "amomin.w.aqrl" },
    { amo_max_w, 6, 4, "amomax.w" },
    { amo_max_w_aq, 6, 4, "amomax.w.aq" },
    { amo_max_w_rl, 6, 4, "amomax.w.rl" },
    { amo_max_w_aqrl, 6, 4, "amomax.w.aqrl" },
    { amo_minu_w, 7, 4, "amominu.w" },
    { amo_minu_w_aq, 7, 4, "amominu.w.aq" },
    { amo_minu_w_rl, 7, 4, "amominu.w.rl" },
    { amo_minu_w_aqrl, 7, 4, "amominu.w.aqrl" },
    { amo_maxu_w, 8, 4, "amomaxu.w" },
    { amo_maxu_w_aq, 8, 4, "amomaxu.w.aq" },
    { amo_maxu_w_rl, 8, 4, "amomaxu.w.rl" },
    { amo_maxu_w_aqrl, 8, 4, "amomaxu.w.aqrl" },
    { amo_swap_d, 0, 8, "amoswap.d" },
    { amo_swap_d_aq, 0, 8, "amoswap.d.aq" },
    { amo_swap_d_rl, 0, 8, "amoswap.d.rl" },
    { amo_swap_d_aqrl, 0, 8, "amoswap.d.aqrl" },
    { amo_add_d, 1, 8, "amoadd.d" },
    { amo_add_d_aq, 1, 8, "amoadd.d.aq" },
    { amo_add_d_rl, 1, 8, "amoadd.d.rl" },
    { amo_add_d_aqrl, 1, 8, "amoadd.d.aqrl" },
    { amo_xor_d, 2, 8, "amoxor.d" },
    { amo_xor_d_aq, 2, 8, "amoxor.d.aq" },
    { amo_xor_d_rl, 2, 8, "amoxor.d.rl" },
    { amo_xor_d_aqrl, 2, 8, "amoxor.d.aqrl" },
    { amo_and_d, 3, 8, "amoand.d" },
    { amo_and_d_aq, 3, 8, "amoand.d.aq" },
    { amo_and_d_rl, 3, 8, "amoand.d.rl" },
    { amo_and_d_aqrl, 3, 8, "amoand.d.aqrl" },
    { amo_or_d, 4, 8, "amoor.d" },
    { amo_or_d_aq, 4, 8, "amoor.d.aq" },
    { amo_or_d_rl, 4, 8, "amoor.d.rl" },
    { amo_or_d_aqrl, 4, 8, "amoor.d.aqrl" },
    { amo_min_d, 5, 8, "amomin.d" },
    { amo_min_d_aq, 5, 8, "amomin.d.aq" },
    { amo_min_d_rl, 5, 8, "amomin.d.rl" },
    { amo_min_d_aqrl, 5, 8, "amomin.d.aqrl" },
    { amo_max_d, 6, 8, "amomax.d" },
    { amo_max_d_aq, 6, 8, "amomax.d.aq" },
    { amo_max_d_rl, 6, 8, "amomax.d.rl" },
    { amo_max_d_aqrl, 6, 8, "amomax.d.aqrl" },
    { amo_minu_d, 7, 8, "amominu.d" },
    { amo_minu_d_aq, 7, 8, "amominu.d.aq" },
    { amo_minu_d_rl, 7, 8, "amominu.d.rl" },
    { amo_minu_d_aqrl, 7, 8, "amominu.d.aqrl" },
    { amo_maxu_d, 8, 8, "amomaxu.d" },
    { amo_maxu_d_aq, 8, 8, "amomaxu.d.aq" },
    { amo_maxu_d_rl, 8, 8, "amomaxu.d.rl" },
    { amo_maxu_d_aqrl, 8, 8, "amomaxu.d.aqrl" },
};

static uint64_t model(int op, int sz, uint64_t a, uint64_t b) {
    if (sz == 4) {
        int32_t sa = (int32_t)a, sb = (int32_t)b; uint32_t ua = (uint32_t)a, ub = (uint32_t)b, r;
        switch (op) {
        case OP_SWAP: r = ub; break;
        case OP_ADD:  r = ua + ub; break;
        case OP_XOR:  r = ua ^ ub; break;
        case OP_AND:  r = ua & ub; break;
        case OP_OR:   r = ua | ub; break;
        case OP_MIN:  r = (uint32_t)(sa < sb ? sa : sb); break;
        case OP_MAX:  r = (uint32_t)(sa > sb ? sa : sb); break;
        case OP_MINU: r = ua < ub ? ua : ub; break;
        default:      r = ua > ub ? ua : ub; break;
        }
        return r;
    }
    int64_t sa = (int64_t)a, sb = (int64_t)b;
    switch (op) {
    case OP_SWAP: return b;
    case OP_ADD:  return a + b;
    case OP_XOR:  return a ^ b;
    case OP_AND:  return a & b;
    case OP_OR:   return a | b;
    case OP_MIN:  return (uint64_t)(sa < sb ? sa : sb);
    case OP_MAX:  return (uint64_t)(sa > sb ? sa : sb);
    case OP_MINU: return a < b ? a : b;
    default:      return a > b ? a : b;
    }
}

static const uint64_t g_edge[] = {
    0, 1, ~0UL, 0x7fffffffUL, 0x80000000UL, 0xffffffff80000000UL, 0x7fffffffffffffffUL,
    0x8000000000000000UL, 0x00000000ffffffffUL, 0xffffffff00000000UL, 0x0123456789abcdefUL };

static uint64_t g_cells[1 << 15] ST_ALIGNED(4096);   /* 256 KiB: plenty of cold lines */

int main(void) {
    st_init();
    st_section("AMO semantics");
    uint64_t bad = 0, n = 0, cold = 0;
    int npair = (int)(ST_ARRAY_LEN(g_edge) * ST_ARRAY_LEN(g_edge));
    for (unsigned k = 0; k < ST_ARRAY_LEN(g_amo); k++) {
        const amo_t *m = &g_amo[k];
        for (int t = 0; t < 12 * ST_SCALE; t++) {
            int pi = (int)st_rand_range((uint64_t)npair);
            uint64_t a = (t & 1) ? g_edge[pi / ST_ARRAY_LEN(g_edge)] : st_rand();
            uint64_t b = (t & 2) ? g_edge[pi % ST_ARRAY_LEN(g_edge)] : st_rand();
            int state = t % 3;                    /* 0 cold, 1 hot clean, 2 dirty */
            volatile uint64_t *cell = &g_cells[(cold++ * 131) % (ST_ARRAY_LEN(g_cells) - 2)];
            int hi = (m->sz == 4) && (t & 4);     /* .w on the upper word */
            uint64_t neighbour = st_rand();
            uint64_t dw = hi ? ((a << 32) | (neighbour & 0xffffffffUL)) : (m->sz == 4 ? ((neighbour << 32) | (a & 0xffffffffUL)) : a);
            *cell = dw;
            if (state == 0) { for (int e = 1; e <= 5; e++) (void)*(volatile uint64_t *)((uint64_t)cell ^ ((uint64_t)e << 13)); }
            else if (state == 1) { st_fence_i(); (void)*cell; }   /* fence.i writes the D$ back: resident and CLEAN */
            else *cell = dw;
            uint64_t addr = (uint64_t)cell + (hi ? 4 : 0);
            uint64_t old = m->fn(addr, b);
            uint64_t want_old = m->sz == 4 ? (uint64_t)(int64_t)(int32_t)(hi ? (dw >> 32) : dw) : dw;
            uint64_t newv = model(m->op, m->sz, want_old, b);
            uint64_t want_mem = m->sz == 8 ? newv :
                hi ? ((newv << 32) | (dw & 0xffffffffUL)) : ((dw & 0xffffffff00000000UL) | (newv & 0xffffffffUL));
            n++;
            if (old != want_old || *cell != want_mem) {
                bad++;
                if (bad < 6) st_check_failed(m->name, old ^ *cell, want_old ^ want_mem, t);
            }
        }
    }
    ST_CHECK_EQ("all AMO results (rd and memory)", bad, 0);
    st_puts("[ST] AMO cases: "); st_putdec(n); st_putc('\n');

    st_section("rd = x0 and rd == rs2");
    volatile uint64_t *c = &g_cells[7];
    *c = 10;
    __asm__ volatile ("amoadd.d zero, %1, (%0)" :: "r"(c), "r"(5UL) : "memory");
    ST_CHECK_EQ("amoadd.d with rd=x0 still writes memory", *c, 15);
    uint64_t r = 3;
    __asm__ volatile ("amoadd.d %0, %0, (%1)" : "+r"(r) : "r"(c) : "memory");
    ST_CHECK_EQ("rd==rs2: rd gets the OLD value", r, 15);
    ST_CHECK_EQ("  memory gets old + rs2", *c, 18);

    st_section("AMO faults leave memory unchanged");
    uint64_t root = pt_new_identity_root(0);
    uint64_t fr = frame_alloc();
    *(volatile uint64_t *)fr = 0x1234;
    map_page(root, 0xC0000000UL, fr, PTE_R | PTE_A);
    csr_write(satp, satp_sv39(1, root));
    sfence_all();
    csr_clear(mstatus, MSTATUS_MPP); csr_set(mstatus, MSTATUS_MPP_S);
    st_expect(ST_EXPECT_SKIP);
    __asm__ volatile (".option push\n.option norvc\ncsrs mstatus, %2\namoadd.d zero, %1, (%0)\ncsrc mstatus, %2\n.option pop"
                      :: "r"(0xC0000000UL), "r"(1UL), "r"(MSTATUS_MPRV) : "memory");
    st_expect_clear();
    csr_clear(mstatus, MSTATUS_MPP); csr_set(mstatus, MSTATUS_MPP_M);
    ST_CHECK_EQ("AMO to read-only page: store page fault", g_trap_cause, CAUSE_STORE_PAGE);
    ST_CHECK_EQ("  value unchanged", *(volatile uint64_t *)fr, 0x1234);
    csr_write(satp, 0);
    sfence_all();
    static const struct { const char *n; uint64_t a; } bad_targets[] = {
        { "AMO to hole", ST_HOLE_ADDR }, { "AMO to CLINT mtimecmp", CLINT_BASE + 0x4000 },
        { "AMO to PLIC priority", PLIC_BASE_ADDR + 4 * PLIC_SRC_UART } };
    for (unsigned i = 0; i < ST_ARRAY_LEN(bad_targets); i++) {
        st_expect(ST_EXPECT_SKIP);
        __asm__ volatile (".option push\n.option norvc\namoor.w zero, %1, (%0)\n.option pop" :: "r"(bad_targets[i].a), "r"(1UL) : "memory");
        st_expect_clear();
        ST_CHECK_EQ(bad_targets[i].n, g_trap_cause, CAUSE_STORE_ACCESS);
        ST_CHECK_EQ("  tval", g_trap_tval, bad_targets[i].a);
    }
    st_timer_off();
    return st_result();
}
