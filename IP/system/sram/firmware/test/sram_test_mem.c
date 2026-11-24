/**
 * @file sram_test_mem.c
 * @brief Host unit tests: fault-injecting memory model (see sram_test_mem.h).
 */

#include "sram_test_mem.h"

static uint32_t   g_mem[TM_MAX_WORDS];
static uint32_t   g_words;
static tm_fault_t g_fault;
static int        g_bad;
static uint32_t   g_acc;

uintptr_t tm_reset(uint32_t size, uint32_t fill)
{
    uint32_t i;

    g_words = size / 4u;
    if (g_words > TM_MAX_WORDS) {
        g_words = TM_MAX_WORDS;
    }
    for (i = 0u; i < TM_MAX_WORDS; i++) {
        g_mem[i] = fill;
    }
    g_fault.kind = TM_NONE;
    g_bad = 0;
    g_acc = 0u;
    return (uintptr_t)&g_mem[0];
}

void tm_set_fault(const tm_fault_t *f)
{
    g_fault = *f;
}

int tm_bad_access(void)
{
    return g_bad;
}

uint32_t tm_accesses(void)
{
    return g_acc;
}

/** Word index of a byte address after the address-decoder faults; -1 if bad. */
static int32_t decode(uintptr_t addr, uint32_t n)
{
    uintptr_t base = (uintptr_t)&g_mem[0];
    uint32_t  idx;

    g_acc++;
    if ((addr < base) || (addr + n > base + 4u * (uintptr_t)g_words) ||
        ((addr & (uintptr_t)(n - 1u)) != 0u)) {
        g_bad = 1;
        return -1;
    }
    idx = (uint32_t)((addr - base) >> 2);
    if (g_fault.kind == TM_ADDR_STUCK) {
        idx = (g_fault.v != 0u) ? (idx | (1u << g_fault.b)) : (idx & ~(1u << g_fault.b));
        idx %= g_words;
    } else if (g_fault.kind == TM_ADDR_SHORT) {
        uint32_t x = ((idx >> g_fault.b) & (idx >> g_fault.b2)) & 1u;

        idx = (idx & ~((1u << g_fault.b) | (1u << g_fault.b2))) |
              (x << g_fault.b) | (x << g_fault.b2);
    }
    return (int32_t)idx;
}

/** Stored word idx as read (read-side faults applied). */
static uint32_t word_rd(uint32_t idx)
{
    uint32_t d = g_mem[idx];

    if ((g_fault.kind == TM_STUCK) && (idx == g_fault.w)) {
        d = (g_fault.v != 0u) ? (d | (1u << g_fault.b)) : (d & ~(1u << g_fault.b));
    }
    if ((g_fault.kind == TM_NPSF) && (idx == g_fault.w) &&
        (((d >> g_fault.b2) & (d >> g_fault.b3) & 1u) != 0u)) {
        d |= 1u << g_fault.b;
    }
    return d;
}

/** Store word idx (write-side faults applied). */
static void word_wr(uint32_t idx, uint32_t d)
{
    uint32_t old = g_mem[idx];

    if ((g_fault.kind == TM_TRANSITION) && (idx == g_fault.w) &&
        (((old >> g_fault.b) & 1u) == 0u)) {
        d &= ~(1u << g_fault.b);
    }
    if ((g_fault.kind == TM_BRIDGE) && (idx == g_fault.w)) {
        uint32_t x = ((d >> g_fault.b) & (d >> g_fault.b2)) & 1u;

        d = (d & ~((1u << g_fault.b) | (1u << g_fault.b2))) |
            (x << g_fault.b) | (x << g_fault.b2);
    }
    g_mem[idx] = d;
    if ((g_fault.kind == TM_COUPLING) && (idx == g_fault.w)) {
        uint32_t o = (old >> g_fault.b) & 1u;
        uint32_t n = (d >> g_fault.b) & 1u;

        if ((g_fault.v == 0u) ? ((o == 0u) && (n != 0u)) : ((o != 0u) && (n == 0u))) {
            g_mem[g_fault.w2] |= 1u << g_fault.b2;
        }
    }
    if ((g_fault.kind == TM_ADDR_MULTI) && (idx == g_fault.w)) {
        g_mem[g_fault.w2] = d;
    }
}

uint32_t sram_test_rd(uintptr_t addr, uint32_t n)
{
    int32_t  idx = decode(addr, n);
    uint32_t sh  = 8u * (uint32_t)(addr & 3u);
    uint32_t d;

    if (idx < 0) {
        return 0u;
    }
    d = word_rd((uint32_t)idx) >> sh;
    return (n == 4u) ? d : (d & ((1u << (8u * n)) - 1u));
}

void sram_test_wr(uintptr_t addr, uint32_t n, uint32_t v)
{
    int32_t  idx = decode(addr, n);
    uint32_t lane = (uint32_t)(addr & 3u);
    int      lane_f;
    uint32_t mask;
    uint32_t d;

    if (idx < 0) {
        return;
    }
    if (n == 4u) {
        word_wr((uint32_t)idx, v);
        return;
    }
    lane_f = ((g_fault.kind == TM_LANE_FULL) || (g_fault.kind == TM_LANE_SWAP) ||
              (g_fault.kind == TM_HALF_LOW)) &&
             ((g_fault.v == 0u) || ((uint32_t)idx == g_fault.w));
    if (lane_f && (g_fault.kind == TM_LANE_SWAP) && (n == 1u)) {
        lane ^= 1u;
    }
    if (lane_f && (g_fault.kind == TM_HALF_LOW) && (n == 2u)) {
        lane = 0u;
    }
    mask = ((1u << (8u * n)) - 1u) << (8u * lane);
    v    = (v << (8u * lane)) & mask;
    if (lane_f && (g_fault.kind == TM_LANE_FULL)) {
        d = v;                                   /* other lanes driven as 0 */
    } else {
        d = (g_mem[(uint32_t)idx] & ~mask) | v;  /* byte-enable merge       */
    }
    word_wr((uint32_t)idx, d);
}
