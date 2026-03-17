# Step 6 — `uvm` Sub-Agent

## Trigger

Step 5 complete (formal verification passing) and all directed tests passing; Vivado license available.

## Prerequisites

- All eight directed-test results logs contain `PASS`
  (`verification/work/icarus/<proto>_sv/results.log` ×4 and
  `verification/work/ghdl/<proto>_vhdl/results.log` ×4).
- `verification/formal/results.log` final line is `OVERALL: PASS`.
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

1. Build a UVM verification environment under `verification/testbench/uvm/`.

   Because each bus protocol is a **separate top-level entity**, there is one UVM agent
   per protocol. All agents share a single UVM env, scoreboard, and sequence library.
   The env is parameterized so the same scoreboard and coverage collector works with any
   protocol agent.

   Structure:

   - `env/IP_NAME_env.sv` — UVM env: scoreboard (uses behavioral model from Step 3),
     coverage collector. Protocol-agnostic; instantiated by each protocol's test top.
   - `agent/IP_NAME_ahb_agent.sv` — UVM agent for AHB-Lite: sequencer, driver, monitor.
   - `agent/IP_NAME_apb_agent.sv` — UVM agent for APB4: sequencer, driver, monitor.
   - `agent/IP_NAME_axi4l_agent.sv` — UVM agent for AXI4-Lite: sequencer, driver, monitor.
   - `agent/IP_NAME_wb_agent.sv` — UVM agent for Wishbone B4: sequencer, driver, monitor.
   - `seq/IP_NAME_seq_lib.sv` — Reusable protocol-agnostic sequences: register read,
     register write, burst, reset-during-transaction.
   - `tests/IP_NAME_test_smoke.sv` — Smoke: basic write/read of every register.
   - `tests/IP_NAME_test_full_reg.sv` — Full register: all access types, all fields.
   - `tests/IP_NAME_test_stress.sv` — Stress: back-to-back random transactions.
   - `top/IP_NAME_ahb_tb_top.sv` — Sim top for AHB-Lite DUT: instantiates `IP_NAME_ahb`,
     clocking, and `run_test()`.
   - `top/IP_NAME_apb_tb_top.sv` — Sim top for APB4 DUT.
   - `top/IP_NAME_axi4l_tb_top.sv` — Sim top for AXI4-Lite DUT.
   - `top/IP_NAME_wb_tb_top.sv` — Sim top for Wishbone B4 DUT.

   Each `top/` file instantiates only its named top-level entity — no DUT-selection defines.
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
   - ASCII or Mermaid block diagram showing the four-agent / shared-env structure.
   - Description of each component's role.
   - Coverage model summary including which covergroups are protocol-specific vs. shared.
8. Update `README.md` — replace the `[TBD]` placeholder in **UVM Verification Results** with
   a table of every test × protocol combination and its result:

   ```markdown
   | Test         | Protocol | Simulator | Result | Func. Coverage |
   |--------------|----------|-----------|--------|----------------|
   | uvm_smoke    | AHB      | vivado    | PASS   | 100%           |
   | uvm_smoke    | APB      | vivado    | PASS   | 100%           |
   | uvm_smoke    | AXI4L    | vivado    | PASS   | 100%           |
   | uvm_smoke    | WB       | vivado    | PASS   | 100%           |
   | uvm_full_reg | AHB      | vivado    | PASS   | 100%           |
   ...
   ```

   Include code coverage summary (line %, branch %, toggle %), a link to `doc/uvm_arch.md`,
   the Vivado version, and the date results were generated.

## Outputs

| Artifact | Description |
|----------|-------------|
| `verification/testbench/uvm/env/` | UVM environment, scoreboard, coverage |
| `verification/testbench/uvm/agent/IP_NAME_ahb_agent.sv` | AHB-Lite UVM agent |
| `verification/testbench/uvm/agent/IP_NAME_apb_agent.sv` | APB4 UVM agent |
| `verification/testbench/uvm/agent/IP_NAME_axi4l_agent.sv` | AXI4-Lite UVM agent |
| `verification/testbench/uvm/agent/IP_NAME_wb_agent.sv` | Wishbone B4 UVM agent |
| `verification/testbench/uvm/seq/` | Reusable sequence library |
| `verification/testbench/uvm/tests/` | UVM test classes (shared across protocols) |
| `verification/testbench/uvm/top/IP_NAME_<proto>_tb_top.sv` | Sim top per protocol (×4) |
| `verification/tools/sim_IP_NAME.py` | Updated with `--uvm-test` and `--proto` support |
| `verification/tools/cov_IP_NAME.py` | Coverage merge and report script |
| `doc/uvm_arch.md` | UVM architecture documentation |

## Quality Gate

- All twelve UVM combinations (3 tests × 4 protocols) pass in Vivado xsim.
- Functional coverage closure reaches 100% on all required bins for all protocols.
- `verification/work/vivado/<proto>/<test>/results.log` contains `PASS` for every combination.
- No UVM test bypasses the scoreboard.
- Each `top/IP_NAME_<proto>_tb_top.sv` instantiates only its named DUT — no DUT-selection defines.
