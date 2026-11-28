# Claude_IP — New IP and SoC Integration Plan

Status: **planning draft, 2026-11-26.** Progress is tracked in
[IP_PHASE_CHECKLIST.md](IP_PHASE_CHECKLIST.md), which is updated with the work. No RTL is implemented from this document yet.
Every block listed here is built later through the normal 12-step flow
(`.agents/Claude_IP.md`), from the timer (register IP) or the sram (memory IP).

This document covers:

1. The **integration architecture**: the shared interfaces that let blocks connect
   without per-pair glue (§2–§4).
2. The **signal-processing chain**: how math/DSP/NPU blocks are strung together
   with little delay or overhead (§5).
3. A **catalog** of every planned block: features, parameters, interfaces and
   dependencies (§6–§12).
4. **Reference SoCs** that the blocks build into (§13), a **phased roadmap** (§14),
   the **open decisions** (§15) and SoC-level verification (§16).

Blocks marked **[NEW]** are proposed additions that were not on the original list.

---

## 1. Starting point

What exists and is verified today:

| Asset | Role in SoCs |
|---|---|
| `IP/system/timer` | Gold-standard register peripheral; `irq`, `trigger_out` |
| `IP/system/sram` | On-chip memory; vendor macros, ECC, BIST, power modes, dual port |
| `IP/interface/bus_matrix` | Crossbar, 1–16 masters × 1–32 slaves, APB4 / AHB-Lite / AXI4-Lite / WB |
| `claude_<proto>_if` | Bus **slave** → regbus (12-bit address, single cycle, no errors) |
| `claude_<proto>_mem_if` | Bus **slave** → memory bus `mem_*` (back-pressure, errors, AHB bursts) |
| `claude_sync`, `claude_pulse_sync` | Level and pulse CDC |

Gaps that block the new IP:

- **No bus master side.** DMA, SPI-slave-to-bus, JTAG-to-bus, the CPUs, VGA and the
  NPU all have to *issue* transactions. Today nothing converts an internal request into
  APB / AHB / AXI4-Lite / WB master signals.
- **No streaming interface.** The DSP chain needs a point-to-point data path that does
  not go through the bus.
- **No event/trigger fabric.** `timer.trigger_out` exists, but nothing routes it.
- **No bursts beyond AHB / AXI4-Lite.** High-bandwidth masters (DMA, VGA, NPU, caches)
  will want AXI4 (full) bursts eventually (§15, D1).
- **No clock / reset infrastructure cells.** The CDC rule forbids clock logic in
  plain RTL, so dividers, clock gates and muxes need a technology-cell layer (§10.3).

---

## 2. SoC architecture: six planes

Each SoC is built from six independent connection "planes". Every IP declares
which planes it joins, and each plane has one standard interface (§3).

```
                    ┌───────────────────────────── DEBUG / TEST PLANE ───────────────────┐
                    │  JTAG pins ─► TAP ─► {RISC-V DTM/DM, JTAG2Bus, boundary scan, MBIST}│
                    └────────────────────────────────────────────────────────────────────┘
  ┌─────────┐  ┌─────────┐  ┌────────┐  ┌──────────┐
  │ CPU     │  │ DMA     │  │JTAG2Bus│  │SPI slave │      MASTERS (mem_* initiator
  │ (I + D) │  │         │  │        │  │ 2 bus    │       + claude_<proto>_mst_if)
  └──┬───┬──┘  └──┬───┬──┘  └───┬────┘  └────┬─────┘
     │   │        │   │stream   │            │
 ════╪═══╪════════╪═══╪═════════╪════════════╪══════  MEMORY / DATA PLANE (bus_matrix,
     │   │        │   │                                AHB-Lite / AXI4-Lite / AXI4)
  ┌──▼┐ ┌▼───┐ ┌──▼──────┐                     ┌──────────────┐
  │ROM│ │SRAM│ │AHB→APB  │═══ CONTROL PLANE ═══│ APB peripherals: UART, SPI, I2C, GPIO,
  └───┘ └────┘ │bridge   │   (APB4, regbus)    │ PWM, WDT, timer, IRQ ctrl, AES, SHA, ...
               └─────────┘                     └──────────────┘
                          │   │
  ════════════════════════╪═══╪═══════════════════  STREAMING PLANE (claude stream,
     PDM/I2S/ADC ─► [stream switch] ─► CIC ─► FIR ─► IIR ─► FFT ─► NPU ─► DMA s2mm
                                                                    
  ─────────────────────────────────────────────────  EVENT PLANE (1-cycle pulses)
     timer.trigger, PWM.period, GPIO.edge, DMA.done ─► [event router] ─► DMA req,
                                                       ADC start, PID step, NPU start
  ─────────────────────────────────────────────────  IRQ PLANE (level, active high)
     every IP irq ─► IRQ controller (PLIC-style) ─► CPU MEIP;  CLINT ─► MTIP/MSIP

  CLOCK / RESET / POWER PLANE: clock gen (dividers + ICG + glitch-free mux cells),
     reset controller (sequenced, per-domain), power manager (sram modes, clock gating)
```

| Plane | Standard interface | Typical latency | Who configures it |
|---|---|---|---|
| Control | regbus via `claude_<proto>_if` (exists) | 1–3 bus cycles | CPU / debugger |
| Memory / data | `mem_*` (exists, target) + **`mem_*` initiator (new)** | 2–4 cycles per beat | address map at elaboration |
| Streaming | **claude stream (new)**, AXI4-Stream subset | 0–1 cycle per hop | stream switch registers |
| Control stream | **second register port (new, §3.8)**: register commands as stream packets | 1 cycle per hop + register access | SoC YAML (ring / point-to-point) |
| Event | **1-cycle pulse (new)** | 1 cycle + CDC | event router registers |
| IRQ | level, active high (convention exists in the timer) | 1–2 cycles | IRQ controller |
| Debug / test | **TAP test data register (TDR) port (new)** | TCK-bound | JTAG host |

---

## 3. Shared interface standards (Phase 0 work in `IP/common/`)

Each of these is specified once in `IP/common/design/rtl/<name>.md` (the same way as
`.agents/IP_SPEC_mem_bus.md`), implemented in SV and VHDL, and verified once in
`IP/common/verification/`. **No IP may invent its own version.**

### 3.1 Register bus (exists)

No change. The 12-bit address gives each peripheral a 4 KiB window, which maps neatly
onto the SoC address map (§13.6).

### 3.2 Memory bus initiator and master adapters [NEW, critical path]

The `mem_*` bus already has the right semantics (req/gnt, rvalid, err, byte enables, full
address). Reuse it in the **initiator** direction: masters speak `mem_*`, and a new family
of adapters turns it into a protocol master port.

```
 DMA / CPU / JTAG2Bus ── mem_* ──► claude_<proto>_mst_if ──► APB4 / AHB-Lite / AXI4-Lite / WB master
 bus slave ──► claude_<proto>_mem_if ── mem_* ──► claude_<proto>_mst_if ──► other protocol
```

- `claude_apb_mst_if`, `claude_ahb_mst_if`, `claude_axi4l_mst_if`, `claude_wb_mst_if`
  (SV + VHDL), plus formal checkers that reuse the existing `claude_<proto>_fv`
  checkers in the master-side role.
- **Protocol bridges come free:** slave adapter → `mem_*` → master adapter. That gives
  4 + 4 adapters instead of 12 hand-written bridges (§10.1).
- **Burst extension (`mem_len`, `mem_burst`) [D1, decided]:** an optional `BURST_EN`
  parameter adds a beat count and INCR/WRAP type, so DMA, VGA, NPU and caches can use AHB
  INCRx and AXI4 bursts. With `BURST_EN=0` the bus is exactly today's `mem_*`.
- **Outstanding transactions:** today it is one at a time. Keep that for v1 and add an
  `MAX_OUTSTANDING` parameter later if AXI4 performance needs it.

### 3.3 Claude stream [NEW, critical path for DSP]

The data path for DSP, NPU, crypto and DMA. It is an AXI4-Stream subset with AXI4-Stream
signal names, so vendor IP, VIPs and Vivado tools can connect directly.

| Signal | Width | Required | Meaning |
|---|---|---|---|
| `tvalid` | 1 | yes | source has a sample |
| `tready` | 1 | param `HAS_READY` (default 1) | sink accepts; transfer = `tvalid & tready` |
| `tdata` | `DW` | yes | sample(s) |
| `tlast` | 1 | yes (tie 0 if unused) | last sample of a frame (FFT block, NPU tensor, packet) |
| `tuser` | `UW` (default 2) | optional | `[0]` start of frame / line (video), `[1]` saturation/overflow seen upstream |
| `tid` | `IW` | optional | channel number for time-multiplexed multi-channel data |

Rules (on top of AXI4-Stream):

1. `tvalid` never depends combinationally on `tready`. Once it is raised, `tdata`,
   `tlast`, `tuser` and `tid` stay stable until the transfer happens.
2. **Ready-less mode** (`HAS_READY=0`): for fixed-rate chains such as audio at
   48 kHz on a 100 MHz clock, `tready` is assumed to be 1. A sink that cannot keep up sets a
   sticky `overrun` status bit; it never stalls the source. This mode removes the skid-buffer
   area and the combinational ready paths.
3. **Boundary registering:** every block has `REG_IN` / `REG_OUT` parameters (0 = combinational
   pass-through, 1 = full-throughput skid buffer) so timing closure is a parameter change
   and not an RTL change.
4. **Number format (D9):** two's complement fixed point, described by `DW` and
   `FRAC_W`. **Default Q1.15** (`DW=16`, `FRAC_W=15`). Any other Q format and plain
   integer (`FRAC_W=0`, for example counts, indices, INT8 NPU data) are parameter
   choices, not RTL changes (§3.10). Complex samples are packed `{Q, I}`, with I in the
   low half. Every block documents its input and output format and its growth, rounding
   and saturation policy.
5. **Rounding / saturation primitives** live in `IP/common` (`claude_fx_round`,
   `claude_fx_sat`, §10.5), so every DSP block rounds and saturates the same way.

### 3.4 Event interface [NEW]

- One-cycle, active-high pulse, synchronous to the producer's clock.
- Crossing to another domain goes through the new lossless `claude_evt_sync` (merges close
  events, never loses one); `claude_pulse_sync` only for events known to be far apart.
- Every IP that has a natural "moment" exports it as an `evt_*_o` pulse. Every IP that
  has a natural "go" accepts an `evt_*_i` pulse. The timer's `trigger_out` is the model.
- Full rules: `.agents/IP_SPEC_event.md` (producer / consumer rules, busy policy and
  `EVT_MISS`, and the new lossless crossing cell `claude_evt_sync`, because
  `claude_pulse_sync` can lose two close events).
- The event router routes events only. Interrupts stay on the PLIC path and DMA requests on
  the DMA path, with two bridges: interrupt / DMA-request lines can be tapped as router
  inputs through edge detectors, and the router has its own `irq_o` for selected outputs
  (user 2026-11-27).

