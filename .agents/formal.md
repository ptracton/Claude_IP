# Step 5 — `formal` Sub-Agent

## Trigger

Step 4 complete and all directed tests passing.

## Prerequisites

- `verification/work/icarus/results.log` and `verification/work/ghdl/results.log` both
  contain `PASS`.
- `design/rtl/verilog/` populated with parse-clean RTL sources.
- `verification/formal/` directory exists.
- `verification/tools/formal_IP_NAME.py` skeleton exists from Step 1.
- `IP_COMMON_PATH` is set (sourced from `setup.sh`).
- Yosys with SymbiYosys (`sby`) from OSS CAD Suite is on `$PATH` (sourced from `setup.sh`).

## Common Components

**Check `${IP_COMMON_PATH}/verification/formal/` before writing any new SVA properties.**

- `${IP_COMMON_PATH}/verification/formal/reset_props.sv` — parameterized reset-state
  property template. Bind and specialize it rather than rewriting reset assertions.
- `${IP_COMMON_PATH}/verification/formal/bus_protocol_props.sv` — bus-protocol invariant
  templates for AHB-Lite, APB4, AXI4-Lite, and Wishbone B4. Use these for the adapter
  verification; only write IP-specific functional properties in `verification/formal/`.
- If new reusable property templates are developed, place them in
  `${IP_COMMON_PATH}/verification/formal/` for other IPs to benefit from.
- All `read` paths in `.sby` files that reference common properties must use
  `IP_COMMON_PATH`, never a hardcoded path.

## Coding Standards

**RULE — Read the SystemVerilog style guide in full before writing any SVA properties.**

- `.agents/VerilogCodingStyle.md` — lowRISC Comportable style for SystemVerilog

**RULE — This document is immutable. Do not edit, summarize, or override it.**
If a style-guide rule and any other instruction conflict, the style guide wins.

**RULE — No silent deviations.** Any line that cannot comply must carry an inline comment
explaining why.

## Responsibilities

### 1. Write SVA property files

Write SystemVerilog Assertion (SVA) property files in `verification/formal/`:

- `IP_NAME_props.sv` — bind file containing all formal properties for the IP core.
  Must include at minimum:
  - **Reset properties**: after reset is asserted, all outputs reach their documented
    reset values within one clock cycle.
  - **Bus-protocol properties**: for each supported bus interface, assert that the
    adapter never violates the protocol specification (e.g., no write response before
    write address, no read data without a pending read).
  - **Register-access properties**: a write followed by a read to the same address
    (with no intervening write) returns the written value for RW registers; RO registers
    never change due to a write.
  - **Cover properties**: at least one `cover` statement per register demonstrating
    that the register is reachable and can be written and read.

### 2. Write SymbiYosys configuration files

Create one `.sby` configuration file per verification task in `verification/formal/`:

- `IP_NAME_bmc.sby` — Bounded Model Checking: prove all `assert` properties hold for
  at least 20 clock cycles.
- `IP_NAME_cover.sby` — Cover checking: prove all `cover` properties are reachable.
- `IP_NAME_prove.sby` — (optional, if design depth permits) Unbounded proof using
  k-induction or PDR.

Each `.sby` file structure:

```
[options]
mode bmc          # or cover / prove
depth 20

[engines]
smtbmc boolector

[script]
read -formal design/rtl/verilog/IP_NAME_reg_pkg.sv
read -formal design/rtl/verilog/IP_NAME_regfile.sv
read -formal design/rtl/verilog/IP_NAME.sv
read -formal verification/formal/IP_NAME_props.sv
prep -top IP_NAME

[files]
design/rtl/verilog/IP_NAME_reg_pkg.sv
design/rtl/verilog/IP_NAME_regfile.sv
design/rtl/verilog/IP_NAME.sv
verification/formal/IP_NAME_props.sv
```

All file paths in `.sby` files must be relative to `CLAUDE_IP_NAME_PATH` and use the
`CLAUDE_IP_NAME_PATH` environment variable via shell expansion in the runner script —
never hardcoded absolute paths.

