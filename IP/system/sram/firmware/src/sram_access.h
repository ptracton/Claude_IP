/**
 * @file sram_access.h
 * @brief Memory access macros used by the sram memory tests.
 *
 * The tests access the memory itself, in 8-, 16- and 32-bit units, so they
 * need more than the 32-bit MMIO_READ32 / MMIO_WRITE32 of the common
 * platform.h. Each macro may be pre-defined (compiler -D or a header included
 * first) to port the tests, e.g. to bus-fault-safe accessors.
 *
 * SRAM_FW_HOST_TEST: the host unit tests (firmware/test/) route every access
 * through a fault-injecting memory model instead.
 */

#ifndef SRAM_ACCESS_H
#define SRAM_ACCESS_H

#include <stdint.h>

#ifdef SRAM_FW_HOST_TEST
#include "sram_test_mem.h"
#define SRAM_RD32(a)     sram_test_rd((uintptr_t)(a), 4u)
#define SRAM_RD16(a)     ((uint16_t)sram_test_rd((uintptr_t)(a), 2u))
#define SRAM_RD8(a)      ((uint8_t)sram_test_rd((uintptr_t)(a), 1u))
#define SRAM_WR32(a, v)  sram_test_wr((uintptr_t)(a), 4u, (uint32_t)(v))
#define SRAM_WR16(a, v)  sram_test_wr((uintptr_t)(a), 2u, (uint32_t)(v))
#define SRAM_WR8(a, v)   sram_test_wr((uintptr_t)(a), 1u, (uint32_t)(v))
#endif

#ifndef SRAM_RD32
#define SRAM_RD32(a)     (*(volatile uint32_t *)(uintptr_t)(a))
#endif
#ifndef SRAM_RD16
#define SRAM_RD16(a)     (*(volatile uint16_t *)(uintptr_t)(a))
#endif
#ifndef SRAM_RD8
#define SRAM_RD8(a)      (*(volatile uint8_t *)(uintptr_t)(a))
#endif
#ifndef SRAM_WR32
#define SRAM_WR32(a, v)  (*(volatile uint32_t *)(uintptr_t)(a) = (uint32_t)(v))
#endif
#ifndef SRAM_WR16
#define SRAM_WR16(a, v)  (*(volatile uint16_t *)(uintptr_t)(a) = (uint16_t)(v))
#endif
#ifndef SRAM_WR8
#define SRAM_WR8(a, v)   (*(volatile uint8_t *)(uintptr_t)(a) = (uint8_t)(v))
#endif

#endif /* SRAM_ACCESS_H */
