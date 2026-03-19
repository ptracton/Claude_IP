# timer

## Overview

The `timer` IP block is a programmable countdown/countup timer peripheral for FPGA and ASIC
SoC designs. Key features include:

- **Programmable pre-scaler**: a configurable divider on the input clock reduces the effective
  counting frequency, enabling long timeout periods without large counter widths.
- **Single interrupt output**: an active-high interrupt signal is asserted when the timer
  reaches its terminal count, allowing the host CPU to respond to timeout events.
- **One-shot mode**: the timer counts once from the programmed load value to terminal count
  and then stops, ideal for single-event timeouts and watchdog-style deadlines.
- **Normal (free-running) mode**: the timer automatically reloads and restarts after each
  terminal count, providing a periodic interrupt source for OS tick generation or PWM.
- **External trigger output**: a dedicated output signal pulses at each terminal count,
  allowing the timer to synchronize or initiate actions in other SoC peripherals without
  CPU intervention.

## Design Architecture

The timer IP is organized as three cooperating modules:

```
         ┌──────────────────────────────────────────────┐
         │  timer_apb / timer_ahb / timer_axi4l / timer_wb  │
         │   (bus adapter — protocol decode only)        │
         │                                               │
         │  ┌──────────────┐   ┌──────────────────────┐ │
Bus ────►│  │ timer_XXX_if │──►│   timer_regfile      │ │
         │  │ (protocol IF)│   │  (CTRL/STATUS/LOAD/  │ │
         │  └──────────────┘   │  COUNT/CAPTURE regs) │ │
         │                     └──────────┬───────────┘ │
         │                                │              │
         │                     ┌──────────▼───────────┐ │
         │                     │   timer_core         │ │
         │                     │  (32-bit counter,    │ │
         │                     │   8-bit pre-scaler,  │ │
         │                     │   IRQ, trigger out)  │ │
         │                     └──────────────────────┘ │
         └──────────────────────────────────────────────┘
                                              │irq  │trigger_out
```

- **`timer_XXX_if`** — protocol-to-register-bus bridge (APB4, AHB-Lite, AXI4-Lite, Wishbone B4). Produces a simple `wr_en/wr_addr/wr_data/wr_strb` + `rd_en/rd_addr/rd_data` internal bus.
- **`timer_regfile`** — five 32-bit registers (CTRL, STATUS, LOAD, COUNT, CAPTURE). Handles byte-enable writes, W1C STATUS.INTR/OVF, RO STATUS.ACTIVE/COUNT/CAPTURE, and self-clearing CTRL.RESTART/SNAPSHOT command bits.
- **`timer_core`** — 32-bit down-counter with 8-bit pre-scaler, one-shot / repeating mode, interrupt pulse/level output, overrun detection, LOAD=0 protection, and gated trigger output.

## Register Map

Full register map: [doc/timer_regs.html](doc/timer_regs.html)

Base address: configured at integration time. All registers are 32-bit, word-aligned.

### Register Summary

| Offset | Name    | Access  | Reset         | Description                                     |
|--------|---------|---------|---------------|-------------------------------------------------|
| `0x00` | CTRL    | RW      | `0x0000_0000` | Control register                                |
| `0x04` | STATUS  | RO/W1C  | `0x0000_0000` | Status register                                 |
| `0x08` | LOAD    | RW      | `0x0000_0000` | Reload / initial count value                    |
| `0x0C` | COUNT   | RO      | `0x0000_0000` | Current counter value (hw-updated)              |
| `0x10` | CAPTURE | RO      | `0x0000_0000` | Race-free counter snapshot (hw-updated on SNAP) |

### CTRL — Control Register (offset `0x00`)

