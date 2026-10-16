# sram

## Overview

Configurable on-chip SRAM with a bus slave port. One RTL source targets
every supported technology by wrapping its SRAM primitives: the SAED90,
SAED32 and SAED14 macros, SkyWater SKY130 OpenRAM macros, Xilinx XPM block
RAM, Intel/Altera `altsyncram`, and a generic behavioral array.

Key features:
- **Bus interfaces:** APB4, AHB-Lite (bursts, HSIZE), AXI4-Lite and Wishbone B4,
  one top-level each, built on the shared `claude_<proto>_mem_if` adapters.
- **Configurable size:** width and depth are parameters. The wrapper tiles the
  technology's macros by depth (banks) and width (columns).
- **Byte enables (optional):** native byte masks where the macro has them,
  otherwise one column of 8-bit macros per byte lane.
- **Power gating:** RUN / LIGHT_SLEEP / DEEP_SLEEP / SHUTDOWN through a
  side-band request/acknowledge pair. These map onto the SAED32 low-power
  macros' LS/DS/SD pins, or onto UPF power domains with isolation on the
  other ASIC PDKs.
- **Always present:** bus error for out-of-range addresses and for access to a
  deep-sleeping or shut-down array, optional output register, clear engine,
  status outputs.
- **Optional, each switchable by a parameter:** SECDED ECC, per-bank power
  gating, March C- built-in self-test, and a second bus port.

There is **no register block** and therefore no SystemRDL step: all control
and status uses side-band pins (design decision D2, 2026-10-15).

Full requirements: [doc/spec.md](doc/spec.md).

## Design Architecture

Eight top-levels: one per bus protocol, each single-port or dual-port. All of
them share one protocol-independent core. A top-level contains only wiring.

```
 sram_<proto>  /  sram_<proto>_dp            (apb, ahb, axi4l, wb)
 ├── claude_<proto>_mem_if   (IP/common; one per port)   bus -> Claude memory bus
 └── sram_core
     ├── sram_port            per bus port: checks, ECC, read-modify-write, response
     │   ├── sram_ecc_enc / sram_ecc_dec   SECDED (ECC_EN)
     ├── sram_pwr_ctrl        one power state machine per domain (whole array or bank)
     ├── sram_clr             clear engine (clr_req_i, after reset with ECC, after shutdown)
     ├── sram_bist            March C- engine (BIST_EN)
     └── sram_array           banks x rows x columns of macro tiles
         └── sram_macro / sram_macro_dp      TECH dispatcher (single- / two-port)
             └── sram_macro[_dp]_<tech>      generic | xilinx | altera | saed90 | saed32 | saed14 | sky130
```

**Request flow.** The bus adapter turns each transfer into one memory-bus
request (`IP/common/design/rtl/mem_bus.md`). `sram_port` handles it in three
stages:

1. **Request cycle.** The request is checked. It is held back (no grant) while
   an engine owns the array, or while its power domain is waking from light
   sleep. It is granted with an error response when:
   - the address is beyond `DEPTH` words;
   - it is a partial write with `BYTE_EN = 0` and `PARTIAL_WR_ERR = 1`;
   - its domain is requested into deep sleep or shutdown;
   - it is a write on SKY130's read-only port B.

   Otherwise it accesses the array. An ECC partial write reads the word first.
2. **Next cycle.** The response is formed: corrected read data, or a
   read-modify-write write-back.
3. **Response.** It is returned in the next cycle with `READ_LATENCY = 1`, or
   one cycle later with `READ_LATENCY = 2`.

**Array ownership.** Self-test has priority over the clear engine, and the
clear engine over the bus port(s). A pending engine stops new grants, and
starts once the ports are idle.

**Dual port.** Ports A and B run in parallel on two-port macros. Same-word
conflicts complete in the order A then B: B waits a cycle if either access
writes, and a port waits while the other port's read-modify-write of that
word is pending. Conflicting writes are serialized, never dropped.

**Tiling.** `sram_pkg::macro_width` / `macro_depth` (and their `_dp`
counterparts) pick a macro for the technology. The array is built from
`NUM_BANKS` banks of `DEPTH / NUM_BANKS` words. Each bank is split into rows of
`MAC_D` words and columns of `MAC_W` bits. SAED macros have no byte mask, so
byte lanes use 8-bit-wide macros. SKY130 and the FPGA/generic tiles have native
byte masks.

