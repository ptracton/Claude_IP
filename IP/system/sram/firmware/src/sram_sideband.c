/**
 * @file sram_sideband.c
 * @brief Side-band helpers for the sram IP: power modes, clear, BIST, ECC
 *        error injection (C99, bare-metal).
 *
 * The pins are reached only through the integrator's hooks (sram_hooks_t);
 * this file holds the sequencing. Every wait polls at most dev->timeout times.
 * No global state, no OS, RTOS, or dynamic-allocation dependencies.
 */

#include "sram.h"

/* =========================================================================
 * Internal helpers
 * ========================================================================= */

static int dev_ok(const sram_dev_t *dev)
{
    return (dev != (const sram_dev_t *)0) && (dev->hooks != (const sram_hooks_t *)0);
}

/** Poll get_pwr_ack(domain) until it equals mode. */
static int wait_ack(const sram_dev_t *dev, uint32_t domain, uint32_t mode)
{
    const sram_hooks_t *h = dev->hooks;
    uint32_t n;

    for (n = 0u; n < dev->timeout; n++) {
        if ((h->get_pwr_ack(h->ctx, domain) & 3u) == mode) {
            return SRAM_OK;
        }
    }
    return SRAM_ERR_TIMEOUT;
}

/* =========================================================================
 * Initialisation
 * ========================================================================= */

int sram_init(sram_dev_t *dev, const sram_hooks_t *hooks,
              uint32_t num_domains, uint32_t timeout)
{
    if ((dev == (sram_dev_t *)0) || (hooks == (const sram_hooks_t *)0) ||
        (hooks->set_pwr_req == 0) || (hooks->get_pwr_ack == 0) ||
        (hooks->get_status == 0) || (num_domains == 0u) || (timeout == 0u)) {
        return SRAM_ERR_ARG;
    }
    dev->hooks       = hooks;
    dev->num_domains = num_domains;
    dev->timeout     = timeout;
    return SRAM_OK;
}

/* =========================================================================
 * Power modes
 * ========================================================================= */

int sram_pwr_set_mode(const sram_dev_t *dev, uint32_t domain, uint32_t mode)
{
    if (!dev_ok(dev) || (domain >= dev->num_domains) || (mode > SRAM_PWR_SD)) {
        return SRAM_ERR_ARG;
    }
    dev->hooks->set_pwr_req(dev->hooks->ctx, domain, mode);
    return wait_ack(dev, domain, mode);
}

int sram_pwr_set_mode_all(const sram_dev_t *dev, uint32_t mode)
{
    uint32_t d;

    if (!dev_ok(dev) || (mode > SRAM_PWR_SD)) {
        return SRAM_ERR_ARG;
    }
    /* request every domain first, so the transitions run in parallel */
    for (d = 0u; d < dev->num_domains; d++) {
        dev->hooks->set_pwr_req(dev->hooks->ctx, d, mode);
    }
    for (d = 0u; d < dev->num_domains; d++) {
        int rc = wait_ack(dev, d, mode);

        if (rc != SRAM_OK) {
            return rc;
        }
    }
    return SRAM_OK;
}

int sram_pwr_get_mode(const sram_dev_t *dev, uint32_t domain)
{
    if (!dev_ok(dev) || (domain >= dev->num_domains)) {
        return SRAM_ERR_ARG;
    }
    return (int)(dev->hooks->get_pwr_ack(dev->hooks->ctx, domain) & 3u);
}

int sram_pwr_domain_range(const sram_dev_t *dev, uint32_t size, uint32_t domain,
                          uint32_t *offset, uint32_t *len)
{
    uint32_t slice;

    if (!dev_ok(dev) || (offset == (uint32_t *)0) || (len == (uint32_t *)0) ||
        (domain >= dev->num_domains) || (size == 0u) ||
        ((size % dev->num_domains) != 0u)) {
        return SRAM_ERR_ARG;
    }
    slice = size / dev->num_domains;
    if ((slice & 3u) != 0u) {
        return SRAM_ERR_ARG;
    }
    *offset = slice * domain;
    *len    = slice;
    return SRAM_OK;
}

/* =========================================================================
 * Status, clear, BIST
 * ========================================================================= */

int sram_wait_idle(const sram_dev_t *dev)
{
    uint32_t n;

    if (!dev_ok(dev)) {
        return SRAM_ERR_ARG;
    }
    for (n = 0u; n < dev->timeout; n++) {
        if ((dev->hooks->get_status(dev->hooks->ctx) & SRAM_STATUS_BUSY) == 0u) {
            return SRAM_OK;
        }
    }
    return SRAM_ERR_TIMEOUT;
}

/**
 * Sequence:
 *  1. every domain must be in RUN or LIGHT_SLEEP (the engine skips the
 *     others, which would leave them uncleared);
 *  2. pulse clr_req_i; busy_o is high from the next cycle until the pass ends;
 *  3. wait for busy_o low.
 */
int sram_clear(const sram_dev_t *dev)
{
    uint32_t d;

    if (!dev_ok(dev)) {
        return SRAM_ERR_ARG;
    }
    if (dev->hooks->pulse_clr == 0) {
        return SRAM_ERR_NOHOOK;
    }
    for (d = 0u; d < dev->num_domains; d++) {
        uint32_t m = dev->hooks->get_pwr_ack(dev->hooks->ctx, d) & 3u;

        if ((m != SRAM_PWR_RUN) && (m != SRAM_PWR_LS)) {
            return SRAM_ERR_STATE;
        }
    }
    dev->hooks->pulse_clr(dev->hooks->ctx);
    return sram_wait_idle(dev);
}

/**
 * Sequence: pulse bist_start_i; busy_o is high from the next cycle until
 * bist_done_o; then bist_fail_o / bist_fail_addr_o hold the result until the
 * next start.
 */
int sram_bist_run(const sram_dev_t *dev, uint32_t *fail_word)
{
    const sram_hooks_t *h;
    int rc;

    if (!dev_ok(dev)) {
        return SRAM_ERR_ARG;
    }
    h = dev->hooks;
    if ((h->pulse_bist == 0) || (h->get_bist_fail_addr == 0)) {
        return SRAM_ERR_NOHOOK;
    }
    h->pulse_bist(h->ctx);
    rc = sram_wait_idle(dev);
    if (rc != SRAM_OK) {
        return rc;
    }
    if ((h->get_status(h->ctx) & SRAM_STATUS_BIST_FAIL) != 0u) {
        if (fail_word != (uint32_t *)0) {
            *fail_word = h->get_bist_fail_addr(h->ctx);
        }
        return SRAM_ERR_FAIL;
    }
    return SRAM_OK;
}

/* =========================================================================
 * ECC error injection
 * ========================================================================= */

int sram_ecc_inject(const sram_dev_t *dev, uint32_t bits)
{
    if (!dev_ok(dev) || ((bits != 1u) && (bits != 2u))) {
        return SRAM_ERR_ARG;
    }
    if (dev->hooks->pulse_ecc_inj == 0) {
        return SRAM_ERR_NOHOOK;
    }
    dev->hooks->pulse_ecc_inj(dev->hooks->ctx, bits);
    return SRAM_OK;
}
