# bus_matrix IP — Specification

## Overview

The `bus_matrix` IP block is a parameterized crossbar interconnect. It connects
`NUM_MASTERS` bus masters to `NUM_SLAVES` bus slaves, so different masters can
reach different slaves at the same time and contention for one slave is
arbitrated. It has no registers: the address map, arbitration mode and
priorities are elaboration-time parameters.

There are four bus-protocol top-levels: APB4, AHB-Lite, AXI4-Lite and Wishbone
B4 (classic). Each connects masters and slaves of that one protocol. All four
share the same protocol-independent core. Each is delivered in SystemVerilog
and VHDL-2008, with the same behavior in both.

## Features

- **1–16 masters, 1–32 slaves**, flat-packed port arrays (master `i` at slice
  `[i*W+:W]`, slave `j` at `[j*W+:W]`)
- **Base + mask address decoding** per slave: slave `j` is selected when
  `(addr & S_MASK[j]) == (S_BASE[j] & S_MASK[j])`; the lowest-numbered match
  wins; an address that matches no slave gets an error response
- **Per-slave arbitration**, one arbiter per slave:
  - Round robin (`ARB_MODE=1`, default): the first requester after the last
    granted master; master 0 is first after reset
  - Fixed priority (`ARB_MODE=0`): lowest `M_PRIORITY` value wins, ties go
    to the lower master index
- **Grant lock**: a grant is held until the owner's transaction completes, so
  no other master can take the slave mid-transaction
- **Error propagation**: decode errors and slave errors (`PSLVERR`, `HRESP`,
  `BRESP`/`RRESP[1]`, `ERR`) are returned to the requesting master
- **Default configuration = a real address map** (`bus_matrix_pkg`). It is the
  configuration that is synthesized, timed, simulated at gate level and
  power-analyzed, because a netlist cannot be re-parameterized.
- **Synchronous active-low reset** (`rst_n`) and a single clock (`clk`) on
  every variant
- **Dual-language delivery**: SystemVerilog and VHDL-2008

## Default configuration (`bus_matrix_pkg`)

| | |
|---|---|
| Masters | 2: M0 = CPU, M1 = DMA |
| Slaves | 4 |
| Arbitration | Round robin (M0 priority 0, M1 priority 1, used only if `ARB_MODE=0`) |

| Slave | Region | Base | Mask | Size |
|-------|--------|------|------|------|
| S0 | Boot ROM    | `0x0000_0000` | `0xFFFF_0000` | 64 KB |
| S1 | SRAM        | `0x2000_0000` | `0xFFFE_0000` | 128 KB |
| S2 | Peripherals | `0x4000_0000` | `0xFFFF_0000` | 64 KB |
| S3 | External    | `0x6000_0000` | `0xF000_0000` | 256 MB |

Any other address is a decode error.

Round robin is the default because, with fixed priority, a CPU issuing
back-to-back AHB or Wishbone transfers can lock the DMA out for ever. VC
Formal found this: the master-port response bound could not be proven.

## Architecture

```text
   M0 port           M1 port            (external masters)
      |                 |
  [<proto>_tgt]     [<proto>_tgt]       target adapters: protocol slave -> core handshake
      |                 |
  +---+-----------------+-----------------------------------+
  |  [decoder]       [decoder]          one per master       |
  |      \  \       /   /                                    |  bus_matrix_core
  |     [arb S0] [arb S1] [arb S2] [arb S3]   one per slave  |
  |      AND-OR request routing / response routing           |
  +---+--------+--------+--------+--------------------------+
      |        |        |        |
  [<proto>_ini] ...                     initiator adapters: core handshake -> protocol master
      |        |        |        |
     S0       S1       S2       S3      (external slaves)
```

| Unit | File (`.sv` / `.vhd`) | Role |
|------|------|------|
| Package | `bus_matrix_pkg` | Default configuration (address map, arbitration) |
| Decoder | `bus_matrix_decoder` | Address → one-hot slave select, decode error |
| Arbiter | `bus_matrix_arb` | Fixed-priority or round-robin pick, grant lock |
| Core | `bus_matrix_core` | Decoders, arbiters, request/response routing, decode-error responder |
| Target adapter | `bus_matrix_<proto>_tgt` | One per master port; the matrix is a protocol slave |
| Initiator adapter | `bus_matrix_<proto>_ini` | One per slave port; the matrix is a protocol master |
| Top-level | `bus_matrix_<proto>` | Adapters + core, `<proto>` ∈ `apb`, `ahb`, `axi4l`, `wb` |

### Internal handshake

The same handshake is used by every protocol variant.

- **Master side:** a target adapter raises `mst_req[i]` and holds it, together
  with `mst_addr/wdata/we/be`, until `mst_done[i]` pulses for one cycle. Read
  data (`mst_rdata`) and the error flag (`mst_err`) are valid in that cycle.
- **Slave side:** `slv_req[j]` is high while slave `j` is granted. Its
  initiator adapter runs exactly one bus transaction and pulses `slv_done[j]`
  (with `slv_rdata`, `slv_err`).
- **Decode error:** a request that matches no slave never reaches an arbiter.
  The core answers it itself with `mst_done` + `mst_err` one cycle later.

