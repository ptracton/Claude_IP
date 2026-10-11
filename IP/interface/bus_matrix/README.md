# bus_matrix

## Overview

A parameterized crossbar interconnect. It connects `NUM_MASTERS` bus masters to
`NUM_SLAVES` bus slaves, so different masters can reach different slaves at
the same time, and contention for one slave is arbitrated per slave. It has
four protocol variants (APB4, AHB-Lite, AXI4-Lite, Wishbone B4 classic), each
in SystemVerilog and VHDL-2008. Each variant connects masters and slaves of
that protocol.

Key features:
- 1–16 masters, 1–32 slaves, flat-packed port arrays
- Base + mask address decoding per slave; unmapped addresses get the
  protocol's error response
- One arbiter per slave: round robin (default) or fixed priority, and the
  grant is locked until the transaction completes
- Slave errors are passed back to the requesting master
- No registers: configuration is by elaboration-time parameters
- **The default configuration is a real address map** (`bus_matrix_pkg`), and
  it is the configuration that is synthesized, timed, simulated at gate level
  and power-analyzed

Full specification: [doc/spec.md](doc/spec.md).

## Design Architecture

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

- **Protocol-agnostic core** (`bus_matrix_core`): one decoder per master and
  one arbiter per slave, with AND-OR routing of the owner's request and of the
  slave's response. Decode errors are answered by the core itself, one cycle
  later.
- **Arbiter** (`bus_matrix_arb`): the grant is registered and held until the
  slave's transaction completes. No new grant is made on the edge that
  releases one, so a slave is idle for one cycle between transactions.
- **Adapters**: a target adapter (`bus_matrix_<proto>_tgt`) per master port
  turns each protocol transfer into one request on the internal handshake. An
  initiator adapter (`bus_matrix_<proto>_ini`) per slave port runs exactly
  one protocol transfer per grant.

### Default configuration (`bus_matrix_pkg`)

2 masters (M0 = CPU, M1 = DMA), 4 slaves, round robin:

| Slave | Region | Base | Mask | Size |
|-------|--------|------|------|------|
| S0 | Boot ROM    | `0x0000_0000` | `0xFFFF_0000` | 64 KB |
| S1 | SRAM        | `0x2000_0000` | `0xFFFE_0000` | 128 KB |
| S2 | Peripherals | `0x4000_0000` | `0xFFFF_0000` | 64 KB |
| S3 | External    | `0x6000_0000` | `0xF000_0000` | 256 MB |

Round robin is the default. With fixed priority, a CPU issuing back-to-back
AHB or Wishbone transfers starves the DMA (found by VC Formal, see below).

### Parameters

| Parameter | Default | Valid Range | Description |
|-----------|---------|-------------|-------------|
| `NUM_MASTERS` | 2 | 1–16 | Active masters |
| `NUM_SLAVES`  | 4 | 1–32 | Active slaves |
| `DATA_W`      | 32 | 32 | Data bus width |
| `ADDR_W`      | 32 | 32 | Address width |
| `ARB_MODE`    | 1 | 0–1 | 0 = fixed priority, 1 = round robin |
| `M_PRIORITY`  | M0=0, M1=1 | 4 bits/master | Lower value = higher priority (fixed priority only) |
| `S_BASE`      | map above | 32 bits/slave | Slave `j` base at `[j*32+:32]` |
| `S_MASK`      | map above | 32 bits/slave | Slave `j` mask at `[j*32+:32]` |

## Register Map

Not applicable. The bus matrix has no register file; all configuration is by
elaboration-time parameters (see Parameters above).

## Interfaces

| Module | Protocol | Master ports (`M_*`, matrix is the slave) | Slave ports (`S_*`, matrix is the master) |
|--------|----------|------------------------------|-----------------------------|
| `bus_matrix_apb`   | APB4        | `PSEL PENABLE PADDR PWRITE PWDATA PSTRB` → `PRDATA PREADY PSLVERR` | mirror image |
| `bus_matrix_ahb`   | AHB-Lite    | `HSEL HADDR HTRANS HWRITE HWDATA HWSTRB` → `HREADY HRDATA HRESP` | `HSEL HADDR HTRANS HWRITE HWDATA HWSTRB` ← `HREADY HRDATA HRESP` |
| `bus_matrix_axi4l` | AXI4-Lite   | `AW*`, `W*`, `B*`, `AR*`, `R*` | mirror image |
| `bus_matrix_wb`    | Wishbone B4 | `CYC STB WE ADR DAT_I SEL` → `DAT_O ACK ERR` | `CYC STB WE ADR DAT_O SEL` ← `DAT_I ACK ERR` |