### 3.5 Standard peripheral side-band (all new register IP)

| Port | Dir | Meaning |
|---|---|---|
| `irq_o` (or `irq_o[N-1:0]`) | out | level, active high; driven from `IRQ_STATUS & IRQ_ENABLE`, W1C status |
| `dbg_freeze_i` | in | CPU is halted in debug: freeze counters and watchdogs, and keep FIFOs from changing on debugger reads |
| `idle_o` | out | no work pending, safe to gate the clock (used by the power manager) |
| `dma_tx_req_o` / `dma_rx_req_o` | out | level request (FIFO above/below its watermark) |
| `dma_tx_ack_i` / `dma_rx_ack_i` | in | one pulse per beat served; the peripheral re-evaluates its request after the ack. Used when DMA reaches the peripheral **over the system bus**; communication IP also has the back door (§6.1) |
| `s_ctl_*` / `m_ctl_*` | in/out | control stream and response stream (§3.8), present when `CTL_PORT=1` |
| `evt_*_o` / `evt_*_i` | out/in | event plane (§3.4) |

Full rules, tie-offs, port order and the standard register block (0xFC0–0xFFF of every
4 KiB window), clock gating across domains and inside one domain, and power gating with
the ARM AMBA Q-channel (`qreq_n_i`, `qaccept_n_o`, `qdeny_o`, `qactive_o`; isolation and
retention in UPF): `.agents/IP_SPEC_sideband.md`.

### 3.6 TAP test data register (TDR) port [NEW]

The JTAG TAP (§9.1) exposes one generic test data register port, `tdr_*` (`capture`, `shift`, `update`,
`tdi`, `tdo`, `sel` per instruction). These run in the TCK domain. Front ends (RISC-V DTM, JTAG2Bus, boundary
scan, MBIST) attach to these ports instead of each one embedding its own TAP.
**Must conform to IEEE 1149.1-2013 (user 2026-11-27)** and be easy to extend: special
operations are opcodes on the `jtag_ops` front end, or new instructions from the SoC YAML,
with no TAP RTL change.
Full rules: `.agents/IP_SPEC_tap_tdr.md` (signal set matching Xilinx `BSCANE2`, so
the same front ends run behind `BSCANE2` / Intel `sld_virtual_jtag` on the FPGA boards;
DMI-style 2-bit status in every DR; default 5-bit instruction map).

### 3.7 Byte command protocol engine [NEW, shared]

SPI slave-to-bus, JTAG2Bus and UART-to-bus all do the same job: turn a serial byte stream
into bus transactions. Build **one** engine, `claude_cmd2bus` (byte stream in/out →
`mem_*` initiator), and give each IP only a thin physical front end. Protocol sketch:

| Cmd | Bytes after cmd | Action |
|---|---|---|
| `0x01` WRITE | addr[4], len[1], data[4×(len+1)] | auto-incrementing word writes |
| `0x02` READ | addr[4], len[1] | returns status[1] + data[4×(len+1)] |
| `0x03` STATUS | — | busy / error / last response |
| `0x04` SET_SIZE | size[1] | byte / half / word access |
| `0x0F` NOP / sync | — | resynchronize the framing |

The response includes a status byte (OK / bus error / timeout), so a hung slave can never
lock the debugger. A bus timeout counter lives inside the engine.

The sketch above is superseded by `.agents/IP_SPEC_cmd2bus.md` (FLAGS byte, STREAM_WRITE /
STREAM_READ / CRC / POLL / CTL commands, `SOR` + trailing STATUS responses, HUNG state for
a target that never answers, extension opcodes `0x80`–`0xFF` sharing the `jtag_ops` handler
port).

### 3.8 Control stream and the second register port [NEW, critical path]

**Requirement (user, 2026-11-26):**
- Every **DSP block** can be controlled either by the regular bus (CPU) or by an internal
  streaming interface.
- Every **communication block** (SPI, I2C, UART, I2S, ...) has a **back-door DMA control
  interface**.

Both requirements are met by one mechanism, so it is designed and verified once.

**Idea:** the IP's register file stays exactly as the timer builds it. In front of it, a
shared arbiter merges two initiators onto the internal regbus:

```
 system bus ──► claude_<proto>_if ──┐  (port A: CPU / debugger, top priority)
                                    ├─► claude_regbus_arb ─► IP_regfile ─► IP_core
 ctl stream in ──► claude_ctl2reg ──┘  (port B: DMA, sequencer, upstream DSP block)
 ctl stream out ◄── (read responses, and forwarding on a ring)
```

- **`claude_ctl2reg`** converts control-stream packets into regbus writes and reads,
  and returns read data and status on the response stream.
- **`claude_regbus_arb`** gives port A (bus) absolute priority. The register bridges expect
  an answer in one cycle and have no back-pressure. The arbiter therefore never stalls the
  bus side: it drops `tready` on the control stream in any cycle the bus uses the regfile.
  **No change to the existing bridges or regfiles.**
- Every register, side effects included (W1C, read-to-pop FIFO data registers, self-clearing
  command bits), behaves the same from either port.
- An IP built without the second port (parameter `CTL_PORT=0`) is exactly today's IP.
- **Which IP has the port (D11, decided):** all DSP blocks and all communication blocks
  (default `CTL_PORT=1`), plus PWM, timer, AES and SHA-256. The **watchdog and key store
  never have it**: they have no `CTL_PORT` parameter, so it cannot be enabled. The timer
  already exists, so it gets the port as a later revision. The `CTL_PORT=0` default keeps
  today's timer unchanged.

Full, current rules (supersede the sketch below where they differ: response header, WAIT /
WAIT_EVT, broadcast, `rd_peek`, `OWNER` in the standard block at `0xFF0`):
`.agents/IP_SPEC_ctl_stream.md`.

**Control stream format** (a claude stream, §3.3, with `DW=32`, one packet per command,
`tlast` on the last word):

| Word | Bits | Field |
|---|---|---|
| 0 (header) | `[31:28]` | `CMD`: `WR`, `RD`, `WR_FIXED` (same address every beat, for FIFO data registers), `RD_FIXED`, `WR_MASK` (read-modify-write with a mask word), `WAIT` (hold until an IP condition or event), `NOP` |
| | `[27]` | `SYNC`: apply at the next data-frame boundary (DSP: the next `tlast` / start of frame on the data stream) instead of at once |
| | `[26]` | `RESP`: send a response even for writes (an acknowledgement) |
| | `[25:20]` | `DEST`: destination ID (for rings and switches; set per instance by the SoC YAML) |
| | `[19:8]` | register byte address (12 bits, the same as the regbus window) |
| | `[7:0]` | `LEN-1`: 1–256 data words |
| 1…LEN | `[31:0]` | write data (for `WR_MASK`: mask word, then data) |

The response packet is a header echo with a status code (`OK`, `BAD_ADDR`, `NOT_OWNER`,
`TIMEOUT`), followed by the read data.

**Ownership** (per IP, in the `CTRL` register reachable from both ports):
`OWNER = BUS | STREAM | SHARED` (reset: `SHARED`). A write from the non-owning port is
dropped and counted, and it returns `NOT_OWNER` on the stream side or sets a sticky status
bit on the bus side. Reads are always allowed, so the CPU can watch a DMA-driven block.
A `LOCK` bit stops software from changing the owner until the next reset.

**Topologies** (chosen in the SoC YAML):

| Topology | Use | Cost |
|---|---|---|
| Point-to-point | DMA channel ↔ one comms IP (back door) | none |
| **Ring / daisy-chain** | One control stream through a whole DSP chain. Each IP takes packets whose `DEST` matches and forwards the rest | 1 cycle per hop, one wire bundle for the whole chain |
| Through a stream switch | Run-time choice of controller | one switch port |

**Who drives port B:**
- **DMA:** descriptor type `CTL` sends a packet from memory, so whole peripheral
  sequences run with no CPU (§6.1).
- **`rv_tiny` as a sequencer:** a small core with a stream port drives a DSP chain.
- **Another DSP block:** for example an AGC or LMS block that sends gain or coefficient
  updates to the FIR it controls, with `SYNC` so the update lands on a frame boundary.
- **The NPU controller,** for its pre- and post-processing blocks.
- **The `claude_cmd2bus` hosts** (JTAG / UART / SPI) can also emit control packets, for
  bring-up without a CPU.

### 3.9 Design-for-test conventions (every IP) [D7, decided]

Goal: synthesizing any SoC built from this library gives **scan flops, scan chains and
a JTAG chain** (TAP + boundary scan + test-mode control) with no RTL change to any IP.
**Applied to the agent flow on 2026-11-26:** `.agents/Claude_IP.md` ("Design-for-Test
Rule"), `rtl.md` §4c, `lint.md` item 7, `synthesis.md` (DC `dft_drc`, functional STA with
the test ports at 0), `directed_tests.md` and `uvm.md` (benches tie the ports to 0). The
rules apply to every new IP from its first RTL. Existing IP (timer, sram, bus_matrix) is
retrofitted in a later revision, with its csun.edu re-runs.

**Ports on every IP top (all protocol variants):**

| Port | Dir | Meaning |
|---|---|---|
| `test_mode_i` | in | 1 = chip in scan / ATPG test mode (static for the whole test) |
| `scan_en_i` | in | 1 = shift, 0 = capture (dynamic, only meaningful while `test_mode_i` = 1) |

In functional use and on FPGA both are tied 0, and synthesis removes the logic. Scan
chains themselves (`scan_in` / `scan_out`) are **not** RTL ports: DFT Compiler stitches
them at SoC level.

**RTL rules that make the design scan-insertable (checked in lint / SpyGlass DFT):**

1. Every flop is on a clock that a top-level test clock can control. Clock cells
   (`claude_clk_gate`, `claude_clk_mux2`, `claude_clk_div`, §10.3) have a test input:
   gates are forced on (`TE = scan_en_i | test_mode_i`), muxes select the test clock and
   dividers bypass to the source clock while `test_mode_i` = 1.
2. Resets are controllable in test mode: `reset_ctrl` forces resets to the inactive
   state (or to the scan-controlled reset pin) while `test_mode_i` = 1. Internally generated
   resets (watchdog, soft reset, `ndmreset`) are blocked in test mode.
3. No combinational loops, no latches outside the clock-gate cells, and no flops clocked by
   data signals.
4. Ring oscillators (TRNG), and anything else self-timed, are stopped in test mode.
5. Memories (sram macros, register-file RAMs) are tested by MBIST (§9), and wrapped in
   test mode with bypass or observation flops so that the surrounding logic stays
   ATPG-testable.
6. CDC synchronizers stay normal flops, scanned like the rest (all clocks are the test
   clock during shift).
7. Security IP: scan must not leak keys. The key store and AES key registers are reset or
   zeroized on entry to test mode (the lifecycle controller, §11, can also forbid test mode
   in production).

**SoC level:**