| Bits  | Field           | Access | Reset  | Description |
|-------|-----------------|--------|--------|-------------|
| 31:15 | reserved        | —      | 0      | Read-as-zero, ignore on write |
| 14    | `SNAPSHOT`      | SC     | 0      | Write `1` to atomically latch COUNT into CAPTURE. Self-clears the next cycle |
| 13    | `IRQ_MODE`      | RW     | 0      | IRQ output mode. `0` = level (asserted while STATUS.INTR=1). `1` = pulse (one cycle per underflow) |
| 12    | `RESTART`       | SC     | 0      | Write `1` to force-reload COUNT from LOAD and reset prescaler without toggling EN. Self-clears the next cycle |
| 11:4  | `PRESCALE[7:0]` | RW     | `0x00` | Clock pre-scale. Divide ratio = PRESCALE + 1. `0` = divide-by-1 |
| 3     | `TRIG_EN`       | RW     | 0      | Trigger output enable. When set, `trigger_out` pulses one cycle on underflow |
| 2     | `INTR_EN`       | RW     | 0      | Interrupt enable. Gates `STATUS.INTR` (or underflow pulse) to the `irq` output |
| 1     | `MODE`          | RW     | 0      | `0` = repeat/free-run (auto-reload). `1` = one-shot (stop after first underflow) |
| 0     | `EN`            | RW     | 0      | Timer enable. `1` = counting; `0` = halted |

SC = self-clearing command bit (reads back as 0; write 1 to trigger one-cycle action).

### STATUS — Status Register (offset `0x04`)

| Bits | Field    | Access | Reset | Description |
|------|----------|--------|-------|-------------|
| 31:3 | reserved | —      | 0     | Read-as-zero |
| 2    | `OVF`    | W1C    | 0     | Overrun flag. Set by hardware when an underflow occurs while STATUS.INTR is already pending. Clear by writing `1` |
| 1    | `ACTIVE` | RO     | 0     | Timer is running. Set/cleared by hardware; reflects `CTRL.EN` qualified by one-shot completion |
| 0    | `INTR`   | W1C    | 0     | Interrupt pending. Set by hardware on underflow. Clear by writing `1`. Not gated by `CTRL.INTR_EN` |

### LOAD — Load Register (offset `0x08`)

| Bits | Field         | Access | Reset         | Description |
|------|---------------|--------|---------------|-------------|
| 31:0 | `VALUE[31:0]` | RW     | `0x0000_0000` | 32-bit reload value. Loaded into the counter on enable or RESTART, and on every underflow in repeat mode. Hardware enforces a minimum effective count of 1 (LOAD=0 treated as 1 in repeat mode) |

### COUNT — Count Register (offset `0x0C`)

| Bits | Field         | Access | Reset         | Description |
|------|---------------|--------|---------------|-------------|
| 31:0 | `VALUE[31:0]` | RO     | `0x0000_0000` | Current value of the 32-bit down-counter. Updated by hardware every prescaled clock cycle. Writes ignored |

### CAPTURE — Capture Register (offset `0x10`)

| Bits | Field         | Access | Reset         | Description |
|------|---------------|--------|---------------|-------------|
| 31:0 | `VALUE[31:0]` | RO     | `0x0000_0000` | Race-free snapshot of COUNT. Updated by hardware on the cycle that CTRL.SNAPSHOT is written. Holds its value until the next snapshot. Writes ignored |

## Interfaces

### Bus interfaces (one top-level module per protocol)

| Module | Protocol | Address bits | Data width | Clock/Reset |
|--------|----------|-------------|-----------|-------------|
| `timer_apb` | APB4 | 12-bit byte addr (PADDR[11:0]) | 32-bit | PCLK / PRESETn (active-low) |
| `timer_ahb` | AHB-Lite | 32-bit byte addr (HADDR[31:0]) | 32-bit | HCLK / HRESETn (active-low) |
| `timer_axi4l` | AXI4-Lite | 32-bit byte addr | 32-bit | ACLK / ARESETn (active-low) |
| `timer_wb` | Wishbone B4 | 4-bit word addr (ADR_I[3:0]) | 32-bit | CLK_I / RST_I (active-high) |

### IP-level outputs (all variants)

