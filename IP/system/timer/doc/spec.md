# timer IP — Specification

## Overview

The `timer` IP block is a programmable 32-bit countdown timer peripheral for FPGA and ASIC
SoC designs. It supports configurable clock pre-scaling, one-shot and free-running modes,
two IRQ output styles (level and pulse), an external trigger output, a force-restart command,
an atomic counter snapshot, and overrun detection.

Four bus-protocol top-levels share identical core logic: APB4, AHB-Lite, AXI4-Lite, and
Wishbone B4. Each is delivered in both SystemVerilog and VHDL-2008 with bit-for-bit identical
behavior.

## Features

- **32-bit down-counter** with parameterizable data width (default 32-bit)
- **8-bit configurable pre-scaler**: divide ratio = PRESCALE + 1; `PRESCALE=0` = divide-by-1
- **One-shot mode**: counts from LOAD to 0 once, then halts; `STATUS.ACTIVE` clears
- **Free-running (repeat) mode**: auto-reloads from LOAD on underflow; runs continuously
- **Interrupt output** (`irq`): active-high; gated by `CTRL.INTR_EN`
  - Level mode (`CTRL.IRQ_MODE=0`): `irq` is asserted while `STATUS.INTR=1`
  - Pulse mode (`CTRL.IRQ_MODE=1`): `irq` pulses one cycle per underflow
- **External trigger output** (`trigger_out`): one-cycle pulse on underflow; gated by `CTRL.TRIG_EN`
- **RESTART command** (`CTRL.RESTART`): self-clearing; force-reloads COUNT from LOAD and resets
  prescaler without toggling `CTRL.EN`
- **Atomic SNAPSHOT** (`CTRL.SNAPSHOT`): self-clearing; latches COUNT into CAPTURE register
  in a single cycle, preventing race conditions on wide counters
- **Overrun detection** (`STATUS.OVF`): set when an underflow occurs while `STATUS.INTR` is
  already pending; cleared by W1C write
- **LOAD=0 protection**: hardware enforces a minimum effective load of 1; LOAD=0 in repeat
  mode would cause continuous underflow — `safe_load_val` guards against this
- **Synchronous reset**: active-low by default; polarity configurable via `RST_POL` generic/parameter
- **Dual-language delivery**: SystemVerilog and VHDL-2008 with identical behavior

## Register Map

Authoritative source: `design/systemrdl/timer.rdl`. Generated HTML: `doc/timer_regs.html`.

Base address: configured at integration time. All registers are 32-bit, word-aligned.

| Offset | Name    | Access | Reset         | Description                                           |
|--------|---------|--------|---------------|-------------------------------------------------------|
| `0x00` | CTRL    | RW     | `0x0000_0000` | Control register                                      |
| `0x04` | STATUS  | RO/W1C | `0x0000_0000` | Status register                                       |
| `0x08` | LOAD    | RW     | `0x0000_0000` | Reload / initial count value                          |
| `0x0C` | COUNT   | RO     | `0x0000_0000` | Current counter value (hardware-updated; writes ignored) |
| `0x10` | CAPTURE | RO     | `0x0000_0000` | Race-free counter snapshot (updated on CTRL.SNAPSHOT) |

### CTRL (0x00)

| Bits  | Field       | Access | Reset  | Description                                                              |
|-------|-------------|--------|--------|--------------------------------------------------------------------------|
| 31:15 | reserved    | —      | 0      | Read-as-zero; writes ignored                                             |
| 14    | `SNAPSHOT`  | SC     | 0      | Write 1 to atomically latch COUNT into CAPTURE; self-clears next cycle   |
| 13    | `IRQ_MODE`  | RW     | 0      | `0` = level (irq asserted while STATUS.INTR=1); `1` = pulse (one cycle per underflow) |
| 12    | `RESTART`   | SC     | 0      | Write 1 to force-reload COUNT from LOAD; self-clears next cycle          |
| 11:4  | `PRESCALE`  | RW     | `0x00` | Clock divide = PRESCALE+1. `0` = divide-by-1                            |
| 3     | `TRIG_EN`   | RW     | 0      | Enable trigger_out pulse on underflow                                    |
| 2     | `INTR_EN`   | RW     | 0      | Gate irq output (level or pulse) to interrupt controller                 |
| 1     | `MODE`      | RW     | 0      | `0` = repeat/free-run; `1` = one-shot                                   |
| 0     | `EN`        | RW     | 0      | Timer enable: `1` = counting; `0` = halted                              |

