/**
 * @file timer.c
 * @brief Timer IP device driver — C99 bare-metal implementation.
 *
 * All register accesses go through the MMIO_READ32 / MMIO_WRITE32 macros
 * defined in platform.h.  No OS, RTOS, or dynamic-allocation dependencies.
 * No magic numbers: every bit position and mask comes from timer_regs.h.
 */

#include "timer.h"
#include "platform.h"

/* =========================================================================
 * Internal helper — compute absolute register address
 * ========================================================================= */

/**
 * @brief Compute the absolute address of a register given base + offset.
 *
 * The cast chain (uintptr_t)(base) + (uintptr_t)(offset) keeps the
 * arithmetic in the integer domain before the final volatile-pointer cast
 * inside MMIO_READ32 / MMIO_WRITE32.
 */
#define TIMER_REG_ADDR(base, offset) ((uintptr_t)(base) + (uintptr_t)(offset))

/* =========================================================================
 * Raw register access
 * ========================================================================= */

/**
 * @brief Write a 32-bit value to a timer register.
 */
void timer_write_reg(uintptr_t base, uint32_t offset, uint32_t value)
{
    MMIO_WRITE32(TIMER_REG_ADDR(base, offset), value);
}

/**
 * @brief Read a 32-bit value from a timer register.
 */
uint32_t timer_read_reg(uintptr_t base, uint32_t offset)
{
    return MMIO_READ32(TIMER_REG_ADDR(base, offset));
}

/* =========================================================================
 * Initialisation
 * ========================================================================= */

/**
 * @brief Initialise the timer peripheral to a known state.
 *
 * Sequence:
 *  1. Disable the timer (clear EN) and write reset defaults to CTRL.
 *  2. Write the load value.
 *  3. Program prescaler and mode into CTRL (timer still disabled).
 *  4. Clear any stale interrupt in STATUS.
 */
void timer_init(uintptr_t base, uint32_t load_val,
                uint8_t prescale, uint8_t mode)
{
    uint32_t ctrl;

    /* Step 1: disable and reset the control register. */
    MMIO_WRITE32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET),
                 TIMER_CTRL_RESET);

    /* Step 2: program the reload value. */
    MMIO_WRITE32(TIMER_REG_ADDR(base, TIMER_LOAD_OFFSET), load_val);

    /* Step 3: build CTRL with prescaler and mode; EN stays 0. */
    ctrl = TIMER_CTRL_RESET;
    ctrl = TIMER_CTRL_PRESCALE_SET(ctrl, (uint32_t)prescale);
    ctrl = TIMER_CTRL_MODE_SET(ctrl, (uint32_t)mode);
    MMIO_WRITE32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET), ctrl);

    /* Step 4: clear any stale interrupt (W1C). */
    MMIO_WRITE32(TIMER_REG_ADDR(base, TIMER_STATUS_OFFSET),
                 TIMER_STATUS_INTR_CLR);
}

/* =========================================================================
 * Enable / Disable
 * ========================================================================= */

/**
 * @brief Enable (start) the timer by setting CTRL.EN.
 */
void timer_enable(uintptr_t base)
{
    uint32_t ctrl = MMIO_READ32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET));
    ctrl = TIMER_CTRL_EN_SET(ctrl, 1U);
    MMIO_WRITE32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET), ctrl);
}

/**
 * @brief Disable (stop) the timer by clearing CTRL.EN.
 */
void timer_disable(uintptr_t base)
{
    uint32_t ctrl = MMIO_READ32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET));
    ctrl = TIMER_CTRL_EN_SET(ctrl, 0U);
    MMIO_WRITE32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET), ctrl);
}

/* =========================================================================
 * Load / Count
 * ========================================================================= */

/**
 * @brief Write a new countdown reload value to TIMER_LOAD.
 */
void timer_set_load(uintptr_t base, uint32_t val)
{
    MMIO_WRITE32(TIMER_REG_ADDR(base, TIMER_LOAD_OFFSET), val);
}

/**
 * @brief Read the current counter value from TIMER_COUNT (read-only register).
 */
uint32_t timer_get_count(uintptr_t base)
{
    return MMIO_READ32(TIMER_REG_ADDR(base, TIMER_COUNT_OFFSET));
}

/* =========================================================================
 * Interrupt control
 * ========================================================================= */

/**
 * @brief Enable the timer interrupt by setting CTRL.INTR_EN.
 */
void timer_irq_enable(uintptr_t base)
{
    uint32_t ctrl = MMIO_READ32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET));
    ctrl = TIMER_CTRL_INTR_EN_SET(ctrl, 1U);
    MMIO_WRITE32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET), ctrl);
}

/**
 * @brief Disable the timer interrupt by clearing CTRL.INTR_EN.
 */
