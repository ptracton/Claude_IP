/**
 * @file sram_test_mem.h
 * @brief Host unit tests: fault-injecting memory model behind SRAM_RD / SRAM_WR.
 *
 * Built only with -DSRAM_FW_HOST_TEST (firmware/test/, host gcc). The model is
 * a word array; addresses outside it, or misaligned, set an error flag that
 * the test program checks (a test-harness bug, not a memory fault).
 */

#ifndef SRAM_TEST_MEM_H
#define SRAM_TEST_MEM_H

#include <stdint.h>

#define TM_MAX_WORDS  8192u

/** Fault kinds (one active at a time). */
typedef enum {
    TM_NONE = 0,
    TM_STUCK,        /* word w, bit b reads as value v                           */
    TM_TRANSITION,   /* word w, bit b cannot rise 0 -> 1 on a write               */
    TM_ADDR_STUCK,   /* word-index bit b stuck at value v                         */
    TM_ADDR_SHORT,   /* word-index bits b and b2 wired-AND                        */
    TM_COUPLING,     /* a write of bit b in word w sets bit b2 of word w2: on a
                        rising edge (v = 0) or a falling edge (v = 1)            */
    TM_NPSF,         /* pattern sensitive: bit b of word w reads 1 while bits b2
                        and b3 of the same word are 1                            */
    TM_ADDR_MULTI,   /* decoder multiple access: a write to word w also writes w2 */
    TM_BRIDGE,       /* bits b and b2 of word w wired-AND on write                */
    TM_LANE_FULL,    /* narrow write writes the whole word, other lanes 0         */
    TM_LANE_SWAP,    /* byte write to lane k lands in lane k ^ 1                  */
    TM_HALF_LOW      /* halfword write to lanes 3:2 lands in lanes 1:0            */
    /* lane faults (LANE_FULL, LANE_SWAP, HALF_LOW): every word, or only word w
     * when v = 1 */
} tm_kind_t;

typedef struct {
    tm_kind_t kind;
    uint32_t  w, b, v, w2, b2, b3;
} tm_fault_t;

/** Reset the model: size bytes (multiple of 4, <= 4 * TM_MAX_WORDS), contents
 *  set to fill, no fault, error flag clear. Returns the base address. */
uintptr_t tm_reset(uint32_t size, uint32_t fill);

/** Activate one fault (kind TM_NONE removes it). */
void tm_set_fault(const tm_fault_t *f);

/** Non-zero if an access was out of range or misaligned since tm_reset(). */
int tm_bad_access(void);

/** Number of accesses since tm_reset(). */
uint32_t tm_accesses(void);

/* Access functions used by sram_access.h (n = 1, 2 or 4 bytes). */
uint32_t sram_test_rd(uintptr_t addr, uint32_t n);
void     sram_test_wr(uintptr_t addr, uint32_t n, uint32_t v);

#endif /* SRAM_TEST_MEM_H */