SC = self-clearing: reads back 0; write 1 to issue the command.

### STATUS (0x04)

| Bits | Field    | Access | Reset | Description                                                           |
|------|----------|--------|-------|-----------------------------------------------------------------------|
| 31:3 | reserved | —      | 0     | Read-as-zero                                                          |
| 2    | `OVF`    | W1C    | 0     | Overrun: set when underflow occurs while STATUS.INTR is already pending |
| 1    | `ACTIVE` | RO     | 0     | Timer is running (cleared in one-shot mode after first underflow)     |
| 0    | `INTR`   | W1C    | 0     | Interrupt pending: set on underflow; clear by writing 1               |

### LOAD (0x08)

32-bit reload value. Loaded into COUNT on `EN` rising edge, RESTART, or every underflow
in repeat mode. Hardware enforces a minimum effective count of 1 — LOAD=0 is treated as 1.

### COUNT (0x0C)

Current 32-bit counter value, updated by hardware every prescaled clock. Writes are ignored.

### CAPTURE (0x10)

Race-free snapshot of COUNT. Latched by hardware on the cycle `CTRL.SNAPSHOT` is written.
Holds its value until the next snapshot. Writes are ignored.

## Interfaces

### Bus protocol top-levels

| Module         | Protocol    | Clock/Reset                         |
|----------------|-------------|-------------------------------------|
| `timer_apb`    | APB4        | `PCLK` / `PRESETn` (active-low)     |
| `timer_ahb`    | AHB-Lite    | `HCLK` / `HRESETn` (active-low)     |
| `timer_axi4l`  | AXI4-Lite   | `ACLK` / `ARESETn` (active-low)     |
| `timer_wb`     | Wishbone B4 | `CLK_I` / `RST_I` (active-high)     |

All variants use 12-bit byte-address inputs and 32-bit data.

### Common IP outputs

| Signal        | Direction | Description                                               |
|---------------|-----------|-----------------------------------------------------------|
| `irq`         | output    | Interrupt: level (STATUS.INTR & INTR_EN) or pulse mode   |
| `trigger_out` | output    | One-cycle pulse on underflow when TRIG_EN=1               |

## Timing

- **Zero wait-state bus interfaces**: all bus bridges assert HREADY/PREADY/RVALID/ACK_O in the
  minimum number of cycles permitted by each protocol.
- **Count update latency**: COUNT decrements one cycle after each prescaled tick. Prescaler
  tick period = (PRESCALE+1) × CLK period.
- **Interrupt latency**: `STATUS.INTR` is set and `irq` is asserted in the same cycle as the
  underflow (combinational for level mode; registered for pulse mode).
- **RESTART latency**: COUNT is reloaded and prescaler is reset the cycle after CTRL.RESTART
  is written.
- **SNAPSHOT latency**: CAPTURE is updated the cycle CTRL.SNAPSHOT is written.
- **Maximum frequency**: synthesis-dependent. Zynq-7010 result: 100 MHz with WNS +6.16 ns
  (see `synthesis/vivado/timing_summary.rpt`).

## Known Limitations

- LOAD=0 is silently clamped to 1. Software should avoid writing 0 to LOAD in repeat mode
  if a zero-length count period is intended for another purpose.
- Wishbone B4 uses synchronous active-high reset (`RST_I`), while APB/AHB/AXI4-Lite use
  asynchronous active-low reset. This is a protocol requirement, not a design limitation.
- The CAPTURE register does not record the timestamp of the snapshot; it only holds the
  counter value at the time CTRL.SNAPSHOT was written.
- Formal verification uses BMC depth 20. Properties involving timer periods longer than 20
  cycles (large LOAD or PRESCALE values) are not exhaustively verified.
