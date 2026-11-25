// @stress tier=pr build=no_spike duts=legacy,forte timeout=20000000 ecc=no dummy=no pin=no
//
// st_cache_ecc_directed -- every way an uncorrectable (2-bit) cache error is
// handled, end to end through the core.  The testbench corrupts exact cache
// rows on request (hvl/common/top_tb.svh, "ECC mailbox": two flipped bits in a
// line's tag or data), so each case is deterministic:
//   clean D$ line, bad data   dropped and refetched: right value, no trap
//   clean D$ line, bad tag    dropped and refetched: right value, no trap
//   dirty D$ line, bad data   trap cause 20, mtval = the address, mepc = the load;
//                             the line is dropped: a reload sees memory's older copy
//   dirty D$ line, bad tag    trap cause 21 (the address is lost); the modified
//                             line is gone, a reload sees memory's older copy
//   I$ line, bad data / tag   refetched: the code runs correctly, no trap
// and, for each, the fault counters it must move (0x10080000: 5/7 I$/D$ DED,
// 19/21 I$/D$ tag DED, 22 D$ data lost), MSECFAULT[6] for the losses, and the
// cache's last-error record (words 24-27: tag/lost/source/way/set/line address).
// Also that software can clear one counter, all of them, and a record.
// Needs the testbench mailbox, so not on the pin bench or silicon (pin=no).
#include "../lib/stress.h"

#define MBOX_ADDR   (*(volatile uint64_t *)0x8FFFF000UL)
#define MBOX_CMD    (*(volatile uint64_t *)0x8FFFF008UL)
#define MBOX_MAGIC  0xECC0DE00UL
enum { OP_DTAG = 1, OP_DLINE = 2, OP_ITAG = 3, OP_ILINE = 4, OP_REPAIR = 15 };

#define CNT_IDED     5
#define CNT_DDED     7
#define CNT_ITAGDED  19
#define CNT_DTAGDED  21
#define CNT_DLOST    22
#define NCNT         23
#define W_DREC       24
#define W_DADR       25
#define W_IREC       26
#define W_IADR       27
#define W_CLEARALL   31
#define REC_VALID    (1u << 0)
#define REC_MULTIPLE (1u << 1)
#define REC_TAG      (1u << 2)
#define REC_LOST     (1u << 3)
#define REC_SOURCE(r) (((r) >> 4) & 3u)
#define REC_WAYS(r)   (((r) >> 8) & 0xfu)
#define REC_SET(r)    (((r) >> 16) & 0xfffu)
#define MSECFAULT_DCACHE_LOST (1UL << 6)

#define LINE  AMOEBA_DCACHE_LINE_BYTES
#define NSETS AMOEBA_DCACHE_SETS

// One way's worth of lines: offset 16*s is cache set s.
static uint64_t g_buf[NSETS * LINE / 8] ST_ALIGNED(NSETS * LINE);

// The I$ target, alone in its line, away from the code that calls it.
uint64_t ic_target(uint64_t);
__asm__(".text\n.option push\n.option norvc\n.balign 1024\n.skip 528\n"
        ".globl ic_target\nic_target:\n  addi a0, a0, 7\n  ret\n.option pop\n");

static inline uint32_t cnt(int i) { return *(volatile uint32_t *)(ECC_COUNTER_BASE + 4UL * (uint64_t)i) & 0xffff; }
static void snap(uint32_t *c) { for (int i = 0; i < NCNT; i++) c[i] = cnt(i); }
static inline uint32_t word(int i) { return *(volatile uint32_t *)(ECC_COUNTER_BASE + 4UL * (uint64_t)i); }
static inline void wr(int i) { *(volatile uint32_t *)(ECC_COUNTER_BASE + 4UL * (uint64_t)i) = 0xffffffffu; }

