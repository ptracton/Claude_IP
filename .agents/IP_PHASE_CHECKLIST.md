# Claude_IP — Phase Checklist

The working checklist for [IP_PLAN.md](IP_PLAN.md). The plan says **what** each block
is and why. This file tracks **what is done**. Update it in the same change as the work.

Started 2026-11-26. Nothing below has RTL yet unless it is checked.

## How to use this file

- **Phase-level tasks** use `- [ ]` / `- [x]` check boxes.
- **IP blocks** use one table row per block, with one cell per step of the 12-step flow
  (`Claude_IP.md`, Sub-Agents). Cell values:

  | Mark | Meaning |
  |---|---|
  | `☐` | to do |
  | `◐` | in progress |
  | `☑` | done: the step's quality gate passed (standard host) |
  | `☑c` | done on csun.edu as well (or csun.edu only, for steps that run only there) |
  | `—` | not applicable (for example no registers → no Step 2) |

- **Step columns** (current order, 2026-11-26): `Spec` = block spec written in the IP's
  `doc/` (features, parameters, ports, register map, latency) and reviewed by the user ·
  `1` setup · `2` rdl · `3` rtl · `4` directed tests · `5` lint (with DFT checks) · `6` uvm ·
  `7` formal · `8` regression · `9` firmware · `10` synthesis (with `dft_drc`) · `11` power
  · `12` cleanup.
- **Reqs** lists the plan requirements a block must meet on top of the normal flow:

  | Code | Requirement | Plan |
  |---|---|---|
  | DFT | `test_mode_i` / `scan_en_i` and the seven DFT rules (**every new IP**, so not repeated per row) | §3.9 |
  | DFT-r*n* | the block is affected by DFT rule *n* (clock, reset, oscillator, memory, secrets) and needs a directed DFT test | §3.9 |
  | CTL | second register port (control stream), `CTL_PORT=1` default | §3.8 |
  | noCTL | must **never** have the control-stream port | §3.8, D11 |
  | BD | DMA back door: control + TX/RX data streams + done/error events | §6.1 |
  | STR | claude stream data ports | §3.3 |
  | EVT | event inputs/outputs | §3.4 |
  | GM | quantized bit-exact Python golden model on `claude_fx.py`, float reference, Q1.15 + wider Q + integer in regression | §3.10 |
  | SF | SoftFloat / TestFloat golden model | §8.2 |
  | ML | TFLite **and** PyTorch three-way checking | §8.1 |
  | RTOS | needed by FreeRTOS / Zephyr; stock-driver register compatibility | §12.1 |
  | MST | bus master through `mem_*` initiator + `claude_<proto>_mst_if` | §3.2 |

- A phase is **done** when every row is `☑` (or `—`) through Step 8, every phase task is
  checked, and its exit criteria hold. Steps 9–12 may finish while the next phase starts
  (roadmap rule, plan §14).
- Every block also follows the timer (or the sram for memory IP), except where the DFT rule
  says otherwise.

---

## Already in place (before this plan)

- [x] timer: complete, both flows
- [x] sram: Steps 1–12 (left: user commit + `v1.0.0` tag; csun.edu clean regression)
- [x] bus_matrix: complete on csun.edu (standard-host scripts not re-run)
- [x] `claude_<proto>_if` register bridges, `claude_<proto>_mem_if` memory adapters, `claude_sync`, `claude_pulse_sync`
- [x] Plan written: `.agents/IP_PLAN.md` (2026-11-26)
- [x] Decisions D1–D9, D11–D13 made (D10 deferred), plan §15
- [x] DFT rule applied to the agent files (`Claude_IP.md`, `rtl.md` §4c, `lint.md` item 7, `synthesis.md`, `directed_tests.md`, `uvm.md`), 2026-11-26

---

## Phase 0 — Foundations (`IP/common`)

Shared parts are verified once, in `IP/common/verification/`, the way the memory adapters
were (`mem_if/`, `verify_mem_if.py`), not through the full 12-step flow. Their columns are
therefore different:

