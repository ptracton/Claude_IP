/**
 * @file timer_example.c
 * @brief Usage examples for the timer IP device driver.
 *
 * Demonstrates three usage patterns:
 *
 *   1. One-shot timer with interrupt-based completion detection
 *      — Configure the timer for a single countdown, enable the interrupt,
 *        start the timer, then spin until the ISR clears the pending flag.
 *        (In a real system the ISR sets a volatile flag; the main loop polls
 *        that flag instead of polling the hardware register directly.)
 *
 *   2. Repeating (free-run) timer with polling
 *      — Configure the timer to reload automatically after each terminal
 *        count, then poll STATUS.INTR to measure elapsed periods.
 *
 *   3. Trigger output usage
 *      — Enable the hardware trigger output so that a GPIO or DMA request
 *        fires at each terminal count without CPU involvement, while the
 *        CPU continues other work.
 *
 * Build
 * -----
 *   gcc -std=c99 -Wall -Wextra \
 *       -I../include \
 *       -I<IP_COMMON_PATH>/firmware/include \
 *       timer_example.c ../src/timer.c -o timer_example
 *
 * Note: This file is designed to compile cleanly against the driver library.
 * The hardware register accesses are performed through the MMIO macros in
 * platform.h; on a host PC those macros dereference the simulated address
 * 0x40001000, which will fault if executed.  The file is therefore compiled
 * with -fsyntax-only for the quality-gate check.
 */

#include <stdint.h>
#include "timer.h"

/* ---------------------------------------------------------------------------
 * Hardware base address for this example.
 * Replace with the actual peripheral address from your memory map.
 * ---------------------------------------------------------------------------*/
#define TIMER0_BASE  ((uintptr_t)0x40001000UL)

/* ---------------------------------------------------------------------------
 * Example 1 — One-shot timer with interrupt-based completion detection
 *
 * In real firmware an interrupt service routine sets `timer0_expired`.
 * Here we simulate ISR behaviour by polling the hardware interrupt flag
 * directly, then clearing it — identical to what the ISR would do.
 * ---------------------------------------------------------------------------*/
static volatile int timer0_expired = 0;

/**
 * @brief Simulated ISR for TIMER0.
 *
 * In production firmware this function is registered as the IRQ handler
 * for the timer interrupt line.  It clears the hardware W1C bit and sets
 * the application-level flag.
 */
static void timer0_isr(void)
{
    if (timer_irq_pending(TIMER0_BASE)) {
        timer_irq_clear(TIMER0_BASE);   /* W1C: clear STATUS.INTR        */
        timer0_expired = 1;             /* signal application layer       */
    }
}

/**
 * @brief Demonstrate one-shot countdown with interrupt notification.
 *
 * Uses TIMER_CTRL_MODE_ONESHOT so the counter stops after one expiry.
 * Prescale = 99 → effective clock = f_clk / 100.
 * Load value = 9999 → timeout = 10 000 × (100 / f_clk).
 */
static void example_oneshot_irq(void)
{
    /* Reset and configure: one-shot, prescale=99, load=9999 */
    timer_init(TIMER0_BASE, 9999U, 99U, TIMER_CTRL_MODE_ONESHOT);

    /* Enable interrupt before starting so no edge is missed. */
    timer_irq_enable(TIMER0_BASE);

    timer0_expired = 0;

    /* Start the countdown. */
    timer_enable(TIMER0_BASE);

    /*
     * Spin until the ISR signals completion.
     * In a real RTOS application this would be a semaphore pend or
     * task notification wait; here we poll to keep the example dependency-free.
     */
    while (!timer0_expired) {
        /*
         * Poll hardware directly — stand-in for "wait for interrupt".
         * Call the simulated ISR so the example terminates cleanly.
         */
        timer0_isr();
    }

    /* Timer is now stopped (one-shot). Interrupt is already cleared. */
    timer_irq_disable(TIMER0_BASE);
}

/* ---------------------------------------------------------------------------
 * Example 2 — Repeating timer with polling
 *
 * The timer is configured in free-run (repeat) mode.  The application polls
 * STATUS.INTR to detect each period boundary, then clears the flag and
 * increments a tick counter.
 * ---------------------------------------------------------------------------*/

/**
 * @brief Demonstrate a free-running tick timer polled from the main loop.
 *
 * Prescale = 0 → no division.  Load = 0xFFFFUL → 65 536-cycle period.
 * Interrupt output is not used; the status bit is polled instead.
 */
static void example_repeating_poll(void)
{
    uint32_t tick_count = 0U;

    /* Configure: free-run, no prescaler, 16-bit period */
    timer_init(TIMER0_BASE, 0xFFFFUL, 0U, TIMER_CTRL_MODE_REPEAT);

    timer_enable(TIMER0_BASE);

    /*
     * Count 5 complete periods then stop.
     * In real firmware this loop body sits inside the main superloop.
     */
    while (tick_count < 5U) {
        if (timer_irq_pending(TIMER0_BASE)) {
            timer_irq_clear(TIMER0_BASE);  /* acknowledge and re-arm      */
            tick_count++;
        }
    }

    timer_disable(TIMER0_BASE);
}

/* ---------------------------------------------------------------------------
 * Example 3 — Trigger output usage
 *
 * The trigger output is asserted by the hardware at each terminal count
 * without CPU involvement.  This example enables the trigger, runs the
 * timer for several periods, then disables both the trigger and the timer.
 * The CPU is free to perform other work while the trigger fires.
 * ---------------------------------------------------------------------------*/

/**
 * @brief Demonstrate hardware trigger output in free-run mode.
 *
 * Each terminal count produces a one-cycle pulse on the trigger output.
 * A downstream DMA controller or GPIO toggle block can use this signal
 * without any CPU interaction.
 *
 * Prescale = 7 → f_eff = f_clk / 8.  Load = 0xFFFFFFFFUL → maximum period.
 */
static void example_trigger_output(void)
{
    uint32_t periods_observed = 0U;

    /* Configure: free-run, prescale=7, maximum countdown */
    timer_init(TIMER0_BASE, 0xFFFFFFFFUL, 7U, TIMER_CTRL_MODE_REPEAT);

    /* Enable trigger output — hardware fires a pulse at each reload. */
    timer_trigger_enable(TIMER0_BASE);

    timer_enable(TIMER0_BASE);

    /*
     * CPU performs useful work here while the trigger output fires
     * autonomously.  We observe 3 periods via STATUS.INTR polling, then exit.
     *
     * In production, INTR_EN would remain zero; the trigger output is
     * the only notification mechanism used.  We enable INTR here only
     * so the loop has a software-visible period boundary.
     */
    timer_irq_enable(TIMER0_BASE);

    while (periods_observed < 3U) {
        if (timer_irq_pending(TIMER0_BASE)) {
            timer_irq_clear(TIMER0_BASE);
            periods_observed++;
        }
        /* ... other work ... */
    }

    timer_irq_disable(TIMER0_BASE);
    timer_trigger_disable(TIMER0_BASE);
    timer_disable(TIMER0_BASE);
}

/* ---------------------------------------------------------------------------
 * Entry point — call all three examples in sequence.
 * ---------------------------------------------------------------------------*/

/**
 * @brief Main entry point for the timer driver usage examples.
 *
 * @return 0 on success (unreachable on real hardware — bare-metal infinite loop
 *         is expected at the application level above this function).
 */
int main(void)
{
    example_oneshot_irq();
    example_repeating_poll();
    example_trigger_output();

    return 0;
}
