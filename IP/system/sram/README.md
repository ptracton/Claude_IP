# sram

## Overview

Configurable on-chip SRAM with a bus slave port. One RTL source targets
every supported technology by wrapping its SRAM primitives: the SAED90,
SAED32 and SAED14 macros, SkyWater SKY130 OpenRAM macros, Xilinx XPM block
RAM, Intel/Altera `altsyncram`, and a generic behavioral array.

Key features:
- **Bus interfaces:** APB4, AHB-Lite (bursts, HSIZE), AXI4-Lite and Wishbone B4,
  one top-level each, built on the shared `claude_<proto>_mem_if` adapters.
- **Configurable size:** width and depth are parameters. Each ASIC technology
  wrapper builds the requested width x depth from its vendor primitives, with
  generate loops: primitives side by side for width, stacked for depth (the
  upper address bits pick the row). FPGA and generic memories are inferred
  whole and the tool does the tiling.
- **Byte enables (optional):** native byte masks where the macro has them,
  otherwise one column of 8-bit primitives per byte lane.
- **Power gating:** RUN / LIGHT_SLEEP / DEEP_SLEEP / SHUTDOWN through a
  side-band request/acknowledge pair. These map onto the SAED32 low-power
  macros' LS/DS/SD pins, or onto UPF power domains with isolation on the
  other ASIC PDKs.
- **Always present:** bus error for out-of-range addresses and for access to a
  deep-sleeping or shut-down array, optional output register, clear engine,
  status outputs.
- **Optional, each switchable by a parameter:** SECDED ECC, per-bank power
  gating, March C- built-in self-test, and a second bus port. The second port
  may have a different width (and so depth) and its own clock.

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
     │   ├── sram_ecc_enc / sram_ecc_dec   SECDED, one per codeword (ECC_EN)
     ├── sram_cdc             port B on its own clock (COMMON_CLK = 0): permission
     │                        handshake, claude_sync / claude_pulse_sync (IP/common)
     ├── sram_pwr_ctrl        one power state machine per domain (whole array or bank)
     ├── sram_clr             clear engine (clr_req_i, after reset with ECC, after shutdown)
     ├── sram_bist            March C- engine (BIST_EN)
     └── sram_array           NUM_BANKS banks (power domains), bank select + read mux;
                              dual port with different widths: R slices per bank
         └── sram_macro / sram_macro_dp      TECH dispatcher (single- / two-port), any W x D
             └── sram_macro[_dp]_<tech>      saed90 | saed32 | saed14 | sky130: rows x columns
                                             of vendor primitives; generic | xilinx | altera:
                                             one inferred memory
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

**Dual port.** Ports A and B run in parallel on two-port macros.
- *Widths.* Port B has `WIDTH_B` bits (`WIDTH / WIDTH_B` a power of two
  either way) and `DEPTH_B = WIDTH * DEPTH / WIDTH_B` words of the same
  storage. Both ports use the same byte addresses: narrow word `j` is bits
  `[(j % R) * N +: N]` of wide word `j / R` (little-endian, `R` = ratio, `N` =
  narrow width). `sram_array` builds each bank from `R` slices of the narrow
  width: the wide port drives all slices, the narrow port one.
- *ECC.* Codewords are as wide as the narrower port, and each codeword is one
  write lane. A narrow write never needs a read of the wide word, and a wide
  read-modify-write only writes back the codewords it strobes.
- *Clocks.* Each port has its own clock and reset pins.
  - `COMMON_CLK = 1` (default): drive both clock pins from the same clock.
    Same-word conflicts complete in the order A then B: B waits a cycle if
    either access writes, and a port waits while the other port's
    read-modify-write of that word is pending. Conflicting writes are
    serialized, never dropped.
  - `COMMON_CLK = 0`: the clocks are unrelated, and same-word accesses in
    overlapping cycles are undefined (as on any true dual-port RAM). Power,
    clear, BIST and status stay on port A's clock. Port B reaches them
    through `sram_cdc`: a four-phase permission handshake per power domain,
    built from 2-flop synchronizers (`claude_sync`, `claude_pulse_sync` in
    IP/common). The core takes the permission back, and waits for port B's
    last access to finish, before a domain sleeps or an engine starts. Port
    B's clock must keep running while that happens.
  - SAED14's two-port macro (`SRAM2RW`) has a write clock and a read clock,
    not one clock per port (liberty and model agree), so `TECH_SAED14` needs
    `COMMON_CLK = 1`. SAED90, SAED32, SKY130 and the FPGA/generic memories
    support both modes.

**Tiling.** `sram_array` splits the array into `NUM_BANKS` banks of
`DEPTH / NUM_BANKS` words, one `sram_macro` wrapper each. Each ASIC wrapper
(`sram_macro[_dp]_<tech>`) builds its W x D bank from vendor primitives:
- `sram_pkg::prim_width` / `prim_depth` (and the `_dp` versions) pick one
  primitive size `PRIM_W x PRIM_D`: the deepest available one that is not
  deeper than D.
