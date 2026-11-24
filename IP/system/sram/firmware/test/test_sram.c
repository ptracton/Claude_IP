/**
 * @file test_sram.c
 * @brief Host unit tests for the sram firmware (memory tests + side band).
 *
 * Memory tests run against the fault-injecting model of sram_test_mem.c; the
 * side-band helpers against a fake IP (fake_*) that models the power state
 * machine, clear engine and BIST with a delay counted in hook calls.
 *
 * Build and run: verification/tools/fw_sram.py (host gcc, -DSRAM_FW_HOST_TEST).
 * Output: one "PASS <check>" / "FAIL <check>: ..." line per check, then
 * "RESULT: PASS n/n" or "RESULT: FAIL k/n". Exit status 0 only if all pass.
 */

#include <stdio.h>
#include <string.h>

#include "sram.h"
#include "sram_test_mem.h"

static unsigned g_pass;
static unsigned g_fail;

static void check(int ok, const char *name, const char *detail)
{
    if (ok) {
        g_pass++;
        printf("PASS %s\n", name);
    } else {
        g_fail++;
        printf("FAIL %s: %s\n", name, detail);
    }
}

/* =========================================================================
 * Memory tests
 * ========================================================================= */

typedef int (*memtest_fn)(uintptr_t, uint32_t, sram_fail_t *);

static int run_march0(uintptr_t b, uint32_t s, sram_fail_t *f)
{
    return sram_test_march_c(b, s, 0u, f);
}

static int run_march55(uintptr_t b, uint32_t s, sram_fail_t *f)
{
    return sram_test_march_c(b, s, 0x55555555u, f);
}

static int run_all(uintptr_t b, uint32_t s, sram_fail_t *f)
{
    return sram_test_all(b, s, SRAM_TEST_ALL, f);
}

static const struct {
    const char *name;
    memtest_fn  fn;
} k_tests[] = {
    { "addr_bus",    sram_test_addr_bus },
    { "walking",     sram_test_walking },
    { "addr_in",     sram_test_addr_in_addr },
    { "march_c_0",   run_march0 },
    { "march_c_55",  run_march55 },
    { "byte_lanes",  sram_test_byte_lanes },
    { "all",         run_all },
};
#define N_TESTS (sizeof(k_tests) / sizeof(k_tests[0]))

/* Every test passes on a fault-free memory of several sizes, from any fill,
 * and never accesses outside the range. */
static void test_fault_free(void)
{
    static const uint32_t sizes[] = { 4u, 8u, 12u, 64u, 1020u, 4096u, 16384u };
    static const uint32_t fills[] = { 0u, 0xFFFFFFFFu, 0xDEADBEEFu };
    unsigned t, s, f;
    char name[96];

    for (t = 0u; t < N_TESTS; t++) {
        for (s = 0u; s < sizeof(sizes) / sizeof(sizes[0]); s++) {
            int ok = 1;

            for (f = 0u; f < sizeof(fills) / sizeof(fills[0]); f++) {
                uintptr_t base = tm_reset(sizes[s], fills[f]);
                int rc = k_tests[t].fn(base, sizes[s], 0);

                ok = ok && (rc == SRAM_OK) && !tm_bad_access();
            }
            snprintf(name, sizeof(name), "fault_free/%s/%uB", k_tests[t].name,
                     (unsigned)sizes[s]);
            check(ok, name, "fault-free memory did not pass (or bad access)");
        }
    }
}

/* Argument checks. */
static void test_args(void)
{
    uintptr_t base = tm_reset(64u, 0u);
    unsigned t;
    char name[96];

    for (t = 0u; t < N_TESTS; t++) {
        snprintf(name, sizeof(name), "args/%s", k_tests[t].name);
        check((k_tests[t].fn(base + 2u, 16u, 0) == SRAM_ERR_ARG) &&
              (k_tests[t].fn(base, 0u, 0) == SRAM_ERR_ARG) &&
              (k_tests[t].fn(base, 6u, 0) == SRAM_ERR_ARG) &&
              (tm_accesses() == 0u),
              name, "misaligned base / zero size / size not x4 not rejected");
    }
    check((sram_test_all(base, 64u, 0u, 0) == SRAM_ERR_ARG) &&
          (sram_test_all(base, 64u, 1u << 7, 0) == SRAM_ERR_ARG),
          "args/all_mask", "empty or unknown test mask not rejected");
}

