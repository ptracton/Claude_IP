/**
 * @file timer.h
 * @brief Public API for the timer IP device driver (C99, bare-metal).
 *
 * This header declares every public function exposed by the timer driver.
 * Driver internals are not exposed here; they live exclusively in
 * firmware/src/timer.c.
 *
 * Usage
 * -----
 * 1. Define TIMER_BASE_ADDR to the peripheral's base address before including
 *    this header, OR pass the base address as the first argument to every
 *    driver function (preferred for multi-instance use).
 * 2. Call timer_init() once to configure the peripheral.
 * 3. Use the higher-level helpers to start, stop, and poll the timer.
 *
 * Dependencies
 * ------------
 * - timer_regs.h  : register offsets and bit-field macros (auto-generated).
 * - platform.h    : MMIO_READ32 / MMIO_WRITE32 macros (replace for your MCU).
 *
 * No OS, RTOS, or dynamic-allocation dependencies.
 */

#ifndef TIMER_H
#define TIMER_H

#include <stdint.h>
#include "timer_regs.h"

#ifdef __cplusplus
extern "C" {
#endif

/* =========================================================================
 * Raw register access
 * ========================================================================= */

/**
 * @brief Write a 32-bit value to a timer register.
 *
 * @param base    Peripheral base address.
 * @param offset  Register byte offset (use TIMER_*_OFFSET macros).
 * @param value   Value to write.
 */
void timer_write_reg(uintptr_t base, uint32_t offset, uint32_t value);

/**
 * @brief Read a 32-bit value from a timer register.
 *
 * @param base    Peripheral base address.
 * @param offset  Register byte offset (use TIMER_*_OFFSET macros).
 * @return        Register value.
 */
uint32_t timer_read_reg(uintptr_t base, uint32_t offset);

/* =========================================================================
 * Initialisation
 * ========================================================================= */

/**
 * @brief Initialise the timer peripheral.
 *
 * Brings the timer to a known reset state, then programs the load value,
 * prescaler, and operating mode.  The timer is left disabled; call
 * timer_enable() to start counting.
 *
 * @param base      Peripheral base address.
 * @param load_val  Countdown reload value written to TIMER_LOAD.
 * @param prescale  8-bit prescale value (bits 11:4 of CTRL); effective clock
 *                  divisor = prescale + 1.  Range 0–255.
 * @param mode      Operating mode: TIMER_CTRL_MODE_REPEAT (0) for free-run,
 *                  TIMER_CTRL_MODE_ONESHOT (1) for one-shot.
 */
void timer_init(uintptr_t base, uint32_t load_val,
                uint8_t prescale, uint8_t mode);

/* =========================================================================
 * Enable / Disable
 * ========================================================================= */

/**
 * @brief Enable (start) the timer.
 *
 * Sets the EN bit in CTRL.  The timer begins counting from the current
 * LOAD value immediately.
 *
 * @param base  Peripheral base address.
 */
void timer_enable(uintptr_t base);

/**
 * @brief Disable (stop) the timer.
 *
 * Clears the EN bit in CTRL.  The counter freezes at its current value.
 *
 * @param base  Peripheral base address.
 */
void timer_disable(uintptr_t base);

/* =========================================================================
 * Load / Count
 * ========================================================================= */

/**
 * @brief Write a new countdown reload value to TIMER_LOAD.
 *
 * The new value takes effect on the next enable or reload event.
 *
 * @param base  Peripheral base address.
 * @param val   32-bit reload value.
 */
void timer_set_load(uintptr_t base, uint32_t val);

/**
 * @brief Read the current counter value from TIMER_COUNT (read-only).
 *
 * @param base  Peripheral base address.
 * @return      Current 32-bit counter value.
 */
uint32_t timer_get_count(uintptr_t base);

/* =========================================================================
 * Interrupt control
 * ========================================================================= */

/**
 * @brief Enable the timer interrupt output (sets CTRL.INTR_EN).
 *
 * @param base  Peripheral base address.
 */
void timer_irq_enable(uintptr_t base);

/**
 * @brief Disable the timer interrupt output (clears CTRL.INTR_EN).
 *
 * @param base  Peripheral base address.
 */
void timer_irq_disable(uintptr_t base);

/**
 * @brief Test whether an interrupt is pending (STATUS.INTR, bit 0).
 *
 * @param base  Peripheral base address.
 * @return      Non-zero if an interrupt is pending, zero otherwise.
 */
int timer_irq_pending(uintptr_t base);

/**
 * @brief Clear a pending interrupt (writes 1 to STATUS.INTR — W1C).
 *
 * @param base  Peripheral base address.
 */
void timer_irq_clear(uintptr_t base);

/* =========================================================================
 * Trigger output control
 * ========================================================================= */

/**
 * @brief Enable the trigger output pulse (sets CTRL.TRIG_EN).
 *
 * When enabled, the peripheral drives a one-cycle pulse on its trigger
 * output at every terminal count without CPU involvement.
 *
 * @param base  Peripheral base address.
 */
void timer_trigger_enable(uintptr_t base);

/**
 * @brief Disable the trigger output pulse (clears CTRL.TRIG_EN).
 *
 * @param base  Peripheral base address.
 */
void timer_trigger_disable(uintptr_t base);

/* =========================================================================
 * Status queries
 * ========================================================================= */

/**
 * @brief Test whether the timer is currently running (STATUS.ACTIVE, bit 1).
 *
 * STATUS.ACTIVE is a read-only hardware bit that reflects whether the
 * counter is actively decrementing.
 *
 * @param base  Peripheral base address.
 * @return      Non-zero if the timer is active, zero if it is stopped.
 */
int timer_is_active(uintptr_t base);

/**
 * @brief Test whether the overrun flag is set (STATUS.OVF, bit 2).
 *
 * STATUS.OVF is set by hardware when an underflow occurs while STATUS.INTR
 * is already pending (timer fired again before the interrupt was cleared).
 *
 * @param base  Peripheral base address.
 * @return      Non-zero if an overrun has occurred, zero otherwise.
 */
int timer_ovf_pending(uintptr_t base);

/**
 * @brief Clear the overrun flag (writes 1 to STATUS.OVF — W1C).
 *
 * @param base  Peripheral base address.
 */
void timer_ovf_clear(uintptr_t base);

/* =========================================================================
 * Force-reload (RESTART)
 * ========================================================================= */

/**
 * @brief Force-reload the counter from LOAD without toggling EN (CTRL.RESTART).
 *
 * Writes the self-clearing RESTART command bit.  The counter instantly reloads
 * from LOAD and the prescaler resets.  The timer continues running; EN is not
 * affected.  Has no effect if the timer is not running.
 *
 * @param base  Peripheral base address.
 */
void timer_restart(uintptr_t base);

/* =========================================================================
 * IRQ output mode
 * ========================================================================= */

/**
 * @brief Set the IRQ output mode (CTRL.IRQ_MODE).
 *
 * @param base  Peripheral base address.
 * @param mode  TIMER_CTRL_IRQ_MODE_LEVEL (0) for level-sensitive output
 *              (irq asserted while STATUS.INTR is set), or
 *              TIMER_CTRL_IRQ_MODE_PULSE (1) for a one-cycle pulse per
 *              underflow event.
 */
void timer_set_irq_mode(uintptr_t base, uint8_t mode);

/* =========================================================================
 * Capture (race-free COUNT snapshot)
 * ========================================================================= */

/**
 * @brief Latch the current counter value into the CAPTURE register.
 *
 * Writes the self-clearing SNAPSHOT command bit in CTRL.  The hardware
 * atomically latches hw_count_val into the CAPTURE register on the same
 * clock cycle.  Read the captured value with timer_get_capture().
 *
 * @param base  Peripheral base address.
 */
void timer_snapshot(uintptr_t base);

/**
 * @brief Read the most recent captured counter value from TIMER_CAPTURE.
 *
 * The CAPTURE register holds the value latched by the last timer_snapshot()
 * call (or CTRL.SNAPSHOT write).  It is read-only and does not change until
 * another snapshot is triggered.
 *
 * @param base  Peripheral base address.
 * @return      Captured 32-bit counter value.
 */
uint32_t timer_get_capture(uintptr_t base);

#ifdef __cplusplus
}
#endif

#endif /* TIMER_H */
