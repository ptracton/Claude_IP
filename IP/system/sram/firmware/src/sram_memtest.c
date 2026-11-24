/**
 * @file sram_memtest.c
 * @brief Memory tests for the sram IP (C99, bare-metal).
 *
 * Every access goes through the SRAM_RD* / SRAM_WR* macros of sram_access.h.
 * The tests are destructive. No OS, RTOS, or dynamic-allocation dependencies.
 */

#include "sram.h"
#include "sram_access.h"

/* =========================================================================
 * Internal helpers
 * ========================================================================= */

#define SRAM_PAT       0xAAAAAAAAu  /* address-bus test pattern           */
#define SRAM_ANTIPAT   0x55555555u  /* its complement                     */
#define SRAM_CHECKER   0x55555555u  /* March C- second background         */

/** Byte address of word i. */
#define WORD_ADDR(base, i)  ((uintptr_t)(base) + ((uintptr_t)(i) << 2))

/** Record the first failure (fail may be NULL) and return SRAM_ERR_FAIL. */
static int report(sram_fail_t *fail, uintptr_t addr, uint32_t exp, uint32_t act)
{
    if (fail != (sram_fail_t *)0) {
        fail->addr     = addr;
        fail->expected = exp;
        fail->actual   = act;
    }
    return SRAM_ERR_FAIL;
}

/** Read word i and compare it with exp. */
static int check_word(uintptr_t base, uint32_t i, uint32_t exp, sram_fail_t *fail)
{
    uint32_t act = SRAM_RD32(WORD_ADDR(base, i));

    return (act == exp) ? SRAM_OK : report(fail, WORD_ADDR(base, i), exp, act);
}

/** Common argument check: 4-byte aligned base, size a non-zero multiple of 4. */
static int args_ok(uintptr_t base, uint32_t size)
{
    return ((base & 3u) == 0u) && (size != 0u) && ((size & 3u) == 0u);
}

/* =========================================================================
 * Address bus
 * ========================================================================= */

/**
 * Sequence (words = size / 4, offsets o = 1, 2, 4, ... < words):
 *  1. every offset holds PAT, word 0 holds ANTIPAT;
 *  2. each offset still reads PAT (else it aliases word 0: address bit stuck);
 *  3. word 0 = PAT; for each offset t: write ANTIPAT at t, then word 0 and
 *     every other offset must still read PAT (else t aliases them), restore t.
 */
int sram_test_addr_bus(uintptr_t base, uint32_t size, sram_fail_t *fail)
{
    uint32_t words;
    uint32_t o;
    uint32_t t;

    if (!args_ok(base, size)) {
        return SRAM_ERR_ARG;
    }
    words = size >> 2;

    for (o = 1u; o < words; o <<= 1) {
        SRAM_WR32(WORD_ADDR(base, o), SRAM_PAT);
    }
    SRAM_WR32(WORD_ADDR(base, 0u), SRAM_ANTIPAT);
    for (o = 1u; o < words; o <<= 1) {
        if (check_word(base, o, SRAM_PAT, fail) != SRAM_OK) {
            return SRAM_ERR_FAIL;
        }
    }

    SRAM_WR32(WORD_ADDR(base, 0u), SRAM_PAT);
    for (t = 1u; t < words; t <<= 1) {
        SRAM_WR32(WORD_ADDR(base, t), SRAM_ANTIPAT);
        if (check_word(base, 0u, SRAM_PAT, fail) != SRAM_OK) {
            return SRAM_ERR_FAIL;
        }
        for (o = 1u; o < words; o <<= 1) {
            if ((o != t) && (check_word(base, o, SRAM_PAT, fail) != SRAM_OK)) {
                return SRAM_ERR_FAIL;
            }
        }
        SRAM_WR32(WORD_ADDR(base, t), SRAM_PAT);
    }
    return SRAM_OK;
}

/* =========================================================================
 * Walking 1s / 0s
 * ========================================================================= */

int sram_test_walking(uintptr_t base, uint32_t size, sram_fail_t *fail)
{
    uint32_t words;
    uint32_t i;
    uint32_t b;

    if (!args_ok(base, size)) {
        return SRAM_ERR_ARG;
    }
    words = size >> 2;

    for (i = 0u; i < words; i++) {
        for (b = 0u; b < 32u; b++) {
            uint32_t one = 1u << b;

            SRAM_WR32(WORD_ADDR(base, i), one);
            if (check_word(base, i, one, fail) != SRAM_OK) {
                return SRAM_ERR_FAIL;
            }
            SRAM_WR32(WORD_ADDR(base, i), ~one);
            if (check_word(base, i, ~one, fail) != SRAM_OK) {
                return SRAM_ERR_FAIL;
            }
        }
    }
    return SRAM_OK;
}

/* =========================================================================
 * Address in address
 * ========================================================================= */

int sram_test_addr_in_addr(uintptr_t base, uint32_t size, sram_fail_t *fail)
{
    uint32_t words;
    uint32_t i;
    uint32_t inv;

    if (!args_ok(base, size)) {
        return SRAM_ERR_ARG;
    }
    words = size >> 2;

    /* pass 0: each word holds its own (low 32 bits of the) address;
     * pass 1: its complement, so every bit is seen at both values. */
    for (inv = 0u; inv < 2u; inv++) {
        uint32_t x = (inv != 0u) ? 0xFFFFFFFFu : 0u;

        for (i = 0u; i < words; i++) {
            SRAM_WR32(WORD_ADDR(base, i), (uint32_t)WORD_ADDR(base, i) ^ x);
        }
        for (i = 0u; i < words; i++) {
            if (check_word(base, i, (uint32_t)WORD_ADDR(base, i) ^ x, fail) != SRAM_OK) {
                return SRAM_ERR_FAIL;
            }
        }
    }
    return SRAM_OK;
}

