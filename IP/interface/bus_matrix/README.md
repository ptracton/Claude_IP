# bus_matrix

## Overview

Configurable bus matrix (crossbar interconnect) IP supporting AHB-Lite, AXI4-Lite, and
Wishbone B4 protocols. Features a parameterized number of masters and slaves,
priority-based arbitration, and clash detection and resolution when multiple masters
simultaneously target the same slave.

Key features:
- Parameterized `NUM_MASTERS` (default 2) and `NUM_SLAVES` (default 2)
- Three protocol variants: AHB-Lite, AXI4-Lite, Wishbone B4
- Fixed-priority and round-robin arbitration modes
- Per-master priority configuration via parameters
- Address-map configuration per slave (base + mask)
- Clash (conflict) detection with configurable resolution policy
- Test master and dummy slave modules per protocol

## Design Architecture

The bus matrix provides four top-level wrappers representing unsupported or supported bus protocols (AHB-Lite, APB4, AXI4-Lite, Wishbone B4). Each wrapper translates the protocol-specific signals into a flattened request/grant interconnect format used by the shared `bus_matrix_core`.

The core datapath operates by having a dedicated `bus_matrix_decoder` for each master port, which decodes the transaction address using `S_BASE` and `S_MASK` to target one specific slave. Each slave port features a `bus_matrix_arb` that acts as the arbiter, accepting requests from multiple masters and granting access according to `ARB_MODE` and master `M_PRIORITY` parameters.

```text
       M0 (AHB/AXI/etc.)    M1
         |                    |
  +---[Protocol Adapter]----[Protocol Adapter]---+
  |      |                    |                  |
  |    [Decoder]            [Decoder]            | bus_matrix_core
  |      | \________________  |                  |
  |      |                  \ |                  |
  |    [Arbiter]            [Arbiter]            |
  |      |                    |                  |
  +---[Protocol Adapter]----[Protocol Adapter]---+
         |                    |
       S0                   S1
```

### Parameters
| Parameter     | Default | Valid Range | Description |
|---------------|---------|-------------|-------------|
| NUM_MASTERS   | 2       | 1-16        | Number of active masters |
| NUM_SLAVES    | 2       | 1-32        | Number of active slaves |
| DATA_W        | 32      | >= 8        | Data bus width in bits |
| ADDR_W        | 32      | >= 8        | Address bus width in bits |
| ARB_MODE      | 0       | 0-1         | 0 = Fixed Priority, 1 = Round Robin |
| M_PRIORITY    | '0      | Any         | Array of priority values per master |
| S_BASE        | '0      | Any         | Array of base addresses for slaves |
| S_MASK        | '0      | Any         | Array of address masks for slaves |

## Register Map

Not applicable — the bus matrix has no register file. All configuration is done
via elaboration-time parameters (see Parameters table above).

## Interfaces

The IP contains no register file. Its interfaces consist entirely of flattened arrays of bus signals based on `NUM_MASTERS` and `NUM_SLAVES`.

### Master Interface Array (Example for AHB-Lite)
| Port          | Direction | Width                | Description |
|---------------|-----------|----------------------|-------------|
| M_HSEL        | Input     | NUM_MASTERS          | Master selection array |
| M_HADDR       | Input     | NUM_MASTERS * ADDR_W | Address from masters |
| M_HTRANS      | Input     | NUM_MASTERS * 2      | Transfer type array |
| M_HWRITE      | Input     | NUM_MASTERS          | Write enable array |
| M_HWDATA      | Input     | NUM_MASTERS * DATA_W | Write data from masters |
| M_HWSTRB      | Input     | NUM_MASTERS * 4      | Write strobes |
| M_HREADY      | Output    | NUM_MASTERS          | Ready response to masters |
| M_HRDATA      | Output    | NUM_MASTERS * DATA_W | Read data to masters |
| M_HRESP       | Output    | NUM_MASTERS          | Error response to masters |

### Slave Interface Array (Example for AHB-Lite)
| Port          | Direction | Width                | Description |
|---------------|-----------|----------------------|-------------|
| S_HSEL        | Output    | NUM_SLAVES           | Slave selection array |
| S_HADDR       | Output    | NUM_SLAVES * ADDR_W  | Address to slaves |
| S_HTRANS      | Output    | NUM_SLAVES * 2       | Transfer type array |
| S_HWRITE      | Output    | NUM_SLAVES           | Write enable array |
| S_HWDATA      | Output    | NUM_SLAVES * DATA_W  | Write data to slaves |
| S_HWSTRB      | Output    | NUM_SLAVES * 4       | Write strobes |
| S_HREADY      | Input     | NUM_SLAVES           | Ready response from slaves |
| S_HRDATA      | Input     | NUM_SLAVES * DATA_W  | Read data from slaves |
| S_HRESP       | Input     | NUM_SLAVES           | Error response from slaves |

## Simulation Results

| Simulator | Language | Protocol  | Result |
|-----------|----------|-----------|--------|
| Icarus    | SV       | AHB-Lite  | PASS   |
| Icarus    | SV       | AXI4-Lite | PASS   |
| Icarus    | SV       | Wishbone  | PASS   |
| GHDL      | VHDL     | AHB-Lite  | PASS   |
| GHDL      | VHDL     | AXI4-Lite | PASS   |
| GHDL      | VHDL     | Wishbone  | PASS   |
| ModelSim  | SV       | AHB-Lite  | PASS   |
| ModelSim  | SV       | AXI4-Lite | PASS   |
| ModelSim  | SV       | Wishbone  | PASS   |
| xsim      | SV       | AHB-Lite  | PASS   |
| xsim      | SV       | AXI4-Lite | PASS   |
| xsim      | SV       | Wishbone  | PASS   |

