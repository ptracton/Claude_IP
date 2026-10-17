# sram IP — Specification

Status: requirements agreed 2026-10-15 (see `.agents/project_sram_plan.md`);
RTL implemented 2026-10-15 (Step 3) — decisions taken during implementation
are marked *[Step 3]*.
Sections marked _[TBD — Step N]_ are filled in by that step.

## Overview

`sram` is a configurable on-chip static RAM with a bus slave port. It wraps
the SRAM macros of each supported technology behind one interface, so the
same RTL targets:

| `TECH` | Storage | Notes |
|---|---|---|
| `GENERIC` | behavioral array | simulation, formal, Yosys; portable inference |
| `XILINX` | `xpm_memory_spram` (block RAM / UltraRAM) | used when Vivado is installed |
| `ALTERA` | `altsyncram` (M10K on Cyclone V) | used when Quartus is installed |
| `SAED90` | `SRAM<w>x<d>_1rw` macros | |
| `SAED32` | `SRAMLP1RW<d>x<w>` low-power macros | native light sleep / deep sleep / shutdown pins |
| `SAED14` | `SRAM1RW<d>x<w>` macros | |
| `SKY130` | OpenRAM `sky130_sram_*_1rw1r_*` macros | port 0 used as read/write, port 1 tied off |

Width and depth are parameters. Each ASIC technology wrapper builds the
requested size from its vendor primitives with generate loops: primitives in
parallel for width, stacked for depth, with the upper address bits selecting
the row. FPGA and generic memories are inferred whole; the tool tiles them.
Byte enables, power gating, ECC, per-bank power gating, built-in self-test
and a second port can each be turned on or off.

## Features

Always present:
- One bus slave port: APB4, AHB-Lite (bursts, HSIZE), AXI4-Lite or Wishbone B4.
  One top-level per protocol (`sram_apb`, `sram_ahb`, `sram_axi4l`, `sram_wb`),
  built on the shared `claude_<proto>_mem_if` adapters
  (`IP/common/design/rtl/mem_bus.md`).
- Bus error for addresses beyond `DEPTH` words.
- Optional output pipeline register (`READ_LATENCY` = 1 or 2).
- Clear engine: a side-band request zeroes the whole array. It also runs
  automatically on wake-up from SHUTDOWN.
- Status outputs for a power controller / interrupt controller.

Optional (parameters, default off unless noted):
- `BYTE_EN` — byte-granular writes (default on).
- `PWR_GATE` — power modes RUN / LIGHT_SLEEP / DEEP_SLEEP / SHUTDOWN (default on).
- `ECC_EN` — SECDED per word, with error reporting and error injection.
- `BANK_PG` — an independent power mode per bank of macros.
- `BIST_EN` — March C- self-test engine.
- `DUAL_PORT` — a second bus port of the same protocol. *[Step 3]* Provided as
  separate top-levels `sram_<proto>_dp` (ports `A_*` / `B_*`). With SKY130
  port B is read-only (OpenRAM 1rw1r): writes get a bus error.
  - *[Step 3c]* Port B may have a **different width** (`WIDTH_B`, ratio a
    power of two; `DEPTH_B = WIDTH * DEPTH / WIDTH_B`, same storage,
    little-endian packing) and a **different clock** (`COMMON_CLK = 0`; each
    port has its own clock and reset pins).
  - With `COMMON_CLK = 1` same-word conflicts are **serialized A then B** (B
    waits a cycle when either writes; a port waits for the other's pending
    ECC read-modify-write), so no write is dropped. This replaces the planned
    "port A wins".
  - With `COMMON_CLK = 0` same-word collisions are undefined. The side-band
    runs on port A's clock, and port B reaches it through a CDC handshake
    (`sram_cdc`). `TECH_SAED14` needs `COMMON_CLK = 1`: its two-port macro has
    a write clock and a read clock.
  - ECC codewords are as wide as the narrower port.

There is no register block: all control and status is side-band pins.

## Parameters