/* One fault, one test: expect detect (and, if want_word >= 0, the failing
 * word index), or expect a pass (detect = 0, the test does not cover it). */
static void expect(const char *fault, const tm_fault_t *flt, unsigned t,
                   int detect, int want_word)
{
    const uint32_t size = 4096u;              /* 1024 words */
    sram_fail_t fl;
    char name[128];
    char why[160];
    uintptr_t base = tm_reset(size, 0u);
    int rc;
    int ok;

    memset(&fl, 0, sizeof(fl));
    tm_set_fault(flt);
    rc = k_tests[t].fn(base, size, &fl);
    if (detect) {
        ok = (rc == SRAM_ERR_FAIL) && (fl.expected != fl.actual) &&
             ((want_word < 0) || (fl.addr >> 2 == (base >> 2) + (uintptr_t)want_word));
        snprintf(why, sizeof(why), "rc %d, fail at word %ld exp 0x%08x act 0x%08x",
                 rc, (long)((fl.addr - base) >> 2), (unsigned)fl.expected,
                 (unsigned)fl.actual);
    } else {
        ok = (rc == SRAM_OK);
        snprintf(why, sizeof(why), "rc %d, expected a pass (fault not covered)", rc);
    }
    ok = ok && !tm_bad_access();
    snprintf(name, sizeof(name), "%s/%s/%s", detect ? "detect" : "blind", fault,
             k_tests[t].name);
    check(ok, name, why);
}

enum { T_ADDR, T_WALK, T_AIN, T_M0, T_M55, T_LANES, T_ALL };