/* =========================================================================
 * March C-
 * ========================================================================= */

/** One read-then-write March element over every word, up or down. */
static int march_rw(uintptr_t base, uint32_t words, int up,
                    uint32_t rd, uint32_t wr, sram_fail_t *fail)
{
    uint32_t n;

    for (n = 0u; n < words; n++) {
        uint32_t i = (up != 0) ? n : (words - 1u - n);

        if (check_word(base, i, rd, fail) != SRAM_OK) {
            return SRAM_ERR_FAIL;
        }
        SRAM_WR32(WORD_ADDR(base, i), wr);
    }
    return SRAM_OK;
}

int sram_test_march_c(uintptr_t base, uint32_t size, uint32_t bg,
                      sram_fail_t *fail)
{
    uint32_t words;
    uint32_t i;

    if (!args_ok(base, size)) {
        return SRAM_ERR_ARG;
    }
    words = size >> 2;

    for (i = 0u; i < words; i++) {                          /* M0 up (w bg)   */
        SRAM_WR32(WORD_ADDR(base, i), bg);
    }
    if ((march_rw(base, words, 1, bg, ~bg, fail) != SRAM_OK) ||   /* M1 up   */
        (march_rw(base, words, 1, ~bg, bg, fail) != SRAM_OK) ||   /* M2 up   */
        (march_rw(base, words, 0, bg, ~bg, fail) != SRAM_OK) ||   /* M3 down */
        (march_rw(base, words, 0, ~bg, bg, fail) != SRAM_OK)) {   /* M4 down */
        return SRAM_ERR_FAIL;
    }
    for (i = 0u; i < words; i++) {                          /* M5 up (r bg)   */
        if (check_word(base, i, bg, fail) != SRAM_OK) {
            return SRAM_ERR_FAIL;
        }
    }
    return SRAM_OK;
}

/* =========================================================================
 * Byte lanes
 * ========================================================================= */

/** Byte and halfword writes / reads on the word at byte address a. */
static int lanes_word(uintptr_t a, sram_fail_t *fail)
{
    uint32_t exp = 0u;
    uint32_t act;
    uint32_t k;

    /* bytes into a zero word, one lane at a time (little-endian lanes) */
    SRAM_WR32(a, 0u);
    for (k = 0u; k < 4u; k++) {
        uint32_t v = 0x11u * (k + 1u);                /* 0x11 0x22 0x33 0x44 */

        SRAM_WR8(a + k, v);
        exp |= v << (8u * k);
        act = SRAM_RD32(a);
        if (act != exp) {
            return report(fail, a, exp, act);
        }
    }
    for (k = 0u; k < 4u; k++) {
        act = SRAM_RD8(a + k);
        if (act != ((exp >> (8u * k)) & 0xFFu)) {
            return report(fail, a + k, (exp >> (8u * k)) & 0xFFu, act);
        }
    }

    /* halfwords into an all-ones word */
    SRAM_WR32(a, 0xFFFFFFFFu);
    SRAM_WR16(a, 0x1234u);
    act = SRAM_RD32(a);
    if (act != 0xFFFF1234u) {
        return report(fail, a, 0xFFFF1234u, act);
    }
    SRAM_WR16(a + 2u, 0x5678u);
    act = SRAM_RD32(a);
    if (act != 0x56781234u) {
        return report(fail, a, 0x56781234u, act);
    }
    act = SRAM_RD16(a + 2u);
    if (act != 0x5678u) {
        return report(fail, a + 2u, 0x5678u, act);
    }
    act = SRAM_RD16(a);
    if (act != 0x1234u) {
        return report(fail, a, 0x1234u, act);
    }
    return SRAM_OK;
}

int sram_test_byte_lanes(uintptr_t base, uint32_t size, sram_fail_t *fail)
{
    if (!args_ok(base, size)) {
        return SRAM_ERR_ARG;
    }
    if (lanes_word(base, fail) != SRAM_OK) {
        return SRAM_ERR_FAIL;
    }
    if ((size > 4u) && (lanes_word(base + size - 4u, fail) != SRAM_OK)) {
        return SRAM_ERR_FAIL;
    }
    return SRAM_OK;
}

/* =========================================================================
 * All
 * ========================================================================= */

int sram_test_all(uintptr_t base, uint32_t size, uint32_t tests,
                  sram_fail_t *fail)
{
    int rc = SRAM_OK;

    if (!args_ok(base, size) || ((tests & SRAM_TEST_ALL) == 0u) ||
        ((tests & ~SRAM_TEST_ALL) != 0u)) {
        return SRAM_ERR_ARG;
    }
    if ((rc == SRAM_OK) && ((tests & SRAM_TEST_ADDR_BUS) != 0u)) {
        rc = sram_test_addr_bus(base, size, fail);
    }
    if ((rc == SRAM_OK) && ((tests & SRAM_TEST_WALKING) != 0u)) {
        rc = sram_test_walking(base, size, fail);
    }
    if ((rc == SRAM_OK) && ((tests & SRAM_TEST_ADDR_IN) != 0u)) {
        rc = sram_test_addr_in_addr(base, size, fail);
    }
    if ((rc == SRAM_OK) && ((tests & SRAM_TEST_MARCH_C) != 0u)) {
        rc = sram_test_march_c(base, size, 0u, fail);
        if (rc == SRAM_OK) {
            rc = sram_test_march_c(base, size, SRAM_CHECKER, fail);
        }
    }
    if ((rc == SRAM_OK) && ((tests & SRAM_TEST_BYTE_LANES) != 0u)) {
        rc = sram_test_byte_lanes(base, size, fail);
    }
    return rc;
}