| Parameter | Range | Default | Meaning |
|---|---|---|---|
| `TECH` | see Overview | `GENERIC` | storage implementation |
| `WIDTH` | 8..128 (multiple of 8 if `BYTE_EN`) | 32 | word width = bus data width |
| `DEPTH` | power of two | 1024 | number of words |
| `BYTE_EN` | 0/1 | 1 | byte-lane writes |
| `PARTIAL_WR_ERR` | 0/1 | 1 | `BYTE_EN = 0` only: a partial write is a bus error (1) or writes the full word (0) |
| `READ_LATENCY` | 1/2 | 1 | 2 adds an output register |
| `PWR_GATE` | 0/1 | 1 | power modes |
| `ECC_EN` | 0/1 | 0 | SECDED; *[Step 3]* the array is cleared after reset so every word holds a valid codeword |
| `BANK_PG` | 0/1 | 0 | per-bank power modes |
| `BIST_EN` | 0/1 | 0 | March C- engine |
| `DUAL_PORT` | 0/1 | 0 | second bus port (core parameter; *[Step 3]* exposed as the `sram_<proto>_dp` top-levels) |
| `WIDTH_B` | 8..128, `WIDTH / WIDTH_B` a power of two | `WIDTH` | *[Step 3c]* port B width (dual port) |
| `BYTE_EN_B`, `PARTIAL_WR_ERR_B`, `READ_LATENCY_B` | as port A | port A's | *[Step 3c]* port B options |
| `COMMON_CLK` | 0/1 | 1 | *[Step 3c]* 1: one clock; 0: port B on its own clock (not SAED14) |
| `INIT_FILE` | path | "" | FPGA / simulation preload (`$readmemh` format) |

Default synthesized configuration (DC, PrimeTime, gate-level, power):
`WIDTH = 32`, `DEPTH = 1024` (4 KB), `BYTE_EN = 1`, `PWR_GATE = 1`, other
options off. Two more netlists cover the options: ECC + BANK_PG + BIST, and
DUAL_PORT.

## Memory Map

The SRAM occupies `DEPTH * WIDTH / 8` bytes starting at byte offset 0 of
its slave port. Word `n` is at byte offset `n * WIDTH / 8`. Accesses at or
beyond the end return the protocol's bus error and do not change the
contents.

*[Step 3c]* Dual port: port B sees the same bytes at the same offsets. Its
word `j` is at byte offset `j * WIDTH_B / 8`, and it has
`DEPTH_B = WIDTH * DEPTH / WIDTH_B` words. With different widths, packing is
little-endian: narrow word `j` is bits `[(j % R) * N +: N]` of wide word
`j / R` (R = width ratio, N = narrow width).

## Interfaces

### Bus protocol top-levels

| Top | Bus | Notes |
|---|---|---|
| `sram_apb` | APB4 | zero-wait reads/writes when the macro answers in one cycle |
| `sram_ahb` | AHB-Lite | HSIZE byte lanes, INCR/WRAP bursts, BUSY; HREADY in, HREADYOUT out |
| `sram_axi4l` | AXI4-Lite | one read and one write in flight, alternated |
| `sram_wb` | Wishbone B4 classic | ERR_O on error |
| `sram_<proto>_dp` | two of the above (`A_*`, `B_*`) | *[Step 3c]* each port has its own clock and reset pins (with `COMMON_CLK = 1` drive both from one clock); port B's data and strobes are `WIDTH_B` wide |

### Side-band ports

| Port | Dir | Meaning |
|---|---|---|
| `pwr_mode_req_i[1:0]` | in | requested mode: 0 RUN, 1 LIGHT_SLEEP, 2 DEEP_SLEEP, 3 SHUTDOWN (`BANK_PG`: one field per bank) |
| `pwr_mode_ack_o[1:0]` | out | mode now in effect (changes only once the transition is complete) |
| `clr_req_i` / `clr_done_o` | in/out | zero the array; done pulse |
| `busy_o` | out | clear, BIST, wake-up or ECC read-modify-write in progress |
| `err_irq_o` | out | pulse on bus error / ECC event (*[Step 3]* registered, one cycle after the response) |
| `ecc_corr_o`, `ecc_uncorr_o`, `ecc_inj_i[1:0]` | | `ECC_EN` only; pulses registered; injection applies to the next port-A write |
| `bist_start_i`, `bist_done_o`, `bist_fail_o`, `bist_fail_addr_o` | | `BIST_EN` only |

*[Step 3c]* All side-band ports are synchronous to port A's clock, including
in a dual-port top with `COMMON_CLK = 0`. Port B's ECC and error events reach
`ecc_*_o` / `err_irq_o` through pulse synchronizers, a few cycles later.

