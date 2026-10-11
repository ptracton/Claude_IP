# Claude_IP

A collection of production-quality digital IP blocks for FPGA and ASIC design.
Every IP is delivered in both **SystemVerilog** and **VHDL-2008**, with one
top-level per bus protocol (APB4, AHB-Lite, AXI4-Lite, Wishbone B4). Each IP is
verified, linted, synthesized and documented through the same flow.

Two tool flows are supported, and every script picks one from the host name:
- **Open-source / FPGA (standard hosts):** Icarus Verilog, GHDL, ModelSim,
  Vivado, Quartus, Yosys, SymbiYosys and Verilator.
- **Commercial ASIC (`*.csun.edu` hosts):** Synopsys VCS, Cadence Xcelium,
  VC Formal, SpyGlass, Design Compiler, PrimeTime and PrimePower. It targets
  the SAED90/32/14 and SkyWater SKY130 PDKs.

The [timer](IP/system/timer/) is the reference implementation: new IPs follow
its structure, scripts and documentation.

## Project Structure

```
Claude_IP/
├── IP/
│   ├── common/          Shared components (bus bridges, BFMs, formal checkers, test packages, tool libraries)
│   ├── interface/       Bus interconnect and interface IP
│   └── system/          System peripherals (timers, ...)
├── .agents/             Sub-agent workflow definitions (12-step IP development process) and tool notes
└── virtualenv/          Python virtual environment for PeakRDL, volare and tool scripts
```

Every IP has the same layout: `design/` (RTL in SV and VHDL, plus SystemRDL
where it has registers), `verification/`, `synthesis/`, `firmware/` (where it
has registers), `doc/` and a `README.md` with all results. Each IP's
`setup.sh` sets `CLAUDE_<IP>_PATH` and detects the host.

## IP Catalog

### System

| IP | Description | Protocols | Status |
|----|-------------|-----------|--------|
| [timer](IP/system/timer/) | Programmable 32-bit timer with prescaler, one-shot/free-running modes, interrupt, trigger output, restart and atomic snapshot | APB4, AHB-Lite, AXI4-Lite, WB | Complete (both flows) |

### Interface

| IP | Description | Protocols | Status |
|----|-------------|-----------|--------|
| [bus_matrix](IP/interface/bus_matrix/) | Crossbar interconnect, 1–16 masters × 1–32 slaves. Base/mask address map with decode errors, per-slave round-robin or fixed-priority arbitration with grant lock, error propagation. Default config: CPU + DMA, 4-region map | APB4, AHB-Lite, AXI4-Lite, WB | Complete on the csun.edu flow; standard-host scripts ported, not yet re-run |

### Verification status (csun.edu flow)

| IP | Directed sim (VCS + Xcelium, SV + VHDL) | Formal (VC Formal) | UVM | Lint (SpyGlass SV) | DC + PrimeTime (4 PDKs) | Gate-level sim | Power |
|----|------|------|-----|------|------|------|------|
| timer | 16/16 PASS | 8/8 PASS | 1/1 PASS on xsim (standard host; not run on csun.edu) | PASS | SAED90 -0.40 ns accepted; others MET | SAED32/14, SKY130 PASS; SAED90 known fail | 12/16 (SAED90 skipped) |
| bus_matrix | 16/16 PASS (82 checks each) | 10/10 PASS | 5/5 PASS on VCS, 100 % coverage | PASS | SAED90 -0.56 ns accepted; others MET | 16/16 PASS | 16/16 |

See each IP's README for the details and `synthesis/known_issues.md` for the
accepted SAED90 violations.

## Shared Components

The [IP/common/](IP/common/) directory contains components shared by all IPs:

- **Bus bridges** (`design/rtl/verilog/`, `design/rtl/vhdl/`):
  `claude_<proto>_if` turns APB4, AHB-Lite, AXI4-Lite or Wishbone B4 into a
  simple register bus.
- **BFM task libraries** (`verification/tasks/`): handshake-correct bus
  masters for directed tests, configurable address width and timeout, with an
  error flag.
- **Test packages** (`verification/tests/`): `ip_test_pkg` for SV and
  VHDL-2008.