Every signal is flat-packed: master `i` at `[i*W+:W]` of `M_<sig>`, and slave
`j` at `[j*W+:W]` of `S_<sig>`. All variants use `clk` and a synchronous
active-low `rst_n`. Per-protocol behaviour is described in
[doc/spec.md](doc/spec.md).

## Simulation Results

Directed simulation in SystemVerilog and VHDL-2008. Each run executes six
protocol-neutral tests (`verification/tests/`), 82 checks in total:

| Test | Checks |
|------|--------|
| `test_reset` | Every master reads every slave after reset (data and OKAY) |
| `test_route` | Each master writes every slave and the other master reads it back, plus the top word of each slave |
| `test_strobe` | Byte-lane writes from both masters; an all-zero strobe writes nothing |
| `test_decode_err` | Unmapped and gap addresses return errors and never reach a slave; good traffic still works afterwards |
| `test_contention` | Both masters hammer the same slave and other slaves in parallel |
| `test_arb` | Simultaneous requests are granted in round-robin order |

Master side: the shared, handshake-correct BFMs in
`IP/common/verification/tasks/`. Slave side: the shared `claude_<proto>_if`
bridge plus a 4 KB memory per slave (`bus_matrix_tb_mem`).

| Variant | Simulator | SV | VHDL |
|---------|-----------|----|------|
| APB4      | Synopsys VCS Y-2026.03  | PASS (82) | PASS (82) |
| AHB-Lite  | Synopsys VCS Y-2026.03  | PASS (82) | PASS (82) |
| AXI4-Lite | Synopsys VCS Y-2026.03  | PASS (82) | PASS (82) |
| Wishbone  | Synopsys VCS Y-2026.03  | PASS (82) | PASS (82) |
| APB4      | Cadence Xcelium 25.03   | PASS (82) | PASS (82) |
| AHB-Lite  | Cadence Xcelium 25.03   | PASS (82) | PASS (82) |
| AXI4-Lite | Cadence Xcelium 25.03   | PASS (82) | PASS (82) |
| Wishbone  | Cadence Xcelium 25.03   | PASS (82) | PASS (82) |

Results generated 2026-10-10 on a `*.csun.edu` host.

**Icarus, GHDL, ModelSim and Vivado xsim have not been run since the
2026-10-09 redesign.** They are not installed on csun.edu. `sim_bus_matrix.py`
supports all six simulators. Icarus is supported because the shared tasks
avoid `do`-`while`.

```bash
python3 verification/tools/sim_bus_matrix.py --sim all --proto all --lang all   # host-appropriate simulators
python3 verification/tools/sim_bus_matrix.py --sim xcelium --proto axi4l --lang vhdl
```

VCS dumps waveforms to `vcdplus.vpd` and Xcelium to `waves.shm/`, in
`verification/work/<sim>/<proto>_<lang>/`.

## Interactive Simulation (GUI)

Scripts for waveform-based simulation of the SV testbenches. They require
`source IP/interface/bus_matrix/setup.sh`. They are **not yet tested** (no
ModelSim or Vivado on csun.edu).

| Tool | Script | Notes |
|------|--------|-------|
| ModelSim | `verification/modelsim/tb_bus_matrix_<proto>.do` | `do` it from the ModelSim transcript; loads `tb_bus_matrix_<proto>_wave.do` |
| Vivado   | `verification/vivado/create_project_<proto>.tcl` | creates `verification/vivado/work/<proto>/tb_bus_matrix_<proto>.xpr`; `wave_<proto>.tcl` runs on simulation start |

Wave groups: Clock & Reset, Master ports, Slave ports, Core handshake
(`mst_req/done`, `slv_req/done`, …) and Arbiters (the four grant vectors).

## Formal Verification Results

### Synopsys VC Formal (csun.edu) — SV and VHDL

Unbounded proofs of all four bus top-levels in **both SystemVerilog and
VHDL-2008**, plus a stand-alone arbiter harness that checks both arbitration
modes with 4 masters:
- Shared protocol checkers sit on every master port (the matrix must behave
  as a slave and answer within 64 cycles) and on every slave port (the matrix
  must behave as a master).
