# Claude_IP — Top-Level Agent

## Mission

Generate world-class, high-quality, flexible, and reliable digital IP for FPGA and ASIC use.
Every IP block is delivered in **both SystemVerilog (SV) and VHDL-2008**, is fully verified,
linted, synthesized, and accompanied by firmware device-driver support and complete documentation.

---

## Common Components Rule (mandatory for all sub-agents)

Reusable parts live in `IP/common/` and are shared across every IP project in this
repository. Using `IP/common/` enforces standardization and avoids duplicating code that
has already been written and verified.

**RULE — Check `IP/common/` before writing anything new.** Before creating any RTL
component, BFM task, SVA property template, Python tool utility, CMake module, or firmware
header, the sub-agent must first check whether an equivalent already exists in `IP/common/`.
If it does, use it directly — do not copy or rewrite it.

**RULE — Put reusable work in `IP/common/`, not in `IP/IP_NAME/`.** If a component
produced by a sub-agent would be useful to another IP project (bus BFMs, synchronizer
cells, Python base classes, `platform.h`, CMake modules, etc.) it must be placed in
`IP/common/` rather than inside the IP-specific directory. The IP-specific directory
contains only what is unique to that IP block.

**RULE — `IP_COMMON_PATH` is the canonical reference to `IP/common/`.** All scripts and
generated files must reference common components through the `IP_COMMON_PATH` environment
variable, never through a hardcoded path.

The `IP/common/` directory structure is:

```
IP/common/
├── rtl/
│   ├── verilog/          # Shared SV primitives: CDC sync cells, reset synchronizers, etc.
│   └── vhdl/             # VHDL-2008 equivalents of every component in verilog/
├── verification/
│   ├── tasks/            # Protocol BFM task libraries (one file per bus protocol)
│   │   ├── ahb_bfm.sv
│   │   ├── apb_bfm.sv
│   │   ├── axi4lite_bfm.sv
│   │   └── wishbone_bfm.sv
│   ├── formal/           # Reusable SVA property templates
│   │   ├── reset_props.sv
│   │   └── bus_protocol_props.sv
│   └── tools/            # Python base class and shared utilities for all tool scripts
│       └── ip_tool_base.py
├── firmware/
│   ├── include/          # platform.h MMIO stub, shared C types
│   └── cmake/            # Shared CMake modules (used by every IP's firmware/cmake/)
└── doc/                  # Shared documentation templates
```

`IP_COMMON_PATH` is set by `setup.sh` and points to this directory.

---

## SystemVerilog Interface Prohibition (mandatory for all sub-agents)

**RULE — Do NOT use SystemVerilog `interface` constructs in directed-test files.**

Icarus Verilog does not support SV `interface` blocks. Since Icarus is a required
simulator for all directed tests, `interface` is forbidden in every RTL source file,
every directed-test testbench, and every BFM task library.

All inter-module connections — including the internal register-access bus between
`IP_NAME_<proto>_if`, `IP_NAME_regfile`, and `IP_NAME_core` — must be expressed as
explicit individual `input` / `output` ports on every module boundary.

**UVM exception**: UVM runs exclusively on Vivado xsim, which fully supports SV
interfaces. `virtual interface` is the standard UVM VIF mechanism and is **permitted**
inside `verification/tasks/uvm/`. It must not appear outside that directory.

Any use of `interface` / `modport` / `virtual interface` outside `verification/tasks/uvm/`
is a quality-gate failure and must be rewritten before the step can be marked complete.

---

## IP Name Substitution Rule (mandatory for all sub-agents)

Throughout these agent documents the string `IP_NAME` is used as a placeholder only.

**RULE — Every sub-agent must replace every occurrence of `IP_NAME` with the actual name
of the IP block being developed before generating any file, directory, variable, function,
module, entity, or string literal.**

This substitution applies without exception to:

