/**
 * @file sram_example.c
 * @brief Example: power-on self test and bank power management for one sram
 *        instance (BANK_PG = 1, NUM_BANKS = 2, ECC_EN, BIST_EN).
 *
 * Assumed SoC wiring (an example only; the IP has no registers): the side-band
 * pins of the sram sit in one 32-bit system-control register SYSCTL_SRAM at
 * SYSCTL_SRAM_ADDR. Writes:
 *     [1:0]  pwr_mode_req_i, domain 0      [3:2]  pwr_mode_req_i, domain 1
 *     [8]    clr_req_i (self-clearing)     [9]    bist_start_i (self-clearing)
 *     [11:10] ecc_inj_i (self-clearing)
 * Reads: [1:0]/[3:2] pwr_mode_ack_o, [16] busy_o, [17] bist_fail_o,
 *        [31:20] bist_fail_addr_o.
 * Replace the hook bodies with whatever the real SoC provides.
 *
 * The program runs from another memory; the tested sram holds no stack or data.
 */

#include <stdint.h>

#include "sram.h"

#define SRAM_BASE          0x20000000u   /* sram instance on the bus   */
#define SRAM_SIZE          0x00001000u   /* 32 x 1024 = 4 KiB          */
#define SRAM_DOMAINS       2u            /* NUM_BANKS with BANK_PG     */
#define SYSCTL_SRAM_ADDR   0x40001000u   /* example side-band register */

#define SYSCTL (*(volatile uint32_t *)(uintptr_t)SYSCTL_SRAM_ADDR)

/* ---- hooks: example SoC wiring ---------------------------------------- */

static void hk_set_req(void *ctx, uint32_t domain, uint32_t mode)
{
    uint32_t sh = 2u * domain;

    (void)ctx;
    SYSCTL = (SYSCTL & ~(3u << sh) & 0x000000FFu) | ((mode & 3u) << sh);
}

static uint32_t hk_get_ack(void *ctx, uint32_t domain)
{
    (void)ctx;
    return (SYSCTL >> (2u * domain)) & 3u;
}

static void hk_pulse_clr(void *ctx)
{
    (void)ctx;
    SYSCTL = (SYSCTL & 0x000000FFu) | (1u << 8);
}

static void hk_pulse_bist(void *ctx)
{
    (void)ctx;
    SYSCTL = (SYSCTL & 0x000000FFu) | (1u << 9);
}

static uint32_t hk_get_status(void *ctx)
{
    uint32_t r = SYSCTL;

    (void)ctx;
    return (((r >> 16) & 1u) != 0u ? SRAM_STATUS_BUSY : 0u) |
           (((r >> 17) & 1u) != 0u ? SRAM_STATUS_BIST_FAIL : 0u);
}

static uint32_t hk_get_bist_fail_addr(void *ctx)
{
    (void)ctx;
    return SYSCTL >> 20;
}

static void hk_pulse_ecc_inj(void *ctx, uint32_t bits)
{
    (void)ctx;
    SYSCTL = (SYSCTL & 0x000000FFu) | ((bits & 3u) << 10);
}

static const sram_hooks_t k_hooks = {
    0,
    hk_set_req,
    hk_get_ack,
    hk_pulse_clr,
    hk_pulse_bist,
    hk_get_status,
    hk_get_bist_fail_addr,
    hk_pulse_ecc_inj
};

/* ---- example flow ------------------------------------------------------- */

int main(void)
{
    sram_dev_t  dev;
    sram_fail_t fail;
    uint32_t    word;
    uint32_t    off;
    uint32_t    len;
    int         rc;

    if (sram_init(&dev, &k_hooks, SRAM_DOMAINS, 100000u) != SRAM_OK) {
        return 1;
    }

    /* 1. Power-on self test: hardware BIST, then the software tests. */
    rc = sram_pwr_set_mode_all(&dev, SRAM_PWR_RUN);
    if (rc == SRAM_OK) {
        rc = sram_bist_run(&dev, &word);           /* word = first failing word */
    }
    if (rc == SRAM_OK) {
        rc = sram_test_all(SRAM_BASE, SRAM_SIZE, SRAM_TEST_ALL, &fail);
    }
    if (rc != SRAM_OK) {
        return 2;                                  /* report fail.addr etc.     */
    }

    /* 2. Start from a zeroed array (the clear engine is faster than a loop). */
    if (sram_clear(&dev) != SRAM_OK) {
        return 3;
    }

    /* 3. Only bank 0 is needed for now: test it, keep bank 1 in deep sleep
     *    (contents kept; an access to it would be a bus error). */
    if ((sram_pwr_domain_range(&dev, SRAM_SIZE, 0u, &off, &len) != SRAM_OK) ||
        (sram_pwr_set_mode(&dev, 1u, SRAM_PWR_DS) != SRAM_OK) ||
        (sram_test_march_c(SRAM_BASE + off, len, 0u, &fail) != SRAM_OK)) {
        return 4;
    }

    /* 4. Idle: bank 0 to light sleep (wakes by itself on an access). */
    if (sram_pwr_set_mode(&dev, 0u, SRAM_PWR_LS) != SRAM_OK) {
        return 5;
    }

    /* 5. Bank 1 is not needed any more: shut it down. It reads as zero after
     *    it is woken again. */
    if (sram_pwr_set_mode(&dev, 1u, SRAM_PWR_SD) != SRAM_OK) {
        return 6;
    }
    return 0;
}