- End-to-end checks: a slave only sees writes some master issued, and only
  inside its own region.
- Core routing / decode-error / response properties, and arbiter grant
  properties.

Details, waivers and findings:
[verification/formal/vcf/README.md](verification/formal/vcf/README.md).

```bash
python3 verification/tools/formal_bus_matrix.py --tool vcf
```

| Top-level | Language | Assertions proven | Covers covered | Waived | Result |
|-----------|----------|-------------------|----------------|--------|--------|
| arbiter harness (FP + RR, 4 masters) | SV   | 17/17 | 14/14 | 0  | PASS |
| arbiter harness (FP + RR, 4 masters) | VHDL | 17/17 | 14/14 | 0  | PASS |
| `bus_matrix_apb`   | SV   | 88/88 | 56/60 | 4  | PASS |
| `bus_matrix_apb`   | VHDL | 88/88 | 56/60 | 4  | PASS |
| `bus_matrix_ahb`   | SV   | 72/76 | 58/66 | 12 | PASS |
| `bus_matrix_ahb`   | VHDL | 72/76 | 58/66 | 12 | PASS |
| `bus_matrix_axi4l` | SV   | 96/96 | 60/72 | 12 | PASS |
| `bus_matrix_axi4l` | VHDL | 96/96 | 60/72 | 12 | PASS |
| `bus_matrix_wb`    | SV   | 72/72 | 56/60 | 4  | PASS |
| `bus_matrix_wb`    | VHDL | 72/72 | 56/60 | 4  | PASS |

On AHB the 4 assertions that are not "proven" are vacuous and waived
(`g_m_addr_hold.*`): the initiator never presents an address phase that a
slave could stall.

**AXI4-Lite needs a longer budget.** Its master-port response bounds
(`s_b_bounded` / `s_r_bounded`: B and R within `M_WAIT` = 64 cycles) take
about 100 minutes to prove; at 30 minutes they are inconclusive.
`formal_bus_matrix.py` therefore gives the AXI4-Lite jobs a 3-hour budget and
every other job 30 minutes. `--max-time` overrides both.

All waived results follow from two design choices: one single transfer per
grant, and one idle cycle between grants. Examples: back-to-back and pipelined
slave-side covers, and AXI back-pressure covers.

Tool: VC Formal Y-2026.03-SP1. Results generated: 2026-10-10.

### SymbiYosys (standard hosts) — SV

`verification/formal/bus_matrix_core.sby`: BMC (depth 24) of `bus_matrix_core`
with the default address map, in two tasks, round robin and fixed priority. The
harness (`bus_matrix_props.sv`) assumes masters hold their requests and slaves
answer only when requested. It asserts these properties:
- P1–P2: done only while requesting; decode errors are answered next cycle.
- P3–P4: requests and responses reach the right counterpart.
- P5: slave-side fields are stable until done.
- P6: there is an idle cycle between transactions on a slave.

**Not yet run** (no SymbiYosys on csun.edu). The harness compiles cleanly in VCS.

```bash
python3 verification/tools/formal_bus_matrix.py --tool sby
```

## UVM Verification Results

UVM 1.2 environment (`verification/uvm/`) for the AXI4-Lite variant in its
default configuration. It has two active master agents (CPU, DMA), and both
monitors feed two components:
- **Scoreboard:** it predicts every response from the address alone (OKAY,
  decode error, or slave error) and checks read data against a reference
  memory. The reference memory is keyed per slave, because each testbench
  slave holds 4 KB aliased across its region.
- **Coverage collector.**

The slaves are:
- S0/S1: the shared `claude_axi4l_if` bridge plus memory, as in the directed
  testbench. They always answer OKAY with no wait states.
- S2/S3: `verification/testbench/bus_matrix_tb_axi4l_slave.sv`, a behavioral
  AXI4-Lite slave. It inserts random wait states on every channel (up to 2
  cycles on S2, 4 on S3) and accepts AW and W independently. Offsets
  `0xE00`–`0xEFF` of its window answer **SLVERR** without writing, which
  exercises slave-error propagation separately from decode errors.