- Directory and file names (`gpio/`, `generate_gpio.py`, `gpio_regfile.sv`, etc.)
- Shell variable names (`CLAUDE_GPIO_PATH`, `GPIO_DESIGN_PATH`, etc.)
- Python variable names and string literals
- RTL module and entity names (`gpio`, `gpio_ahb`, `gpio_reg_pkg`, etc.)
- C function and macro names (`gpio_init()`, `GPIO_REG_CTRL_OFFSET`, etc.)
- Comments, print statements, log messages, and documentation

No generated file may contain the literal string `IP_NAME`. If it does, the sub-agent has
failed to perform the substitution and must correct all occurrences before proceeding.

---

## Environment Variable Rules (mandatory for all sub-agents)

Every IP block uses a dedicated environment variable `CLAUDE_<IP_NAME>_PATH` (e.g., for an IP
named `uart` the variable is `CLAUDE_UART_PATH`). This variable holds the absolute path to the
`IP_NAME/` directory — the directory containing `setup.sh`. It is set by `setup.sh` and is the
canonical root for all path references inside every script and tool.

**RULE — Use `CLAUDE_<IP_NAME>_PATH` for all paths.** No script, tool, or generated file may
use a hardcoded absolute path to refer to anything inside the IP directory. All paths are
derived from `CLAUDE_<IP_NAME>_PATH`.

**RULE — All scripts must guard on `CLAUDE_<IP_NAME>_PATH`.** Every shell script and Python
tool must check at startup that `CLAUDE_<IP_NAME>_PATH` is set and non-empty. If it is not
set the script must print a clear error and exit non-zero. It must **not** proceed.

Shell script guard (place immediately after the shebang):
```bash
if [ -z "${CLAUDE_IP_NAME_PATH}" ]; then
    echo "ERROR: CLAUDE_IP_NAME_PATH is not set."
    echo "       Please run:  source IP_NAME/setup.sh"
    exit 1
fi
```

Python script guard (place at the top of `main()`):
```python
import os, sys
IP_NAME_PATH = os.environ.get("CLAUDE_IP_NAME_PATH")
if not IP_NAME_PATH:
    print("ERROR: CLAUDE_IP_NAME_PATH is not set.")
    print("       Please run:  source IP_NAME/setup.sh")
    sys.exit(1)
```

---

## Coding Standards (mandatory for all sub-agents)

All generated RTL and testbench code **must** conform to the project coding style guides:

- `.agents/VerilogCodingStyle.md` — lowRISC Comportable style for SystemVerilog
- `.agents/VHDL2008CodingStyle.md` — IEEE 1076-2008 VHDL style

**RULE — Read before writing.** Sub-agents must read both style guides in full before
generating any SystemVerilog or VHDL-2008 code. There are no exceptions.

**RULE — The coding style documents are immutable.** They must never be edited, summarized,
paraphrased, or overridden. If a rule in a style guide conflicts with any other instruction,
the style guide takes precedence for all matters of code formatting and structure.

**RULE — No undocumented deviations.** If a tool constraint, language limitation, or
synthesis requirement makes strict compliance impossible, the deviation must be documented
with an inline comment at the exact line where it occurs, stating the reason. Deviations
are the exception, not the rule.

---

## Design Principles

- **Dual-language parity**: Every module, package, and testbench component is written in both SV
  and VHDL-2008. Functionality must be bit-for-bit identical across both implementations.
- **Parameterization**: Data width, address width, and bus protocol parameters are always generic/
  parameter-driven. No hardcoded widths.
- **Reset policy**: Synchronous active-low reset unless the target technology explicitly requires
  otherwise. Reset polarity is a top-level parameter.
- **Clock domain hygiene**: Each clock domain is explicit. CDC crossings use verified synchronizer
  cells only. No implicit multi-cycle paths.
- **Bus-protocol agnosticism**: Core logic is decoupled from bus wrappers. Bus interfaces are thin
  adapter layers that terminate at a simple register-file interface.
- **Lint-clean from day one**: Code must pass the linter (Step 7) before a PR is merged. Never
  defer lint fixes.
- **Simulation-synthesis equivalence**: Constructs that simulate differently from how they
  synthesize are forbidden in RTL files (only allowed in `verification/`).

---

## Repository Layout (canonical — established by Step 1)

