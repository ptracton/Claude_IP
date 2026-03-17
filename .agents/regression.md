# Step 7 — `regression` Sub-Agent

## Trigger

Steps 4, 5, and 6 complete (all directed tests, formal verification, and UVM tests passing).

## Prerequisites

- `verification/work/icarus/results.log` and `verification/work/ghdl/results.log` contain `PASS`.
- `verification/formal/results.log` contains `PASS`.
- `verification/work/vivado/*/results.log` contains `PASS` for all UVM tests.
- `verification/lint/lint_results.log` contains `PASS` (coordinate with lint sub-agent, Step 8).
- `verification/regression/` directory exists.
- `verification/tools/regression_IP_NAME.py` skeleton exists from Step 1.
- `IP_COMMON_PATH` is set (sourced from `setup.sh`).
- `${IP_COMMON_PATH}/verification/tools/ip_tool_base.py` exists (provides base class).

## Common Components

Import `ip_tool_base.py` from `${IP_COMMON_PATH}/verification/tools/ip_tool_base.py`.
Do not duplicate the env-var guard, results-log writer, or subprocess runner — use the
shared base class.

## Responsibilities

1. Complete `verification/tools/regression_IP_NAME.py`:
   - Sources `setup.sh` environment at startup (via `subprocess` or `os.environ`).
   - Calls `sim_IP_NAME.py` for every directed test across all configured simulators.
   - Calls `formal_IP_NAME.py` for formal verification.
   - Calls `sim_IP_NAME.py --uvm-test` for every UVM test via Vivado.
   - Calls `lint_IP_NAME.py --lang all`.
   - Collects exit codes and parses `results.log` / `lint_results.log` from every step.
   - Writes `verification/regression/report.md` with a complete pass/fail table.
   - Exits non-zero if **any** test or lint check fails.
2. `verification/regression/report.md` must follow this exact format:

   ```
   | Test                    | Simulator  | Language | Result |
   |-------------------------|------------|----------|--------|
   | test_reset               | icarus     | SV       | PASS   |
   | test_reset               | ghdl       | VHDL     | PASS   |
   | test_rw                  | icarus     | SV       | PASS   |
   | formal_bmc              | yosys      | SV       | PASS   |
   | formal_cover            | yosys      | SV       | PASS   |
   | uvm_smoke               | vivado     | SV       | PASS   |
   | uvm_full_reg            | vivado     | SV       | PASS   |
   | uvm_stress              | vivado     | SV       | PASS   |
   | lint_sv                 | verilator  | SV       | PASS   |
   | lint_vhdl               | vhdl_ls    | VHDL     | PASS   |
   ```

3. `regression_IP_NAME.py` exit code must be 0 **only** when every test and lint check passes.
4. The regression is fully reproducible — no tool GUI, no manual steps, no hardcoded paths
   (all paths derived from environment variables set by `setup.sh`).
5. Write `verification/regression/README.md`:
   - Prerequisites (tools and minimum versions).
   - Step-by-step instructions to run from a clean checkout.
   - How to interpret `report.md`.
   - How to add a new test to the regression.

## Outputs

| Artifact | Description |
|----------|-------------|
| `verification/tools/regression_IP_NAME.py` | Completed single-command regression runner |
| `verification/regression/report.md` | Human-readable pass/fail table |
| `verification/regression/README.md` | Prerequisites and usage instructions |

## Quality Gate

- `regression_IP_NAME.py` exits 0 on a fully passing run.
- `regression_IP_NAME.py` exits non-zero when any single test is forced to fail.
- `report.md` is regenerated fresh on every run (not appended to).
- No hardcoded absolute paths in `regression_IP_NAME.py`.