| Test | What it does | Data transfers / errors | Coverage | Result |
|------|--------------|-------------------------|----------|--------|
| `bus_matrix_base_test` | Builds the environment, no traffic | — | — | PASS |
| `bus_matrix_rw_test` | M0 writes then reads back 32 words on S0 and S1 | 64 W / 64 R | 36.5 % | PASS |
| `bus_matrix_contention_test` | M0 and M1 write and read the same S0 words at once | 32 W / 32 R | 32.9 % | PASS |
| `bus_matrix_map_test` | M0 and M1 in parallel walk every slave, then both run the decode-error sequence (below) | 152 W / 148 R, 96 decode errors, 16 slave errors | **100 %** | PASS |
| `bus_matrix_decerr_test` | Decode errors only, both masters at once | 8 W / 8 R, 96 decode errors | 72.1 % | PASS |

For each slave, `bus_matrix_map_test` runs:
- full-word writes and read-back;
- every byte-strobe pattern, merged into one word;
- the first word, the last word and a mid-region word;
- the slave-error page on S2/S3.

The decode-error sequence covers:
- the first byte past each region;
- the last word before each region;
- the inside of every gap in the map, and the top of the address space.

Before the error accesses, guard values are written into every slave word a
misrouted access would alias to, and afterwards they are checked unchanged.
All runs had 0 scoreboard mismatches.

Coverage crosses (all at 100 % in `bus_matrix_map_test`):
- master × region (S0–S3, decode error) × direction;
- outcome (OKAY per slave, slave error on S2/S3, decode error) × direction;
- slave × write-strobe pattern;
- slave × position in region (first, last, interior word);
- which map gap a decode error hit;
- both masters' latest completions on the same slave or on different slaves.

**Mutation check (2026-10-10).** Two deliberate DUT bugs were caught by the
new tests and missed by the older RW and contention tests:
- Target adapter always answers OKAY: 224 errors in `map_test`, 192 in
  `decerr_test`.
- Decoder ignores address bit 16, which leaks `0x0001_0000` into S0 and
  `0x4001_0000` into S2: 36 errors in each test. The guard read-back also
  caught the overwritten slave words.

Results generated 2026-10-10 on Synopsys VCS Y-2026.03. The Vivado xsim path
of the runner has not been re-run since the port.

```bash
python3 verification/tools/uvm_bus_matrix.py --test all --sim vcs     # csun.edu
python3 verification/tools/uvm_bus_matrix.py --test bus_matrix_map_test # xsim on standard hosts
```

## Lint Results

**On csun.edu** (Verilator and GHDL are not installed there):

| Language | Tool     | Version       | Findings | Waivers | Result  |
|----------|----------|---------------|----------|---------|---------|
| SV       | SpyGlass | Y-2026.03-SP1 | 0        | 0       | PASS    |
| VHDL     | —        | —             | —        | —       | SKIPPED |

Results generated 2026-10-10 (4 top-levels, `lint_rtl` goal).

The redesigned RTL was written to be SpyGlass-clean without waivers:
- no multiply-assigned signals in loops;
- one-hot picks use `x & (~x + 1)`;
- AND-OR routing uses generate chains;
- FSMs have separate next-state and state processes.

The VHDL mirrors the same structure. VHDL lint has no working path on csun.edu
(see `.agents/reference_spyglass_lint.md`).

**Standard hosts:** Verilator and GHDL have not been re-run since the redesign.

## Firmware

Not applicable. The bus matrix has no registers, so there is no firmware
driver.

## Synthesis Results

All ASIC results below synthesize the **default configuration**
(`bus_matrix_pkg`) at 100 MHz. 30 % of the period is budgeted outside the
matrix on each side of every port.

### Yosys / Vivado / Quartus (standard hosts)

**Not re-run since the 2026-10-09 redesign.** None of these tools is on
csun.edu. The scripts have been ported to the new file set and to all four
protocols, but they are untested:
- `synthesis/yosys/synth_bus_matrix_<proto>[_vhdl].ys`
- `synthesis/vivado/synth_bus_matrix_<proto>.tcl`
- `synthesis/quartus/synth_bus_matrix_<proto>.tcl`

The SV tops reference `bus_matrix_pkg::` by name rather than importing it in
the module header, which Yosys cannot parse. `synthesis/vivado/report.txt` and
`synthesis/quartus/report.txt` describe the old RTL.