- The `jtag_tap` (§9) gets standard 1149.1 instructions (BYPASS, SAMPLE, PRELOAD, EXTEST
  mandatory; IDCODE, CLAMP, HIGHZ) plus private ones: `TEST_CTRL` (drives `test_mode_i`),
  `MBIST`, `OPS`, and the RISC-V DTM and jtag2bus test data registers (`IP_SPEC_tap_tdr.md`).
- **Boundary scan** cells are generated from the SoC's pad list (YAML) with a BSDL file,
  and the chain is TDI → boundary register → TDO through the TAP.
- The SoC generator (§4) routes `test_mode_i` and `scan_en_i` to every instance and
  reserves scan-in / scan-out pins (muxed onto functional pins in test mode).
- The csun.edu synthesis step gains a DFT stage: DFT Compiler scan insertion (with
  optional compression), then TestMAX ATPG with stuck-at and transition coverage targets,
  then gate-level simulation of the ATPG patterns.

### 3.10 Number formats and golden models for math IP [D9, decided]

**Formats.** Every math IP (all DSP blocks, PID, CORDIC, NCO, div/sqrt, mag_log, stats,
the NPU) takes its numeric format from parameters:

| Parameter | Meaning | Default |
|---|---|---|
| `DW` | input/output sample width | 16 |
| `FRAC_W` | fractional bits; `0` = plain integer | 15 (Q1.15) |
| `COEF_W` / `COEF_FRAC_W` | coefficient format | 16 / 15 (or a wider format where the block's spec says so, for example biquad Q2.30) |
| `ACC_W` | accumulator width (guard bits) | sized so the default cannot overflow internally |
| `ROUND` | `TRUNC`, `ZERO`, `HALF_UP`, `HALF_AWAY` (TFLite), `CONVERGENT` (round half to even, PyTorch) | `CONVERGENT` |
| `SAT` | wrap (0), saturate (1), symmetric saturate (2) at each quantization point | 1 |
| `SIGNED` | signed (1) or unsigned (0), for integer use | 1 |

The same RTL serves Q1.15 audio, other Q formats (for example Q1.23 or 18/25-bit for DSP48
use) and integer pipelines. Every block's spec gives the supported range of each parameter,
and the regression runs every named format the block supports plus custom ones.
**Required named formats (user 2026-11-27):** uint8, sint8, uint16, sint16, uint32, sint32,
q1.15, q1.31, q16.16, and custom sizes (any width 2–64, any fractional bits), including
operations that mix formats.
Exact definitions of formats, `convert` (align → round → saturate) and every mode, shared by
RTL, Python and C: `.agents/IP_SPEC_fx.md`.

**Golden models (mandatory for every math IP):**

- Every math IP ships `verification/model/<ip>_model.py`: an **accurate, quantized,
  bit-exact** Python model that takes the same parameters as the RTL (formats, rounding,
  saturation, `CYCLES_PER_SAMPLE`-independent results).
- All models are built on one shared fixed-point package,
  `IP/common/verification/tools/claude_fx.py` (quantize, round, saturate, multiply,
  accumulate, with the same modes as the RTL primitives `claude_fx_*`). It is verified once
  against the RTL primitives, so a rounding difference cannot hide in one IP.
- Each model also has a floating-point reference path. Tests report SQNR / maximum error
  against float, so the quantized design is shown to be *accurate*, not only to match
  itself.
- The model is the single reference for: directed-test vectors and expected results, UVM
  scoreboards (through files or DPI), the regression, and the firmware examples. The match
  criterion is **bit-exact** (zero LSB difference) unless the block's spec documents
  otherwise.
- Chains: the SoC generator builds a chain model from the per-block models, so a whole
  YAML chain (§5) can be checked end to end.
- Chains may quantize at every block or let precision grow and quantize once: links can be
  `fmt: auto` (lossless width from each model's `out_fmt`, optional `max_w` cap), are
  reported per link (SQNR, error, headroom, what-if width sweeps), and can be marked
  `lossless: true` (static and run-time checks) — `.agents/IP_SPEC_fx.md` (user 2026-11-27).
- The NPU model is checked against **both TFLite and PyTorch** quantized references for
  each layer and for whole models, so the RTL, the Python model and both frameworks agree
  (§8.1).
- Floating-point and block-scaled formats (`fp64` … `fp4_e2m1`, `e8m0`, MX, NVFP4), with
  rounding (including stochastic), overflow / NaN / subnormal rules, are defined once in
  `.agents/IP_SPEC_float_formats.md` (user 2026-11-27); 4-bit integers, the TFLite 16x8
  mode and G.711 companding are in `.agents/IP_SPEC_fx.md`.
- The FPU (§8.2) is floating point: its golden model is Berkeley SoftFloat (bit-exact
  results and flags), with TestFloat vectors, instead of `claude_fx.py`.
- Crypto IP (AES, SHA-256, DRBG) is exact by nature. It is checked against NIST test
  vectors and a Python reference (`hashlib` / `cryptography`) the same way.

---

## 4. System conventions for SoC assembly

- **Specs (user 2026-11-27):** the SoC description and generator outputs, including a
  **devicetree** (`soc.dts`) for Zephyr, are in `.agents/IP_SPEC_soc_yaml.md`; per-IP metadata
  (`<ip>.ip.yaml`) in `.agents/IP_SPEC_ip_meta.md`; resets in `.agents/IP_SPEC_reset.md`.
- **One SoC = one generated top.** A Python generator (`SoC/tools/gen_soc.py`, later work)
  reads a YAML description: masters, slaves, address map, IRQ numbers, stream routes and
  event routes. It emits an SV and a VHDL top, a C `soc.h` (base addresses and IRQ
  numbers), a linker script and a SystemRDL "address map of address maps". That
  keeps RTL, firmware and documentation from drifting apart.
- **Firmware:** every driver already takes `uintptr_t base`. `soc.h` supplies the bases.
  Drivers stay SoC-independent.
- **Interrupt numbering, address windows and stream port numbers** are assigned only in
  the SoC YAML, never inside an IP.
- **Clocks:** each SoC declares its domains (for example `sys`, `periph`, `pix`, `tck`,
  `lfo`). Each IP lists the domains it needs. Every crossing uses common CDC cells.

---

## 5. The signal-processing chain

### 5.1 Goal

Connect any set of math blocks (CIC, FIR, IIR, FFT, CORDIC, PID, NPU, AES, ...) in any
order, change the order at run time where needed, and add almost no delay: **zero or one
clock per hop plus the block's own algorithmic latency**, with no CPU or memory in the
data path.

### 5.2 Options compared

| Approach | Added latency per stage | Bus load | Flexibility | Verdict |
|---|---|---|---|---|
| CPU moves samples | µs (IRQ + load/store) | high | total | debug only |
| DMA through memory (ping-pong buffers) | ≥ 1 frame + bus contention | 2 bus beats per sample per stage | high | use for frame-based NPU input and for capture |
| Static wired chain (generated) | 0 cycles (or 1 with `REG_OUT`) | none | fixed at elaboration | best for products |
| **Stream switch** (run-time routing) | 1 cycle per switch hop (0 if combinational) | none | high | **default for dev SoCs** |

Recommendation: **support both static and switched**, using the same block wrappers.
A YAML chain description produces either a hard-wired chain or a switch-based
cluster. A product can freeze the routes it has proven.

### 5.3 Building blocks

**`claude_dsp_shell` (common wrapper for every streaming math block)**

```
     system bus (claude_<proto>_if)      ctl stream in / out (§3.8)
                   │                          │
                   └──► claude_regbus_arb ◄── claude_ctl2reg ──► ctl out (resp / ring)
                              │
   ┌──────────────────────────▼─────────────────────────────┐
   │ CTRL: enable, bypass, flush, coef bank select           │
   │ STATUS: overrun, saturation count, busy, frame count    │
   │ COEF window (double-buffered; swap at tlast)            │
   │                                                         │
s ─┼─► [REG_IN skid] ─► [opt. FIFO] ─► KERNEL ─► [REG_OUT] ─┼─► m
   │        └──────────── bypass mux (0-cycle) ────────┘     │
   │ s = s_data_* (in), m = m_data_* (out)                   │
   │ evt_frame_o, irq_o                                      │
   └─────────────────────────────────────────────────────────┘
```

- **Two control paths (requirement):** the CPU over the system bus, or the control stream
  (§3.8), selected by `OWNER`. Every DSP block is built with `CTL_PORT=1` by default.
  Control-stream writes with `SYNC` set take effect at the next data-frame boundary, so a
  sequencer can retune a filter exactly between frames. This ties in with the
  double-buffered coefficients below.
- **Operated by the stream, configured by the bus (requirement, user 2026-11-26):** every
  streaming block has a register-bus slave holding all of its configuration; the data
  stream carries only samples and runs the block once it is enabled. The control stream is
  only an alternate path into the same registers (`.agents/IP_SPEC_stream.md`), and it
  stays optional (`CTL_PORT`).
- **Bus operation mode (requirement, user 2026-11-26):** the CPU can also run a block's
  math over the bus. `SRC_SEL` / `DST_SEL` switch the kernel's input to a `DIN` register
  and its output to a `DOUT` register, through small FIFOs with overflow / underflow flags
  and IRQs. The results are bit-exact with stream mode (`BUS_PORT`, default 1;
  `.agents/IP_SPEC_stream.md`).
- **One stream in, one stream out (requirement, user 2026-11-26):** every streaming block
  receives on `s_data_*` and drives its result on a separate `m_data_*`, so blocks chain
  output-to-input with no glue. Input and output formats are separate parameters (`S_*` /
  `M_*`) and the generator checks each link (`.agents/IP_SPEC_stream.md`).
- The **kernel** is the only block-specific part (FIR MAC array, FFT butterflies, ...). Its
  ports are the stream in, the stream out, the coefficient read port and the status bits.
- **Double-buffered coefficients**: software writes the shadow bank, and the swap happens
  at the next `tlast`, or at once if no frame is in progress. Filters change without
  glitches.
- **Bypass** removes a stage without re-routing, which is useful for A/B tests.
- **Statistics** (sample count, peak |x|, saturation count) are optional and set by
  parameter.

**`claude_stream_switch` [NEW, IP/interface]**

- `N_IN × N_OUT` with parameter `DW`. Each output has a route register `SRC_SEL` (an input
  number, or "none").
- **Fan-out:** one input may feed several outputs. Its `tready` is the AND of the
  selected outputs' `tready`, and a ready-less mode is available.
- **Safe re-route:** a new route takes effect only at a frame boundary (after a
  `tlast` transfer) or when the input is idle. The `ROUTE_PENDING` status shows when a
  route has not taken effect yet.
- `LATENCY` parameter, 0 or 1 (1 = registered, for timing).
- Taps: any output can go to a DMA S2MM channel, so a debugger can capture any point
  in the chain into SRAM.
- Clusters can be chained (switch → switch) for large SoCs.

**Multi-rate**

- A decimator outputs `tvalid` at 1/R of its input rate. Downstream blocks run whenever
  `tvalid` is high, so **no extra clock domain is needed**. Time-multiplexed kernels
  (serial-MAC FIR, single-MAC biquad cascade) use the idle cycles between samples.
  This is the main area-saving technique: a parameter `CYCLES_PER_SAMPLE` lets the
  generator choose a serial, semi-parallel or fully parallel kernel.
- **Multi-channel** (for example 8 microphones) uses `tid`, so one kernel can serve
  every channel with a per-channel state RAM.

**Sources and sinks for the chain**

| Source | Sink |
|---|---|
| PDM microphone interface [NEW], I2S RX [NEW], SPI ADC sequencer [NEW] | I2S TX [NEW], PWM / sigma-delta DAC [NEW] |
| DMA MM2S (memory → stream) | DMA S2MM (stream → memory) |
| CPU stream FIFO port (register access, for test) | CPU stream FIFO port |
| NCO / test-tone generator [NEW] | NPU input |

### 5.4 Example chains

**Audio / keyword spotting (16 kHz output)**

```
PDM mic 3.072 MHz ─► CIC ↓48 ─► halfband ↓2 ─► FIR comp ─► IIR EQ ─► FFT 512 ─► |x|² + log ─► NPU (KWS)
                                                       └──► switch tap ─► DMA S2MM (capture)
```

**Software-defined radio receiver (DDC)**

```
ADC 14-bit ─► mixer (×NCO / CORDIC) ─► CIC ↓R (I/Q) ─► FIR ↓2 ─► FFT ─► DMA ─► CPU / NPU
```

**Hardware motor-control loop (no CPU in the loop)**

```
PWM.evt_center ─► event router ─► SPI ADC seq.start ─► stream ─► PID ─► PWM.duty (direct port)
                                           QEI position ──────┘
```

### 5.5 Latency budget (targets for each block's spec)

| Block | Algorithmic latency | Shell overhead |
|---|---|---|
| Stream switch hop | — | 0 or 1 cycle |
| FIR, N taps, fully parallel | N/2 samples (linear phase) + pipeline ≈ log2 N cycles | 0–2 cycles |
| IIR biquad, per section | 0 samples + 3–5 cycle MAC pipeline | 0–2 cycles |
| CIC | R × M / 2 samples (group delay) | 0–2 cycles |
| FFT (streaming R2²SDF) | N samples + pipeline | 0–2 cycles |
| CORDIC | ITER cycles (pipelined, 1 sample/clk) | 0–2 cycles |
| PID | 3–6 cycles | 0–2 cycles |

---

## 6. Communication IP (`IP/communication/`)

| Block | Size | Key features |
|---|---|---|
| **spi_master** | M | CPOL/CPHA modes 0–3; 4–32-bit frames; MSB/LSB first; 1–8 chip selects with set-up/hold/idle timing; fractional SCK divider; TX/RX FIFOs (param depth); DMA req/ack; dual/quad SPI data lanes (param); RX sample-delay tuning for long board traces; loopback |
| **spi_slave** (to bus master) | M | SCK-domain shift register + async FIFOs into `claude_cmd2bus` (§3.7); modes 0–3; SCK up to sys/4 (oversampled option) or full-speed SCK-domain front end; status / interrupt pin to the external host; optional simple mailbox mode with no bus master |
| **i2c_master** | M | Standard / Fast / Fast+ (100 k / 400 k / 1 M); 7- and 10-bit addresses; repeated START; clock stretching; multi-master arbitration-loss detection; command FIFO (START / WRITE / READ / ACK / STOP) so whole transactions run without the CPU; SDA/SCL glitch filter; SMBus timeouts (param); open-drain `_o/_oe` pads; bus-clear (9 clocks) |
| **uart16550** | M | Register-compatible with the 16550 (8-bit registers, `REG_STRIDE` 1 or 4); 16-entry FIFOs (param up to 256, 16750-style); DLL/DLM + fractional divisor (param); 5–8 data bits, parity, 1/1.5/2 stop bits; break; modem lines; auto RTS/CTS; TXRDY/RXRDY DMA modes 0 and 1 mapped to §3.5; RX timeout interrupt; standard Linux/Zephyr `ns16550` drivers must work unchanged |
| **i2c_slave** [NEW] | S–M | 7-bit address (programmable + mask); register-bank mode, or bus master through `claude_cmd2bus`; clock stretching; general call |
| **uart2bus** [NEW] | S | UART PHY + `claude_cmd2bus`: a debug back door that needs only two pins |
| **i2s** [NEW] | M | TX + RX; master or slave clocks; I2S / left-justified / TDM modes; 16–32-bit; claude stream ports (feeds the DSP chain); MCLK from the clock divider |
| **pdm_rx** [NEW] | S | 1–8 PDM microphones (stereo pairs on rising/falling edges); stream out to CIC |
| **qspi_xip** [NEW] | L | Execute-in-place flash controller: memory-mapped read through `mem_*` target, small read cache/prefetch, command-mode registers for program/erase, SPI / dual / quad / (octal later). **Without it a CPU SoC must boot from SRAM preloaded by JTAG** |
| **can** [NEW, later] | L | CAN 2.0B (and FD later). Optional; mention only for industrial and automotive SoCs |

Common needs: FIFOs (§10.4), fractional clock enables (§10.3), DMA handshake (§3.5),
the DMA back door (§6.1), glitch filters and synchronizers on every pad input.

### 6.1 DMA back door (every communication block) [requirement]

Every communication IP (spi_master, spi_slave in mailbox mode, i2c_master, i2c_slave,
uart16550, i2s, pdm_rx, qspi_xip command mode, can) has a **back-door port** that a DMA
channel connects to directly, bypassing the system bus:

```
                         ┌────────────────── comms IP ───────────────────┐
 system bus ─► _if ─────►│ regbus arb ─► regfile ─► core ─► pins         │
 DMA ctl ch ─► ctl2reg ─►│    ▲ (port B: control / command)              │
 DMA ◄─ ctl resp ◄───────│                                               │
 DMA MM2S ─► tx stream ─►│──► TX FIFO ─► shifter                         │
 DMA S2MM ◄─ rx stream ◄─│◄── RX FIFO ◄─ shifter                         │
                         │ evt_done_o / evt_err_o ─► DMA (descriptor WAIT)│
                         └───────────────────────────────────────────────┘
```

| Part | What it does |
|---|---|
| **Control** (`s_ctl_*` / `m_ctl_*`) | §3.8 port B. DMA writes the same registers the CPU would: SPI chip select, frame length and mode; I2C target address and command FIFO; UART baud and line control. Ownership rules apply |
| **TX data stream** (`s_tx_*`) | Claude stream straight into the TX FIFO. The FIFO's free space is the `tready`, so no req/ack handshake and no bus beat per byte |
| **RX data stream** (`m_rx_*`) | Claude stream straight out of the RX FIFO. `tlast` marks the end of a transaction (SPI CS de-assert, I2C STOP, UART RX timeout / idle line) |
| **Events** | `evt_done_o`, `evt_err_o` (NACK, arbitration lost, parity / framing error, overrun) for the DMA's `WAIT` descriptor and the event router |
| **Data-width packing** | `PACK` parameter: 8/16/32-bit stream words packed or unpacked to the frame width (for example 4 UART bytes per 32-bit word), so DMA moves words |
| **Arbitration with the bus path** | The TX FIFO is fed by the stream port or by the bus data register. Writes through both at once are a configuration error (sticky status), selected by `CTRL.DATA_SRC` |

A whole transaction then runs as one DMA descriptor list, with no CPU:

```
CTL  spi.CS=1, LEN=64, MODE=0      ; configure through port B
MM2S buffer_tx, 64 B  ─► spi.tx    ; data straight into the FIFO
S2MM spi.rx ─► buffer_rx, 64 B     ; data straight out of the FIFO
WAIT spi.evt_done
CTL  spi.CS=0
IRQ                                 ; only now tell the CPU
```

The bus-side DMA handshake (§3.5) stays, so a plain bus-attached DMA (or a third-party
one) still works. The back door is the low-latency, low-bus-load path.

---

## 7. System / control IP (`IP/system/`)

| Block | Size | Key features |
|---|---|---|
| **gpio** | S | N pins (1–32 per instance); DIR / OUT / IN; atomic SET / CLR / TOGGLE registers; 2-flop input sync; per-pin IRQ (rising / falling / both / high / low); debounce (param counter, shared tick); open-drain emulation; `evt_pin_o` to the event router; output-enable per pin for the pad ring |
| **pwm** | M | N channels; edge-aligned or center-aligned counter; per-channel duty and phase; shadow registers loaded at period end (glitch-free); complementary outputs with dead-time insertion; fault/kill input (asynchronous, latched, forces a safe state); `evt_period_o` / `evt_center_o` for ADC sync; direct duty input port so a PID can drive it with no bus; master/slave sync across instances; **Control-stream port (§3.8, D11)** for DMA- or sequencer-driven set-up. |
| **pid** | M | Fixed-point Kp/Ki/Kd (Q format param); setpoint, feed-forward; integrator anti-windup (clamp + back-calculation); output saturation and rate limit; first-order derivative filter; claude stream or register input; direct output port (for example to `pwm.duty`); steps on `evt_step_i`; N channels time-multiplexed on one MAC; bit-exact Python model |
| **watchdog** | S | Independent clock (LFO domain, crossing to the bus clock); windowed mode (too-early kick is also a fault); unlock key sequence for writes; early-warning IRQ before reset; reset output to the reset controller; lock bit (sticky until reset); `dbg_freeze_i`; reset-cause flag; **No control-stream port, ever (D11):** only the CPU on the bus may kick or configure it. |
| **irq_ctrl** | M | **RISC-V PLIC-compatible register layout** (decision D4): 1–1023 sources; per-source priority, pending, enable; per-target threshold and claim/complete; level and edge sources (edge is captured); N targets (harts / contexts). Optional **CLIC-lite** for the small core (vectored, nesting); compatible with the `sifive,plic-1.0.0` / `riscv,plic0` device-tree bindings so RTOS drivers work unchanged (§12.1) |
| **clint** [NEW] | S | RISC-V `mtime` / `mtimecmp` / `msip`; `mtime` ticks from a clock enable so its rate is stable while the core clock changes. Needed by every RISC-V OS; **SiFive-CLINT-compatible layout** (`msip` 0x0000, `mtimecmp` 0x4000, `mtime` 0xBFF8; one `msip` / `mtimecmp` per hart) so the stock FreeRTOS and Zephyr drivers work unchanged (§12.1); `mtime` can run on the always-on clock while the core clock is gated (tickless idle) |
| **dma** | L | 1–16 channels; mem→mem, mem→periph, periph→mem, **mem→stream (MM2S), stream→mem (S2MM)**; linked-list descriptors in memory (scatter-gather); **2-D transfers** (count, stride) for VGA, image and NPU tiles; fixed / increment address per side; byte / half / word / burst; circular mode with half-complete IRQ (audio ping-pong); peripheral req/ack per channel (§3.5) or event trigger; priority + round-robin arbitration; error reporting with the faulting address. **Back-door ports (§6.1):** per channel, optional direct stream ports to one peripheral (TX/RX data) and a control-stream port; descriptor types `MOVE`, `CTL` (send a control packet, optionally capture the response to memory), `WAIT` (event / peripheral done, with timeout), `IRQ`, `JUMP` (loops). Master: `mem_*` initiator + `claude_<proto>_mst_if`; slave: regbus |
| **syscon** [NEW] | S | Chip ID / version, boot-mode straps, scratch registers, software reset request, pad-mux / alternate-function select (or a separate **pinmux**), clock-gate enables. Every SoC needs one place for these |
| **reset_ctrl** [NEW] | S | (`.agents/IP_SPEC_reset.md`) Power-on, external pin, watchdog, software and debug resets → per-domain resets with sequencing (release memories, then interconnect, then CPU); async assert / sync de-assert in each domain; reset-cause register |
| **rtc** [NEW] | S | 32.768 kHz domain; seconds counter + alarm; wakes the system from deep sleep |
| **mailbox / hw_semaphore** [NEW] | S | For multi-core SoCs (small core + big core, or CPU + NPU controller): message FIFOs with doorbell IRQs, and atomic test-and-set locks |
| **qei** [NEW] | S | Quadrature encoder: A/B/index, filtered, 32-bit position, velocity capture; pairs with PID and PWM for motor control |
| **adc_seq** [NEW] | M | Sequencer for external SPI ADCs (or a hard ADC macro): conversion on `evt_start_i`, channel list, results to a stream or FIFO |
| **video / vga** | M–L | Programmable timing (h/v front porch, sync, back porch, polarity), so VGA → 720p is a register change; pixel-clock domain with an async FIFO; framebuffer fetch through `mem_*` master with 2-D addressing; RGB332 / RGB565 / RGB888 / 8-bit palette (LUT RAM); text mode with font ROM (param); hardware cursor / one sprite (param); vsync IRQ + event; double-buffer swap at vsync; underflow status |

---

## 8. Math / DSP / NPU (`IP/DSP/`)

All DSP blocks use `claude_dsp_shell` (§5.3) and the claude stream (§3.3). They default
to **Q1.15**, can be set to any other Q format or to plain integer, and each has an
**accurate, quantized, bit-exact Python golden model** that the directed tests, UVM
scoreboards and regression check against (§3.10). Every block has `CYCLES_PER_SAMPLE` (area vs throughput)
and real/complex options where they make sense.

| Block | Size | Key features |
|---|---|---|
| **fir** | M | 1–1024 taps; direct, transposed or systolic (param); symmetric-coefficient folding; serial / semi-parallel / parallel MAC via `CYCLES_PER_SAMPLE`; polyphase decimate-by-D / interpolate-by-L; multi-channel via `tid`; reloadable double-buffered coefficient RAM; complex data or complex coefficients (param) |
| **iir_biquad** | M | Cascade of 1–16 sections; transposed direct form II (default) or DF-I (param, better for fixed point); Q2.30-style coefficients; per-section output scaling; saturation with sticky flag (never wrap in the loop, fx R1); `STATE_ROUND` and first-order error feedback `ERR_FB` against limit cycles (fx R2); coefficients from `claude_fx.coef` (stability check, ordering, scaling); single time-multiplexed MAC for low rate; multi-channel state RAM |
| **fft** | L | Streaming R2²SDF pipeline (1 sample/clk) and a memory-based radix-2/4 option (small area); N = 16…4096 (max at elaboration, smaller sizes set at run time); forward / inverse; block-floating-point or fixed scaling schedule (exponent in `tuser`); natural or bit-reversed output order; optional window multiply on the input (window ROM/RAM) |
| **decimator family** | M | **CIC** decimator / interpolator (order 1–6, R 2…4096 programmable, M 1–2, Hogenauer pruning); **halfband** FIR ↓2/↑2; **CIC compensation** FIR (preset from a Python design tool); generic integer resampler built from the polyphase FIR |
| **cordic** [NEW] | M | Rotation and vectoring modes: sin/cos, atan2, magnitude, phase, polar↔rectangular; pipelined or iterative; the base for NCO, mixer, FM demodulation and the FFT's magnitude stage |
| **nco / dds** [NEW] | S | Phase accumulator + LUT or CORDIC; frequency / phase registers; dithering; quadrature output; test-tone source for every DSP bench |
| **mixer / ddc** [NEW] | S | Complex multiply with an NCO; building block for a digital down-converter |
| **mag_log** [NEW] | S | |x|, |x|², log2/dB (LUT + interpolation); post-FFT feature extraction for the NPU (mel energies) |
| **g711** [NEW] | S | `claude_g711`: G.711 μ-law / A-law ↔ `sint16` / `q1.15` stream converter (both directions, per ITU-T G.711), for telephony codecs at the edge of an audio chain; golden model = the G.711 tables |
| **moving_avg / stats** [NEW] | S | Boxcar/CIC smoothing, min/max/mean/RMS over a window; peak detect |
| **fx_lib** [NEW, `IP/common`] | S | Rounding (truncate, half-up, convergent), saturation, multiply-with-rounding, leading-zero count. Every DSP block uses these, so they are verified once |
| **div / sqrt** [NEW] | S–M | Pipelined or iterative integer and fixed-point divider and square root, exactly defined by fx R6 (correct rounding per `ROUND`, `DZ_MODE` = `SAT` or `RISCV`); needed by PID, normalization and CORDIC gain correction |
| **npu** | XL | See §8.1 |
| **fpu** [NEW] | M–L | IEEE 754 single and double precision; CPU (RISC-V F/D), stream and bus/control-stream attachments. See §8.2 |

### 8.1 NPU (staged; the largest block in this plan)

Target: **quantized INT8 TinyML inference** (keyword spotting, small CNN vision,
anomaly detection), in a size that still fits the Zynq-7010 (80 DSP48, 60 BRAM36) in its
smallest configuration and grows for ASIC.

```
                    regbus (control, status, perf counters)
                         │
 cmd queue (descriptors) ▼
 ┌──────────────────────────────────────────────────────────────────────┐
 │ CONTROLLER: fetch descriptor ─► program DMA + compute ─► sync ─► IRQ │
 │                                                                      │
 │  mem_* master ─► NPU DMA (2-D/3-D tiles) ─► SCRATCHPAD (sram IP, banked,│
 │                                           double-buffered A/B)       │
 │                                                │                     │
 │                         ┌──────────────────────▼─────────────┐       │
 │  claude stream in ─────►│ PE ARRAY  R × C INT8 MAC, INT32 acc │       │
 │                         │ (weight-stationary systolic)        │       │
 │                         └──────────────────────┬─────────────┘       │
 │                         POST: bias, requant (scale, shift, zero-point),│
 │                         ReLU/ReLU6/LUT activation, pooling          ─┼─► claude stream out
 └──────────────────────────────────────────────────────────────────────┘
```

| Stage | Scope | Why this order |
|---|---|---|
| **NPU-0 "vector MAC"** | INT8 dot products / 1-D convolution over two streams, INT32 accumulate, requantize. Register driven | Proves the arithmetic, quantization model and Python bit-exact flow cheaply |
| **NPU-1 "GEMM"** | R×C systolic array (param 4×4 … 32×32), scratchpad, tiled matrix multiply, descriptor queue | Fully connected and 1×1 convolution layers |
| **NPU-2 "CNN"** | Conv2D (im2col in the DMA address generator), depthwise conv, pooling, activation LUT, layer fusion | Real CNN models |
| **NPU-3 "more integer"** | **TFLite 16x8** (`sint16` activations × `sint8` weights, `sint64` accumulators), **int4 weights** (`sint4` / `uint4`, packed, group scales), sparsity skip, CPU coprocessor port (§12) | Audio / speech accuracy (16x8); half the weight memory (int4) |
| **NPU-4 "float"** | **`bf16`** activations / weights with `fp32` accumulation, then **`fp8_e4m3` / `fp8_e5m2`** and the **OCP MX** formats (`mxfp8`, `mxfp6`, `mxfp4`, `mxint8`), then `nvfp4`; block-scale units (`claude_mx_quant` / `_dequant`) in the DMA / post-processing path | Models exported in float or low-precision float; checked against PyTorch dtypes, `ml_dtypes` and the OCP MX reference (`IP_SPEC_float_formats.md`, user 2026-11-27) |

Software (planned alongside the RTL, under `IP/DSP/npu/firmware` + `tools/`):
a Python compiler with **two front ends**, **TFLite** (int8 `.tflite`) and **PyTorch**
(a quantized model from `torch.export` / PT2E quantization, or eager-mode
`torch.ao.quantization`). Both lower to one internal graph, then emit a descriptor list,
a weight blob and a C runtime. The same descriptors drive the Python golden model.

**The two frameworks quantize differently, so the NPU has to support both exactly:**

| Difference | TFLite | PyTorch | NPU support |
|---|---|---|---|
| Requantization | int32 multiplier + shift, rounding doubling high multiply, then rounding divide by a power of two | fp32 scale multiply, then round half to even | **`REQUANT_MODE` register per layer:** `TFLITE` (integer multiplier/shift) or `TORCH` (a small fp32-scale multiply + round-half-even unit in the post-processing stage, one per output lane or shared) |
| Activation type | int8, asymmetric (zero point) | often uint8 (`quint8`) with a zero point, or int8 | signed and unsigned 8-bit activations, per-tensor zero point |
| Weights | int8 symmetric, per-channel | int8 symmetric, per-channel or per-tensor | per-channel and per-tensor scales |
| Tensor layout | NHWC | NCHW | the compiler converts; the DMA's 2-D/3-D addressing handles either layout |
| Fused activations | ReLU / ReLU6 folded into clamping | ReLU fused, hardswish / hardsigmoid common | clamp + activation LUT (covers hardswish / hardsigmoid) |

**Checking (three-way, per layer and per whole model):**

1. RTL ↔ Python golden model: **bit-exact**, always.
2. Python golden model ↔ **TFLite** interpreter (reference kernels, not XNNPACK, whose
   rounding can differ): **bit-exact** in `TFLITE` mode.
3. Python golden model ↔ **PyTorch** quantized reference (the same backend that was used
   to quantize, for example `qnnpack` / `x86` / the PT2E reference decomposition):
   **bit-exact** in `TORCH` mode. If a backend has a documented non-determinism (for
   example a fused kernel), the difference is limited to ≤ 1 LSB on a reported fraction of
   outputs, and each such case is listed in the NPU's known-issues file.
4. End to end: the top-1 / accuracy metric on a reference dataset is identical to the
   framework's quantized model, and within a documented tolerance of the float model.

Reference models in the NPU regression: one keyword-spotting model (for example DS-CNN), one
small image model (for example a MobileNet-style or ResNet-8 network) and one MLP, each
exported from **both** TFLite and PyTorch.

### 8.2 FPU: single and double precision [NEW]

One shared arithmetic core, `fpu_core`, with three ways to attach it. All three use the
same verified datapath.

| Attachment | Top | Use |
|---|---|---|
| **CPU** | `fpu_rv` | RISC-V **F** and **D** extensions for rv_core: 32 × 64-bit FP register file (`FLEN` = 32 or 64 by parameter), `fcsr` (`frm`, `fflags`), FP loads/stores through the core's LSU, attached through the coprocessor port (§12). Optional **Zfinx / Zdinx** (FP in the integer registers, no FP register file) for rv_tiny |
| **Stream** | `fpu_stream` (inside `claude_dsp_shell`) | `fp32` / `fp64` / `fp16` / `bf16` / `fp8` samples in the DSP chain (stream `FLT` parameter): elementwise ops between two streams, scaling, multiply-accumulate, and **int / Q-format ↔ float converters**, so a chain can switch between fixed point and float (for example a float FFT stage or float post-processing ahead of the CPU) |
| **Peripheral** | `fpu_reg` | Register / control-stream (§3.8) operand-and-result interface for SoCs whose CPU has no F/D, and for DMA-driven batches |

**Features (`fpu_core`):**

| Feature | Detail |
|---|---|
| Precision | `PRECISION` = `SP`, `DP` or `SP_DP` (double datapath that also does single, NaN-boxed per the RISC-V spec); **`HAS_FP16`** (`fp16`: `Zfh` full arithmetic or `Zfhmin` load / store / convert, by parameter) and **`HAS_BF16`** (`bf16` conversions, `Zfbfmin`), user 2026-11-27; formats and rules in `.agents/IP_SPEC_float_formats.md` |
| Operations | add, sub, mul, **fused multiply-add** (fmadd / fmsub / fnmadd / fnmsub), div, sqrt, min / max (IEEE 754-2019 `minimumNumber` / `maximumNumber` as RISC-V requires), compare (eq / lt / le), classify, sign inject, int32 / uint32 / int64 / uint64 ↔ float conversions, SP ↔ DP conversion |
| Rounding | all five IEEE 754 modes: RNE, RTZ, RDN, RUP, RMM; dynamic (`frm`) or static per instruction |
| Exceptions | the five IEEE flags (NV, DZ, OF, UF, NX), sticky, in `fcsr` / a status register; no traps (RISC-V style) |
| Special values | full subnormal support (default) or flush-to-zero (`FTZ` parameter, smaller and faster); canonical quiet NaN as RISC-V requires |
| Micro-architecture | add / mul / FMA pipelined (`PIPE_STAGES` parameter, 1 result per clock); divide and sqrt iterative (radix-4 SRT or Newton-Raphson on the FMA, by parameter) with a `busy` handshake; ops can be removed by parameter (`HAS_DIV`, `HAS_SQRT`, `HAS_FMA`) to save area |
| FPGA mapping | multipliers infer onto DSP48 / variable-precision DSP blocks. Rough size: SP FMA about 2–4 DSP48 and 1.5–3 k LUT; DP FMA about 10–20 DSP48 and 5–10 k LUT. **Default `PRECISION=SP` (D13)**; `DP` / `SP_DP` targets the DE0-Nano-SoC and ASIC |
| DFT, languages | the §3.9 test ports and rules; SV and VHDL-2008 (D3) |

**Verification (the golden-model rule, §3.10, applied to floating point):**

- Golden model: **Berkeley SoftFloat** (through a Python binding or a small C/DPI wrapper),
  configured for RISC-V behavior (NaN handling and tininess after rounding). It is
  **bit-exact on results and on exception flags**, for every rounding mode. `claude_fx.py`
  is not used here, since this is floating point, not fixed point.
- Compliance: **Berkeley TestFloat** vectors for every operation, precision and rounding
  mode, plus targeted corner cases (subnormals, ±0, ±∞, NaN payloads, overflow / underflow
  boundaries, FMA cancellation).
- CPU: `riscv-arch-test` F and D suites, and lock-step comparison against Spike / Sail
  through RVFI (§12).
- Formal: equivalence of the pipelined add/mul against a simple reference model on SP
  (SymbiYosys / VC Formal), and handshake and protocol properties for the iterative units.
- Firmware: `-march=rv32imafdc_zicsr -mabi=ilp32d` (and `rv32imafc` / `ilp32f` for
  SP-only) builds for rv_core, beside the existing rv32imac builds. The ARM Cortex-M33
  builds can use `-mfloat-abi=hard -mfpu=fpv5-sp-d16` for driver examples that use FP.

---

## 9. Debug / test / testability (`IP/test/`, new category)

| Block | Size | Key features |
|---|---|---|
| **jtag_tap** | S | IEEE 1149.1 16-state FSM; IR length param; IDCODE (param value), BYPASS, SAMPLE, PRELOAD, EXTEST, CLAMP, HIGHZ (with boundary scan), **IEEE 1149.1-2013 conforming**; N design-specific instructions, each driving a test data register through the `tdr_*` port (§3.6); `jtag_ops` for special operations; optional TRST*; TCK-domain only, with clean hand-offs to the system clock. Daisy-chain friendly |
| **jtag2bus** | S | User-DR front end + `claude_cmd2bus` (§3.7): single reads/writes, auto-increment bursts. Works with OpenOCD (a custom driver or a Tcl `irscan`/`drscan` script) |
| **jtag_dma** | M | The bulk-load path: streams words from TCK into an async FIFO, then into memory through `mem_*` with no per-word handshake over JTAG. Fast program download and memory dump. **Built as the burst/streaming mode of jtag2bus, not a separate IP (D5, decided)** |
| **riscv_dm + dtm** [NEW, essential] | M | RISC-V External Debug Support 0.13.2: DTM on the TAP (DTMCS / DMI) and a Debug Module with halt/resume, abstract register access, program buffer, system-bus access and `ndmreset`. **Without it neither CPU can be debugged with GDB/OpenOCD.** It drives `dbg_freeze_i` across the SoC |
| **boundary_scan** [NEW] | M | BSR cells generated from a pad list; EXTEST, SAMPLE, PRELOAD (separate, IEEE 1149.1-2013); BSDL generated by script; CLAMP / HIGHZ; generated per SoC from the pad-list YAML; Phase 2 (D7, §3.9) |
| **mbist_ctrl** [NEW] | M | Shared memory-BIST controller (March C-, MATS+, checkerboard), with a programmable algorithm, reached from the TAP and from registers. The sram's built-in March C- becomes one engine behind it; reports failing address and bank |
| **lbist** [NEW, later] | M | PRPG (LFSR) + MISR around scan chains for logic BIST (ASIC) |
| **scan / DFT flow** [NEW, flow work] | — | Not RTL. **Required for every SoC (D7):** `test_mode_i` / `scan_en_i` on every IP and the RTL rules of §3.9; DFT Compiler scan insertion (csun.edu, optional compression); TestMAX ATPG (stuck-at + transition) with coverage targets; gate-level simulation of the patterns |
| **ila / logic analyzer** [NEW] | M | Embedded trigger + capture buffer (sram IP), trigger on bus/stream patterns, read out through JTAG. Vendor-independent "SignalTap/ILA", which also works on ASIC |
| **bus_monitor / perf counters** [NEW] | S | Transaction counters, latency histogram, error and timeout capture with address on any bus; protocol-violation flags (reusing the formal checkers' logic as synthesizable monitors) |
| **error injector** [NEW, verification] | S | Forces bus errors / ECC errors / stream stalls for SoC-level robustness tests |

---

## 10. Infrastructure / supporting utilities (`IP/interface/`, `IP/common/`)

### 10.1 Bus utilities

| Block | Key features |
|---|---|
| **Protocol bridges** | Built as slave adapter → `mem_*` → master adapter (§3.2). Named shortcuts: `ahb2apb` (the classic peripheral bridge), `axi4l2ahb`, `wb2axi4l`, ...; generated, not hand-written |
| **Bus CDC bridge** | `mem_*` request and response through two small async FIFOs (or a handshake synchronizer for low bandwidth); any protocol on either side through the adapters |
| **Bus RDC / isolation fence** | When the target domain is in reset or powered down (for example an sram bank in shutdown), it returns an error response instead of hanging; drains outstanding traffic before the domain goes to sleep; clamps outputs to safe values |
| **Bus clock-enable bridge** | Same clock, slave side running at 1/N via `clk_en` (for example a slow APB peripheral island). No CDC. Supports both rate-ratio directions |
| **Bus mux (N:1)** | Lightweight master arbiter (fixed / round-robin) when a full bus_matrix is overkill |
| **Bus demux / decoder (1:N)** | Address decoder + **default slave** (error response on unmapped addresses) |
| **Register slice** | Pipeline stage for long routes / timing (per protocol, or once on `mem_*`) |
| **Bus timeout watchdog** | Terminates a transaction with an error after N cycles; logs the address |
| **Bus firewall / MPU** [NEW, security] | Address-range rules per master (read / write / execute, secure / non-secure attribute) → error and IRQ on violation. See §11 |

### 10.2 Reset and clock-domain cells (extend `IP/common`)

`claude_sync` and `claude_pulse_sync` exist. Add:

- `claude_reset_sync`: async assert, sync de-assert (decide whether this replaces the
  current synchronous-reset convention for reset inputs, D8).
- `claude_handshake_sync`: multi-bit bundle with req/ack.
- `claude_gray_sync`: Gray-coded counter crossing (used by the async FIFO).
- `claude_edge_detect`, `claude_glitch_filter`, `claude_debounce`.

### 10.3 Clock generation — **dividers that are not powers of 2**

The current rule ("never select, gate or derive a clock in RTL") stays. Clock logic is
split in two:

1. **Clock-enable generators (plain RTL, the default):**
   - `claude_clk_en_div`: integer N (any N ≥ 1, programmable at run time), a 1-cycle
     enable every N clocks.
   - `claude_clk_en_frac`: fractional N.F with a phase accumulator / sigma-delta, for
     example exact 115200 baud from 50 MHz, or 44.1 kHz audio from 100 MHz. The average
     rate is exact and the jitter is one source clock.
   - `claude_clk_en_tick`: shared µs / ms ticks for debounce, watchdog and RTC.
   These cover almost every peripheral: UART, SPI, I2C, PWM and DSP sample strobes
   all use enables, not clocks.
2. **Real clocks, only through a technology-cell layer** `claude_clk_*` with
   per-technology leaves (the same pattern as the sram's vendor macros: generic model,
   SAED/SKY130 cells, Xilinx BUFGCE / BUFGMUX / MMCM, Altera clock control):
   - `claude_clk_gate` (ICG, latch-based in the generic model),
   - `claude_clk_mux2` (glitch-free, with select synchronized in both domains),
   - `claude_clk_div`: integer divide by N (odd N with 50 % duty using the
     negedge-assisted method), built on the cells above. For SPI SCK out, I2S
     BCLK/MCLK and the VGA pixel clock when a PLL is not available,
   - `claude_clk_pll` wrapper (vendor PLL/MMCM on FPGA, a black box for ASIC).
   STA / SDC: each leaf ships its `create_generated_clock` constraints.

### 10.4 FIFOs (no bus interface)

| Variant | Features |
|---|---|
| `claude_fifo_sync` | Width/depth params (depth need not be a power of 2); standard or **FWFT** (show-ahead) read; full / empty / almost-full / almost-empty (programmable thresholds); fill count; sticky overflow / underflow flags; storage = flops, inferred RAM, or the sram IP (param `MEM_STYLE`) |
| `claude_fifo_async` | Gray-pointer dual-clock FIFO, power-of-2 depth (or the documented gray-skip method for other depths); fill count in both domains; reset in both domains with a documented reset protocol (RDC); `SYNC_STAGES` param |
| `claude_fifo_stream` | Claude stream wrappers for both (`tvalid` / `tready` / `tlast` packed alongside the data), and a **packet mode** (holds the output until a whole `tlast` frame is in) |
| `claude_skid_buffer` | 2-entry full-throughput register slice for the stream |

These go in `IP/common` (they are primitives), and each is verified once (formal:
no overflow / underflow, ordering, Gray single-bit change).

### 10.5 Other common primitives [NEW]

- `claude_fx_*` (rounding and saturation, §8), `claude_lfsr` (PRBS, also for BIST and
  test patterns), `claude_crc` (param polynomial, also a register-IP wrapper **crc**
  for software use), `claude_arb` (round-robin and fixed-priority arbiter shared by
  DMA, bus mux and stream switch), `claude_ecc` (SECDED, factored out of the sram).

---

## 11. Security (`IP/security/`, new category)

| Block | Size | Key features |
|---|---|---|
| **aes** | M–L | AES-128/192/256 encrypt and decrypt; ECB / CBC / CTR / CFB / OFB, and **GCM** (adds a GHASH GF(2¹²⁸) multiplier, param); iterative (1 round per clock, small) or unrolled/pipelined (param); on-the-fly key expansion; key from software registers **or from the key store** over a side-band port that software can never read; claude stream ports for DMA-driven bulk encryption; zeroize command; optional masking against DPA (decision for ASIC); **Control-stream port (§3.8, D11)**, so DMA can run whole key / IV / data sequences. |
| **sha256** | M | SHA-256 (SHA-224 param); 1 round per clock; hardware padding (message length in bits); context save/restore for multitasking; stream input; **HMAC-SHA256** mode (key from registers or the key store); **Control-stream port (§3.8, D11).** |
| **trng** [NEW, essential] | M | Entropy from free-running ring oscillators (a technology-cell leaf, like §10.3); NIST SP 800-90B health tests (repetition count, adaptive proportion); conditioning; a seed source for the DRBG and for AES masking. *Without it, AES keys and nonces have nowhere secure to come from* |
| **drbg** [NEW] | M | CTR_DRBG (SP 800-90A) on top of AES; reseeds from the TRNG |
| **key_store / otp_ctrl** [NEW] | M | Key slots that hardware can use and software cannot read (or can only write); lock bits; interface to OTP/eFuse macros (black box) or a simulation model; device-unique key |
| **pka** [NEW, later] | L–XL | Public-key accelerator: modular multiply/exponentiation (RSA), ECC point multiply (P-256 / Curve25519), for secure boot signature checking |
| **bus firewall / TrustZone-lite** [NEW] | M | Secure / non-secure attribute carried on the bus (`mem_prot`), per-region rules, per-master IDs; violation IRQ + error response. Pairs with the CPU's PMP |
| **lifecycle / secure debug** [NEW] | M | Device states (development / production / RMA); JTAG locked unless authenticated (challenge-response through the DM); debug zeroizes keys |
| **tamper / glitch monitor** [NEW, later] | S–M | Clock-frequency monitor, voltage-glitch canary, active-shield checks (ASIC). Raises an alarm that zeroizes the key store |
| **secure boot ROM flow** [NEW, integration] | — | ROM code that hashes the image (SHA-256), verifies a signature (PKA, or HMAC as a first step), then jumps. An SoC-level deliverable, not a single IP |

---

## 12. CPU (`IP/CPU/`)

Both cores are **mem_* initiators** (one port for the small core, separate I and D
ports for the large core), so they connect to the bus_matrix through the master adapters
like any other master. The existing firmware builds with
`-march=rv32imac_zicsr -mabi=ilp32`, so the large core must implement **RV32IMAC +
Zicsr** to run every existing driver unmodified.

| | **rv_tiny** (very simple) | **rv_core** (more powerful) |
|---|---|---|
| ISA | RV32E or RV32I (param) + Zicsr; M and C as params; optional Zfinx (FP in integer registers, through `fpu_core`, §8.2) | RV32IMAC + Zicsr + Zifencei; **F and D** (param, `fpu_rv`, §8.2); Zba/Zbb (param) |
| Pipeline | Multi-cycle (2–4 CPI) or 2-stage; smallest area target (~1–2 k LUT) | 5-stage in-order, forwarding, static/BHT branch prediction, 1-cycle multiply (DSP), iterative divider |
| Privilege | M-mode only (enough for FreeRTOS); optional U-mode + PMP (param) | M + U; PMP (8–16 regions) for FreeRTOS-MPU and Zephyr user mode |
| Memory | Single `mem_*` port, or ITCM/DTCM | I-cache + D-cache (param size/ways, AXI4 bursts, D1), TCMs, write buffer |
| Interrupts | CLINT (`mtip`, `msip`) + PLIC (`meip`) as the RTOS baseline; optional fast local IRQs / CLIC-lite | CLINT + PLIC (§7), or CLIC |
| Debug | `riscv_dm` (§9) halt/resume/abstract access | Full `riscv_dm` incl. hardware breakpoints (trigger module) |
| Extension port | — | **Coprocessor interface** (CV-X-IF style): custom instructions dispatched to an accelerator. Connects to the FPU (§8.2), NPU-3, CORDIC and MAC units with no bus overhead |
| Perf counters | `mcycle` / `minstret` / `time` (Zicntr) | Zicntr + full HPM counters (Zihpm) |
| Use | Housekeeping core, boot/security controller, NPU sequencer, inside the PID or VGA SoC | Application core |

Verification plan (beyond the normal 12 steps): `riscv-arch-test` compliance suite,
lock-step comparison against a reference ISS (Spike or Sail) through a retirement trace
(RVFI), random instruction generation (riscv-dv on xsim if possible), and `riscv-formal`
via RVFI for the SymbiYosys flow. Both cores (and the NPU) are delivered in
SV **and** VHDL-2008 (D3).

### 12.1 RTOS support [requirement, user 2026-11-26]

**Both cores must run an RTOS: FreeRTOS first, then Zephyr; others (Eclipse ThreadX,
RT-Thread, NuttX) should port with no hardware change.** The way to get there is to stick
to the standard RISC-V privileged spec and the de-facto standard peripherals, so the
RTOSes' existing RISC-V ports work unchanged. Linux is **out of scope (user decision, 2026-11-26)**:
no S-mode, no MMU (Sv32) and no Linux-specific hardware is planned for either core.

**Hardware the RTOSes need (both cores, unless noted):**

| Need | Hardware | Why |
|---|---|---|
| Precise traps | `mtvec` (direct and vectored modes), `mepc`, `mcause`, `mtval`, `mscratch`, `mret`; `ecall`, `ebreak`, illegal-instruction and misaligned-access exceptions (misaligned: trap, or handled in hardware by parameter) | Context switch (FreeRTOS yields with `ecall`), system calls, fault reporting |
| Tick timer | CLINT `mtime` / `mtimecmp` → `mtip`, SiFive layout (§7) | RTOS tick; FreeRTOS `configMTIME_BASE_ADDRESS` / `configMTIMECMP_BASE_ADDRESS`, Zephyr `riscv,machine-timer` |
| Software interrupt | CLINT `msip` per hart | Yield / inter-processor interrupts (SMP) |
| External interrupts | PLIC (`meip`) with claim / complete | Peripheral IRQs routed to tasks |
| Global interrupt control | `mstatus.MIE` / `MPIE`, `mie` / `mip` | Critical sections |
| Low power idle | `wfi` stops the pipeline until any enabled interrupt (even with `MIE`=0); `idle_o` to the power manager so the core clock can be gated; `mtime` stays on the always-on clock | Tickless idle (`configUSE_TICKLESS_IDLE`, Zephyr PM) |
| Time and statistics | `mcycle`, `minstret`, `time` CSRs readable (Zicntr) | Run-time statistics, `k_cycle_get`, tracing |
| Atomics | **A** extension (LR/SC + AMO) on rv_core; Zaamo / Zalrsc optional on rv_tiny | Lock-free kernel objects, Zephyr atomics, SMP |
| Memory protection | PMP (and U-mode) on rv_core; optional on rv_tiny | FreeRTOS-MPU, Zephyr user mode and stack guards |
| FPU context | `mstatus.FS` (Off / Initial / Clean / Dirty) tracked by `fpu_rv`, so an RTOS saves the FP registers only for tasks that used them; Zfinx needs no extra context | FreeRTOS / Zephyr FP-sharing options |
| Multi-core (later) | `mhartid`, one `msip` / `mtimecmp` per hart, A extension, coherent shared memory or uncached shared regions, mailbox / hw_semaphore (§7) | FreeRTOS SMP, Zephyr SMP |
| Debug | `riscv_dm` system-bus access while running (§9) | RTOS-aware debugging (OpenOCD FreeRTOS / Zephyr thread awareness) |

**Interrupt latency** is a spec item for both cores: the worst-case number of cycles from
an interrupt input to the first handler instruction, and from `mret` back to the task, is
documented and measured in a directed test. RTOS scheduling depends on it being bounded.

**rv_tiny configuration for RTOS use:** RV32I (+M, +C) with Zicsr, Zicntr, CLINT and PLIC.
RV32E remains a parameter for the smallest designs: Zephyr supports RV32E, but FreeRTOS
support for RV32E has to be checked before we rely on it.

**Software deliverables** (under `SoC/<soc>/firmware/`, generated where possible by the
SoC generator, §4):

- **FreeRTOS port:** `FreeRTOSConfig.h` plus the chip-specific-extensions header for the
  standard RISC-V port (with the FPU context for rv_core F/D), and the tick from the CLINT.
  Demos: blinky, the standard "full" demo task set, and a DMA + UART + IRQ demo.
- **Zephyr:** SoC and board definitions with a devicetree generated from the SoC YAML. The
  stock drivers cover the CPU, CLINT (`riscv,machine-timer`), PLIC (`sifive,plic-1.0.0`)
  and UART (`ns16550`, §6). Claude-specific drivers (GPIO, SPI, I2C, DMA, PWM, watchdog)
  are thin wrappers over the existing C99 drivers.
- **Bare-metal** stays supported: the existing drivers keep the `uintptr_t base` API and
  must not depend on any RTOS.

**Verification:**

- FreeRTOS blinky and the full demo run in simulation (Verilator, or xsim for the VHDL
  core) on SoC-1 as part of the regression, and on the FPGA boards.
- A subset of the Zephyr kernel test suite (`tests/kernel`: threads, semaphores, timers,
  interrupts, FPU sharing on rv_core) runs on rv_core, in simulation and on hardware.
- Directed tests for every trap / interrupt path, `wfi` wake-up, nested interrupts and the
  interrupt-latency figure.

---

## 13. Reference SoCs (`SoC/`)

Each reference SoC is a regression target for every block it contains, and runs real
firmware on real FPGA boards (Zybo-Z7-10, DE0-Nano-SoC).

### 13.1 SoC-0 "Bus bring-up" — no CPU

```
UART pins ─► uart2bus ─┐
JTAG ─► TAP ─► jtag2bus ┼─► bus_matrix ─► sram, AHB→APB ─► {gpio, timer, uart16550, spi_m, i2c_m, pwm, wdt}
SPI pins ─► spi_slave ──┘
```

This proves the master adapters, `claude_cmd2bus` and the first peripherals from a host
Python script **before any CPU exists**. It is also the FPGA lab bench for every later
peripheral.

### 13.2 SoC-1 "Tiny MCU"

`rv_tiny` + boot ROM + SRAM + JTAG/DM + irq_ctrl/CLINT + UART + GPIO + timer + SPI + I2C +
watchdog + syscon + reset_ctrl. The first SoC to boot C firmware; `soc.h`, the linker
script and drivers come from the generator.

### 13.3 SoC-2 "Audio / sensor DSP"

SoC-1 + DMA + PDM/I2S + stream switch + CIC / halfband / FIR / IIR / FFT / mag_log +
NPU-0/1. Runs the keyword-spotting chain (§5.4).

### 13.4 SoC-3 "Motor control"

`rv_tiny` + PWM (dead-time) + QEI + adc_seq + PID + event router + watchdog. The control
loop runs with no CPU; the CPU only adjusts set-points.

### 13.5 SoC-4 "Secure application"

`rv_core` (PMP) + `rv_tiny` as a security controller + AES/SHA/TRNG/DRBG/key store +
firewall + lifecycle + qspi_xip + secure boot ROM + VGA.

### 13.6 Default address map (RISC-V conventional where it exists)

| Base | Size | Region |
|---|---|---|
| `0x0000_0000` | 4 KiB | RISC-V Debug Module (program buffer / ROM) |
| `0x0001_0000` | 64 KiB | Boot ROM (reset vector) |
| `0x0200_0000` | 64 KiB | CLINT |
| `0x0C00_0000` | 64 MiB | PLIC |
| `0x1000_0000` | per SoC | On-chip SRAM (sram IP banks) |
| `0x2000_0000` | 256 MiB | QSPI XIP flash |
| `0x4000_0000` | 4 KiB per slot | APB peripherals (one regbus window each) |
| `0x5000_0000` | 4 KiB per slot | DSP shells + stream switch + event router |
| `0x6000_0000` | per config | NPU registers + scratchpad window |
| `0x7000_0000` | 4 KiB per slot | Security block (firewall-protected) |
| `0x8000_0000` | — | External memory (later) |

---

## 14. Roadmap (dependency-ordered phases)

Every block goes through the 12-step flow. A phase starts when its predecessors
have passed at least Step 8 (regression).

| Phase | Blocks | Depends on | Unlocks |
|---|---|---|---|
| **0 — Foundations** (`IP/common`) | `mem_*` initiator + 4 master adapters (+ formal); claude stream spec + skid buffer; FIFOs sync/async/stream; reset/handshake/gray sync cells; `claude_clk_en_*`; `claude_fx_*`; `claude_arb`; `claude_lfsr`; `claude_cmd2bus`; event spec; **control stream spec + `claude_ctl2reg` + `claude_regbus_arb` + ring forwarder (§3.8)**; stream and control-stream BFMs + Python drivers for benches; **DFT convention (§3.9): agent files done 2026-11-26; `claude_clk_*` test inputs and DFT0 waiver template still to build**; **`claude_fx.py` golden-model package (§3.10)**. **0b:** `BURST_EN` on `mem_*` + AXI4 (full) adapters (D1) | existing common | everything |
| **1 — Simple peripherals** | gpio, uart16550, spi_master, i2c_master, pwm, watchdog, syscon, clk tech cells (`claude_clk_*`) | 0 | SoC-0 slaves |
| **2 — Bus masters / bring-up** | jtag_tap (with `SCAN_MODE` / boundary-scan instructions), boundary_scan generator + BSDL, jtag2bus (+ burst mode = jtag_dma), uart2bus, spi_slave, bus utilities (bridges, mux, demux, default slave, CDC bridge, timeout), SoC generator v1 | 0, 1 | **SoC-0 on FPGA** |
| **3 — CPU tiny** | rv_tiny, riscv_dm/dtm, irq_ctrl, clint, reset_ctrl, boot ROM, dma; **FreeRTOS port + demos on rv_tiny (§12.1)** | 2 | **SoC-1 running FreeRTOS** |
| **4 — DSP chain** | dsp_shell, stream_switch, event_router, nco, cic/halfband, fir, iir_biquad, cordic, fft, mag_log, pdm_rx, i2s, **`fpu_core` (SP first, then DP) + `fpu_stream` + `fpu_reg`**; then pid, qei, adc_seq | 0, 3 (DMA) | **SoC-2 (without NPU), SoC-3** |
| **5 — Security** | sha256, aes (+GCM later), trng, drbg, key_store, firewall, lifecycle | 3 | SoC-4 (part) |
| **6 — Big blocks** | NPU-0 → NPU-1 → NPU-2; rv_core (+caches, AXI4 bursts, **F/D through `fpu_rv`**, A extension, PMP; **FreeRTOS (with FPU context) and Zephyr on rv_core, §12.1**); qspi_xip; vga; mbist_ctrl; ila | 3, 4, 5 | SoC-2 full, SoC-4 |
| **7 — Advanced** | PKA, LBIST, CAN, CLIC, NPU-3 + coprocessor port, tamper | 6 | — |

Rough size key used above: S < 1 k LUT, M 1–5 k, L 5–15 k, XL > 15 k (or multiple
sub-IPs). The Zybo-Z7-10 has about 17.6 k LUT, 80 DSP48 and 60 BRAM36, so SoC-2 and SoC-4
probably need the DE0-Nano-SoC (Cyclone V, about 40 k LE) or careful parameter choices.

---

## 15. Decisions

Decided by the user on 2026-11-26 unless marked open.

| # | Decision | Outcome |
|---|---|---|
| D1 | AXI4 (full) with bursts, and burst support on `mem_*` | **DECIDED: yes.** Optional `BURST_EN` on `mem_*` (§3.2), plus `claude_axi4_if` / `claude_axi4_mem_if` / `claude_axi4_mst_if` in SV and VHDL. Phase 0b, before the DMA |
| D2 | Stream signal names | **DECIDED: AXI4-Stream names** (`tvalid`, `tready`, `tdata`, `tlast`, `tuser`, `tid`), §3.3 |
| D3 | VHDL-2008 for the CPUs and the NPU as well | **DECIDED: yes.** The "every IP in SV and VHDL-2008" rule has no exceptions, including rv_tiny, rv_core and every NPU stage |
| D4 | IRQ controller register model | **DECIDED: RISC-V PLIC-compatible** (§7); CLIC-lite stays an optional later addition for rv_tiny |
| D5 | JTAG DMA | **DECIDED: a mode of jtag2bus**, not a separate IP (§9) |
| D6 | Stream switch or static chains | **DECIDED: both**, generated from the same YAML (§5.2) |
| D7 | DFT ports on every IP | **DECIDED: yes, every IP.** Synthesizing any SoC must give scan flops, scan chains and a JTAG chain (TAP + boundary scan). Conventions in §3.9 |
| D8 | Reset style | **DECIDED:** synchronous active-low reset inside IP stays; `claude_reset_sync` (async assert, sync de-assert) at domain boundaries in the reset controller (§7, §10.2) |
| D9 | Number formats for math IP | **DECIDED: default Q1.15** (`DW=16`, `FRAC_W=15`). Every math IP is parameterized for other Q formats and for plain integer (`FRAC_W=0`). Every math IP has an accurate quantized Python golden model. §3.10 |
| D10 | First reference SoC to build towards | **Deferred (user, 2026-11-26):** decide later, once Phases 0–2 are further along. Candidate: SoC-0 (no CPU; exercises Phases 0–2 on real hardware) |
| D11 | Second register port beyond DSP and comms | **DECIDED:** yes for **PWM, timer, AES, SHA**. **Never** for the **watchdog or key store**: a DMA must not be able to kick a watchdog or read keys. Those two have no `CTL_PORT` parameter at all, so it cannot be turned on |
| D12 | Bus vs stream priority on the register file | **DECIDED: the bus always wins** (the register bridges cannot be stalled). The stream port waits, so its latency is bounded by bus traffic |
| D13 | FPU defaults | **DECIDED:** single precision (`PRECISION=SP`) by default, with DP and `SP_DP` by parameter; **full subnormal support by default** (FTZ optional by parameter); **Zfinx / Zdinx optional** on rv_tiny, not the default |

---

## 16. Verification additions at the SoC level

- **New shared BFMs:** claude stream source/sink (SV tasks + UVM agent), `mem_*` initiator
  responder, JTAG host BFM (TAP driver), SPI / I2C / UART line models, PDM/I2S models.
- **Python golden models** (§3.10): quantized and bit-exact for every math IP, built on the
  shared `claude_fx.py`, with a float reference for SQNR. Reused by directed tests, UVM
  scoreboards, the regression and the firmware examples. One reference, not one per
  testbench.
- **DFT checks** (§3.9): lint/SpyGlass DFT rules on every IP; at SoC level, scan-insertion
  coverage, ATPG coverage, and gate-level simulation of the ATPG and boundary-scan
  patterns.
- **RTOS tests** (§12.1): FreeRTOS demos on rv_tiny and rv_core and a Zephyr kernel-test
  subset on rv_core, in simulation and on the FPGA boards, as regression items.
- **SoC integration tests:** C firmware on rv_tiny driving every peripheral
  (cross-compiled, as today); host-scripted tests through jtag2bus / uart2bus on SoC-0;
  stream chain end-to-end tests against the Python chain model.
- **Dual-port register tests:** every IP with `CTL_PORT=1` runs its register tests from
  both ports, and runs a collision test (bus and control stream hitting the regfile in the
  same cycle) plus ownership tests. These are shared test templates in
  `IP/common/verification/tests/`.
- **Formal:** protocol checkers for the master adapters, the stream (`claude_stream_fv`),
  the control stream (`claude_ctl_fv`: every packet gets exactly one response when `RESP`
  is set, and the bus port is never stalled),
  FIFOs and CDC; `riscv-formal` for the cores.
- **FPGA:** each reference SoC gets board constraints for the Zybo-Z7-10 and the
  DE0-Nano-SoC and a hardware smoke test.
