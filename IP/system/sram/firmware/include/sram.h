/**
 * @file sram.h
 * @brief Public API of the sram IP firmware: memory tests and side-band helpers
 *        (C99, bare-metal).
 *
 * The sram IP has no register block (design decision D2): software sees only
 * the memory itself on the bus. Power modes, the clear engine, BIST and ECC
 * error injection are side-band pins that the SoC integrator wires to
 * something software can reach (GPIO, a system-control register, ...). This
 * firmware therefore has two parts:
 *
 *  1. Memory tests (sram_test_*): run directly on the memory through a base
 *     address and a size. No side-band access needed.
 *  2. Side-band helpers (sram_pwr_*, sram_clear, sram_bist_run,
 *     sram_ecc_inject): sequencing only. The integrator supplies the pin
 *     access as a table of callbacks (sram_hooks_t), so no address map is
 *     assumed.
 *
 * Usage
 * -----
 * Memory tests:
 *     sram_fail_t f;
 *     if (sram_test_march_c(SRAM_BASE, SRAM_SIZE, 0u, &f) != SRAM_OK) { ... }
 *
 * Side band:
 *     static const sram_hooks_t hooks = { my_ctx, my_set_req, my_get_ack, ... };
 *     sram_dev_t dev;
 *     sram_init(&dev, &hooks, 2u, 100000u);      // 2 power domains (BANK_PG)
 *     sram_pwr_set_mode(&dev, 1u, SRAM_PWR_DS);  // bank 1 to deep sleep
 *
 * Rules the hardware imposes (README "Power Management"):
 *  - A bus access to a domain requested into DEEP_SLEEP or SHUTDOWN returns a
 *    bus error. Do not run a memory test on such a domain.
 *  - LIGHT_SLEEP wakes automatically on an access (wait states).
 *  - SHUTDOWN loses the contents; the IP zeroes the domain before it
 *    acknowledges RUN again.
 *  - The memory tests and BIST destroy the contents of the tested range.
 *    The stack, the code and the data of the program running the test must
 *    not be in that range.
 *  - With BYTE_EN = 0 and PARTIAL_WR_ERR = 1 a byte or halfword write is a bus
 *    error: do not run sram_test_byte_lanes() on such a configuration.
 *
 * Dependencies
 * ------------
 * - stdint.h only. Memory accesses go through the SRAM_RD / SRAM_WR macros in
 *   src/sram_access.h (volatile pointers; replace them for your platform).
 *
 * No OS, RTOS, or dynamic-allocation dependencies.
 */

#ifndef SRAM_H
#define SRAM_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* =========================================================================
 * Return codes
 * ========================================================================= */

#define SRAM_OK              0   /**< success / test passed                     */
#define SRAM_ERR_FAIL      (-1)  /**< memory test or BIST found a fault          */
#define SRAM_ERR_ARG       (-2)  /**< bad argument (NULL, alignment, size, mode) */
#define SRAM_ERR_TIMEOUT   (-3)  /**< side band did not respond in time          */
#define SRAM_ERR_STATE     (-4)  /**< not allowed in the current power state     */
#define SRAM_ERR_NOHOOK    (-5)  /**< the needed hook is NULL (option not wired) */

/* =========================================================================
 * Power modes (values of pwr_mode_req_i / pwr_mode_ack_o, sram_pkg::PWR_*)
 * ========================================================================= */

#define SRAM_PWR_RUN  0u  /**< normal operation                                  */
#define SRAM_PWR_LS   1u  /**< light sleep: kept; an access wakes the domain     */
#define SRAM_PWR_DS   2u  /**< deep sleep: kept; an access is a bus error        */
#define SRAM_PWR_SD   3u  /**< shutdown: lost (zeroed on wake); bus error        */

/* =========================================================================
 * Status bits returned by sram_hooks_t.get_status
 * ========================================================================= */

#define SRAM_STATUS_BUSY       (1u << 0)  /**< busy_o                            */
#define SRAM_STATUS_BIST_FAIL  (1u << 1)  /**< bist_fail_o (valid after a run)   */

/* =========================================================================
 * Memory tests
 * ========================================================================= */

/** First failure found by a memory test. */
typedef struct {
    uintptr_t addr;      /**< byte address of the failing access            */
    uint32_t  expected;  /**< value expected (byte / halfword tests: zero-extended) */
    uint32_t  actual;    /**< value read                                    */
} sram_fail_t;