| TECH | Single-port macros | Two-port macros | Byte mask |
|---|---|---|---|
| GENERIC | behavioral array | behavioral array | yes |
| XILINX | `xpm_memory_spram` | `xpm_memory_tdpram` | yes |
| ALTERA | `altsyncram` SINGLE_PORT | `altsyncram` BIDIR_DUAL_PORT | yes |
| SAED90 | `SRAM{8,32}x{64..1024}_1rw` | `SRAM{8,32}x{16..128}`, `SRAM39x32` | no (x8 lanes) |
| SAED32 | `SRAMLP1RW{64..1024}x{8,32}` | `SRAMLP2RW{16..128}x{8,32}` | no (x8 lanes) |
| SAED14 | `SRAM1RW{16..512}x{8,32}` | `SRAM2RW{16..512}x{8,32}` | no (x8 lanes) |
| SKY130 | OpenRAM `sky130_sram_*_1rw1r_*` (port 1 unused) | same macros, port B read-only | yes (`wmask`) |

Default configuration (32 x 1024, byte enables): SAED90/SAED32 use 4 lanes of
`8x1024` / `1024x8`; SAED14 uses 2 rows x 4 lanes of `512x8`; SKY130 uses 2
rows of `32x512`.

**Macro and model quirks handled:**
- The SAED14 single-port macros have an active-high `CSB`. The two-port macros
  have an active-low `CSB`, as do SAED90 and SAED32.
- `SRAM1RW32x8` has a 32-bit `I` bus, in the model and in the liberty.
- The SAED14 SRAM simulation models never drive their outputs, and the SKY130
  OpenRAM models use their memory array before declaring it. Both are fixed in
  generated copies by `IP/common/verification/tools/pdk_sram_models.py`; the
  vendor files are not modified.

## Parameters and Memory Map

| Parameter | Range | Default | Meaning |
|---|---|---|---|
| `TECH` | `sram_pkg::TECH_*` (0..6) | GENERIC | storage implementation |
| `ADDR_W` | >= log2(DEPTH x WIDTH/8) | 32 | bus byte-address width |
| `WIDTH` | 8..128, multiple of 8 | 32 | word width = bus data width |
| `DEPTH` | power of two >= 2 | 1024 | words |
| `BYTE_EN` | 0/1 | 1 | byte-lane writes |
| `PARTIAL_WR_ERR` | 0/1 | 1 | `BYTE_EN = 0`: a partial write is a bus error (1) or writes the whole word (0) |
| `READ_LATENCY` | 1/2 | 1 | 2 adds an output register |
| `PWR_GATE` | 0/1 | 1 | power modes |
| `ECC_EN` | 0/1 | 0 | SECDED; the array is cleared after reset |
| `BANK_PG` | 0/1 | 0 | one power domain per bank (needs `PWR_GATE`) |
| `NUM_BANKS` | power of two, <= DEPTH/2 | 1 | banks |
| `BIST_EN` | 0/1 | 0 | March C- engine |
| `INIT_FILE` | path | "" | preload, GENERIC / FPGA, `NUM_BANKS = 1` |
| `RST_POL` | 0 | 0 | documents the reset polarity, which is carried by the bus reset pin |

Dual port is a separate top-level (`sram_<proto>_dp`), not a parameter of the
single-port top-levels.

**Memory map.** Word `n` sits at byte offset `n * WIDTH / 8` of the slave
port. Addresses at or beyond `DEPTH * WIDTH / 8` get the bus error response,
and the contents are unchanged. Narrow AHB transfers use the byte lanes given
by HSIZE/HADDR.

## Interfaces

### Bus ports

| Top-level | Bus signals | Notes |
|---|---|---|
| `sram_apb` | `PCLK PRESETn PSEL PENABLE PADDR PWRITE PWDATA PSTRB PRDATA PREADY PSLVERR` | PSLVERR on error |
| `sram_ahb` | `HCLK HRESETn HSEL HADDR HTRANS HWRITE HSIZE HWDATA HWSTRB HREADY HRDATA HREADYOUT HRESP` | bursts, BUSY, HSIZE; HREADY in / HREADYOUT out |
| `sram_axi4l` | `ACLK ARESETn AW* W* B* AR* R*` | BRESP/RRESP = SLVERR on error |
| `sram_wb` | `CLK_I RST_I CYC_I STB_I WE_I ADR_I DAT_I SEL_I DAT_O ACK_O ERR_O` | classic cycles; ERR_O on error |
| `sram_<proto>_dp` | the above, twice: `A_*` and `B_*`, sharing the clock and reset | |

The bus adapter timing is described in `IP/common/design/rtl/mem_bus.md`.

### Side-band ports (all top-levels)

