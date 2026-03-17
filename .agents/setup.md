# Step 1 — `setup` Sub-Agent

## Trigger

User provides the actual IP name and target bus protocol(s).

## IP Name Substitution — Do This First

Before creating a single file or directory, record the actual IP name supplied by the user.
Call it `<name>` (e.g., `gpio`, `uart`, `spi_master`).

**Every occurrence of the placeholder `IP_NAME` in this document and in every file you
generate must be replaced with `<name>`.** This includes:

| Placeholder | Example replacement (`<name>` = `gpio`) |
|-------------|----------------------------------------|
| Directory `IP_NAME/` | `gpio/` |
| File `generate_IP_NAME.py` | `generate_gpio.py` |
| File `sim_IP_NAME.py` | `sim_gpio.py` |
| File `lint_IP_NAME.py` | `lint_gpio.py` |
| File `regression_IP_NAME.py` | `regression_gpio.py` |
| Variable `CLAUDE_IP_NAME_PATH` | `CLAUDE_GPIO_PATH` |
| Variable `IP_COMMON_PATH` | `IP_COMMON_PATH` (unchanged — shared across all IPs) |
| Variable `IP_DESIGN_PATH` | `GPIO_DESIGN_PATH` |
| Shell export `IP_NAME="IP_NAME"` | `IP_NAME="gpio"` |
| File `IP_NAME.rdl` | `gpio.rdl` |
| Module/entity `IP_NAME_regfile` | `gpio_regfile` |
| C header `IP_NAME_regs.h` | `gpio_regs.h` |
| Library `libIP_NAME.a` | `libgpio.a` |
| Print message `IP_NAME environment ready` | `gpio environment ready` |

No generated file may contain the literal string `IP_NAME`. Verify with:
```bash
grep -r "IP_NAME" <name>/  # must return zero results
```

## Prerequisites

None — this is the first step.

---

## Responsibilities

### 1. Create the directory tree

Create the full directory tree under `IP_NAME/` exactly as specified in the *Repository
Layout* section of [Claude_IP.md](Claude_IP.md).

---

### 2. Generate `IP_NAME/setup.sh`

This is the most critical file. Every other script in the project depends on it.

`setup.sh` must:

- Determine its own location at source-time using `BASH_SOURCE` so it works regardless of
  the caller's working directory.
- Export `CLAUDE_<IP_NAME>_PATH` (e.g., `CLAUDE_UART_PATH` for an IP named `uart`) set to
  the absolute path of the directory containing `setup.sh` — i.e., the `IP_NAME/` root.
  This is the canonical path variable used by every other script.
- Be idempotent: safe to source multiple times without side effects.
- Print a one-line confirmation message on successful sourcing.

The generated `setup.sh` must follow this exact structure and include all of the following:

```bash
#!/usr/bin/env bash
# setup.sh — Environment setup for IP_NAME
# Usage: source IP_NAME/setup.sh

# ---------------------------------------------------------------------------
# Self-locate: set CLAUDE_IP_NAME_PATH to the directory containing this file
# ---------------------------------------------------------------------------
export CLAUDE_IP_NAME_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# Common components path  (IP/common/ — shared across all IP projects)
# ---------------------------------------------------------------------------
export IP_COMMON_PATH="$(dirname "${CLAUDE_IP_NAME_PATH}")/common"

# ---------------------------------------------------------------------------
# Project identity
# ---------------------------------------------------------------------------
export IP_NAME="IP_NAME"

# ---------------------------------------------------------------------------
# OSS CAD Suite  (Icarus Verilog, GHDL, Verilator, Yosys, nextpnr, etc.)
# ---------------------------------------------------------------------------
export OSS_CAD_SUITE_PATH="/opt/oss-cad-suite"
export PATH="${OSS_CAD_SUITE_PATH}/bin:${PATH}"

# ---------------------------------------------------------------------------
# Vivado 2023.2
# ---------------------------------------------------------------------------
if [ -f "/opt/Xilinx/Vivado/2023.2/settings64.sh" ]; then
    source "/opt/Xilinx/Vivado/2023.2/settings64.sh"
else
    echo "WARNING: Vivado not found at /opt/Xilinx/Vivado/2023.2/settings64.sh"
fi

# ---------------------------------------------------------------------------
# ModelSim ASE 21.1
# ---------------------------------------------------------------------------
export MODELSIM_PATH="/opt/intelFPGA_pro/21.1/modelsim_ase/bin"
export PATH="${MODELSIM_PATH}:${PATH}"

# ---------------------------------------------------------------------------
# Python virtual environment  (PeakRDL and all tool scripts)
# ---------------------------------------------------------------------------
CLAUDE_IP_VENV="$(dirname "${CLAUDE_IP_NAME_PATH}")/virtualenv/CLAUDE_IP/bin/activate"
if [ -f "${CLAUDE_IP_VENV}" ]; then
    source "${CLAUDE_IP_VENV}"
else
    echo "WARNING: Python venv not found at ${CLAUDE_IP_VENV}"
    echo "         Run: python3 -m venv $(dirname "${CLAUDE_IP_NAME_PATH}")/virtualenv/CLAUDE_IP"
fi
unset CLAUDE_IP_VENV

# ---------------------------------------------------------------------------
# Convenience paths derived from CLAUDE_IP_NAME_PATH
# ---------------------------------------------------------------------------
export IP_DESIGN_PATH="${CLAUDE_IP_NAME_PATH}/design"
export IP_VERIFICATION_PATH="${CLAUDE_IP_NAME_PATH}/verification"
export IP_FIRMWARE_PATH="${CLAUDE_IP_NAME_PATH}/firmware"
export IP_SYNTHESIS_PATH="${CLAUDE_IP_NAME_PATH}/synthesis"
export IP_DOC_PATH="${CLAUDE_IP_NAME_PATH}/doc"

echo "IP_NAME environment ready. CLAUDE_IP_NAME_PATH=${CLAUDE_IP_NAME_PATH}"
```