/** Test selection for sram_test_all(). */
#define SRAM_TEST_ADDR_BUS    (1u << 0)
#define SRAM_TEST_WALKING     (1u << 1)
#define SRAM_TEST_ADDR_IN     (1u << 2)
#define SRAM_TEST_MARCH_C     (1u << 3)
#define SRAM_TEST_BYTE_LANES  (1u << 4)
#define SRAM_TEST_ALL_WORD    (SRAM_TEST_ADDR_BUS | SRAM_TEST_WALKING | \
                               SRAM_TEST_ADDR_IN | SRAM_TEST_MARCH_C)
#define SRAM_TEST_ALL         (SRAM_TEST_ALL_WORD | SRAM_TEST_BYTE_LANES)

/*
 * Common arguments of every test:
 *   base  byte address of the first word; must be 4-byte aligned.
 *   size  bytes to test; a non-zero multiple of 4.
 *   fail  filled with the first failure (may be NULL).
 * Return SRAM_OK, SRAM_ERR_FAIL, or SRAM_ERR_ARG.
 */

/**
 * @brief Address-bus test: finds stuck and shorted address lines.
 *
 * Writes a pattern at base and at every power-of-two word offset below size,
 * then checks that writing one location never changes another. 2 x log2(words)
 * accesses, so it is cheap to run first. Faults in address bits beyond the
 * largest power of two below size are not covered.
 */
int sram_test_addr_bus(uintptr_t base, uint32_t size, sram_fail_t *fail);

/**
 * @brief Walking 1s and walking 0s in every word: stuck and bridged data bits.
 *
 * Each word: a single 1 walked through all 32 bits, then a single 0. 128
 * accesses per word. Pass size = 4 for a quick data-bus test on one word.
 */
int sram_test_walking(uintptr_t base, uint32_t size, sram_fail_t *fail);

/**
 * @brief Address-in-address: each word holds its own address, then its
 *        complement. Finds address-decoder faults (aliased and unreachable
 *        words) over the whole range.
 */
int sram_test_addr_in_addr(uintptr_t base, uint32_t size, sram_fail_t *fail);

/**
 * @brief March C- over words with data background bg (bit-wise):
 *        up/dn(w bg); up(r bg, w ~bg); up(r ~bg, w bg);
 *        dn(r bg, w ~bg); dn(r ~bg, w bg); up/dn(r bg).
 *
 * 10 accesses per word. Detects stuck-at, transition, address-decoder and
 * unlinked coupling faults between words. Use bg = 0 (solid) and, for faults
 * between neighbouring bits, bg = 0x55555555 (checkerboard).
 */
int sram_test_march_c(uintptr_t base, uint32_t size, uint32_t bg,
                      sram_fail_t *fail);

/**
 * @brief Byte lanes: byte and halfword writes change only their own lanes,
 *        and byte / halfword reads return the right lane (little-endian).
 *
 * Runs on the first and the last word of the range (size >= 4). Needs
 * BYTE_EN = 1, or BYTE_EN = 0 with PARTIAL_WR_ERR = 0 (then a narrow write
 * writes the full word, and this test reports the failure).
 */
int sram_test_byte_lanes(uintptr_t base, uint32_t size, sram_fail_t *fail);

/**
 * @brief Run the selected tests (SRAM_TEST_* mask) in the order addr bus,
 *        walking, address-in-address, March C- (bg 0, then 0x55555555),
 *        byte lanes. Stops at the first failing test.
 * @return SRAM_OK, SRAM_ERR_FAIL, SRAM_ERR_ARG (also for an empty mask).
 */
int sram_test_all(uintptr_t base, uint32_t size, uint32_t tests,
                  sram_fail_t *fail);

/* =========================================================================
 * Side band
 * ========================================================================= */

/**
 * Pin access supplied by the integrator. ctx is passed back unchanged.
 * Each pulse_* hook must return only after the pulse has reached the IP
 * (one cycle of port A's clock), so that a following get_status sees its
 * effect. A hook may be NULL when the option is not built or not wired; the
 * helpers that need it then return SRAM_ERR_NOHOOK.
 */