`Spec` = interface spec `.md` in `IP/common/design/rtl/` · `SV` · `VHDL` · `Sim` (Icarus /
GHDL / xsim; VCS + Xcelium on csun.edu) · `Lint` · `Formal` · `Py` (Python model / driver /
BFM where needed) · `Doc` (`Claude_IP.md` Common Components list + IP_PLAN cross-reference).

### 0.1 Interface specifications (write and review before any RTL)

- [ ] `mem_bus.md` extended for the **initiator** direction (master adapters) — §3.2
- [ ] `stream.md`: claude stream (AXI4-Stream names, `HAS_READY`, `REG_IN`/`REG_OUT`, `tuser`/`tid`, Q-format rules) — §3.3
- [ ] `event.md`: event pulse interface — §3.4
- [ ] `sideband.md`: standard peripheral side-band (`irq_o`, `dbg_freeze_i`, `idle_o`, DMA req/ack, `evt_*`) — §3.5
- [ ] `tap_user_dr.md`: TAP user-DR port — §3.6
- [ ] `cmd2bus.md`: byte command protocol — §3.7
- [ ] `ctl_stream.md`: control stream packet format, ownership, ring topology, bus-wins arbitration — §3.8
- [ ] `fx.md`: fixed-point formats, rounding and saturation modes (RTL and Python agree) — §3.10
- [ ] User review of all of the above

### 0.2 Common RTL components

| Component | Spec | SV | VHDL | Sim | Lint | Formal | Py | Doc |
|---|---|---|---|---|---|---|---|---|
| `claude_apb_mst_if` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_ahb_mst_if` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_axi4l_mst_if` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_wb_mst_if` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_skid_buffer` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_fifo_sync` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_fifo_async` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_fifo_stream` (incl. packet mode) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_reset_sync` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_handshake_sync` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_gray_sync` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_edge_detect` / `claude_glitch_filter` / `claude_debounce` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_clk_en_div` (any integer N) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_clk_en_frac` (fractional N.F) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| `claude_clk_en_tick` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_fx_*` (round, sat, mul, lzc) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| `claude_arb` (round-robin, fixed priority) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_lfsr` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| `claude_crc` (primitive) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| `claude_cmd2bus` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| `claude_ctl2reg` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| `claude_regbus_arb` (bus always wins) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_ctl_ring` (DEST-ID forwarder) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |

### 0.3 Verification infrastructure

- [ ] Formal checkers: master-role use of `claude_<proto>_fv`; `claude_stream_fv`; `claude_ctl_fv`; FIFO and Gray-code properties
- [ ] SV BFM tasks (no `interface`, Icarus-safe): stream source/sink, control-stream driver/monitor, `mem_*` initiator responder
- [ ] UVM agents (xsim): stream, control stream
- [ ] VHDL equivalents of the BFM tasks used by the VHDL benches
- [ ] `IP/common/verification/tools/claude_fx.py`, checked bit-exact against `claude_fx_*` RTL
- [ ] Python stream / control-stream drivers for benches (file-based vectors)
- [ ] Shared dual-port register test template (both ports, collision, ownership) — §16
- [ ] DFT0 waiver template (Verilator `.vlt` entry, `waivers.md` class text, SpyGlass pragma) — §3.9
- [ ] Shared lint port-check helper for `test_mode_i` / `scan_en_i` (`lint.md` item 7)
- [ ] Runner: `IP/common/verification/tools/verify_common.py` (or extend `verify_mem_if.py`) covering 0.2

### 0.4 Phase 0b — bursts and AXI4 (D1)

The `mem_*` adapters are signed off on csun.edu: `BURST_EN=0` must leave them
bit-identical, and the `mem_if` suite is re-run on both hosts.

