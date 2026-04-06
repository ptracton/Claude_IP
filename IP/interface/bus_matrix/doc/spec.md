# bus_matrix — Specification

## Overview

The `bus_matrix` IP is a configurable crossbar interconnect that connects multiple bus
masters to multiple bus slaves. It supports three industry-standard bus protocols:
AHB-Lite, AXI4-Lite, and Wishbone B4. The matrix is fully parameterized, allowing the
number of masters and slaves to be adjusted at elaboration time without changing the RTL
source.

All configuration — address map, arbitration mode, and master priorities — is done via
elaboration-time parameters. There are no runtime registers, no admin bus port, and no
firmware required.

Each master port has its own independent arbitration channel. When a master requests
access to a slave, the bus matrix decodes the target address, selects the appropriate
slave, and grants the connection. If multiple masters simultaneously request the same
slave, the clash-detection logic selects a winner based on the configured arbitration
policy (fixed-priority or round-robin) and holds off the losing masters until the slave
becomes free.

The bus matrix is intended for use in SoC interconnect fabrics where a small number of
high-bandwidth masters (e.g., a CPU, a DMA engine, a debug port) need low-latency access
to a collection of memory-mapped peripherals or memory banks.

## Features

- **Parameterized topology**: `NUM_MASTERS` (1–16) and `NUM_SLAVES` (1–32) are top-level
  parameters. All flat-packed port widths scale automatically.
- **Multi-protocol support**: Three independent RTL variants share a common arbitration
  core:
  - AHB-Lite (AMBA 3 AHB-Lite): single-phase pipeline, split/retry not supported.
  - AXI4-Lite: separate read/write channels, no bursts, no exclusive access.
  - Wishbone B4: classic and pipelined (registered feedback) cycle types.
- **Arbitration modes** (selectable per instantiation via `ARB_MODE` parameter):
  - `0` (FIXED_PRIORITY): uses per-master priority values from `M_PRIORITY` parameter.
    Lowest numerical value wins; ties broken by lowest master index.
  - `1` (ROUND_ROBIN): rotating priority, equal long-term bandwidth share.
- **Address map via parameters**: Each slave occupies a contiguous region defined by a
  `S_BASE` and `S_MASK` parameter pair, flat-packed into vectors. No runtime
  reconfiguration needed.
- **Clash detection and resolution**: A dedicated clash-detection unit monitors all
  master requests each cycle. When two or more masters target the same slave
  simultaneously, only the highest-priority master is granted; the others receive a
  wait/stall response until the slave becomes available.
- **Zero-latency decode path**: Address decoding is purely combinational; no extra clock
  cycles are added to the grant path when no conflict exists.
- **Single-cycle arbitration**: Conflict resolution completes within one clock cycle for
  the fixed-priority mode.
- **No firmware required**: The bus matrix is entirely configured at synthesis/elaboration
  time. There is no admin bus port, no register file, and no firmware driver.

## Interfaces

### Top-level parameters

| Parameter    | Default | Range  | Description                                                |
|--------------|---------|--------|------------------------------------------------------------|
| NUM_MASTERS  | 2       | 1–16   | Number of active master ports                              |
| NUM_SLAVES   | 2       | 1–32   | Number of active slave ports                               |
| DATA_W       | 32      | 32     | Data bus width (bits)                                      |
| ADDR_W       | 32      | 32     | Address bus width (bits)                                   |
| ARB_MODE     | 0       | 0–1    | Arbitration mode: 0=fixed-priority, 1=round-robin          |
| M_PRIORITY   | '0      | —      | Flat-packed master priorities [i*4+:4], 4 bits per master  |
| S_BASE       | '0      | —      | Flat-packed slave base addresses [j*32+:32]                |
| S_MASK       | '0      | —      | Flat-packed slave address masks [j*32+:32]                 |

**Address decode**: Slave j matches address `addr` when
`(addr & S_MASK[j*32+:32]) == (S_BASE[j*32+:32] & S_MASK[j*32+:32])`.
Lowest-numbered matching slave wins (priority encoding).

### Master ports (flat-packed, `NUM_MASTERS` active)

Each master port is sliced from a flat-packed vector at index `[i*W +:W]`.

**AHB variant** — `M_HSEL[i]`, `M_HADDR[i*32+:32]`, `M_HTRANS[i*2+:2]`,
`M_HWRITE[i]`, `M_HWDATA[i*32+:32]`, `M_HWSTRB[i*4+:4]` (inputs);
`M_HREADY[i]`, `M_HRDATA[i*32+:32]`, `M_HRESP[i]` (outputs).

**AXI4-Lite variant** — Standard AW/W/B/AR/R channels per master, flat-packed.

**Wishbone variant** — `M_CYC[i]`, `M_STB[i]`, `M_WE[i]`, `M_ADR[i*32+:32]`,
`M_DAT_I[i*32+:32]`, `M_SEL[i*4+:4]` (inputs); `M_ACK[i]`, `M_ERR[i]`,
`M_DAT_O[i*32+:32]` (outputs).

### Slave ports (flat-packed, `NUM_SLAVES` active)

Mirror of master ports with directions inverted.

## Timing

### Arbitration latency (AHB, worst case)
- Address decode: combinational (0 cycles)
- Grant (no contention): 1 clock cycle (registered arbiter output)
- Grant (with contention): 1 clock cycle to select winner, losing masters
  wait until the winner's transaction completes (slave ACK/READY)

### Synthesis results (Yosys, generic standard cells, NUM_MASTERS=2, NUM_SLAVES=2)

| Variant        | Cells  | Registers (FFs) |
|----------------|--------|-----------------|
| bus_matrix_ahb | ~2100  | ~280            |
| bus_matrix_axi | ~2150  | ~310            |
| bus_matrix_wb  | ~2000  | ~260            |

*Cell counts are technology-independent (ABC generic cells). FPGA LUT counts
will differ. Run the Vivado or Quartus scripts for device-specific numbers.*

## VHDL Notes

VHDL-2008 does not support generics whose size depends on other generics. The VHDL
wrappers use maximum-width constants:
- `S_BASE`, `S_MASK`: `std_ulogic_vector(32*32-1 downto 0)` — supports up to 32 slaves
- `M_PRIORITY`: `std_ulogic_vector(16*4-1 downto 0)` — supports up to 16 masters

Only the lower `NUM_SLAVES` / `NUM_MASTERS` entries are used by the design.

## Known Limitations

- **Single outstanding transaction per master (AXI)**: The AXI master-side
  adapter supports one in-flight transaction per master. Out-of-order or
  interleaved transactions are not supported.
- **No AHB split/retry**: The AHB adapter uses HREADY only; HSPLIT and
  HRETRY responses are not generated or consumed.
- **No burst support**: AHB and AXI adapters only accept NONSEQ / single
  transfers. Burst transactions must be broken into individual beats by the
  master BFM or SoC interconnect layer above.
- **Registered grant latency**: The arbiter grant (`arb_gnt`) is registered,
  adding one clock cycle of latency. This means a master can drop its request
  between grant computation and grant assertion. Traditional SVA properties
  like "grant implies request" do not hold; formal verification uses
  structural one-hot properties instead.