| Signal | Direction | Description |
|--------|-----------|-------------|
| `irq` | output | Masked interrupt — level (STATUS.INTR=1 & CTRL.INTR_EN=1) or pulse (one cycle per underflow & CTRL.INTR_EN=1), selected by CTRL.IRQ_MODE |
| `trigger_out` | output | One-cycle pulse on counter underflow when CTRL.TRIG_EN=1 |

## Simulation Results

Directed simulation using Icarus Verilog. Five test sequences run per variant.

| Variant   | Simulator | Tests | Result |
|-----------|-----------|-------|--------|
| APB4      | Icarus Verilog 12.0 | reset, rw, back2back, strobe, timer_ops | PASS |
| AHB-Lite  | Icarus Verilog 12.0 | reset, rw, back2back, strobe, timer_ops | PASS |
| AXI4-Lite | Icarus Verilog 12.0 | reset, rw, back2back, strobe, timer_ops | PASS |
| Wishbone  | Icarus Verilog 12.0 | reset, rw, back2back, strobe, timer_ops | PASS |

Results generated: 2026-03-18. See `verification/work/icarus/*/results.log` for full output.

## Formal Verification Results

Bounded model checking (BMC, depth 20) using SymbiYosys with smtbmc/boolector.
All four bus-interface variants verified with 9 properties each (P1–P9) plus 3 cover goals.

| Variant   | Tool         | Engine          | Depth | Properties | Result |
|-----------|--------------|-----------------|-------|------------|--------|
| APB4      | SymbiYosys   | smtbmc boolector | 20   | 9 assert, 3 cover | PASS |
| AHB-Lite  | SymbiYosys   | smtbmc boolector | 20   | 9 assert, 3 cover | PASS |
| AXI4-Lite | SymbiYosys   | smtbmc boolector | 20   | 9 assert, 3 cover | PASS |
| Wishbone  | SymbiYosys   | smtbmc boolector | 20   | 9 assert, 3 cover | PASS |

Results generated: 2026-03-18. See `verification/formal/` for `.sby` scripts and flat wrapper modules.

**Properties verified (all variants):**
- P1: `irq == status_intr & ctrl_intr_en` (combinational IRQ gate)
- P2: `hw_active` de-asserts within one cycle of `ctrl_en` going low
- P3: `hw_intr_set` is a maximum one-cycle-wide pulse
- P4: `trigger_out` is a maximum one-cycle-wide pulse
- P5: `trigger_out` is gated by `ctrl_trig_en`
- P6: Counter loads `load_val` one cycle after `ctrl_en` rises
- P7: CTRL register write updates `ctrl_en` next cycle
- P8: W1C write to STATUS clears `status_intr`
- P9: `hw_intr_set` sets `status_intr` next cycle

**Assumption:** Degenerate timer configuration (repeat mode, `load_val=0`, `prescale=0`) excluded via formal assumption — this combination causes continuous underflow which is not a meaningful timer operation.

## UVM Verification Results

Full UVM regression run on Vivado xsim 2023.2 using the APB4 bus variant.
UVM sources are in `verification/tasks/uvm/`.

| Test                | Bus   | Simulator    | Result |
|---------------------|-------|--------------|--------|
| timer_base_test     | APB4  | Vivado xsim  | PASS   |

Scoreboard: PASS=4 FAIL=0. No UVM_ERROR or UVM_FATAL.

Results generated: 2026-03-18. Vivado version: 2023.2.

Run with: `python3 verification/tools/uvm_timer.py --test timer_base_test`
Skip UVM (no Vivado): `python3 verification/tools/run_regression.py --skip-uvm`

See `verification/work/xsim/uvm/results.log` for full simulator output.

## Lint Results

| Language | Tool       | Version                     | Warnings | Waivers | Result |
|----------|------------|-----------------------------|----------|---------|--------|
| SV       | Verilator  | 5.043 devel rev v5.042-171  | 0        | 0       | PASS   |
| VHDL     | GHDL       | 6.0.0-dev (4.1.0.r1095)    | 0        | 0       | PASS   |

