# Claude_IP

A collection of production-quality digital IP blocks for FPGA and ASIC design.
Every IP is delivered in both **SystemVerilog** and **VHDL-2008**, fully verified,
linted, synthesized, and documented.

## Project Structure

```
Claude_IP/
├── IP/
│   ├── common/          Shared components (bus bridges, BFMs, test packages, CMake)
│   ├── communication/   Communication peripherals (UART, SPI, I2C, ...)
│   ├── CPU/             Processor cores
│   ├── DSP/             DSP blocks (filters, FFT, ...)
│   ├── interface/       Bus interconnect and interface IP
│   └── system/          System peripherals (timers, GPIO, interrupt controllers, ...)
├── SoC/                 SoC integration examples
├── .agents/             Sub-agent workflow definitions (11-step IP development process)
└── virtualenv/          Python virtual environment for PeakRDL and tool scripts
```

## IP Catalog

### System

| IP | Description | Protocols | Status |
|----|-------------|-----------|--------|
| [timer](IP/system/timer/) | Programmable countdown/countup timer with prescaler, one-shot/free-running modes, interrupt, and external trigger output | AHB, APB, AXI4-Lite, WB | Complete |

### Interface

| IP | Description | Protocols | Status |
|----|-------------|-----------|--------|
| [bus_matrix](IP/interface/bus_matrix/) | Configurable crossbar interconnect with priority-based and round-robin arbitration, parameterized masters/slaves | AHB, AXI4-Lite, WB | Complete |

### Communication

*No IPs yet.*

### CPU

*No IPs yet.*

### DSP

*No IPs yet.*

## Shared Components

The [IP/common/](IP/common/) directory contains reusable components shared across all IPs:

- **Bus bridges** (`design/rtl/verilog/`, `design/rtl/vhdl/`) — Protocol-to-regbus adapters (APB4, AHB-Lite, AXI4-Lite, Wishbone B4)
- **BFM task libraries** (`verification/tasks/`) — Bus functional models for directed tests
- **Test packages** (`verification/tests/`) — `ip_test_pkg` for SV and VHDL-2008
- **Formal property templates** (`verification/formal/`) — Reusable SVA reset and bus-protocol properties
- **Python tool base** (`verification/tools/`) — Shared env-var guard, results-log writer, subprocess runner
- **CMake toolchain files** (`firmware/cmake/`) — ARM Cortex-M33 and RISC-V 32-bit cross-compilation

## Development Workflow

Each IP follows an 11-step sub-agent workflow defined in [.agents/Claude_IP.md](.agents/Claude_IP.md):

1. **setup** — Directory tree, `setup.sh`, `cleanup.sh`, tool skeletons
2. **rdl** — SystemRDL register definitions and code generation (PeakRDL)
3. **rtl** — Core logic and bus adapters in SV and VHDL-2008
4. **directed_tests** — Testbenches for Icarus, GHDL, ModelSim, xsim
5. **formal** — SymbiYosys BMC and cover verification
6. **uvm** — UVM environment targeting Vivado xsim
7. **regression** — `run_regression.py` with full pass/fail reporting
8. **lint** — Verilator (SV) and GHDL (VHDL), zero un-waived warnings
9. **firmware** — C99 device driver, cross-compiled for ARM Cortex-M33 and RISC-V
10. **synthesis** — Yosys (generic), Vivado (Zynq-7010), Quartus (Cyclone V SE)
11. **cleanup** — Scrub artifacts, finalize docs, tag release

## Tool Requirements

| Tool | Purpose |
|------|---------|
| Icarus Verilog 11+ | SV directed simulation |
| GHDL 3.0+ | VHDL-2008 directed simulation |
| Verilator 5.0+ | SV linting |
| Yosys 0.36+ / SymbiYosys | Open-source synthesis and formal verification |
| ModelSim ASE 21.1 | Mixed-language simulation (optional) |
| Vivado 2023.2 | UVM simulation and Zynq-7010 synthesis |
| Quartus Prime Lite 23.1 | Cyclone V SE synthesis |
| arm-none-eabi-gcc | ARM Cortex-M33 firmware |
| riscv-none-elf-gcc | RISC-V 32-bit firmware |
| PeakRDL 2.0+ | SystemRDL register generation |
| Python 3.10+ | Tool scripts |

## License

[MIT License](LICENSE) -- Copyright (c) 2026 Phil Tracton
