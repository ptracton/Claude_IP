# Step 5 — `formal` Sub-Agent

## Trigger

Step 4 complete and all directed tests passing.

## Prerequisites

- All eight directed-test results logs
  (`verification/work/icarus/<proto>_sv/results.log` ×4 and
  `verification/work/ghdl/<proto>_vhdl/results.log` ×4) contain `PASS`.
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

Because each bus protocol is a **separate top-level entity**, write one SVA bind file
per top-level. Each bind file instantiates common protocol invariants from
`${IP_COMMON_PATH}/verification/formal/bus_protocol_props.sv` and adds
IP-specific functional properties.

Files in `verification/formal/`:

| File | Bound to top-level |
|------|--------------------|
| `IP_NAME_ahb_props.sv` | `IP_NAME_ahb` |
| `IP_NAME_apb_props.sv` | `IP_NAME_apb` |
| `IP_NAME_axi4l_props.sv` | `IP_NAME_axi4l` |
| `IP_NAME_wb_props.sv` | `IP_NAME_wb` |

Each property file must include at minimum:
- **Reset properties** (from `${IP_COMMON_PATH}/verification/formal/reset_props.sv`):
  after reset, all outputs reach documented reset values within one clock cycle.
- **Bus-protocol invariants** (from `${IP_COMMON_PATH}/verification/formal/bus_protocol_props.sv`):
  the bus interface never violates its protocol specification.
- **Register-access properties**: a write followed by a read to the same address
  (no intervening write) returns the written value for RW registers; RO registers
  never change due to a write.
- **Cover properties**: at least one `cover` statement per register, reachable via
  the specific bus protocol for this top-level.

### 2. Write SymbiYosys configuration files

Create BMC and cover `.sby` files per top-level per task in `verification/formal/`:

| File | Top-level | Task |
|------|-----------|------|
| `IP_NAME_ahb_bmc.sby` | `IP_NAME_ahb` | BMC (20 cycles) |
| `IP_NAME_ahb_cover.sby` | `IP_NAME_ahb` | Cover reachability |
| `IP_NAME_apb_bmc.sby` | `IP_NAME_apb` | BMC (20 cycles) |
| `IP_NAME_apb_cover.sby` | `IP_NAME_apb` | Cover reachability |
| `IP_NAME_axi4l_bmc.sby` | `IP_NAME_axi4l` | BMC (20 cycles) |
| `IP_NAME_axi4l_cover.sby` | `IP_NAME_axi4l` | Cover reachability |
| `IP_NAME_wb_bmc.sby` | `IP_NAME_wb` | BMC (20 cycles) |
| `IP_NAME_wb_cover.sby` | `IP_NAME_wb` | Cover reachability |

Optional: `IP_NAME_<proto>_prove.sby` for unbounded proof via k-induction or PDR if
the design depth permits.

Each `.sby` file follows this structure (example for `IP_NAME_ahb_bmc.sby`):

```
[options]
mode bmc          # or cover / prove
depth 20

[engines]
smtbmc boolector

[script]
read -formal design/rtl/verilog/IP_NAME_reg_pkg.sv
read -formal design/rtl/verilog/IP_NAME_regfile.sv
read -formal design/rtl/verilog/IP_NAME_core.sv
read -formal design/rtl/verilog/IP_NAME_ahb_if.sv
read -formal design/rtl/verilog/IP_NAME_ahb.sv
read -formal verification/formal/IP_NAME_ahb_props.sv
prep -top IP_NAME_ahb

[files]
design/rtl/verilog/IP_NAME_reg_pkg.sv
design/rtl/verilog/IP_NAME_regfile.sv
design/rtl/verilog/IP_NAME_core.sv
design/rtl/verilog/IP_NAME_ahb_if.sv
design/rtl/verilog/IP_NAME_ahb.sv
verification/formal/IP_NAME_ahb_props.sv
```

Repeat the pattern for `apb`, `axi4l`, and `wb`, substituting the top-level name in
`prep -top` and the property file in the file lists.

All file paths in `.sby` files must be relative to `CLAUDE_IP_NAME_PATH` and use the
`CLAUDE_IP_NAME_PATH` environment variable via shell expansion in the runner script —
never hardcoded absolute paths.

### 3. Complete `verification/tools/formal_IP_NAME.py`

Replace the Step 1 skeleton with a full implementation:

- Guards on `CLAUDE_IP_NAME_PATH` at startup.
- Accepts `--proto {ahb,apb,axi4l,wb,all}` and `--task {bmc,cover,prove,all}`
  (defaults: `all`/`all`).