Results generated: 2026-03-18. See `verification/lint/lint_results.log` for full output.
No waivers required — all RTL sources are clean.

## Firmware

### Build Targets

Driver source: `firmware/src/timer.c` (20 functions, ~278 lines of C99).

The firmware is cross-compiled for embedded targets only — host GCC is never used.
Run `bash firmware/build.sh` to build all targets, or pass `arm` / `riscv` to build one.

| Target            | Toolchain                   | Flags                              | Library output                       |
|-------------------|-----------------------------|------------------------------------|--------------------------------------|
| ARM Cortex-M33    | `arm-none-eabi-gcc`         | `-mcpu=cortex-m33 -mthumb`         | `firmware/lib/arm-cortex-m33/libtimer.a` |
| RISC-V 32-bit     | `riscv-none-elf-gcc` (xPack 15.2.0) | `-march=rv32imac_zicsr -mabi=ilp32` | `firmware/lib/riscv32/libtimer.a` |

Toolchain files are in `firmware/cmake/`. Pass them to CMake directly for manual builds:

```sh
cmake -S firmware -B firmware/build/arm-cortex-m33 \
      -DCMAKE_TOOLCHAIN_FILE=firmware/cmake/arm-cortex-m33.cmake \
      -DCMAKE_BUILD_TYPE=Release
cmake --build firmware/build/arm-cortex-m33
```

### Code Size

Estimated `.text` at `-O2` (run `size firmware/lib/<arch>/libtimer.a` for exact figures):

| Target         | `.text` (est.) | `.data` | `.bss` |
|----------------|----------------|---------|--------|
| ARM Cortex-M33 | ~420 B         | 0       | 0      |
| RISC-V 32-bit  | ~480 B         | 0       | 0      |

Notes:
- `.data` and `.bss` are zero: the driver has no global mutable state.
- All functions are thin wrappers around MMIO macros; most inline to 2–6
  instructions at `-O2`, so `.text` shrinks further with `-flto`.

### API Summary

All functions are declared in `firmware/include/timer.h`.
No OS dependencies.  No dynamic allocation.  C99 only.