static void test_faults(void)
{
    tm_fault_t f;

    /* stuck-at bits: every word test finds them at the right word */
    memset(&f, 0, sizeof(f));
    f.kind = TM_STUCK; f.w = 37u; f.b = 5u; f.v = 0u;
    expect("stuck0_w37b5", &f, T_WALK, 1, 37);
    expect("stuck0_w37b5", &f, T_AIN, 1, 37);
    expect("stuck0_w37b5", &f, T_M0, 1, 37);
    expect("stuck0_w37b5", &f, T_M55, 1, 37);
    expect("stuck0_w37b5", &f, T_ALL, 1, -1);
    f.v = 1u; f.w = 1000u; f.b = 31u;
    expect("stuck1_w1000b31", &f, T_WALK, 1, 1000);
    expect("stuck1_w1000b31", &f, T_AIN, 1, 1000);
    expect("stuck1_w1000b31", &f, T_M0, 1, 1000);

    /* transition fault (cannot rise): March and walking */
    memset(&f, 0, sizeof(f));
    f.kind = TM_TRANSITION; f.w = 512u; f.b = 0u;
    expect("trans_w512b0", &f, T_WALK, 1, 512);
    expect("trans_w512b0", &f, T_M0, 1, 512);

    /* address decoder: address-bus, address-in-address and March */
    memset(&f, 0, sizeof(f));
    f.kind = TM_ADDR_STUCK; f.b = 3u; f.v = 0u;
    expect("addr_b3_stuck0", &f, T_ADDR, 1, -1);
    expect("addr_b3_stuck0", &f, T_AIN, 1, -1);
    expect("addr_b3_stuck0", &f, T_M0, 1, -1);
    expect("addr_b3_stuck0", &f, T_WALK, 0, -1);  /* per-word test is blind */
    f.v = 1u; f.b = 9u;
    expect("addr_b9_stuck1", &f, T_ADDR, 1, -1);
    expect("addr_b9_stuck1", &f, T_AIN, 1, -1);
    expect("addr_b9_stuck1", &f, T_M0, 1, -1);
    memset(&f, 0, sizeof(f));
    f.kind = TM_ADDR_SHORT; f.b = 2u; f.b2 = 6u;
    expect("addr_b2b6_short", &f, T_ADDR, 1, -1);
    expect("addr_b2b6_short", &f, T_AIN, 1, -1);

    /* coupling between words: March (both directions), not walking */
    memset(&f, 0, sizeof(f));
    f.kind = TM_COUPLING; f.w = 10u; f.b = 4u; f.w2 = 200u; f.b2 = 4u;
    expect("couple_w10_w200", &f, T_M0, 1, 200);
    expect("couple_w10_w200", &f, T_WALK, 0, -1);
    f.w = 900u; f.w2 = 3u; f.b2 = 17u;            /* aggressor above victim */
    expect("couple_w900_w3", &f, T_M0, 1, 3);

    /* falling-edge coupling, aggressor below victim: the last write of M4
     * (down) disturbs a word already passed, so only the final read element M5
     * sees it */
    memset(&f, 0, sizeof(f));
    f.kind = TM_COUPLING; f.v = 1u; f.w = 3u; f.b = 0u; f.w2 = 900u; f.b2 = 9u;
    expect("couple_fall_w3_w900", &f, T_M0, 1, 900);

    /* pattern sensitive: a 0 between two 1s reads as 1. Walking 0s and the
     * checkerboard March find it, walking 1s and the solid March cannot */
    memset(&f, 0, sizeof(f));
    f.kind = TM_NPSF; f.w = 200u; f.b = 5u; f.b2 = 4u; f.b3 = 6u;
    expect("npsf_w200_b5", &f, T_WALK, 1, 200);
    expect("npsf_w200_b5", &f, T_M55, 1, 200);
    expect("npsf_w200_b5", &f, T_M0, 0, -1);
    f.w = 300u; f.b = 31u; f.b2 = 30u; f.b3 = 0u;   /* only walking 0 at bit 31 */
    expect("npsf_w300_b31", &f, T_WALK, 1, 300);

    /* decoder multiple access, both directions of the address-bus test */
    memset(&f, 0, sizeof(f));
    f.kind = TM_ADDR_MULTI; f.w = 0u; f.w2 = 8u;     /* base write hits offset 8 */
    expect("multi_w0_w8", &f, T_ADDR, 1, 8);
    f.w = 4u; f.w2 = 64u;                            /* offset 4 hits offset 64 */
    expect("multi_w4_w64", &f, T_ADDR, 1, 64);

    /* bridge inside a word: walking and the checkerboard March, not the
     * solid-background March */
    memset(&f, 0, sizeof(f));
    f.kind = TM_BRIDGE; f.w = 77u; f.b = 3u; f.b2 = 4u;
    expect("bridge_w77_b3b4", &f, T_WALK, 1, 77);
    expect("bridge_w77_b3b4", &f, T_M55, 1, 77);
    expect("bridge_w77_b3b4", &f, T_M0, 0, -1);

    /* byte lanes: only the byte-lane test sees them */
    memset(&f, 0, sizeof(f));
    f.kind = TM_LANE_FULL;
    expect("lane_full_word", &f, T_LANES, 1, 0);
    expect("lane_full_word", &f, T_M0, 0, -1);
    expect("lane_full_word", &f, T_ALL, 1, 0);
    f.kind = TM_LANE_SWAP;
    expect("lane_swap", &f, T_LANES, 1, 0);
    f.v = 1u; f.w = 1023u;                           /* last word only */
    expect("lane_swap_last_word", &f, T_LANES, 1, 1023);
    memset(&f, 0, sizeof(f));
    f.kind = TM_HALF_LOW;
    expect("half_low", &f, T_LANES, 1, 0);

    /* stuck-at on a bit that is 0 in the word's own address: only the
     * complement pass of address-in-address can see it */
    {
        uintptr_t base = tm_reset(4096u, 0u);
        uint32_t a = (uint32_t)(base + 4u * 100u);
        uint32_t k = 2u;

        while ((k < 31u) && (((a >> k) & 1u) != 0u)) {
            k++;
        }
        memset(&f, 0, sizeof(f));
        f.kind = TM_STUCK; f.w = 100u; f.b = k; f.v = 0u;
        expect("stuck0_addr_bit_zero", &f, T_AIN, 1, 100);
    }
}

