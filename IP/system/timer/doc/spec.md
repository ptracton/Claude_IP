# timer IP — Specification

## Overview

The `timer` IP block is a programmable timer peripheral providing configurable pre-scaling,
one-shot and free-running operating modes, a single interrupt output, and an external trigger
output for synchronizing other SoC peripherals.

[TBD — expand with target clock frequencies, supported bus protocols, and integration context]

## Features

- Programmable pre-scaler (divider ratio configurable via register field)
- 32-bit (parameterizable) down-counter with configurable load value
- One-shot mode: counts to zero once, then halts; interrupt asserted at terminal count
- Normal (free-running) mode: automatically reloads and restarts; periodic interrupt source
- Single interrupt output (active-high, level or pulse; polarity configurable)
- External trigger output pulse at each terminal count
- Software-readable current count value
- Synchronous active-low reset; reset polarity is a top-level parameter
- Dual-language delivery: SystemVerilog and VHDL-2008 with bit-for-bit identical behavior

## Register Map

[TBD — populated by Step 2 (rdl). See `design/systemrdl/timer.rdl` for the authoritative
source and `doc/timer_regs.html` for the generated HTML reference.]

## Interfaces

[TBD — populated by Step 3 (rtl). Will include bus-protocol adapter ports (APB/AHB/AXI4-Lite/
Wishbone), clock and reset signals, interrupt output, and external trigger output.]

## Timing

[TBD — populated by Step 3 (rtl). Will include maximum operating frequency, pre-scaler
latency, interrupt assertion-to-acknowledge timing, and trigger pulse width.]

## Known Limitations

[TBD — to be updated as design and verification progress through Steps 2–10.]