// The record must describe exactly one error (cleared just before), found by a lookup.
static void check_rec(int w_rec, uint64_t adr, int tag, int lost) {
    uint32_t r = word(w_rec);
    ST_CHECK("  record: valid", r & REC_VALID);
    ST_CHECK_EQ("  record: one error", r & REC_MULTIPLE, 0);
    ST_CHECK_EQ("  record: tag", (r & REC_TAG) != 0, tag);
    ST_CHECK_EQ("  record: data lost", (r & REC_LOST) != 0, lost);
    ST_CHECK_EQ("  record: found by a lookup", REC_SOURCE(r), 0);
    ST_CHECK_EQ("  record: set", REC_SET(r), (adr / LINE) % NSETS);
    ST_CHECK("  record: one way", REC_WAYS(r) != 0 && (REC_WAYS(r) & (REC_WAYS(r) - 1)) == 0);
    if (!tag) ST_CHECK_EQ("  record: line address", word(w_rec + 1), (uint32_t)(adr & ~(uint64_t)(LINE - 1)));
}

// Ask the testbench to corrupt (or repair) the line at adr.  Inline and
// stack-free: nothing between the request and the access may touch the
// target's cache set.
static inline __attribute__((always_inline)) void mbox(uint64_t adr, uint64_t op) {
    MBOX_ADDR = adr;
    __asm__ volatile ("fence rw, rw" ::: "memory");
    MBOX_CMD = MBOX_MAGIC | op;
    __asm__ volatile ("fence rw, rw\n nop\n nop\n nop\n nop\n nop\n nop\n nop\n nop" ::: "memory");
}

// A 4-byte load that may trap; *pc gets its address.
static inline __attribute__((always_inline)) int probe_load(uint64_t a, uint64_t *v, uint64_t *pc) {
    uint64_t r = 0x5a5a5a5a5a5a5a5aUL, p;
    st_expect(ST_EXPECT_SKIP);
    __asm__ volatile (".option push\n.option norvc\n la %1, 1f\n1: ld %0, 0(%2)\n.option pop"
                      : "+&r"(r), "=&r"(p) : "r"(a) : "memory");
    st_expect_clear();
    *v = r; *pc = p;
    return st_trapped();
}

// Cache sets the harness itself writes during a trap (its frame on the current
// stack, its globals): a target there could be evicted from a 2-way set mid-case.
static uint64_t g_busy;
static void mark(uint64_t a) { g_busy |= 1UL << ((a / LINE) % NSETS); }
static uint64_t pick_set(void) {
    for (uint64_t s = 1; s < NSETS; s++)
        if (!((g_busy >> s) & 1)) { g_busy |= 1UL << s; return s; }
    ST_ASSERT("a free cache set for the next target", 0);
    return 0;
}

static void make_clean(volatile uint64_t *p, uint64_t v) {
    *p = v;
    st_fence_i();            // fence.i writes the D$ back: memory has v, the line is clean
    (void)*p;                // and resident
}