- Resolves all paths relative to `CLAUDE_IP_NAME_PATH`.
- Runs `sby -f IP_NAME_<proto>_<task>.sby` for each selected combination from the
  `verification/formal/` working directory.
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


PROTOS = ["ahb", "apb", "axi4l", "wb"]
TASKS  = ["bmc", "cover"]  # add "prove" if unbounded proof is included


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
    parser.add_argument("--proto", choices=PROTOS + ["all"], default="all")
    parser.add_argument("--task",  choices=TASKS  + ["all"], default="all")
    args = parser.parse_args()

    protos = PROTOS if args.proto == "all" else [args.proto]
    tasks  = TASKS  if args.task  == "all" else [args.task]
    results = {}

    for proto in protos:
        for task in tasks:
            key     = f"IP_NAME_{proto}_{task}"
            sby_file = formal_dir / f"{key}.sby"
            print(f"Running formal: {key}")
            ret = subprocess.run(["sby", "-f", str(sby_file)], cwd=formal_dir)
            results[key] = "PASS" if ret.returncode == 0 else "FAIL"

    with open(results_log, "w") as f:
        for key, result in results.items():
            f.write(f"{result}: {key}\n")
        overall = "PASS" if all(r == "PASS" for r in results.values()) else "FAIL"
        f.write(f"OVERALL: {overall}\n")

    print(f"Formal verification: {overall}")
    sys.exit(0 if overall == "PASS" else 1)


if __name__ == "__main__":
    main()
```

Apply the `IP_NAME` substitution throughout before writing the file.

### 4. Run and verify

Run `formal_IP_NAME.py --proto all --task all` and confirm:

- `verification/formal/results.log` contains `OVERALL: PASS`.
- All eight BMC runs (4 protocols × bmc + cover) produce no counterexample within 20 cycles.
- All cover properties are reachable for each top-level.

### 5. Update `README.md`

Replace the `[TBD]` placeholder in **Formal Verification Results** with:

- A table of every proto × task combination and its result:

  ```markdown
  | Top-level       | Task  | Engine           | Depth | Result |
  |-----------------|-------|------------------|-------|--------|
  | IP_NAME_ahb     | BMC   | smtbmc/boolector | 20    | PASS   |
  | IP_NAME_ahb     | Cover | smtbmc/boolector | 20    | PASS   |
  | IP_NAME_apb     | BMC   | smtbmc/boolector | 20    | PASS   |
  | IP_NAME_apb     | Cover | smtbmc/boolector | 20    | PASS   |
  | IP_NAME_axi4l   | BMC   | smtbmc/boolector | 20    | PASS   |
  | IP_NAME_axi4l   | Cover | smtbmc/boolector | 20    | PASS   |
  | IP_NAME_wb      | BMC   | smtbmc/boolector | 20    | PASS   |
  | IP_NAME_wb      | Cover | smtbmc/boolector | 20    | PASS   |
  ```

- A brief list of the properties checked (reset, bus-protocol invariants per protocol,
  register read-back, cover reachability).
- The Yosys/SymbiYosys version used and the date results were generated.

## Outputs

| Artifact | Description |
|----------|-------------|
| `verification/formal/IP_NAME_ahb_props.sv` | SVA properties bound to `IP_NAME_ahb` |
| `verification/formal/IP_NAME_apb_props.sv` | SVA properties bound to `IP_NAME_apb` |
| `verification/formal/IP_NAME_axi4l_props.sv` | SVA properties bound to `IP_NAME_axi4l` |
| `verification/formal/IP_NAME_wb_props.sv` | SVA properties bound to `IP_NAME_wb` |
| `verification/formal/IP_NAME_<proto>_bmc.sby` | SymbiYosys BMC config (one per protocol) |
| `verification/formal/IP_NAME_<proto>_cover.sby` | SymbiYosys cover config (one per protocol) |
| `verification/formal/IP_NAME_<proto>_prove.sby` | Unbounded proof config, optional |
| `verification/tools/formal_IP_NAME.py` | Completed formal verification runner |
| `verification/formal/results.log` | Per proto×task and overall `PASS` / `FAIL` |

## Quality Gate

- `formal_IP_NAME.py --proto all --task all` exits 0.
- `verification/formal/results.log` final line is `OVERALL: PASS`.
- All eight BMC+cover runs (4 protocols × 2 tasks) pass.
- No counterexample produced by any BMC run within 20 cycles.
- All `cover` properties are reachable for every top-level.
- No hardcoded absolute paths in any `.sby` file or in `formal_IP_NAME.py`.
- All SVA property names follow the naming convention from `VerilogCodingStyle.md`.
