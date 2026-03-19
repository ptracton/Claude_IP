/**
 * @file platform.h
 * @brief Platform-specific MMIO abstraction layer.
 *
 * This is the canonical MMIO stub shared by all IP device drivers in this
 * repository.  It defines the two macros — MMIO_WRITE32 and MMIO_READ32 —
 * that every driver uses to access memory-mapped registers.
 *
 * Porting guide
 * -------------
 * Replace the volatile-pointer implementation below with whatever mechanism
 * the target platform requires (e.g., HAL calls, cache-coherent wrappers,
 * bus-fault-safe accessors).  Only this file needs to change; no driver
 * source files need modification.
 *
 * This file is intentionally free of OS and RTOS dependencies.
 */

#ifndef PLATFORM_H
#define PLATFORM_H

#include <stdint.h>

/**
 * @brief Write a 32-bit value to a memory-mapped register.
 *
 * @param addr  Absolute byte address of the register (integer or pointer type).
 * @param val   32-bit value to write.
 */
#define MMIO_WRITE32(addr, val) \
    (*(volatile uint32_t *)(uintptr_t)(addr) = (uint32_t)(val))

/**
 * @brief Read a 32-bit value from a memory-mapped register.
 *
 * @param addr  Absolute byte address of the register (integer or pointer type).
 * @return      The 32-bit register value.
 */
#define MMIO_READ32(addr) \
    (*(volatile uint32_t *)(uintptr_t)(addr))

#endif /* PLATFORM_H */