Each IP block lives as a peer of `common/` inside the `IP/` directory. The layout below
shows both the shared common tree and a single IP block tree.

```
IP/
├── common/                                 # Shared components — see Common Components Rule
│   ├── rtl/verilog/                        # Shared SV primitives
│   ├── rtl/vhdl/                           # Shared VHDL-2008 primitives
│   ├── verification/tasks/                 # Protocol BFM task libraries
│   ├── verification/formal/                # Reusable SVA property templates
│   ├── verification/tools/                 # Python base class (ip_tool_base.py)
│   ├── firmware/include/                   # platform.h and shared C types
│   ├── firmware/cmake/                     # Shared CMake modules
│   └── doc/                                # Shared documentation templates
│
└── IP_NAME/
├── README.md                               # Top-level documentation (progressively filled by each sub-agent)
├── cleanup.sh                              # Removes all build/sim artifacts
├── setup.sh                                # Exports environment variables and tool paths
├── design/
│   ├── behavioral/                         # Behavioral / reference models
│   ├── rtl/
│   │   ├── verilog/                        # SystemVerilog RTL sources + bus adapters
│   │   └── vhdl/                           # VHDL-2008 RTL sources + bus adapters
│   └── systemrdl/
│       ├── IP_NAME.rdl                     # SystemRDL 2.0 source (single source of truth)
│       └── tools/
│           └── generate_IP_NAME.py         # Drives PeakRDL to generate all outputs
├── doc/                                    # Specifications, architecture, and generated docs
├── firmware/
│   ├── build/                              # Compiled output (gitignored)
│   ├── build.sh                            # Invokes CMake and make
│   ├── cmake/                              # CMake helper modules
│   ├── examples/                           # Usage example programs
│   ├── include/                            # Public C headers (driver API + generated regs)
│   ├── lib/                                # Built static library output
│   ├── obj/                                # Intermediate object files (gitignored)
│   └── src/                                # Driver implementation sources
├── synthesis/
│   ├── quartus/                            # Quartus Prime synthesis scripts and reports
│   ├── vivado/                             # Vivado synthesis scripts and reports
│   └── yosys/                              # Yosys synthesis scripts and reports
└── verification/
    ├── formal/                             # Yosys formal verification scripts and results
    ├── lint/                               # Lint results and waiver files
    ├── regression/                         # Regression reports
    ├── tasks/                              # Reusable simulation task libraries
    ├── testbench/
    │   └── testbench.sv                    # Top-level simulation testbench
    ├── tests/                              # Individual directed and UVM test cases
    ├── tools/
    │   ├── formal_IP_NAME.py               # Formal verification runner (Yosys)
    │   ├── lint_IP_NAME.py                 # Lint runner
    │   ├── run_regression.py               # Regression runner and reporter
    │   ├── sim_IP_NAME.py                  # Simulation runner (Icarus/GHDL/ModelSim)
    │   └── uvm_IP_NAME.py                  # UVM runner (Vivado xsim)
    └── work/                               # Simulator working directories (gitignored)
```

---

## Sub-Agents

Each step is defined in its own file under `.agents/`. Sub-agents communicate via files in the
repository — never via in-memory state. Each sub-agent must verify that all prior-step
deliverables exist before starting work.

| Step | Agent File | Description |
|------|-----------|-------------|
| 1  | [.agents/setup.md](.agents/setup.md) | Directory structure and environment setup |
| 2  | [.agents/rdl.md](.agents/rdl.md) | SystemRDL register definitions and code generation |
| 3  | [.agents/rtl.md](.agents/rtl.md) | RTL design and bus-interface adapters |
| 4  | [.agents/directed_tests.md](.agents/directed_tests.md) | Directed simulation tests |
| 5  | [.agents/formal.md](.agents/formal.md) | Formal verification via Yosys |
| 6  | [.agents/uvm.md](.agents/uvm.md) | UVM verification environment |
| 7  | [.agents/regression.md](.agents/regression.md) | Regression harness and reporting |
| 8  | [.agents/lint.md](.agents/lint.md) | RTL linting (runs in parallel with Steps 4–6) |
| 9  | [.agents/firmware.md](.agents/firmware.md) | C99 device driver library (runs in parallel with Steps 3–8) |
| 10 | [.agents/synthesis.md](.agents/synthesis.md) | Synthesis via Yosys, Vivado, and Quartus |
| 11 | [.agents/cleanup.md](.agents/cleanup.md) | Final cleanup, documentation, and release tag |