## Interfaces

### Parameters / generics

| Name | Default | Range | Description |
|------|---------|-------|-------------|
| `NUM_MASTERS` | 2 | 1–16 | Active masters |
| `NUM_SLAVES`  | 4 | 1–32 | Active slaves |
| `DATA_W`      | 32 | 32 | Data bus width |
| `ADDR_W`      | 32 | 32 | Address width (the map is 32-bit) |
| `ARB_MODE`    | 1 | 0–1 | 0 = fixed priority, 1 = round robin |
| `M_PRIORITY`  | M0=0, M1=1 | 4 bits per master | Master `i` at `[i*4+:4]`, lower = higher priority |
| `S_BASE`      | map above | 32 bits per slave | Slave `j` base at `[j*32+:32]` |
| `S_MASK`      | map above | 32 bits per slave | Slave `j` mask at `[j*32+:32]` |

In SystemVerilog the vectors are `NUM_MASTERS*4` / `NUM_SLAVES*32` bits wide.
In VHDL they are fixed at the maximum width (16×4 and 32×32 bits), and only the
active entries are used.

### Bus protocol top-levels

| Module | Protocol | Master-port signals (`M_*`) | Slave-port signals (`S_*`) |
|--------|----------|------------------------------|-----------------------------|
| `bus_matrix_apb`   | APB4        | `PSEL PENABLE PADDR PWRITE PWDATA PSTRB` → `PRDATA PREADY PSLVERR` | mirror image |
| `bus_matrix_ahb`   | AHB-Lite    | `HSEL HADDR HTRANS HWRITE HWDATA HWSTRB` → `HREADY HRDATA HRESP` | `HSEL … HWSTRB` → / ← `HREADY(OUT) HRDATA HRESP` |
| `bus_matrix_axi4l` | AXI4-Lite   | `AW*`, `W*`, `B*`, `AR*`, `R*` channels | mirror image |
| `bus_matrix_wb`    | Wishbone B4 | `CYC STB WE ADR DAT_I SEL` → `DAT_O ACK ERR` | `CYC STB WE ADR DAT_O SEL` ← `DAT_I ACK ERR` |

Every port signal is flat-packed: `M_<sig>` is `NUM_MASTERS × width`, and
`S_<sig>` is `NUM_SLAVES × width`. All variants use `clk` and `rst_n`.

### Per-protocol behavior

- **APB4:** the master's ACCESS phase is the core request. `PREADY`/`PSLVERR`
  are the core's done/err, so ACCESS lasts as long as the routed
  transaction, including any wait for arbitration. The slave side runs one
  SETUP + ACCESS per grant, with `PSTRB = 0` on reads.
- **AHB-Lite:** an address phase with `HTRANS[1]` set (NONSEQ or SEQ; every
  beat is treated as a single transfer) starts a request. The data phase is
  stalled with `HREADY` low until done. ERROR takes the two-cycle response.
  The slave side runs one single NONSEQ transfer per grant.
- **AXI4-Lite:** one write and one read may be outstanding per master port.
  Writes go first when both are waiting. AW and W are accepted in either
  order. Decode and slave errors come back as SLVERR. The slave side runs one
  transaction per grant, holding `BREADY`/`RREADY` high throughout.
- **Wishbone B4 classic:** `CYC & STB` is the request, and `ACK`/`ERR` is the
  core's done split by err. Back-to-back transfers are supported (STB held
  high after a termination).

## Timing

- **Arbitration:** the grant is registered. It is set on the clock edge after a
  request is seen with the slave free, and cleared on the edge where the
  slave's transaction completes. No new grant is made on the edge that
  releases one, so a slave sits idle for one cycle between transactions.
- **Slave request:** `slv_req` comes straight from the registered grant, so a
  slave-side transaction starts the cycle after the grant edge.
- **Responses** pass back to the master combinationally in the cycle the slave
  completes. APB, AHB and Wishbone masters see done in the same cycle as the
  slave. AXI4-Lite registers the response onto B/R.
- **Decode error:** answered one cycle after the request.
- **Maximum frequency:** 100 MHz is met on SAED32, SAED14 and SKY130 (all
  three corners). SAED90 misses by up to 0.56 ns pre-layout; this is accepted,
  see `synthesis/known_issues.md`.

## Known Limitations

- **No bursts or pipelining.** Each slave-side grant is exactly one single
  transfer. AHB SEQ beats are handled as singles, and the AHB slave side never
  overlaps address and data phases.
- **One idle cycle on a slave between grants**, even when the same master asks
  again.
- **Wishbone transfer abort is not supported:** a master must not drop
  `CYC`/`STB` before `ACK`/`ERR`.
- **Decode errors are reported as the protocol's slave error** (`PSLVERR`,
  `HRESP`=ERROR, `SLVERR`, `ERR`). AXI4-Lite does not use `DECERR`.
- **Address width is fixed at 32 bits** (the address map is 32-bit).
- **Per-master priorities apply only in fixed-priority mode**. In that mode a
  continuously requesting high-priority master can starve the others.
- **Gate-level results cover only the default configuration** (`bus_matrix_pkg`).