### 3. Complete `verification/tools/formal_IP_NAME.py`

Replace the Step 1 skeleton with a full implementation:

- Guards on `CLAUDE_IP_NAME_PATH` at startup.
- Accepts `--task {bmc,cover,prove,all}` (default: `all`).
- Resolves all paths relative to `CLAUDE_IP_NAME_PATH`.
- Runs `sby -f <task>.sby` for each selected task from the `verification/formal/`
  working directory.
- Captures stdout/stderr per task.
- Writes `verification/formal/results.log`:
  - One line per task: `PASS: IP_NAME_bmc` or `FAIL: IP_NAME_bmc`.
  - Final summary line: `PASS` (all tasks passed) or `FAIL` (one or more failed).
- Exits 0 only when all tasks pass; exits non-zero on any failure.

```python
#!/usr/bin/env python3
"""formal_IP_NAME.py — Run Yosys/SymbiYosys formal verification on IP_NAME."""

import argparse
import os
import subprocess
import sys
from pathlib import Path


TASKS = ["bmc", "cover"]  # add "prove" if unbounded proof is included


def main():
    # Guard: require CLAUDE_IP_NAME_PATH
    ip_path = os.environ.get("CLAUDE_IP_NAME_PATH")
    if not ip_path:
        print("ERROR: CLAUDE_IP_NAME_PATH is not set.")
        print("       Please run:  source IP_NAME/setup.sh")
        sys.exit(1)

    formal_dir = Path(ip_path) / "verification" / "formal"
    results_log = formal_dir / "results.log"

    parser = argparse.ArgumentParser(description="Run formal verification for IP_NAME")
    parser.add_argument("--task", choices=TASKS + ["all"], default="all")
    args = parser.parse_args()

    tasks = TASKS if args.task == "all" else [args.task]
    results = {}

    for task in tasks:
        sby_file = formal_dir / f"IP_NAME_{task}.sby"
        print(f"Running formal task: {task}")
        ret = subprocess.run(
            ["sby", "-f", str(sby_file)],
            cwd=formal_dir,
        )
        results[task] = "PASS" if ret.returncode == 0 else "FAIL"

    with open(results_log, "w") as f:
        for task, result in results.items():
            f.write(f"{result}: IP_NAME_{task}\n")
        overall = "PASS" if all(r == "PASS" for r in results.values()) else "FAIL"
        f.write(f"{overall}\n")

    print(f"Formal verification: {overall}")
    sys.exit(0 if overall == "PASS" else 1)


if __name__ == "__main__":
    main()
```

Apply the `IP_NAME` substitution throughout before writing the file.

### 4. Run and verify

Run `formal_IP_NAME.py --task all` and confirm:

- `verification/formal/results.log` contains `PASS`.
- No unbounded counterexample is produced by BMC within 20 cycles.
- All cover properties are reachable.

## Outputs

| Artifact | Description |
|----------|-------------|
| `verification/formal/IP_NAME_props.sv` | SVA property and cover file |
| `verification/formal/IP_NAME_bmc.sby` | SymbiYosys BMC configuration |
| `verification/formal/IP_NAME_cover.sby` | SymbiYosys cover configuration |
| `verification/formal/IP_NAME_prove.sby` | SymbiYosys unbounded proof config (optional) |
| `verification/tools/formal_IP_NAME.py` | Completed formal verification runner |
| `verification/formal/results.log` | Per-task and overall `PASS` / `FAIL` |

## Quality Gate

- `formal_IP_NAME.py --task all` exits 0.
- `verification/formal/results.log` final line is `PASS`.
- BMC reaches depth 20 with no counterexample.
- All `cover` properties are reachable (SymbiYosys reports `reached`).
- No hardcoded absolute paths in any `.sby` file or in `formal_IP_NAME.py`.
- All SVA property names follow the naming convention from `VerilogCodingStyle.md`.