### Power modes

| Mode | Contents | Bus access | SAED32-LP pins | Other ASIC PDKs | FPGA |
|---|---|---|---|---|---|
| RUN | kept | normal | — | — | — |
| LIGHT_SLEEP | kept | wakes automatically, with wait states | LS | clock/chip-select gated | CE / `sleep` |
| DEEP_SLEEP | kept | **bus error** | DS | clock/chip-select gated, periphery off (UPF) | CE / `sleep` |
| SHUTDOWN | **lost** (cleared on wake-up) | **bus error** | SD | power switched off (UPF), outputs isolated | contents marked invalid in simulation |

Transitions honour each macro's databook timing; the wake-up latency becomes
bus wait states or delays `pwr_mode_ack_o`.

## Technology Mapping

| PDK | Macro family | Byte mask | Byte-enable strategy |
|---|---|---|---|
| SAED90 | `SRAM<w>x<d>_1rw` | no | one column of 8-bit macros per byte lane |
| SAED32 | `SRAMLP1RW<d>x<w>` | no | 8-bit macro columns per lane |
| SAED14 | `SRAM1RW<d>x<w>` | no | 8-bit macro columns per lane |
| SKY130 | `sky130_sram_2kbyte_1rw1r_32x512_8` and others | yes (`wmask`) | native |
| XILINX / ALTERA / GENERIC | inferred / primitive | yes | native |

*[Step 3c]* Two-port primitives and their clocking (dual port):

| PDK | Two-port family | Clocks | `COMMON_CLK = 0` |
|---|---|---|---|
| SAED90 | `SRAM<w>x<d>` (w 8/32/39, d 16..128) | CE1 port A, CE2 port B | yes |
| SAED32 | `SRAMLP2RW<d>x<w>` | CE1 port A, CE2 port B | yes |
| SAED14 | `SRAM2RW<d>x<w>` | CE1 writes of both ports, CE2 reads of both ports (liberty and model) | **no**: `sram_core` stops elaboration |
| SKY130 | OpenRAM `1rw1r` (port B read-only) | clk0 port A, clk1 port B | yes |
| XILINX / ALTERA / GENERIC | `xpm_memory_tdpram` / altsyncram BIDIR / inferred | `independent_clock` / clock0 + clock1 / two processes | yes |

With different port widths, every technology uses R slices of the narrow
width per bank; FPGA mixed-width primitives are not used.

Default 32 x 1024 on SKY130 = two 32 x 512 macros stacked in depth.
*[Step 3b]* Each `sram_macro[_dp]_<tech>` ASIC wrapper is a W x D memory of
`ROWS x COLS` primitives of one size, chosen by `sram_pkg` (`prim_width`,
`prim_depth`, `prim_width_dp`, `prim_depth_dp`): `ROWS = D / PRIM_D` selected by
the upper address bits, `COLS = ceil(W / PRIM_W)`. Example: 16 x 2048 on SAED32
= 2 rows x 2 columns of `1024x8`. `sram_array` only splits the array into
`NUM_BANKS` power-domain banks. Exact primitive lists are in the README's
Design Architecture table. Quirks handled: SAED14 single-port `CSB` is
active high (two-port and SAED90/32 active low); `SRAM1RW32x8` has a 32-bit
`I` bus; the SAED14 and SKY130 simulation models need fixes, generated by
`IP/common/verification/tools/pdk_sram_models.py`.

## Timing

_[TBD — Step 3/4: cycle-level timing per protocol; Step 10: achieved clock per PDK]_

## Known Limitations

- SKY130 OpenRAM macros ship liberty for the typical corner only (except the
  older `sram_1rw1r_32_256_8`), so SS/FF timing of the macros is limited.
  _[TBD — Step 10]_
- No VHDL lint on csun.edu (SpyGlass has no working VHDL-2008 path).
- *[Step 3c]* Dual port with `COMMON_CLK = 0`:
  - same-word accesses in overlapping cycles are undefined;
  - port B's clock must keep running while the core changes power modes or
    runs the clear / BIST engines (it waits for port B to acknowledge);
  - not available with `TECH_SAED14`.
  - The XPM / altsyncram dual-clock leaves have not been elaborated yet (no
    Vivado / Quartus on csun.edu).