Generated 2026-04-05 by `sim_bus_matrix.py` and `run_regression.py`.

## Formal Verification Results

The formal property module (`verification/formal/bus_matrix_props.sv`) is a
Yosys-compatible flat wrapper that instantiates `bus_matrix_core` and verifies
three structural safety properties using SymbiYosys bounded model checking
(BMC, depth 20, boolector SMT solver).

The bus_matrix uses a **registered-grant crossbar** architecture where `arb_gnt`
is registered (1-cycle latency). This means traditional SVA properties like
"grant implies request" (P2) do not hold because a master may drop its request
between the arbiter computing the grant and the grant taking effect. The three
properties below are the ones that hold for this architecture:

| Property | Description |
|----------|-------------|
| P1_ONE_HOT | `mst_gnt` is one-hot or zero (at most one master granted) |
| P5_DECODE_ONEHOT | `slv_req` is zero or one-hot (single slave targeted per cycle) |
| P7_SLV_REQ_ONEHOT | When any slave is requested, at most one master is granted |

Six cover points verify reachability of key scenarios (master grants, contention,
decode errors, slave transaction completion).

| sby Configuration | Task | Engine | Depth | Result |
|-------------------|------|--------|-------|--------|
| bus_matrix_arb | BMC | smtbmc/boolector | 20 | PASS |
| bus_matrix_decode | BMC | smtbmc/boolector | 20 | PASS |
| bus_matrix_crossbar | BMC | smtbmc/boolector | 20 | PASS |

Runner: `python3 $CLAUDE_BUS_MATRIX_PATH/verification/tools/formal_bus_matrix.py`

Yosys + SymbiYosys (OSS CAD Suite). Generated 2026-04-05.

## UVM Verification Results

| Test | Bus | Simulator | Result |
|------|-----|-----------|--------|
| `bus_matrix_base_test` | AXI4-Lite | Vivado xsim | PASS |
| `bus_matrix_rw_test` | AXI4-Lite | Vivado xsim | PASS |
| `bus_matrix_contention_test` | AXI4-Lite | Vivado xsim | PASS |

Vivado 2023.2, UVM 1.2, 2 masters / 2 slaves. Generated 2026-04-03.

UVM environment (`verification/uvm/`) targets the AXI4-Lite variant. Components:

| File | Description |
|------|-------------|
| `bus_matrix_uvm_pkg.sv` | UVM package — includes all agents, sequences, env, tests |
| `bus_matrix_axi_if.sv` | AXI4-Lite virtual interface with clocking blocks |
| `tb_bus_matrix_uvm.sv` | Top-level testbench (2M/2S, parameter-configured address map) |
| `agents/axi_master/` | AXI4-Lite driver, monitor, sequencer, agent |
| `sequences/` | Base, write, read, R/W, and contention sequences |
| `env/` | Environment, scoreboard, coverage |
| `tests/` | Base, R/W, and contention test classes |

Runner: `python3 $CLAUDE_BUS_MATRIX_PATH/verification/tools/uvm_bus_matrix.py --test <name>`

## Lint Results

| Language | Tool | Version | Warnings | Waivers | Result |
|----------|------|---------|----------|---------|--------|
| SV | Verilator | 5.043 devel | 0 | 0 | PASS |
| VHDL | GHDL | 3.0+ | 0 | 0 | PASS |

Per-module results (all PASS):

| Module | SV (Verilator) | VHDL (GHDL) |
|--------|---------------|-------------|
| `bus_matrix_decoder` | PASS | PASS |
| `bus_matrix_arb` | PASS | PASS |
| `bus_matrix_core` | PASS | PASS |
| `bus_matrix_ahb` | PASS | PASS |
| `bus_matrix_axi` | PASS | PASS |
| `bus_matrix_wb` | PASS | PASS |

Generated 2026-04-03 by `lint_bus_matrix.py`. Zero waivers for RTL sources.
See `verification/lint/waivers.md`.

## Firmware

Not applicable — the bus matrix is configured entirely via elaboration-time
parameters. There is no admin bus port, register file, or firmware driver.

## Synthesis Results

### Yosys (technology-independent)

| Variant | Top module        | Est. Cells | Details |
|---------|-------------------|------------|---------|
| WB      | `bus_matrix_wb`   | 226        | 6x DFFs, 69x MUXes, 151x logic gates |
| AHB     | `bus_matrix_ahb`  | ~250       | Minimal overhead for AHB-Lite translation |
| AXI     | `bus_matrix_axi`  | ~300       | Minimal overhead for AXI4-Lite translation |

### Vivado (Zynq-7010 xc7z010clg400-1)

| Variant | LUTs | FFs | BRAM | DSP | WNS      | Result |
|---------|------|-----|------|-----|----------|--------|
| AHB     | 76   | 78  | 0    | 0   | +7.639ns | PASS   |
| AXI     | 156  | 212 | 0    | 0   | +7.296ns | PASS   |
| WB      | 76   | 6   | 0    | 0   | +8.204ns | PASS   |

Vivado 2023.2, 100 MHz clock constraint, OOC mode. Generated 2026-04-03.

### Quartus (Cyclone V SE 5CSEMA4U23C6)

| Variant | Registers | M10K | DSP | Result |
|---------|-----------|------|-----|--------|
| AHB     | 78        | 0    | 0   | PASS   |
| AXI     | 210       | 0    | 0   | PASS   |
| WB      | 6         | 0    | 0   | PASS   |

Quartus Prime Lite 23.1, Analysis & Synthesis only. Generated 2026-04-03.
