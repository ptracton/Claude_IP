# Step 7 — `regression` Sub-Agent

## Trigger

Steps 4, 5, and 6 complete (all directed tests, formal verification, and UVM tests passing).

## Prerequisites

- `verification/work/icarus/<proto>_sv/results.log` contains `PASS` for all 4 protocols.
- `verification/work/ghdl/<proto>_vhdl/results.log` contains `PASS` for all 4 protocols.
- `verification/work/formal/<proto>/results.log` contains `PASS` for all protocols.
- `verification/work/xsim/uvm/results.log` contains `PASS` (UVM, Step 6).
- `verification/lint/lint_results.log` contains `PASS` (coordinate with lint sub-agent, Step 8).
- `verification/regression/` directory exists.
- `verification/tools/run_regression.py` skeleton exists from Step 1.
- `CLAUDE_<IP_NAME>_PATH` is set (sourced from `setup.sh`).

## Responsibilities

### 1. Complete `verification/tools/run_regression.py`

- Sources `setup.sh` environment at startup (via `os.environ` / `CLAUDE_<IP_NAME>_PATH`).
- Accepts flags: `--skip-sim`, `--skip-uvm`, `--skip-formal`, `--skip-lint`.
- Runs steps in order:
  1. `sim_IP_NAME.py --sim icarus --proto all --lang sv`
  2. `sim_IP_NAME.py --sim ghdl --proto all --lang vhdl`
  3. `uvm_IP_NAME.py --test IP_NAME_base_test`  ← **separate script, NOT a flag on sim**
  4. `run_formal.py --proto all`
  5. Lint results (read `verification/lint/lint_results.log`)
- Collects exit codes and reads `results.log` files.
- Writes `verification/work/regression_results.log` with a complete pass/fail table.
- Exits non-zero if **any** test or lint check fails.

### 2. UVM result collection

UVM produces a **single** results file at `verification/work/xsim/uvm/results.log`
(first line `PASS` or `FAIL`, remaining lines are the full simulator output).

**Do NOT expand this into per-directed-test entries** — the generic sim result parser
looks for lines like `test_reset: PASS` which are not present in UVM logs, causing it to
fall back to 5 bogus per-test entries.

Instead, skip `xsim/uvm/` in the generic sim loop and collect it separately as one entry:

```python
# In the sim dir loop — skip UVM before the generic parser:
if sim_dir.name == "xsim" and run_dir.name == "uvm":
    continue

# After the sim loop — collect UVM as a single labeled entry:
uvm_work = work / "xsim" / "uvm"
if uvm_work.exists():
    status = read_result_log(str(uvm_work / "results.log"))
    entries.append(("uvm/xsim/IP_NAME_base_test", status))
```

### 3. Results table format

```
============================================================
IP_NAME Regression Results
============================================================
  sim/icarus/ahb_sv/test_reset          PASS
  sim/icarus/ahb_sv/test_rw             PASS
  ...
  sim/ghdl/wb_vhdl/test_timer_ops       PASS
  formal/ahb                            PASS
  formal/apb                            PASS
  formal/axi4l                          PASS
  formal/wb                             PASS
  uvm/xsim/IP_NAME_base_test            PASS
  lint                                  PASS
------------------------------------------------------------
  Total: N  Pass: N  Fail: 0
============================================================
REGRESSION PASSED
```

### 4. Reproducibility requirements

- No hardcoded absolute paths — all paths derived from `CLAUDE_<IP_NAME>_PATH`.
- `--skip-uvm` allows running without Vivado installed.
- Report file regenerated fresh on every run (not appended).
- Exit code 0 **only** when every entry is `PASS`.

### 5. Write `verification/regression/README.md`

Include:
- Prerequisites (tools and minimum versions).
- Step-by-step instructions to run from a clean checkout.
- How to interpret the results table.
- How to add a new test.

## Outputs

| Artifact | Description |
|----------|-------------|
| `verification/tools/run_regression.py` | Completed single-command regression runner |
| `verification/work/regression_results.log` | Full pass/fail table (regenerated each run) |
| `verification/regression/README.md` | Prerequisites and usage instructions |

## Quality Gate

- `run_regression.py` exits 0 on a fully passing run.
- `run_regression.py` exits non-zero when any single test is forced to fail.
- `regression_results.log` is regenerated fresh on every run (not appended).
- No hardcoded absolute paths.
- `uvm/xsim/IP_NAME_base_test` appears as a single entry in the table (not 5 per-test entries).
- `--skip-uvm` skips the UVM step cleanly when Vivado is unavailable.