| Port | Dir | Width | Description |
|---|---|---|---|
| `pwr_mode_req_i` | in | 2 x NPD | requested power mode per domain (0 RUN, 1 LS, 2 DS, 3 SD); NPD = NUM_BANKS with BANK_PG, else 1 |
| `pwr_mode_ack_o` | out | 2 x NPD | mode in effect per domain (changes when a transition completes) |
| `clr_req_i` | in | 1 | clear the array (pulse) |
| `clr_done_o` | out | 1 | clear pass finished (pulse) |
| `busy_o` | out | 1 | clear, BIST, power transition or read-modify-write in progress |
| `err_irq_o` | out | 1 | bus error or ECC event (registered pulse) |
| `ecc_inj_i` | in | 2 | ECC: arm a 1-bit [0] / 2-bit [1] error on the next port-A write |
| `ecc_corr_o` | out | 1 | ECC: corrected error (registered pulse) |
| `ecc_uncorr_o` | out | 1 | ECC: uncorrectable error (registered pulse) |
| `bist_start_i` | in | 1 | BIST: start March C- (pulse) |
| `bist_done_o` | out | 1 | BIST: finished (pulse) |
| `bist_fail_o` | out | 1 | BIST: a word failed (valid from `bist_done_o` until the next start) |
| `bist_fail_addr_o` | out | log2(DEPTH) | BIST: first failing word |

Inputs of disabled options must be tied to 0. Their outputs stay 0.

### `sram_core`

| Port group | Signals |
|---|---|
| clock / reset | `clk`, `rst_n` (synchronous, active low) |
| memory bus, port A | `mem_req_i mem_gnt_o mem_we_i mem_addr_i mem_be_i mem_wdata_i mem_rvalid_o mem_rdata_o mem_err_o` |
| memory bus, port B | the same names with `mem_b_` (DUAL_PORT; tie off otherwise) |
| side-band | as the table above |

## Power Management

Each power domain (the whole array, or one bank with `BANK_PG`) has its own
state machine: RUN -> enter -> sleep -> wake -> (clear) -> RUN. A domain only
enters a sleep mode when no access to it is in flight. `pwr_mode_ack_o`
changes only once a transition is complete.

| Mode | Contents | Bus access | SAED32-LP pins | Other ASIC PDKs | FPGA |
|---|---|---|---|---|---|
| RUN | kept | normal | none | none | none |
| LIGHT_SLEEP | kept | wakes automatically (wait states), then re-enters LS | LS | chip select held off; UPF retention | XPM `sleep` / clock enable |
| DEEP_SLEEP | kept | bus error | DS | chip select held off; periphery off (UPF) | XPM `sleep` / clock enable |
| SHUTDOWN | lost; zeroed by the clear engine before RUN is acknowledged | bus error | SD | power switched (UPF), isolation | contents X in simulation |

Entry and wake times come from `sram_pkg::pwr_enter_cycles` /
`pwr_wake_cycles`. They default to 2/2/4/8 cycles (SAED32: 4/2/8/16) and are to
be checked against the liberty timing at synthesis. While BIST runs, every
domain is held in RUN. UPF files for SAED90, SAED14 and SKY130 belong in
`design/upf/` (Step 10).

## Simulation Results

> Populated by Step 4 (directed_tests)

[TBD]

## Formal Verification Results

> Populated by Step 5 (formal)

[TBD]

## UVM Verification Results

> Populated by Step 6 (uvm)

[TBD]

## Lint Results

> Populated by Step 8 (lint)

[TBD]

## Firmware

> Populated by Step 9 (firmware): memory-test routines and power-mode helpers
> (there is no register-level driver).

### Code Size

[TBD]

### API Summary

[TBD]

## Synthesis Results

> Populated by Step 10 (synthesis)

[TBD]

## Power Analysis

> Populated by Step 12 (power)

[TBD]

## Directory Layout

```
sram/
├── setup.sh / cleanup.sh       environment (CLAUDE_SRAM_PATH) and artifact cleanup
├── design/
│   ├── behavioral/             reference model
│   ├── rtl/verilog, rtl/vhdl   RTL (SV and VHDL-2008)
│   └── upf/                    power intent for the PDKs without native sleep pins
├── doc/                        specification
├── firmware/                   memory-test and power-mode helpers (C99)
├── synthesis/                  Yosys, Vivado, Quartus, Design Compiler, PrimeTime
└── verification/               testbenches, tests, formal, lint, UVM, regression, tools
```

## Getting Started

```bash
source IP/system/sram/setup.sh      # sets CLAUDE_SRAM_PATH, IP_COMMON_PATH (and on
                                    # csun.edu CLAUDE_SKY130_PDK_PATH)
bash $CLAUDE_SRAM_PATH/cleanup.sh   # remove generated files
```