- **Formal checkers** (`verification/formal/`):
  - `claude_<proto>_fv`, SVA protocol checkers usable on either side of a bus;
  - `claude_reg_fv`, a register read-back checker;
  - the VC Formal run script.
- **Python tool libraries** (`verification/tools/`):
  - `claude_vcf.py`, the VC Formal driver with waivers;
  - `ip_tool_base.py`, a shared environment and results helper;
  - `run_regression.py`.
- **SKY130 library cache** (`synthesis/designcompiler/`):
  `build_sky130_libs.py` compiles SKY130's `.lib` files to `.db` with Library
  Compiler, for DC, PrimeTime and PrimePower.
- **CMake toolchain files** (`firmware/cmake/`): ARM Cortex-M33 and RISC-V
  32-bit cross-compilation.

## Development Workflow

Each IP follows a 12-step sub-agent workflow defined in
[.agents/Claude_IP.md](.agents/Claude_IP.md):

1. **setup**: directory tree, `setup.sh` (host detection), `cleanup.sh`,
   tool skeletons
2. **rdl**: SystemRDL register definitions and code generation (PeakRDL).
   Only for IPs with registers.
3. **rtl**: core logic and bus adapters in SV and VHDL-2008
4. **directed_tests**: testbenches on Icarus/GHDL/ModelSim/xsim, or on
   VCS/Xcelium on csun.edu
5. **formal**: SymbiYosys BMC, or VC Formal unbounded proofs with shared
   protocol checkers (SV and VHDL)
6. **uvm**: UVM environment on Vivado xsim, or on VCS on csun.edu
7. **regression**: `run_regression.py` with full pass/fail reporting
8. **lint**: Verilator and GHDL, or SpyGlass on csun.edu. Zero un-waived
   findings.
9. **firmware**: C99 device driver, cross-compiled for ARM Cortex-M33 and
   RISC-V. Only for IPs with registers.
10. **synthesis**:
    - Yosys, Vivado (Zynq-7010) and Quartus (Cyclone V SE);
    - Design Compiler (SAED90/32/14, SKY130);
    - PrimeTime STA;
    - SDF gate-level simulation.
11. **cleanup**: scrub artifacts, finalize docs, tag the release
12. **power**: PrimePower analysis of the gate-level netlist with SAIF from
    gate-level simulation (csun.edu)

## Tool Requirements

**Standard hosts**

| Tool | Purpose |
|------|---------|
| Icarus Verilog 11+ | SV directed simulation |
| GHDL 3.0+ | VHDL-2008 directed simulation |
| Verilator 5.0+ | SV linting |
| Yosys 0.36+ / SymbiYosys | Open-source synthesis and formal verification |
| ModelSim ASE 21.1 | Mixed-language simulation (optional) |
| Vivado 2023.2 | xsim and UVM simulation, Zynq-7010 synthesis |
| Quartus Prime Lite 23.1 | Cyclone V SE synthesis |

**`*.csun.edu` hosts**

| Tool | Purpose |
|------|---------|
| Synopsys VCS Y-2026.03 | SV/VHDL directed simulation, UVM, gate-level simulation |
| Cadence Xcelium 25.03 | SV/VHDL directed simulation |
| Synopsys VC Formal Y-2026.03 | Formal property verification (SV and VHDL) |
| Synopsys SpyGlass Y-2026.03 | SV lint (VHDL-2008 lint is not available there) |
| Synopsys Design Compiler / Library Compiler | ASIC synthesis; SKY130 `.db` generation |
| Synopsys PrimeTime / PrimePower | Static timing analysis; power analysis |
| SAED90/32/14 and SKY130 PDKs | Standard-cell libraries (SKY130 via `volare`) |

**Both**

| Tool | Purpose |
|------|---------|
| arm-none-eabi-gcc | ARM Cortex-M33 firmware |
| riscv-none-elf-gcc | RISC-V 32-bit firmware |
| PeakRDL 2.0+ | SystemRDL register generation |
| Python 3.10+ | Tool scripts |

## License

[MIT License](LICENSE) -- Copyright (c) 2026 Phil Tracton