| Component | Spec | SV | VHDL | Sim | Lint | Formal | Py | Doc |
|---|---|---|---|---|---|---|---|---|
| `mem_*` `BURST_EN` (`mem_len`, `mem_burst`) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_axi4_if` (register bridge) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_axi4_mem_if` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_axi4_mst_if` | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ |
| `claude_axi4_fv` checker + AXI4 BFM | ☐ | ☐ | — | ☐ | ☐ | ☐ | — | ☐ |

- [ ] `mem_if` regression re-run, unchanged results with `BURST_EN=0` (standard host and csun.edu)
- [ ] Agent files updated: AXI4 as a fifth protocol (`rtl.md` top-levels, BFM lists, synthesis variant lists)

**Phase 0 exit:** every spec reviewed; every 0.2 / 0.4 component passes sim, lint and
formal in SV and VHDL; `claude_fx.py` matches the RTL; the agent files reference the new
common parts.

---

## Phase 1 — Simple peripherals

| Block | Reqs | Spec | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| gpio | EVT | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| uart16550 | CTL, BD, RTOS (ns16550-compatible) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| spi_master | CTL, BD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| i2c_master | CTL, BD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| pwm | CTL, EVT | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| watchdog | noCTL, DFT-r2 | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| syscon (+ pinmux) | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| crc (register wrapper) | CTL | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |

Clock technology cells (common, per-technology leaves like the sram macros; plan §10.3):

| Cell | Spec | SV | VHDL | Sim | Lint | Formal | Leaves (generic / SAED / SKY130 / Xilinx / Altera) | SDC | Doc |
|---|---|---|---|---|---|---|---|---|---|
| `claude_clk_gate` (ICG, test enable) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| `claude_clk_mux2` (glitch-free, test select) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| `claude_clk_div` (integer N, odd 50 %, test bypass) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| `claude_clk_pll` wrapper | ☐ | ☐ | ☐ | ☐ | — | — | ☐ | ☐ | ☐ |

- [ ] Each comms IP: back-door directed test (DMA-style descriptor sequence driven by the control-stream BFM)
- [ ] Each `CTL` IP: dual-port register template test passes
- [ ] watchdog: test proves no control-stream path exists; DFT test (internal reset blocked in test mode)

**Phase 1 exit:** all rows through Step 8; clock cells verified on every leaf.

---

## Phase 2 — Bus masters, debug access, bring-up

| Block | Reqs | Spec | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| jtag_tap (1149.1 + `SCAN_MODE`, `MBIST`, user DRs) | DFT-r1 | ☐ | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ | ☐ | ☐ |
| jtag2bus (+ burst mode = jtag_dma, D5) | MST | ☐ | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ | ☐ | ☐ |
| uart2bus | MST | ☐ | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ | ☐ | ☐ |
| spi_slave (to bus master; mailbox mode) | MST, CTL, BD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| i2c_slave | MST, CTL, BD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| bus bridges (generated: slave adapter → `mem_*` → master adapter) | — | ☐ | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ | ☐ | ☐ |
| bus CDC bridge | — | ☐ | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ | ☐ | ☐ |
| bus RDC / isolation fence | DFT-r2 | ☐ | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ | ☐ | ☐ |
| bus clock-enable bridge | — | ☐ | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ | ☐ | ☐ |
| bus mux (N:1) | — | ☐ | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ | ☐ | ☐ |
| bus demux / decoder + default slave | — | ☐ | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ | ☐ | ☐ |
| register slice | — | ☐ | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ | ☐ | ☐ |
| bus timeout watchdog | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| bus_monitor / perf counters | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| error injector (verification IP) | — | ☐ | ☐ | — | ☐ | ☐ | ☐ | — | — | ☐ | — | — | — | ☐ |

SoC tooling and first SoC:

- [ ] Boundary-scan generator: BSR cells from a pad-list YAML, BSDL writer, verified against the TAP (§3.9, §9)
- [ ] SoC generator v1 (`SoC/tools/gen_soc.py`): YAML → SV + VHDL top, `soc.h`, linker script, SystemRDL address map, DFT port routing, pad list
- [ ] JTAG host BFM + OpenOCD configuration / Tcl for jtag2bus
- [ ] Host Python library for uart2bus / jtag2bus / spi_slave (shared `cmd2bus` client)
- [ ] **D10 decision:** first reference SoC (deferred by the user; SoC-0 is the candidate)
- [ ] First SoC assembled from the generator; directed SoC tests driven over uart2bus / jtag2bus
- [ ] First SoC on FPGA: Zybo-Z7-10 and DE0-Nano-SoC constraints, hardware smoke test
- [ ] csun.edu: first SoC through DC with **scan insertion**, TestMAX ATPG (stuck-at + transition coverage reported), boundary-scan and ATPG pattern gate-level simulation

**Phase 2 exit:** a host PC reads and writes every Phase 1 peripheral through each of the
three debug paths, in simulation and on both boards; the SoC netlist has scan chains and
a working JTAG / boundary-scan chain.

---

## Phase 3 — Small CPU, interrupts, DMA, FreeRTOS

| Block | Reqs | Spec | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| rv_tiny (RV32I/E + M, C, Zicsr, Zicntr; opt. Zfinx, U+PMP) | MST, RTOS | ☐ | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| riscv_dm + dtm (debug spec 0.13.2) | MST | ☐ | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ | ☐ | ☐ |
| irq_ctrl (PLIC-compatible, D4) | RTOS | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| clint (SiFive layout) | RTOS | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| reset_ctrl | DFT-r2 | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| boot ROM | DFT-r5 | ☐ | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| rtc | DFT-r1 | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| dma (MM2S/S2MM, 2-D, linked list, back-door ports, `CTL`/`WAIT` descriptors) | MST, STR, EVT | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |

CPU-specific verification (in addition to the 12 steps):

- [ ] RVFI trace port on rv_tiny
- [ ] `riscv-arch-test` (I, M, C, Zicsr) pass, SV and VHDL
- [ ] Lock-step comparison against Spike or Sail
- [ ] `riscv-formal` through RVFI (SymbiYosys)
- [ ] riscv-dv random instruction tests (xsim, if practical)
- [ ] Interrupt-latency figure measured and documented (§12.1)
- [ ] GDB + OpenOCD debug session works through `riscv_dm` (halt, step, breakpoints, memory)

RTOS (§12.1):

- [ ] Check FreeRTOS RV32E support (decides whether RV32E is an RTOS configuration)
- [ ] FreeRTOS port: `FreeRTOSConfig.h`, chip-specific extensions header, CLINT tick
- [ ] FreeRTOS demos: blinky, full demo task set, DMA + UART + IRQ demo
- [ ] FreeRTOS demos in the regression (Verilator; xsim for the VHDL core) and on both boards
- [ ] Tickless idle: `wfi` + core clock gating with `mtime` on the always-on clock

SoC:

- [ ] SoC-1 "Tiny MCU" generated, C firmware tests for every peripheral, FPGA and csun.edu flows

**Phase 3 exit:** SoC-1 boots from ROM, runs FreeRTOS on both boards and in simulation,
and is debuggable with GDB.

---

## Phase 4 — DSP chain, FPU, motor control

Infrastructure:

| Block | Reqs | Spec | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| claude_dsp_shell (bypass, double-buffered coefs, stats) | CTL, STR, EVT | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| stream_switch (safe re-route, fan-out) | CTL, STR | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| event_router | CTL, EVT | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |

Math blocks (each also needs its golden model checked off in the Reqs list below the table):

| Block | Reqs | Spec | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| nco / dds | CTL, STR, GM | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| cic (decimator / interpolator) | CTL, STR, GM | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| halfband (↓2 / ↑2) | CTL, STR, GM | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| fir (incl. polyphase, CIC compensation preset) | CTL, STR, GM | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| iir_biquad | CTL, STR, GM | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| cordic | CTL, STR, GM | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| mixer / ddc | CTL, STR, GM | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| fft (streaming + memory-based) | CTL, STR, GM, DFT-r5 | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| mag_log | CTL, STR, GM | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| moving_avg / stats | CTL, STR, GM | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| div / sqrt | CTL, STR, GM | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| fpu_core — SP (D13 default) | SF | ☐ | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ | ☐ | ☐ |
| fpu_core — DP / SP_DP | SF | ☐ | — | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ | ☐ | ☐ |
| fpu_stream (incl. int / Q ↔ float) | CTL, STR, SF | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| fpu_reg | CTL, SF | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |

Data sources and sinks for the chain:

| Block | Reqs | Spec | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| pdm_rx | CTL, BD, STR | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| i2s (TX + RX, TDM) | CTL, BD, STR | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |

Motor control:

| Block | Reqs | Spec | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| pid | CTL, STR, EVT, GM | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| qei | CTL, EVT | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| adc_seq | CTL, BD, STR, EVT | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |

Golden models and chain tooling:

- [ ] Golden model, float reference and SQNR report for every GM block: nco, cic, halfband, fir, iir_biquad, cordic, mixer, fft, mag_log, moving_avg, div/sqrt, pid
- [ ] Every GM block's regression covers Q1.15, one wider Q format and integer mode
- [ ] SoftFloat binding (Python or DPI) + TestFloat vector runner for the FPU
- [ ] Chain YAML format; generator emits both a static chain and a switch-based cluster (D6)
- [ ] Chain golden model built from the per-block models; end-to-end chain tests
- [ ] Filter design helpers (CIC compensation, halfband, biquad coefficients) in Python
- [ ] Each DSP block: control from the bus **and** from the control stream (ring), incl. `SYNC` writes at frame boundaries

SoCs:

- [ ] Audio / sensor DSP SoC (without NPU): PDM → CIC → halfband → FIR → IIR → FFT → mag_log, with a DMA capture tap
- [ ] Motor-control SoC: PWM → event router → adc_seq → PID → PWM loop with no CPU in the loop

**Phase 4 exit:** both SoCs run their chains bit-exact against the chain model in
simulation and on hardware; the FPU passes TestFloat in SP (and DP where built).

---

## Phase 5 — Security

| Block | Reqs | Spec | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| sha256 (+ HMAC) | CTL, STR, DFT-r7 | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| aes (ECB/CBC/CTR/CFB/OFB) | CTL, STR, DFT-r7 | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| aes GCM (GHASH) | CTL, STR | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| trng (ring oscillators + SP 800-90B health tests) | DFT-r4 | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| drbg (CTR_DRBG) | DFT-r7 | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| key_store / otp_ctrl | noCTL, DFT-r7 | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| bus firewall / TrustZone-lite (`mem_prot`) | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| lifecycle / secure debug | DFT-r7 | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |

- [ ] NIST vectors (AES, SHA-256, HMAC, CTR_DRBG) + Python reference (`hashlib` / `cryptography`) in every regression
- [ ] Key-clearing-on-test-mode directed tests (DFT rule 7) for every DFT-r7 block
- [ ] Proof that keys cannot be read by software or reached by any control stream / DMA (tests, plus formal where practical)
- [ ] Ring-oscillator technology leaves (FPGA and ASIC) for the TRNG; stopped in test mode
- [ ] DMA-driven bulk encryption demo (MM2S → aes → S2MM)

**Phase 5 exit:** every crypto block passes its NIST vectors on both languages; no key
leaves the key store through software, DMA, debug or scan.

---

## Phase 6 — Large blocks

| Block | Reqs | Spec | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| NPU-0 vector MAC | CTL, STR, GM, ML | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| NPU-1 GEMM (systolic array, scratchpad, descriptors) | CTL, STR, MST, GM, ML, DFT-r5 | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| NPU-2 CNN (conv2d, depthwise, pooling, activation LUT) | CTL, STR, MST, GM, ML | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| rv_core (RV32IMAC + Zicsr + Zifencei, 5-stage, U + PMP) | MST, RTOS | ☐ | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| rv_core caches + TCM (AXI4 bursts) | MST, DFT-r5 | ☐ | — | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | — | ☐ | ☐ | ☐ |
| fpu_rv (F/D, `mstatus.FS`) + coprocessor port | SF, RTOS | ☐ | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| qspi_xip | MST, CTL, BD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| vga / video | MST, CTL, EVT, DFT-r5 | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| mbist_ctrl (shared; sram March C- engine behind it) | DFT-r5 | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| ila / logic analyzer | CTL, DFT-r5 | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| mailbox / hw_semaphore | RTOS (SMP) | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |

NPU software and checking (§8.1):

- [ ] Compiler internal graph + descriptor / weight-blob writer + C runtime
- [ ] TFLite front end (int8 `.tflite`)
- [ ] PyTorch front end (PT2E / `torch.export` and eager `torch.ao.quantization`)
- [ ] `REQUANT_MODE` `TFLITE` and `TORCH` both bit-exact against the golden model
- [ ] Three-way checks per layer and per model: RTL ↔ model (bit-exact), model ↔ TFLite reference kernels (bit-exact), model ↔ PyTorch reference (bit-exact, or documented ≤ 1 LSB exceptions)
- [ ] Reference models exported from **both** frameworks: keyword spotting (DS-CNN), small image model, MLP; accuracy equal to the frameworks' quantized models

rv_core verification and RTOS:

- [ ] `riscv-arch-test` I, M, A, C, F, D, Zicsr, Zifencei; lock-step vs Spike / Sail; `riscv-formal`
- [ ] FreeRTOS on rv_core, including FPU context (lazy save through `mstatus.FS`)
- [ ] Zephyr SoC + board definition, devicetree generated from the SoC YAML
- [ ] Zephyr drivers: stock (CLINT, PLIC, ns16550) + thin wrappers over the Claude C99 drivers
- [ ] Zephyr kernel-test subset (threads, semaphores, timers, interrupts, FPU sharing) in regression and on hardware
- [ ] Firmware builds `rv32imafdc_zicsr` / `ilp32d` and `rv32imafc` / `ilp32f`; ARM hard-float examples

SoCs:

- [ ] Audio / sensor SoC with the NPU: keyword spotting end to end
- [ ] Secure application SoC: rv_core + rv_tiny security controller + crypto + firewall + lifecycle + qspi_xip + VGA
- [ ] Secure boot ROM flow: hash (SHA-256) and verify (HMAC first; PKA in Phase 7), then jump

**Phase 6 exit:** keyword spotting matches TFLite and PyTorch on hardware; rv_core runs
FreeRTOS and the Zephyr kernel tests; the secure SoC boots only signed images.

---

## Phase 7 — Advanced (later)

| Block | Reqs | Spec | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | 10 | 11 | 12 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| pka (RSA modexp, ECC P-256 / Curve25519) | CTL, DFT-r7 | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| lbist (PRPG + MISR) | DFT-r1 | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| can (2.0B, FD later) | CTL, BD | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| clic-lite (for rv_tiny) | RTOS | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| NPU-3 (INT4 / INT16, sparsity, coprocessor instructions) | CTL, STR, GM, ML | ☐ | — | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |
| tamper / glitch monitor | DFT-r4, DFT-r7 | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ | ☐ |

- [ ] Secure boot with PKA signature verification

---

## Retrofit track (existing IP; runs alongside the phases, needs csun.edu re-runs)

These change signed-off RTL, so each is a planned revision with its full csun.edu re-run
(Signed-Off Code Rule), never a side effect of other work.

- [ ] **timer:** DFT ports + rule checklist; control-stream port (`CTL_PORT`, D11, default 0 keeps today's behavior); README, regression, csun.edu re-runs; new tag
- [ ] **sram:** DFT ports + rules 2 and 5 (memory bypass / observation in test mode, BIST reachable from `mbist_ctrl`); factor SECDED out to `claude_ecc` (common); csun.edu re-runs; new tag
- [ ] **bus_matrix:** DFT ports + rule checklist; AXI4 (full) variant after Phase 0b; csun.edu re-runs; new tag
- [ ] **common bridges / adapters:** no DFT ports needed (no state or only bus state), confirm in their docs; `mem_*` `BURST_EN` covered in Phase 0b

---

## Open items

- [ ] D10: first reference SoC (deferred until Phases 0–2 are further along)
- [ ] csun.edu: confirm licenses for SpyGlass DFT, DFT Compiler and TestMAX (if one is missing, the other check has to pass; `lint.md` item 7, `synthesis.md`)
- [ ] FreeRTOS RV32E support (Phase 3)