### Design Compiler (csun.edu only)

Synopsys Design Compiler for SAED90/32/14 (one corner each) and SKY130
(synthesized at its worst-case corner, `ss_100C_1v60`). The flow uses:
- `compile_ultra -no_autoungroup` with DesignWare, then an incremental
  `compile_ultra` pass;
- `set_cost_priority -delay` and `set_max_fanout 16` (see
  `synthesis/known_issues.md` for why).

All 4 SV + 4 VHDL variants are synthesized per PDK.

| PDK | APB cells | AHB cells | AXI4-Lite cells | WB cells | Flip-flops (APB/AHB/AXI/WB) | Worst WNS | Result |
|-----|-----------|-----------|-----------------|----------|-----------------------------|-----------|--------|
| SAED90 (90nm)  | 1024 | 1221 | 1962 | 965 | 18 / 88 / 316 / 14 | -0.56 ns | VIOLATED (accepted) |
| SAED32 (32nm)  | 704  | 875  | 1781 | 674 | 18 / 88 / 316 / 14 | +3.58 ns | MET |
| SAED14 (14nm)  | 937  | 1090 | 1724 | 898 | 18 / 88 / 316 / 14 | +1.83 ns | MET |
| SKY130 (130nm) | 849  | 1020 | 1668 | 819 | 18 / 88 / 316 / 14 | +2.54 ns | MET |

The cell counts are for the SV variants; the VHDL twins are within about 9 %.
Results generated 2026-10-10. Tool: Design Compiler Y-2026.03-SP1. Per-variant
area and timing are in `synthesis/designcompiler/report_<pdk>.txt`.

**SAED90 misses 100 MHz by up to 0.56 ns, and this is accepted.** The
failing paths are the arbiter grant → 69-bit routing mux → output port. Under
SAED90's wire-load models every buffer level of that fan-out costs 2.5–3 ns
of wire delay. Synthesis tuning plus an RTL change (`slv_req` driven by the
registered grant alone) brought it from -1.25 ns to -0.56 ns. Closing the
rest would need registered slave-side fields (about 2× area). See
`synthesis/known_issues.md`.

```bash
python3 synthesis/run_vendor_synth.py --dc     # all four PDKs; --dc90/--dc32/--dc14/--dcsky130 for one
```

### PrimeTime STA (csun.edu only)

`synthesis/run_primetime_sta.py` rechecks the DC netlists, one corner each for
SAED90/32/14 and all three PVT corners for SKY130. Clock: 100 MHz, all 8
variants per target.

| Target | Corner | Worst setup WNS | Worst hold WNS | Setup TNS | DRV violators | Result |
|--------|--------|-----------------|----------------|-----------|---------------|--------|
| SAED90 (90nm) | `saed90nm_max` | -0.560 ns | +0.910 ns | -210.16 ns | 0 | VIOLATED (accepted) |
| SAED32 (32nm) | SS 0.95 V 125 °C | +3.580 ns | +0.220 ns | 0 | 168 max_capacitance | MET (DRV open) |
| SAED14 (14nm) | SS 0.72 V 125 °C | +1.830 ns | +0.130 ns | 0 | 0 | MET |
| SKY130 `ss_100C_1v60` | 1.60 V, 100 °C | +2.540 ns | +0.850 ns | 0 | 0 | MET |
| SKY130 `tt_025C_1v80` | 1.80 V, 25 °C  | +3.250 ns | +0.440 ns | 0 | 0 | MET |
| SKY130 `ff_n40C_1v95` | 1.95 V, -40 °C | +3.570 ns | +0.290 ns | 0 | 0 | MET |

Results generated 2026-10-10. Tool: PrimeTime Y-2026.03-SP1.
- SAED32's max-capacitance violators (19.7 fF against a 16 fF limit, on the
  grant/select nets) are an open item. Timing and gate-level simulation are
  unaffected.
- The per-target reports (`synthesis/primetime/report_sta_<target>.txt`) list
  setup WNS, hold WNS and violator counts for each variant.

```bash
python3 synthesis/run_primetime_sta.py     # all six targets; --saed90/--saed32/--saed14/--sky130/--ss/--tt/--ff for one
```

### Post-Synthesis Gate-Level Simulation (csun.edu only)