/* sram_test_all stops at the first failing test and skips unselected ones. */
static void test_all_select(void)
{
    sram_fail_t fl;
    tm_fault_t f;
    uintptr_t base;

    memset(&f, 0, sizeof(f));
    f.kind = TM_LANE_FULL;
    base = tm_reset(1024u, 0u);
    tm_set_fault(&f);
    check(sram_test_all(base, 1024u, SRAM_TEST_ALL_WORD, &fl) == SRAM_OK,
          "all/word_only_skips_lanes", "word tests should not see a lane fault");
    base = tm_reset(1024u, 0u);
    tm_set_fault(&f);
    check(sram_test_all(base, 1024u, SRAM_TEST_BYTE_LANES, &fl) == SRAM_ERR_FAIL,
          "all/lanes_only", "byte-lane test alone should fail");
    check(sram_test_byte_lanes(base, 4u, 0) == SRAM_ERR_FAIL,
          "byte_lanes/one_word", "single-word range should be tested");
    memset(&f, 0, sizeof(f));
    f.kind = TM_BRIDGE; f.w = 77u; f.b = 3u; f.b2 = 4u;
    base = tm_reset(1024u, 0u);
    tm_set_fault(&f);
    check(sram_test_all(base, 1024u, SRAM_TEST_MARCH_C, &fl) == SRAM_ERR_FAIL,
          "all/march_runs_checkerboard", "March C- selection must include the 0x55 background");
}

/* =========================================================================
 * Side band: fake IP
 * ========================================================================= */

#define FAKE_DOMAINS 4u

typedef struct {
    uint32_t req[FAKE_DOMAINS];
    uint32_t ack[FAKE_DOMAINS];
    uint32_t cnt[FAKE_DOMAINS];   /* hook calls until ack follows req */
    uint32_t clr_cnt;             /* hook calls until the clear ends   */
    uint32_t bist_cnt;
    int      bist_fail;
    uint32_t bist_fail_addr;
    int      stuck;               /* acks / busy never settle          */
    uint32_t delay;               /* transition / engine length        */
    unsigned n_clr, n_bist, n_inj, n_req, n_ack_before_last_req;
    uint32_t inj_bits;
    unsigned calls;
} fake_t;

static fake_t g_fake;

/* advance the fake IP by one step (one hook call) */
static void fake_tick(fake_t *f)
{
    uint32_t d;

    f->calls++;
    if (f->stuck) {
        return;
    }
    for (d = 0u; d < FAKE_DOMAINS; d++) {
        if (f->ack[d] != f->req[d]) {
            if (f->cnt[d] == 0u) {
                f->ack[d] = f->req[d];
            } else {
                f->cnt[d]--;
            }
        }
    }
    if (f->clr_cnt != 0u) {
        f->clr_cnt--;
    }
    if (f->bist_cnt != 0u) {
        f->bist_cnt--;
    }
}

static void fake_set_req(void *ctx, uint32_t d, uint32_t m)
{
    fake_t *f = (fake_t *)ctx;

    fake_tick(f);
    f->req[d] = m;
    f->cnt[d] = f->delay;
    f->n_req++;
    f->n_ack_before_last_req = 0u;
}

static uint32_t fake_get_ack(void *ctx, uint32_t d)
{
    fake_t *f = (fake_t *)ctx;

    fake_tick(f);
    f->n_ack_before_last_req++;
    return f->ack[d];
}