| Function | Signature | Description |
|----------|-----------|-------------|
| `timer_init` | `void timer_init(uintptr_t base, uint32_t load_val, uint8_t prescale, uint8_t mode)` | Initialise the peripheral: reset CTRL, write load value, set prescaler and mode.  Timer is left disabled. |
| `timer_enable` | `void timer_enable(uintptr_t base)` | Set CTRL.EN to start the countdown. |
| `timer_disable` | `void timer_disable(uintptr_t base)` | Clear CTRL.EN to freeze the counter. |
| `timer_set_load` | `void timer_set_load(uintptr_t base, uint32_t val)` | Write a new reload value to TIMER_LOAD. |
| `timer_get_count` | `uint32_t timer_get_count(uintptr_t base)` | Read the current counter value from TIMER_COUNT (read-only register). |
| `timer_irq_enable` | `void timer_irq_enable(uintptr_t base)` | Set CTRL.INTR_EN to enable the interrupt output. |
| `timer_irq_disable` | `void timer_irq_disable(uintptr_t base)` | Clear CTRL.INTR_EN to mask the interrupt output. |
| `timer_irq_pending` | `int timer_irq_pending(uintptr_t base)` | Return non-zero if STATUS.INTR (bit 0) is set. |
| `timer_irq_clear` | `void timer_irq_clear(uintptr_t base)` | Write 1 to STATUS.INTR to clear the pending interrupt (W1C). |
| `timer_trigger_enable` | `void timer_trigger_enable(uintptr_t base)` | Set CTRL.TRIG_EN to enable the hardware trigger output pulse. |
| `timer_trigger_disable` | `void timer_trigger_disable(uintptr_t base)` | Clear CTRL.TRIG_EN to disable the trigger output. |
| `timer_is_active` | `int timer_is_active(uintptr_t base)` | Return non-zero if STATUS.ACTIVE (bit 1) is set — timer is counting. |
| `timer_ovf_pending` | `int timer_ovf_pending(uintptr_t base)` | Return non-zero if STATUS.OVF (bit 2) is set — overrun occurred before previous interrupt was cleared. |
| `timer_ovf_clear` | `void timer_ovf_clear(uintptr_t base)` | Write 1 to STATUS.OVF to clear the overrun flag (W1C). |
| `timer_restart` | `void timer_restart(uintptr_t base)` | Force-reload COUNT from LOAD and reset prescaler without toggling EN (writes self-clearing CTRL.RESTART). |
| `timer_set_irq_mode` | `void timer_set_irq_mode(uintptr_t base, uint8_t mode)` | Set IRQ output mode: `TIMER_CTRL_IRQ_MODE_LEVEL` (0) for level, `TIMER_CTRL_IRQ_MODE_PULSE` (1) for one-cycle pulse per underflow. |
| `timer_snapshot` | `void timer_snapshot(uintptr_t base)` | Atomically latch current COUNT into CAPTURE register (writes self-clearing CTRL.SNAPSHOT). |
| `timer_get_capture` | `uint32_t timer_get_capture(uintptr_t base)` | Read the most recently captured counter value from TIMER_CAPTURE. |
| `timer_write_reg` | `void timer_write_reg(uintptr_t base, uint32_t offset, uint32_t value)` | Raw 32-bit register write (for platform bring-up and testing). |
| `timer_read_reg` | `uint32_t timer_read_reg(uintptr_t base, uint32_t offset)` | Raw 32-bit register read (for platform bring-up and testing). |

## Synthesis Results

Technology-independent synthesis using Yosys 0.60 targeting generic gate primitives.
FPGA synthesis scripts for Vivado and Quartus are provided in `synthesis/` but require
the respective vendor tools (not run as part of the open-source flow).

### Yosys (technology-independent)

| Variant   | Top module   | Total cells | Flip-flops | Result |
|-----------|--------------|-------------|------------|--------|
| APB4      | timer_apb    | 622         | 236        | PASS   |
| AHB-Lite  | timer_ahb    | 627         | 236        | PASS   |
| AXI4-Lite | timer_axi4l  | 713         | 248        | PASS   |
| Wishbone  | timer_wb     | 625         | 155        | PASS   |

Results generated: 2026-03-18. Cell counts use Yosys generic gate library (`synth -flatten`).
See `synthesis/yosys/work/synthesis_report.log` for full cell breakdown.

### Vivado (Zynq-7010 `xc7z010clg400-1`)

Out-of-context synthesis. Top module: `timer_apb`. Clock: 100 MHz.

| Variant | LUTs | FFs | BRAM | DSP | WNS      | Result |
|---------|------|-----|------|-----|----------|--------|
| APB4    | 176  | 191 | 0    | 0   | +6.162 ns | PASS   |

Results generated: 2026-03-18. Tool: Vivado 2023.2. Board: Zybo-Z7-10.
See `synthesis/vivado/utilization.rpt` and `synthesis/vivado/timing_summary.rpt`.

Run: `python3 synthesis/run_vendor_synth.py --vivado`

### Quartus Prime (Cyclone V SE `5CSEMA4U23C6`)

Analysis & Synthesis only (Fitter not run — ALMs require post-fit). Top module: `timer_apb`. Clock: 100 MHz.

| Variant | Registers | M10K | DSP | Result |
|---------|-----------|------|-----|--------|
| APB4    | 191       | 0    | 0   | PASS   |

Results generated: 2026-03-18. Tool: Quartus Prime Lite 23.1. Board: DE0-Nano-SoC (Arrow SoCKit).
See `synthesis/quartus/work/timer_apb.map.rpt`.

Run: `python3 synthesis/run_vendor_synth.py --quartus`