---

## Inter-Agent Contracts

| Producer | Consumer(s) | Contract Artifact |
|----------|------------|-------------------|
| setup (1) | All | `setup.sh`, `cleanup.sh`, directory tree |
| rdl (2) | rtl (3), uvm (6), firmware (9) | `design/rtl/verilog/`, `design/rtl/vhdl/`, `firmware/include/IP_NAME_regs.h` |
| rtl (3) | directed_tests (4), formal (5), uvm (6), lint (8), synthesis (10) | `design/rtl/verilog/`, `design/rtl/vhdl/` |
| directed_tests (4) | formal (5), regression (7) | `verification/work/*/results.log` |
| formal (5) | regression (7) | `verification/formal/results.log` |
| uvm (6) | regression (7) | `verification/work/xsim/uvm/results.log` |
| lint (8) | synthesis (10), regression (7) | `verification/lint/lint_results.log` |
| All (2–9) | cleanup (11) | Full passing regression |

---

## Quality Gates

A sub-agent **must not** mark its step complete until all of the following are satisfied:

1. **Parse-clean**: all generated/written source files pass a syntax check with the relevant
   open-source tool (`iverilog -tnull`, `ghdl -s`, `verilator --lint-only`, `gcc -fsyntax-only`).
2. **Style-compliant**: code matches the applicable coding style guide.
3. **Self-consistent**: file names, module/entity names, port names, and package names are
   consistent across SV and VHDL twins.
4. **Documented**: every public interface has an inline comment block.
5. **Reproducible**: any script produces the same result when run twice from a clean state.

---

## Tool Versions and Installation Paths

| Tool | Version / Path | Purpose |
|------|---------------|---------|
| Icarus Verilog | 11.0+ (via OSS CAD Suite) | SV directed simulation |
| GHDL | 3.0+ (via OSS CAD Suite) | VHDL directed simulation |
| Verilator | 5.0+ (via OSS CAD Suite) | SV linting |
| Yosys | 0.36+ (via OSS CAD Suite) | Open-source synthesis |
| OSS CAD Suite | `/opt/oss-cad-suite/bin` | Open-source EDA toolchain |
| ModelSim ASE | `/opt/intelFPGA_lite/23.1std/modelsim_ase/bin` | Mixed-language simulation |
| Vivado | `/opt/Xilinx/Vivado/2023.2/settings64.sh` | UVM simulation + synthesis (target: Zynq-7010) |
| Quartus Prime Lite | `/opt/intelFPGA_lite/23.1std/quartus/bin` | Intel synthesis (target: Cyclone V SE 5CSEMA4U23C6) |
| arm-none-eabi-gcc | system package (`apt install gcc-arm-none-eabi`) | ARM Cortex-M33 firmware cross-compiler |
| riscv-none-elf-gcc | xPack 15.2.0 at `/opt/xpack-riscv-none-elf-gcc-15.2.0-1/bin` | RISC-V 32-bit firmware cross-compiler |
| PeakRDL | 2.0+ (Python venv) | SystemRDL compilation |
| CMake | 3.20+ | Firmware build system |
| Python | 3.10+ | Tool scripts |
| Python venv | `<repo_root>/virtualenv/CLAUDE_IP/bin/activate` | Isolated Python environment |

---

## Escalation Policy

If a sub-agent encounters an ambiguity, conflict, or toolchain failure it cannot resolve
autonomously, it must:

1. Write a clearly titled `doc/issues/<agent>_<timestamp>_issue.md` describing the problem,
   what was attempted, and what information is needed.
2. Halt and return control to the orchestrating agent (this document's owner) with the issue
   file path in its response.

Do **not** silently work around tool failures by disabling checks or skipping steps.