typedef struct {
    void     *ctx;
    /** drive pwr_mode_req_i for one domain (held until changed) */
    void     (*set_pwr_req)(void *ctx, uint32_t domain, uint32_t mode);
    /** read pwr_mode_ack_o for one domain */
    uint32_t (*get_pwr_ack)(void *ctx, uint32_t domain);
    /** one-cycle pulse on clr_req_i */
    void     (*pulse_clr)(void *ctx);
    /** one-cycle pulse on bist_start_i (BIST_EN) */
    void     (*pulse_bist)(void *ctx);
    /** SRAM_STATUS_* bits from busy_o and bist_fail_o */
    uint32_t (*get_status)(void *ctx);
    /** bist_fail_addr_o: first failing word index (BIST_EN) */
    uint32_t (*get_bist_fail_addr)(void *ctx);
    /** one-cycle pulse on ecc_inj_i, bits [1:0] (ECC_EN) */
    void     (*pulse_ecc_inj)(void *ctx, uint32_t bits);
} sram_hooks_t;

/** One sram instance. Fill with sram_init(); the fields are read-only after. */
typedef struct {
    const sram_hooks_t *hooks;
    uint32_t            num_domains;  /**< NUM_BANKS with BANK_PG, else 1      */
    uint32_t            timeout;      /**< max status polls per wait            */
} sram_dev_t;

/**
 * @brief Bind an instance to its hooks.
 * @param num_domains  power domains (>= 1).
 * @param timeout      maximum number of polls in each wait (>= 1).
 * @return SRAM_OK or SRAM_ERR_ARG (NULL dev / hooks, set_pwr_req or
 *         get_pwr_ack or get_status NULL, zero num_domains / timeout).
 */
int sram_init(sram_dev_t *dev, const sram_hooks_t *hooks,
              uint32_t num_domains, uint32_t timeout);

/**
 * @brief Request a power mode for one domain and wait until it is acknowledged.
 *
 * A move between two sleep modes passes through RUN in hardware; this helper
 * waits for the final mode only. Leaving SHUTDOWN waits for the zeroing pass
 * too (the IP acknowledges RUN after it).
 * @return SRAM_OK, SRAM_ERR_ARG (domain / mode out of range), SRAM_ERR_TIMEOUT.
 */
int sram_pwr_set_mode(const sram_dev_t *dev, uint32_t domain, uint32_t mode);

/**
 * @brief Request a mode in every domain at once, then wait for all of them.
 */
int sram_pwr_set_mode_all(const sram_dev_t *dev, uint32_t mode);

/**
 * @brief Mode in effect (pwr_mode_ack_o) of one domain, or SRAM_ERR_ARG.
 */
int sram_pwr_get_mode(const sram_dev_t *dev, uint32_t domain);

/**
 * @brief Byte range [*offset, *offset + *len) of one domain within an array
 *        of size bytes (domains are equal slices, domain 0 at the lowest
 *        address).
 * @return SRAM_OK or SRAM_ERR_ARG (NULL output, domain out of range, size not
 *         a multiple of 4 x num_domains).
 */
int sram_pwr_domain_range(const sram_dev_t *dev, uint32_t size, uint32_t domain,
                          uint32_t *offset, uint32_t *len);

/**
 * @brief Wait until busy_o is low (no clear, BIST, power transition or ECC
 *        read-modify-write in progress).
 * @return SRAM_OK or SRAM_ERR_TIMEOUT.
 */
int sram_wait_idle(const sram_dev_t *dev);

/**
 * @brief Zero the whole array with the clear engine and wait for the end.
 *
 * The engine skips domains that are in DEEP_SLEEP or SHUTDOWN, so this helper
 * refuses (SRAM_ERR_STATE) unless every domain is in RUN or LIGHT_SLEEP.
 * @return SRAM_OK, SRAM_ERR_STATE, SRAM_ERR_NOHOOK, SRAM_ERR_TIMEOUT.
 */
int sram_clear(const sram_dev_t *dev);

/**
 * @brief Run the March C- BIST engine (BIST_EN) and wait for the result.
 *
 * Destroys the contents of the whole array. The IP holds every domain in RUN
 * while the test runs and restores the requested modes after it.
 * @param fail_word  first failing word index on SRAM_ERR_FAIL (may be NULL).
 * @return SRAM_OK, SRAM_ERR_FAIL, SRAM_ERR_NOHOOK, SRAM_ERR_TIMEOUT.
 */
int sram_bist_run(const sram_dev_t *dev, uint32_t *fail_word);

/**
 * @brief Arm an ECC error on the next port-A write (ECC_EN): bits = 1 flips
 *        one stored bit (corrected on read), 2 flips two (uncorrectable).
 * @return SRAM_OK, SRAM_ERR_ARG (bits not 1 or 2), SRAM_ERR_NOHOOK.
 */
int sram_ecc_inject(const sram_dev_t *dev, uint32_t bits);

#ifdef __cplusplus
}
#endif

#endif /* SRAM_H */