void timer_irq_disable(uintptr_t base)
{
    uint32_t ctrl = MMIO_READ32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET));
    ctrl = TIMER_CTRL_INTR_EN_SET(ctrl, 0U);
    MMIO_WRITE32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET), ctrl);
}

/**
 * @brief Return non-zero if STATUS.INTR (bit 0) is set.
 */
int timer_irq_pending(uintptr_t base)
{
    uint32_t status = MMIO_READ32(TIMER_REG_ADDR(base, TIMER_STATUS_OFFSET));
    return (int)TIMER_STATUS_INTR_GET(status);
}

/**
 * @brief Clear a pending interrupt by writing 1 to STATUS.INTR (W1C).
 */
void timer_irq_clear(uintptr_t base)
{
    MMIO_WRITE32(TIMER_REG_ADDR(base, TIMER_STATUS_OFFSET),
                 TIMER_STATUS_INTR_CLR);
}

/* =========================================================================
 * Trigger output control
 * ========================================================================= */

/**
 * @brief Enable the trigger output by setting CTRL.TRIG_EN.
 */
void timer_trigger_enable(uintptr_t base)
{
    uint32_t ctrl = MMIO_READ32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET));
    ctrl = TIMER_CTRL_TRIG_EN_SET(ctrl, 1U);
    MMIO_WRITE32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET), ctrl);
}

/**
 * @brief Disable the trigger output by clearing CTRL.TRIG_EN.
 */
void timer_trigger_disable(uintptr_t base)
{
    uint32_t ctrl = MMIO_READ32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET));
    ctrl = TIMER_CTRL_TRIG_EN_SET(ctrl, 0U);
    MMIO_WRITE32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET), ctrl);
}

/* =========================================================================
 * Status queries
 * ========================================================================= */

/**
 * @brief Return non-zero if the timer is actively counting (STATUS.ACTIVE).
 */
int timer_is_active(uintptr_t base)
{
    uint32_t status = MMIO_READ32(TIMER_REG_ADDR(base, TIMER_STATUS_OFFSET));
    return (int)TIMER_STATUS_ACTIVE_GET(status);
}

/**
 * @brief Return non-zero if STATUS.OVF is set (overrun — timer fired again
 *        before the previous interrupt was cleared by software).
 */
int timer_ovf_pending(uintptr_t base)
{
    uint32_t status = MMIO_READ32(TIMER_REG_ADDR(base, TIMER_STATUS_OFFSET));
    return (int)TIMER_STATUS_OVF_GET(status);
}

/**
 * @brief Clear the overrun flag by writing 1 to STATUS.OVF (W1C).
 */
void timer_ovf_clear(uintptr_t base)
{
    MMIO_WRITE32(TIMER_REG_ADDR(base, TIMER_STATUS_OFFSET),
                 TIMER_STATUS_OVF_CLR);
}

/* =========================================================================
 * Force-reload (RESTART)
 * ========================================================================= */

/**
 * @brief Force-reload the counter from LOAD without toggling EN.
 *
 * Writes the self-clearing RESTART bit in CTRL.  Hardware reloads COUNT from
 * LOAD and resets the prescaler on the next clock edge.
 */
void timer_restart(uintptr_t base)
{
    uint32_t ctrl = MMIO_READ32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET));
    MMIO_WRITE32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET),
                 ctrl | TIMER_CTRL_RESTART);
}

/* =========================================================================
 * IRQ output mode
 * ========================================================================= */

/**
 * @brief Set the IRQ output mode (CTRL.IRQ_MODE).
 */
void timer_set_irq_mode(uintptr_t base, uint8_t mode)
{
    uint32_t ctrl = MMIO_READ32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET));
    ctrl = TIMER_CTRL_IRQ_MODE_SET(ctrl, (uint32_t)mode);
    MMIO_WRITE32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET), ctrl);
}

/* =========================================================================
 * Capture (race-free COUNT snapshot)
 * ========================================================================= */

/**
 * @brief Latch the current counter value into the CAPTURE register.
 *
 * Writes the self-clearing SNAPSHOT command bit in CTRL.
 */
void timer_snapshot(uintptr_t base)
{
    uint32_t ctrl = MMIO_READ32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET));
    MMIO_WRITE32(TIMER_REG_ADDR(base, TIMER_CTRL_OFFSET),
                 ctrl | TIMER_CTRL_SNAPSHOT);
}

/**
 * @brief Read the most recent captured counter value from TIMER_CAPTURE.
 */
uint32_t timer_get_capture(uintptr_t base)
{
    return MMIO_READ32(TIMER_REG_ADDR(base, TIMER_CAPTURE_OFFSET));
}