static void fake_pulse_clr(void *ctx)
{
    fake_t *f = (fake_t *)ctx;

    fake_tick(f);
    f->n_clr++;
    f->clr_cnt = f->delay + 1u;
}

static void fake_pulse_bist(void *ctx)
{
    fake_t *f = (fake_t *)ctx;

    fake_tick(f);
    f->n_bist++;
    f->bist_cnt = f->delay + 1u;
}

static uint32_t fake_get_status(void *ctx)
{
    fake_t *f = (fake_t *)ctx;
    uint32_t s = 0u;

    fake_tick(f);
    if (f->stuck || (f->clr_cnt != 0u) || (f->bist_cnt != 0u)) {
        s |= SRAM_STATUS_BUSY;
    }
    if (f->bist_fail && (f->n_bist != 0u) && (f->bist_cnt == 0u)) {
        s |= SRAM_STATUS_BIST_FAIL;
    }
    return s;
}

static uint32_t fake_get_bist_fail_addr(void *ctx)
{
    fake_t *f = (fake_t *)ctx;

    fake_tick(f);
    return f->bist_fail_addr;
}

static void fake_pulse_ecc_inj(void *ctx, uint32_t bits)
{
    fake_t *f = (fake_t *)ctx;

    fake_tick(f);
    f->n_inj++;
    f->inj_bits = bits;
}

static sram_hooks_t g_hooks;

static void fake_reset(uint32_t delay)
{
    memset(&g_fake, 0, sizeof(g_fake));
    g_fake.delay = delay;
    g_hooks.ctx                = &g_fake;
    g_hooks.set_pwr_req        = fake_set_req;
    g_hooks.get_pwr_ack        = fake_get_ack;
    g_hooks.pulse_clr          = fake_pulse_clr;
    g_hooks.pulse_bist         = fake_pulse_bist;
    g_hooks.get_status         = fake_get_status;
    g_hooks.get_bist_fail_addr = fake_get_bist_fail_addr;
    g_hooks.pulse_ecc_inj      = fake_pulse_ecc_inj;
}