int main(void) {
    st_init();
    uint32_t b[NCNT], a[NCNT];
    uint64_t v, pc, sp;

    __asm__ volatile ("mv %0, sp" : "=r"(sp));
    for (uint64_t x = sp - 512; x < sp + 128; x += LINE) mark(x);
    mark((uint64_t)&g_trap_cause); mark((uint64_t)&g_trap_tval); mark((uint64_t)&g_trap_epc);
    mark((uint64_t)&g_trap_status); mark((uint64_t)&g_trap_count); mark((uint64_t)&g_exp_mode);
    mark((uint64_t)&g_exp_len); mark((uint64_t)&g_exp_resume); mark((uint64_t)&g_st_pass);
    mark((uint64_t)&g_st_fail); mark((uint64_t)&g_m_hook); mark((uint64_t)&g_m_irq_hook);
    mark((uint64_t)&g_irq_count); mark(0x8FFFF000UL);

    st_section("clean D$ line, uncorrectable data: refetched, no trap");
    {
        volatile uint64_t *t = &g_buf[pick_set() * LINE / 8];
        make_clean(t, 0x1111222233334444UL);
        wr(W_DREC);
        snap(b);
        mbox((uint64_t)t, OP_DLINE);
        int trapped = probe_load((uint64_t)t, &v, &pc);
        snap(a);
        ST_CHECK_EQ("no trap", trapped, 0);
        ST_CHECK_EQ("  right value, refetched", v, 0x1111222233334444UL);
        ST_CHECK_EQ("  D$ DED counted once", a[CNT_DDED] - b[CNT_DDED], 1);
        ST_CHECK_EQ("  not a tag error", a[CNT_DTAGDED] - b[CNT_DTAGDED], 0);
        ST_CHECK_EQ("  no data lost", a[CNT_DLOST] - b[CNT_DLOST], 0);
        check_rec(W_DREC, (uint64_t)t, 0, 0);
    }

    st_section("clean D$ line, uncorrectable tag: dropped and refetched, no trap");
    {
        volatile uint64_t *t = &g_buf[pick_set() * LINE / 8];
        make_clean(t, 0x5555666677778888UL);
        wr(W_DREC);
        snap(b);
        mbox((uint64_t)t, OP_DTAG);
        int trapped = probe_load((uint64_t)t, &v, &pc);
        snap(a);
        ST_CHECK_EQ("no trap", trapped, 0);
        ST_CHECK_EQ("  right value, refetched", v, 0x5555666677778888UL);
        ST_CHECK_EQ("  D$ DED counted once", a[CNT_DDED] - b[CNT_DDED], 1);
        ST_CHECK_EQ("  ... as a tag error", a[CNT_DTAGDED] - b[CNT_DTAGDED], 1);
        ST_CHECK_EQ("  no data lost", a[CNT_DLOST] - b[CNT_DLOST], 0);
        check_rec(W_DREC, (uint64_t)t, 1, 0);
    }

    st_section("dirty D$ line, uncorrectable data: cause 20 with its address");
    {
        volatile uint64_t *t = &g_buf[pick_set() * LINE / 8];
        make_clean(t, 0x0000000000000a0aUL);
        *t = 0xC0FFEE00C0FFEE00UL;                       // dirty: memory still has 0xa0a
        csr_write(0x7c0, MSECFAULT_DCACHE_LOST);         // W1C
        wr(W_DREC);
        snap(b);
        mbox((uint64_t)t, OP_DLINE);
        int trapped = probe_load((uint64_t)t, &v, &pc);
        snap(a);
        ST_CHECK_EQ("the load traps", trapped, 1);
        ST_CHECK_EQ("  cause 20", g_trap_cause, 20);
        ST_CHECK_EQ("  mtval = the line's address", g_trap_tval, (uint64_t)t);
        ST_CHECK_EQ("  mepc = the load", g_trap_epc, pc);
        ST_CHECK_EQ("  data-lost counted once", a[CNT_DLOST] - b[CNT_DLOST], 1);
        ST_CHECK_EQ("  D$ DED counted once", a[CNT_DDED] - b[CNT_DDED], 1);
        ST_CHECK_EQ("  not a tag error", a[CNT_DTAGDED] - b[CNT_DTAGDED], 0);
        ST_CHECK("  MSECFAULT[6] set", csr_read(0x7c0) & MSECFAULT_DCACHE_LOST);
        check_rec(W_DREC, (uint64_t)t, 0, 1);
        // Reported, then dropped (cachefsm.sv ClearValid): no second trap, and the
        // modified value is gone -- memory's older copy is what a reload sees.
        trapped = probe_load((uint64_t)t, &v, &pc);
        ST_CHECK_EQ("reload: no trap (the line was dropped)", trapped, 0);
        ST_CHECK_EQ("  memory's older copy", v, 0xa0aUL);
    }

    st_section("dirty D$ line, uncorrectable tag: cause 21, the line is lost");
    {
        volatile uint64_t *t = &g_buf[pick_set() * LINE / 8];
        make_clean(t, 0x0000000000000b0bUL);
        *t = 0xBADC0FFEE0DDF00DUL;                       // dirty: memory still has 0xb0b
        csr_write(0x7c0, MSECFAULT_DCACHE_LOST);
        wr(W_DREC);
        snap(b);
        mbox((uint64_t)t, OP_DTAG);
        int trapped = probe_load((uint64_t)t, &v, &pc);
        snap(a);
        ST_CHECK_EQ("the load traps", trapped, 1);
        ST_CHECK_EQ("  cause 21 (address lost)", g_trap_cause, 21);
        ST_CHECK_EQ("  mtval = the access that found the set", g_trap_tval, (uint64_t)t);
        ST_CHECK_EQ("  mepc = the load", g_trap_epc, pc);
        ST_CHECK_EQ("  data-lost counted once", a[CNT_DLOST] - b[CNT_DLOST], 1);
        ST_CHECK_EQ("  D$ DED counted once", a[CNT_DDED] - b[CNT_DDED], 1);
        ST_CHECK_EQ("  ... as a tag error", a[CNT_DTAGDED] - b[CNT_DTAGDED], 1);
        ST_CHECK("  MSECFAULT[6] set", csr_read(0x7c0) & MSECFAULT_DCACHE_LOST);
        check_rec(W_DREC, (uint64_t)t, 1, 1);
        trapped = probe_load((uint64_t)t, &v, &pc);
        ST_CHECK_EQ("reload: no trap", trapped, 0);
        ST_CHECK_EQ("  memory's older copy (the modified line was dropped)", v, 0xb0bUL);
    }

    st_section("I$ line, uncorrectable data: refetched, runs correctly");
    {
        ST_CHECK_EQ("warm", ic_target(5), 12);
        wr(W_IREC);
        snap(b);
        mbox((uint64_t)ic_target, OP_ILINE);
        uint64_t r = ic_target(30);
        snap(a);
        ST_CHECK_EQ("runs correctly", r, 37);
        ST_CHECK_EQ("  I$ DED counted once", a[CNT_IDED] - b[CNT_IDED], 1);
        ST_CHECK_EQ("  not a tag error", a[CNT_ITAGDED] - b[CNT_ITAGDED], 0);
        check_rec(W_IREC, (uint64_t)ic_target, 0, 0);
    }

    st_section("I$ line, uncorrectable tag: dropped and refetched");
    {
        ST_CHECK_EQ("warm", ic_target(1), 8);
        wr(W_IREC);
        snap(b);
        mbox((uint64_t)ic_target, OP_ITAG);
        uint64_t r = ic_target(100);
        snap(a);
        ST_CHECK_EQ("runs correctly", r, 107);
        ST_CHECK_EQ("  I$ DED counted once", a[CNT_IDED] - b[CNT_IDED], 1);
        ST_CHECK_EQ("  ... as a tag error", a[CNT_ITAGDED] - b[CNT_ITAGDED], 1);
        check_rec(W_IREC, (uint64_t)ic_target, 1, 0);
    }

    st_section("software clears: one counter, a record, all counters");
    {
        // Nothing has cleared these since the cases above, which moved 5, 7, 19, 21 and 22.
        ST_CHECK("counters 7 and 5 are nonzero", cnt(CNT_DDED) != 0 && cnt(CNT_IDED) != 0);
        wr(CNT_DDED);
        ST_CHECK_EQ("writing counter 7 clears it", cnt(CNT_DDED), 0);
        ST_CHECK("  ... and only it", cnt(CNT_IDED) != 0 && cnt(CNT_DTAGDED) != 0);
        // A second D$ error without clearing the record: the record keeps the newest, marked MULTIPLE
        volatile uint64_t *t = &g_buf[pick_set() * LINE / 8];
        make_clean(t, 0x0123456789abcdefUL);
        mbox((uint64_t)t, OP_DLINE);
        int trapped = probe_load((uint64_t)t, &v, &pc);
        ST_CHECK_EQ("another clean data DED: no trap", trapped, 0);
        ST_CHECK_EQ("  counter 7 counts again from 0", cnt(CNT_DDED), 1);
        uint32_t r = word(W_DREC);
        ST_CHECK("  record: MULTIPLE (not cleared since the last one)", (r & REC_MULTIPLE) && (r & REC_VALID));
        ST_CHECK_EQ("  record: the newest error's set", REC_SET(r), ((uint64_t)t / LINE) % NSETS);
        wr(W_DREC);
        ST_CHECK_EQ("writing the D$ record clears it", word(W_DREC), 0);
        ST_CHECK("  ... and not the I$ record", word(W_IREC) & REC_VALID);
        wr(W_CLEARALL);
        int nonzero = 0;
        for (int i = 0; i < NCNT; i++) nonzero += cnt(i) != 0;
        ST_CHECK_EQ("writing word 31 clears every counter", nonzero, 0);
        ST_CHECK("  ... but not the I$ record", word(W_IREC) & REC_VALID);
        ST_CHECK_EQ("unused words read 0", word(23) | word(28) | word(W_CLEARALL), 0);
    }

    return st_result();
}