The full directed suite (82 checks) runs against the DC netlists with SDF
back-annotation in VCS. The SV testbench is used, because the netlist is
Verilog whichever RTL language was synthesized.

| PDK | APB | AHB | AXI4-Lite | Wishbone |
|-----|-----|-----|-----------|----------|
| SAED90 (90nm)  | PASS | PASS | PASS | PASS |
| SAED32 (32nm)  | PASS | PASS | PASS | PASS |
| SAED14 (14nm)  | PASS | PASS | PASS | PASS |
| SKY130 (130nm) | PASS | PASS | PASS | PASS |

Results generated 2026-10-10.
- SAED90 passes despite its STA violation, because its failing paths end at
  output ports against an assumed 3 ns external budget. The testbench's slaves
  have no logic between those ports and their flops.
- The testbench files carry `` `timescale 1ns / 1ps ``. Without it they
  inherit a SAED32 cell model's `1ps/1ps` and the clock runs 1000× too fast.
- SKY130's VCS model workarounds are the same as the timer's (patched
  `primitives.v`, `sky130_fd_sc_hd.v` as a `-v` library).

```bash
python3 verification/tools/sim_bus_matrix.py --sim vcs --postsyn --pdk all --proto all
```

### Power Analysis — PrimePower (csun.edu only)

`sim_bus_matrix.py --power` runs the gate-level simulation above, converts its
`vcdplus.vpd` to SAIF, and runs PrimePower (averaged mode) on the netlist with
that activity. Every run annotates 100 % of nets from the SAIF.

Total power in mW at 100 MHz (typical corners):

| PDK (corner) | APB | AHB | AXI4-Lite | Wishbone |
|--------------|-----|-----|-----------|----------|
| SAED90 (typ)              | 0.063 | 0.104 | 0.202 | 0.060 |
| SAED32 (tt 1.05 V 25 °C)  | 0.133 | 0.283 | 0.868 | 0.123 |
| SAED14 (tt 0.8 V 25 °C)   | 0.028 | 0.048 | 0.085 | 0.026 |
| SKY130 (tt 1.8 V 25 °C)   | 0.125 | 0.424 | 1.340 | 0.104 |

APB breakdown (mW):

| PDK | Internal | Switching | Leakage |
|-----|----------|-----------|---------|
| SAED90 | 0.017 | 0.011 | 0.035 |
| SAED32 | 0.026 | 0.002 | 0.104 |
| SAED14 | 0.004 | 0.024 | 0.00005 |
| SKY130 | 0.092 | 0.032 | 0.000002 |

Results generated 2026-10-10. Tool: PrimePower Y-2026.03-SP1.

How to read these numbers:
- **Power follows flip-flop count.** AXI4-Lite has 316 flops, because its
  target adapters register the address, data and responses of both channels.
  Its two target adapters account for about 87 % of its SKY130 power. APB (18
  flops) and Wishbone (14) are almost entirely combinational.
- **SAED32 is leakage-dominated** (78 % for APB). SAED14 and SKY130 are almost
  entirely dynamic.
- **The workload is the directed test suite**, not an application profile. Use
  the numbers as relative comparisons.
- **The flow is pre-layout.** There is no clock tree, and the wires are
  wire-load models, so post-CTS power will be higher.

Reports are in `verification/work/postsyn/<pdk>/<proto>/power/`.

```bash
python3 verification/tools/sim_bus_matrix.py --power --pdk all --proto all
```

## Regression

```bash
python3 verification/tools/run_regression.py     # or: bash verification/regression/run_regression.sh
```

On csun.edu the regression runs:
- VCS and Xcelium (SV + VHDL);
- UVM on VCS;
- VC Formal.

On standard hosts it runs Icarus, GHDL, ModelSim and xsim, UVM on xsim, and
SymbiYosys. In both cases it collects the lint result. Output:
`verification/work/regression_results.log`.

## Known Limitations

- **No bursts or pipelining:** one single transfer per slave-side grant, and
  AHB SEQ beats are handled as singles.
- **One idle cycle on a slave between grants.**
- **Wishbone transfer abort** (dropping `CYC`/`STB` before `ACK`/`ERR`) is not
  supported.
- **Decode errors use the slave-error response**: AXI4-Lite returns `SLVERR`,
  not `DECERR`.
- **The address width is fixed at 32 bits.**
- **Gate-level, STA and power results cover only the default configuration.**