**Important substitution**: replace every literal `IP_NAME` above with the actual IP name
provided by the user, and rename the variable `CLAUDE_IP_NAME_PATH` to
`CLAUDE_<ACTUAL_NAME>_PATH` (uppercased). For example, for an IP named `gpio`:
- Variable becomes `CLAUDE_GPIO_PATH`
- File exports `CLAUDE_GPIO_PATH` and `IP_NAME="gpio"`
- Convenience paths become `GPIO_DESIGN_PATH`, `GPIO_VERIFICATION_PATH`, etc.

---

### 3. Generate `IP_NAME/cleanup.sh`

```bash
#!/usr/bin/env bash
# cleanup.sh — Remove all build and simulation artifacts for IP_NAME
# Usage: bash IP_NAME/cleanup.sh

# Guard: require CLAUDE_IP_NAME_PATH
if [ -z "${CLAUDE_IP_NAME_PATH}" ]; then
    echo "ERROR: CLAUDE_IP_NAME_PATH is not set."
    echo "       Please run:  source IP_NAME/setup.sh"
    exit 1
fi

set -e

echo "Cleaning IP_NAME build and simulation artifacts..."

# Simulator working directories
rm -rf "${CLAUDE_IP_NAME_PATH}/verification/work"/*

# Firmware build artifacts
rm -rf "${CLAUDE_IP_NAME_PATH}/firmware/build"/*
rm -rf "${CLAUDE_IP_NAME_PATH}/firmware/obj"/*
rm -rf "${CLAUDE_IP_NAME_PATH}/firmware/lib"/*

# Synthesis intermediates (keep reports and scripts)
find "${CLAUDE_IP_NAME_PATH}/synthesis" \
    \( -name "*.jou" -o -name "*.log" -o -name "*.pb" \
       -o -name ".Xil" -o -name "db" -o -name "incremental_db" \) \
    -exec rm -rf {} + 2>/dev/null || true

# Formal verification results (keep scripts and properties)
rm -f "${CLAUDE_IP_NAME_PATH}/verification/formal/results.log"
rm -rf "${CLAUDE_IP_NAME_PATH}/verification/formal/work"

# Lint logs (keep config and waivers)
rm -f "${CLAUDE_IP_NAME_PATH}/verification/lint/lint_results.log"

echo "Clean complete."
```

Apply the same `IP_NAME` substitution as described for `setup.sh`.

---

### 4. Generate skeleton `IP_NAME/doc/spec.md`

Sections: Overview, Features, Register Map (TBD), Interfaces, Timing, Known Limitations.

---

### 5. Generate `IP_NAME/design/systemrdl/tools/generate_IP_NAME.py`

Skeleton Python script. Must include the env var guard at the top of `main()`:

```python
#!/usr/bin/env python3
"""generate_IP_NAME.py — Drive PeakRDL to generate all outputs from IP_NAME.rdl."""

import argparse
import os
import sys


def main():
    # Guard: require CLAUDE_IP_NAME_PATH
    ip_path = os.environ.get("CLAUDE_IP_NAME_PATH")
    if not ip_path:
        print("ERROR: CLAUDE_IP_NAME_PATH is not set.")
        print("       Please run:  source IP_NAME/setup.sh")
        sys.exit(1)

    parser = argparse.ArgumentParser(description="Generate IP_NAME outputs from SystemRDL")
    parser.add_argument("--rdl",          default=f"{ip_path}/design/systemrdl/IP_NAME.rdl")
    parser.add_argument("--outdir-sv",    default=f"{ip_path}/design/rtl/verilog")
    parser.add_argument("--outdir-vhdl",  default=f"{ip_path}/design/rtl/vhdl")
    parser.add_argument("--outdir-c",     default=f"{ip_path}/firmware/include")
    parser.add_argument("--outdir-html",  default=f"{ip_path}/doc")
    args = parser.parse_args()

    # TODO (Step 2): invoke PeakRDL for each output type


if __name__ == "__main__":
    main()
```

---

### 6. Generate `IP_NAME/verification/tools/sim_IP_NAME.py`

Skeleton. Must include the env var guard. Key argument: `--sim {icarus,ghdl,modelsim,vivado}`,
`--test <name>`, `--lang {sv,vhdl}`. Must write
`${CLAUDE_IP_NAME_PATH}/verification/work/<sim>/results.log` containing `PASS` or `FAIL`.

---

### 7. Generate `IP_NAME/verification/tools/lint_IP_NAME.py`

Skeleton. Must include the env var guard. Argument: `--lang {sv,vhdl,all}`. Must write
`${CLAUDE_IP_NAME_PATH}/verification/lint/lint_results.log` containing `PASS` or `FAIL`.

---

### 8. Generate `IP_NAME/verification/tools/formal_IP_NAME.py`

Skeleton Python formal verification runner. Must include the env var guard. Writes
`${CLAUDE_IP_NAME_PATH}/verification/formal/results.log` containing `PASS` or `FAIL`.
Exits non-zero on `FAIL`. Full implementation is completed by the `formal` sub-agent
(Step 5).

---

### 9. Generate `IP_NAME/verification/tools/regression_IP_NAME.py`

Skeleton. Must include the env var guard. Invokes `sim_IP_NAME.py`, `formal_IP_NAME.py`,
and `lint_IP_NAME.py`. Must write
`${CLAUDE_IP_NAME_PATH}/verification/regression/report.md`. Exits non-zero on any failure.

---

### 10. Validate

Run `ls -R IP_NAME/` and assert all required directories exist.

---

## Outputs

| Artifact | Description |
|----------|-------------|
| `IP_NAME/` | Full directory tree |
| `IP_NAME/setup.sh` | Exports `CLAUDE_<IP_NAME>_PATH` and all tool paths |
| `IP_NAME/cleanup.sh` | Idempotent artifact removal (guards on env var) |
| `IP_NAME/doc/spec.md` | Skeleton specification document |
| `IP_NAME/design/systemrdl/tools/generate_IP_NAME.py` | PeakRDL driver skeleton |
| `IP_NAME/verification/tools/sim_IP_NAME.py` | Simulation runner skeleton |
| `IP_NAME/verification/tools/formal_IP_NAME.py` | Formal verification runner skeleton |
| `IP_NAME/verification/tools/lint_IP_NAME.py` | Lint runner skeleton |
| `IP_NAME/verification/tools/regression_IP_NAME.py` | Regression runner skeleton |

---

## Quality Gate

- `grep -r "IP_NAME" <name>/` returns zero results — no placeholder strings remain.
- All required directories exist (verified with `ls -R`).
- `setup.sh` sources cleanly twice without error or duplicate PATH entries.
- `setup.sh` exports `CLAUDE_<NAME>_PATH` pointing to the correct absolute directory.
- `setup.sh` exports `IP_COMMON_PATH` pointing to `IP/common/` (sibling of `IP_NAME/`).
- `IP_COMMON_PATH` directory exists on disk.
- `cleanup.sh` exits 1 with a clear message when `CLAUDE_<NAME>_PATH` is unset.
- `cleanup.sh` runs without error on a fresh checkout after sourcing `setup.sh`.
- All Python tool skeletons pass `python3 -m py_compile`.
- All Python tool skeletons exit 1 with the correct error message when
  `CLAUDE_<NAME>_PATH` is unset.