- `ROWS = D / PRIM_D` primitives are stacked in depth. The address bits above
  the primitive address drive the rows' chip selects, and a registered row
  select steers the read multiplexer. If D is smaller than every primitive,
  there is one row and the top address bits are tied to 0.
- `COLS = ceil(W / PRIM_W)` primitives sit side by side. The last column is
  zero-padded when `PRIM_W` does not divide W.
- SAED primitives have no byte mask, so each column must lie inside one write
  lane (byte lanes use 8-bit primitives). This is checked at elaboration.
  SKY130 primitives have a native byte mask.

For example, 16 x 2048 on SAED32 uses `1024x8` primitives in 2 rows x 2
columns, with `addr[10]` selecting the row. GENERIC, XILINX and ALTERA
infer one W x D memory per bank (`xpm_memory_*` / `altsyncram` accept any
size) and leave block-RAM cascading to Vivado / Quartus.

| TECH | Single-port macros | Two-port macros | Byte mask |
|---|---|---|---|
| GENERIC | behavioral array | behavioral array | yes |
| XILINX | `xpm_memory_spram` | `xpm_memory_tdpram` | yes |
| ALTERA | `altsyncram` SINGLE_PORT | `altsyncram` BIDIR_DUAL_PORT | yes |
| SAED90 | `SRAM{8,32}x{64..1024}_1rw` | `SRAM{8,32}x{16..128}`, `SRAM39x32` | no (x8 lanes) |
| SAED32 | `SRAMLP1RW{64..1024}x{8,32}` | `SRAMLP2RW{16..128}x{8,32}` | no (x8 lanes) |
| SAED14 | `SRAM1RW{16..512}x{8,32}` | `SRAM2RW{16..512}x{8,32}` | no (x8 lanes) |
| SKY130 | OpenRAM `sky130_sram_*_1rw1r_*` (port 1 unused) | same macros, port B read-only | yes (`wmask`) |

Default configuration (32 x 1024, byte enables): SAED90/SAED32 use 1 row x 4
columns of `8x1024` / `1024x8`; SAED14 uses 2 rows x 4 columns of `512x8`;
SKY130 uses 2 rows x 1 column of `32x512`.

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
single-port top-levels. The dual-port top-levels add:

| Parameter | Range | Default | Meaning |
|---|---|---|---|
| `WIDTH_B` | 8..128, multiple of 8, `WIDTH / WIDTH_B` a power of two | `WIDTH` | port B data width; port B has `WIDTH * DEPTH / WIDTH_B` words |
| `BYTE_EN_B`, `PARTIAL_WR_ERR_B`, `READ_LATENCY_B` | as for port A | port A's | port B options |
| `COMMON_CLK` | 0/1 | 1 | 1: the B clock is the A clock; 0: unrelated clocks (not `TECH_SAED14`) |

**Memory map.** Word `n` sits at byte offset `n * WIDTH / 8` of the slave
port. Addresses at or beyond `DEPTH * WIDTH / 8` get the bus error response,
and the contents are unchanged. Narrow AHB transfers use the byte lanes given
by HSIZE/HADDR. In a dual-port top, port B sees the same bytes at the same
offsets (its word `j` is at `j * WIDTH_B / 8`, `DEPTH_B` words).

## Interfaces

### Bus ports

| Top-level | Bus signals | Notes |
|---|---|---|
| `sram_apb` | `PCLK PRESETn PSEL PENABLE PADDR PWRITE PWDATA PSTRB PRDATA PREADY PSLVERR` | PSLVERR on error |
| `sram_ahb` | `HCLK HRESETn HSEL HADDR HTRANS HWRITE HSIZE HWDATA HWSTRB HREADY HRDATA HREADYOUT HRESP` | bursts, BUSY, HSIZE; HREADY in / HREADYOUT out |
| `sram_axi4l` | `ACLK ARESETn AW* W* B* AR* R*` | BRESP/RRESP = SLVERR on error |
| `sram_wb` | `CLK_I RST_I CYC_I STB_I WE_I ADR_I DAT_I SEL_I DAT_O ACK_O ERR_O` | classic cycles; ERR_O on error |
| `sram_<proto>_dp` | the above, twice: `A_*` and `B_*`, each with its own clock and reset (`A_PCLK`/`B_PCLK`, ...); port B's data and strobes are `WIDTH_B` wide | side-band on port A's clock |

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

Inputs of disabled options must be tied to 0. Their outputs stay 0. All
side-band ports are synchronous to port A's clock; with `COMMON_CLK = 0`,
port B's events reach `ecc_*_o` / `err_irq_o` through pulse synchronizers.

### `sram_core`

| Port group | Signals |
|---|---|
| clock / reset | `clk`, `rst_n` (synchronous, active low); `clk_b`, `rst_b_n` for port B (single port: tie to `clk` / `rst_n`) |
| memory bus, port A | `mem_req_i mem_gnt_o mem_we_i mem_addr_i mem_be_i mem_wdata_i mem_rvalid_o mem_rdata_o mem_err_o` |
| memory bus, port B | the same names with `mem_b_`, `WIDTH_B` wide (DUAL_PORT; tie off otherwise) |
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