static void test_sideband(void)
{
    sram_dev_t dev;
    sram_hooks_t h;
    uint32_t m, off, len, word;
    int ok;

    /* init */
    fake_reset(3u);
    h = g_hooks;
    check((sram_init(0, &h, 1u, 10u) == SRAM_ERR_ARG) &&
          (sram_init(&dev, 0, 1u, 10u) == SRAM_ERR_ARG) &&
          (sram_init(&dev, &h, 0u, 10u) == SRAM_ERR_ARG) &&
          (sram_init(&dev, &h, 1u, 0u) == SRAM_ERR_ARG),
          "sb/init_args", "NULL / zero argument not rejected");
    h.set_pwr_req = 0;
    ok = (sram_init(&dev, &h, 1u, 10u) == SRAM_ERR_ARG);
    h = g_hooks; h.get_pwr_ack = 0;
    ok = ok && (sram_init(&dev, &h, 1u, 10u) == SRAM_ERR_ARG);
    h = g_hooks; h.get_status = 0;
    ok = ok && (sram_init(&dev, &h, 1u, 10u) == SRAM_ERR_ARG);
    check(ok, "sb/init_required_hooks", "missing required hook not rejected");
    check(sram_init(&dev, &g_hooks, FAKE_DOMAINS, 100u) == SRAM_OK,
          "sb/init_ok", "valid init failed");

    /* every mode, every domain, reached and reported */
    ok = 1;
    for (m = SRAM_PWR_LS; m <= SRAM_PWR_SD + 1u; m++) {
        uint32_t mode = m % 4u;   /* LS DS SD RUN */
        uint32_t d;

        for (d = 0u; d < FAKE_DOMAINS; d++) {
            ok = ok && (sram_pwr_set_mode(&dev, d, mode) == SRAM_OK) &&
                 (g_fake.ack[d] == mode) &&
                 (sram_pwr_get_mode(&dev, d) == (int)mode);
        }
    }
    check(ok, "sb/set_mode_each", "mode not reached or not reported");
    check((sram_pwr_set_mode(&dev, FAKE_DOMAINS, SRAM_PWR_LS) == SRAM_ERR_ARG) &&
          (sram_pwr_set_mode(&dev, 0u, 4u) == SRAM_ERR_ARG) &&
          (sram_pwr_get_mode(&dev, FAKE_DOMAINS) == SRAM_ERR_ARG) &&
          (sram_pwr_set_mode_all(&dev, 7u) == SRAM_ERR_ARG),
          "sb/set_mode_args", "bad domain / mode not rejected");

    /* set_mode_all: every request issued before the first wait */
    fake_reset(5u);
    (void)sram_init(&dev, &g_hooks, FAKE_DOMAINS, 100u);
    ok = (sram_pwr_set_mode_all(&dev, SRAM_PWR_DS) == SRAM_OK) &&
         (g_fake.n_req == FAKE_DOMAINS);
    for (m = 0u; m < FAKE_DOMAINS; m++) {
        ok = ok && (g_fake.ack[m] == SRAM_PWR_DS);
    }
    check(ok, "sb/set_mode_all", "not every domain reached DS");
    check(g_fake.calls <= FAKE_DOMAINS + 5u + 1u + 2u * FAKE_DOMAINS,
          "sb/set_mode_all_parallel", "transitions were waited for one at a time");

    /* timeout: bounded number of polls */
    fake_reset(1u);
    (void)sram_init(&dev, &g_hooks, 1u, 25u);
    g_fake.stuck = 1;
    g_fake.calls = 0u;
    check((sram_pwr_set_mode(&dev, 0u, SRAM_PWR_LS) == SRAM_ERR_TIMEOUT) &&
          (g_fake.calls == 1u + 25u),
          "sb/set_mode_timeout", "no timeout, or wrong poll count");
    g_fake.calls = 0u;
    check((sram_wait_idle(&dev) == SRAM_ERR_TIMEOUT) && (g_fake.calls == 25u),
          "sb/wait_idle_timeout", "no timeout, or wrong poll count");

    /* domain ranges */
    fake_reset(0u);
    (void)sram_init(&dev, &g_hooks, 2u, 10u);
    ok = (sram_pwr_domain_range(&dev, 4096u, 1u, &off, &len) == SRAM_OK) &&
         (off == 2048u) && (len == 2048u) &&
         (sram_pwr_domain_range(&dev, 4096u, 0u, &off, &len) == SRAM_OK) &&
         (off == 0u) && (len == 2048u);
    check(ok, "sb/domain_range", "wrong slice");
    check((sram_pwr_domain_range(&dev, 4096u, 2u, &off, &len) == SRAM_ERR_ARG) &&
          (sram_pwr_domain_range(&dev, 4094u, 0u, &off, &len) == SRAM_ERR_ARG) &&
          (sram_pwr_domain_range(&dev, 4u, 0u, &off, &len) == SRAM_ERR_ARG) &&
          (sram_pwr_domain_range(&dev, 4096u, 0u, 0, &len) == SRAM_ERR_ARG),
          "sb/domain_range_args", "bad range arguments not rejected");

    /* clear */
    fake_reset(4u);
    (void)sram_init(&dev, &g_hooks, 2u, 100u);
    (void)sram_pwr_set_mode(&dev, 1u, SRAM_PWR_LS);
    check((sram_clear(&dev) == SRAM_OK) && (g_fake.n_clr == 1u) && (g_fake.clr_cnt == 0u),
          "sb/clear_run_ls", "clear with RUN/LS domains did not run to the end");
    (void)sram_pwr_set_mode(&dev, 1u, SRAM_PWR_DS);
    check((sram_clear(&dev) == SRAM_ERR_STATE) && (g_fake.n_clr == 1u),
          "sb/clear_refused_ds", "clear must be refused with a domain in DS");
    (void)sram_pwr_set_mode(&dev, 1u, SRAM_PWR_SD);
    check(sram_clear(&dev) == SRAM_ERR_STATE,
          "sb/clear_refused_sd", "clear must be refused with a domain in SD");
    h = g_hooks; h.pulse_clr = 0;
    (void)sram_init(&dev, &h, 1u, 100u);
    check(sram_clear(&dev) == SRAM_ERR_NOHOOK, "sb/clear_nohook", "NULL hook not reported");
    fake_reset(200u);
    (void)sram_init(&dev, &g_hooks, 1u, 50u);
    check(sram_clear(&dev) == SRAM_ERR_TIMEOUT, "sb/clear_timeout",
          "clear longer than the timeout not reported");

    /* BIST */
    fake_reset(6u);
    (void)sram_init(&dev, &g_hooks, 1u, 100u);
    word = 0xFFFFu;
    check((sram_bist_run(&dev, &word) == SRAM_OK) && (g_fake.n_bist == 1u) &&
          (g_fake.bist_cnt == 0u) && (word == 0xFFFFu),
          "sb/bist_pass", "passing BIST not reported as SRAM_OK");
    g_fake.bist_fail = 1;
    g_fake.bist_fail_addr = 123u;
    check((sram_bist_run(&dev, &word) == SRAM_ERR_FAIL) && (word == 123u),
          "sb/bist_fail", "failing BIST or its word not reported");
    check(sram_bist_run(&dev, 0) == SRAM_ERR_FAIL, "sb/bist_fail_null",
          "NULL fail_word not accepted");
    h = g_hooks; h.pulse_bist = 0;
    (void)sram_init(&dev, &h, 1u, 100u);
    check(sram_bist_run(&dev, &word) == SRAM_ERR_NOHOOK, "sb/bist_nohook",
          "NULL hook not reported");

    /* ECC injection */
    fake_reset(0u);
    (void)sram_init(&dev, &g_hooks, 1u, 10u);
    ok = (sram_ecc_inject(&dev, 1u) == SRAM_OK) && (g_fake.inj_bits == 1u) &&
         (sram_ecc_inject(&dev, 2u) == SRAM_OK) && (g_fake.inj_bits == 2u) &&
         (g_fake.n_inj == 2u);
    check(ok, "sb/ecc_inject", "pulse not issued with the right bits");
    check((sram_ecc_inject(&dev, 0u) == SRAM_ERR_ARG) &&
          (sram_ecc_inject(&dev, 3u) == SRAM_ERR_ARG) && (g_fake.n_inj == 2u),
          "sb/ecc_inject_args", "bits 0 / 3 not rejected");
    h = g_hooks; h.pulse_ecc_inj = 0;
    (void)sram_init(&dev, &h, 1u, 10u);
    check(sram_ecc_inject(&dev, 1u) == SRAM_ERR_NOHOOK, "sb/ecc_nohook",
          "NULL hook not reported");

    /* NULL device everywhere */
    check((sram_pwr_set_mode(0, 0u, 0u) == SRAM_ERR_ARG) &&
          (sram_pwr_set_mode_all(0, 0u) == SRAM_ERR_ARG) &&
          (sram_pwr_get_mode(0, 0u) == SRAM_ERR_ARG) &&
          (sram_pwr_domain_range(0, 4u, 0u, &off, &len) == SRAM_ERR_ARG) &&
          (sram_wait_idle(0) == SRAM_ERR_ARG) && (sram_clear(0) == SRAM_ERR_ARG) &&
          (sram_bist_run(0, &word) == SRAM_ERR_ARG) &&
          (sram_ecc_inject(0, 1u) == SRAM_ERR_ARG),
          "sb/null_dev", "NULL device not rejected");
}

int main(void)
{
    test_fault_free();
    test_args();
    test_faults();
    test_all_select();
    test_sideband();

    printf("RESULT: %s %u/%u\n", g_fail ? "FAIL" : "PASS", g_pass, g_pass + g_fail);
    return g_fail ? 1 : 0;
}
