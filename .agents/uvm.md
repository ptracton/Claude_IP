# Step 6 — `uvm` Sub-Agent

## Trigger

Step 5 complete (formal verification passing) and all directed tests passing; Vivado license available.

## Prerequisites

- `verification/work/icarus/results.log` and `verification/work/ghdl/results.log` both
  contain `PASS`.
- `verification/formal/results.log` contains `PASS`.
- `verification/testbench/`, `verification/tests/`, `verification/tasks/` exist and
  are populated from Step 4.
- `IP_COMMON_PATH` is set (sourced from `setup.sh`).
- Vivado 2023.1 or later is on `$PATH` (sourced from `setup.sh`).

## Common Components

**Check `${IP_COMMON_PATH}/verification/tasks/` before writing any new UVM driver or
monitor logic that implements bus-protocol mechanics.**

- The protocol BFMs in `${IP_COMMON_PATH}/verification/tasks/` provide the low-level
  signal driving. UVM drivers should delegate signal-level work to these shared tasks
  rather than duplicating bus protocol logic inside the UVM agent.
- If a reusable UVM base agent, sequence, or utility would benefit all IPs, place it in
  `${IP_COMMON_PATH}/verification/tools/` or a new `${IP_COMMON_PATH}/verification/uvm/`
  subdirectory, not inside this IP's testbench tree.

## Coding Standards

**RULE — Read the SystemVerilog style guide in full before writing a single line of UVM code.**

- `.agents/VerilogCodingStyle.md` — lowRISC Comportable style for SystemVerilog

**RULE — This document is immutable. Do not edit, summarize, or override it.**
Every rule applies to every `.sv` file produced by this step. If a style-guide rule and any
other instruction conflict, the style guide wins for all matters of code formatting and
structure.

**RULE — No silent deviations.** Any line that cannot comply must carry an inline comment
explaining why. Deviations without a comment are a quality-gate failure.

## Responsibilities

1. Build a UVM verification environment under `verification/testbench/uvm/`:
   - `env/IP_NAME_env.sv` — UVM env, scoreboard (uses behavioral model from Step 3),
     coverage collector.
   - `agent/IP_NAME_agent.sv` — UVM agent: sequencer, driver, monitor for the target
     bus protocol.
   - `seq/IP_NAME_seq_lib.sv` — Reusable sequence library: register read, register write,
     burst, reset-during-transaction.
   - `tests/IP_NAME_test_smoke.sv` — Smoke: basic write/read of every register.
   - `tests/IP_NAME_test_full_reg.sv` — Full register: all access types, all fields.
   - `tests/IP_NAME_test_stress.sv` — Stress: back-to-back random transactions.
   - `top/IP_NAME_tb_top.sv` — Sim top: DUT instantiation, clocking, `run_test()`.
2. Functional coverage must include:
   - All registers written and read at least once.
   - All field access-type combinations (RW, RO, WO, W1C, etc.).
   - Back-to-back transactions (no idle between consecutive operations).
   - Reset asserted during an active transaction.
3. Enable line, branch, and toggle code coverage in the Vivado xsim run.
4. Use the UVM register model (`uvm_reg_block`) generated from the RDL RAL adapter if
   available; otherwise build a manual `uvm_reg_block` matching the RDL.
5. Update `verification/tools/sim_IP_NAME.py` to support UVM test selection:
   - Adds `--uvm-test <test_name>` argument.
   - Runs via Vivado xsim in batch mode.
   - Writes `verification/work/vivado/<test_name>/results.log`.
6. Write coverage scripts:
   - `verification/tools/cov_IP_NAME.py` — merges Vivado coverage databases and
     generates an HTML report in `verification/work/vivado/coverage/`.
7. Document the UVM architecture in `doc/uvm_arch.md`:
   - ASCII or Mermaid block diagram.
   - Description of each component's role.
   - Coverage model summary.

## Outputs

| Artifact | Description |
|----------|-------------|
| `verification/testbench/uvm/env/` | UVM environment, scoreboard, coverage |
| `verification/testbench/uvm/agent/` | UVM agent (sequencer, driver, monitor) |
| `verification/testbench/uvm/seq/` | Reusable sequence library |
| `verification/testbench/uvm/tests/` | UVM test classes |
| `verification/testbench/uvm/top/` | Simulation top module |
| `verification/tools/sim_IP_NAME.py` | Updated with UVM test support |
| `verification/tools/cov_IP_NAME.py` | Coverage merge and report script |
| `doc/uvm_arch.md` | UVM architecture documentation |

## Quality Gate

- All three UVM tests (smoke, full_reg, stress) pass in Vivado xsim.
- Functional coverage closure reaches 100% on all required bins.
- `verification/work/vivado/*/results.log` contains `PASS` for each test.
- No UVM test bypasses the scoreboard.
