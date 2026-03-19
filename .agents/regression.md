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
- Accepts flags: `--skip-sim`, `--skip-uvm`, `--skip-formal`, `--skip-lint`,
  `--skip-modelsim`, `--skip-xsim`.
- Runs steps in order:
  1. `sim_IP_NAME.py --sim icarus --proto all --lang sv`
  2. `sim_IP_NAME.py --sim ghdl --proto all --lang vhdl`
  3. `sim_IP_NAME.py --sim modelsim --proto all --lang sv`   ← skip if `--skip-modelsim`
  4. `sim_IP_NAME.py --sim modelsim --proto all --lang vhdl` ← skip if `--skip-modelsim`
  5. `sim_IP_NAME.py --sim xsim --proto all --lang sv`       ← skip if `--skip-xsim`
  6. `sim_IP_NAME.py --sim xsim --proto all --lang vhdl`     ← skip if `--skip-xsim`
  7. `uvm_IP_NAME.py --test IP_NAME_base_test`  ← **separate script, NOT a flag on sim**; skip if `--skip-uvm`
  8. `run_formal.py --proto all`                ← skip if `--skip-formal`
  9. Lint results (read `verification/lint/lint_results.log`) ← skip if `--skip-lint`
- Collects exit codes and reads `results.log` files.
- Writes `verification/work/regression_results.log` with a complete pass/fail table.
- Exits non-zero if **any** test is `FAIL`. `SKIP` (tool not installed) is neutral — not a failure.

#### SKIP vs FAIL

When a simulator tool is not installed, `sim_IP_NAME.py` writes `SKIP` as the first
line of `results.log` (not `FAIL`). The regression runner treats `SKIP` as neutral:

```python
n_skip = sum(1 for _, s in results if s in ("SKIP", "MISSING"))
n_fail = total - n_pass - n_skip   # SKIP is not counted as failure
```

This allows partial regression runs on machines that have only a subset of tools installed.

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
  sim/modelsim/ahb_sv/test_reset        PASS
  ...
  sim/modelsim/wb_vhdl/test_timer_ops   PASS
  sim/xsim/ahb_sv/test_reset            PASS
  ...
  sim/xsim/wb_vhdl/test_timer_ops       PASS  (or SKIP if xsim not installed)
  formal/ahb                            PASS
  formal/apb                            PASS
  formal/axi4l                          PASS
  formal/wb                             PASS
  uvm/xsim/IP_NAME_base_test            PASS
  lint                                  PASS
------------------------------------------------------------
  Total: N  Pass: N  Fail: 0  Skip: 0
============================================================
REGRESSION PASSED
```

### 4. `parse_per_test_results` — defense-in-depth

Both `regression_IP_NAME.py` and `run_regression.py` call a helper that reads
`results.log` and maps test names to `PASS`/`FAIL`/`SKIP`. It must include two guards:

**Guard 1 — Downgrade stale PASS to FAIL if content contains FAIL:**
```python
if overall == "PASS" and any("FAIL" in l for l in lines[1:]):
    overall = "FAIL"
```
This catches results.log files written with a weak PASS check (e.g. `grep -q "PASS"` before
the FAIL-detection fix in `run_sims.sh`).

**Guard 2 — Treat `SKIP` as neutral (not `FAIL`):**
```python
valid_statuses = ("PASS", "FAIL", "SKIP")
overall = lines[0] if lines[0] in valid_statuses else "NO_RUN"
```

### 5. Reproducibility requirements

- No hardcoded absolute paths — all paths derived from `CLAUDE_<IP_NAME>_PATH`.
- `--skip-uvm`, `--skip-modelsim`, `--skip-xsim` allow running without those tools installed.
- Report file regenerated fresh on every run (not appended).
- Exit code 0 **only** when every non-SKIP entry is `PASS`.

### 6. `sim_IP_NAME.py` PASS/FAIL detection — simulator-specific rules

**PASS/FAIL detection for all simulator runners (Icarus, GHDL, ModelSim, xsim):**

```python
pass_marker  = f"PASS tb_IP_NAME_{proto}"
fail_markers = ["FAIL", "FATAL_ERROR"]   # FATAL_ERROR ≠ substring of "FAIL"
```

**Position-based check** — a `FATAL_ERROR` after the PASS banner is caused by process
termination (simulator kernel orphaned), not a real test failure:

```python
pass_pos = sim_out.find(pass_marker)
if pass_pos >= 0:
    pre_pass = sim_out[:pass_pos]
    passed = not any(m in pre_pass for m in fail_markers)
else:
    passed = False
```

**xsim process termination** — xsim does not reliably respond to SIGTERM. Wait up to
15 seconds for the process to exit cleanly (after `std.env.stop` is called by the
testbench), then force-kill:

```python
try:
    proc.wait(timeout=15)
except subprocess.TimeoutExpired:
    proc.kill()
    proc.wait()
```

**`run_sims.sh` PASS detection** — shell scripts must check for the specific final banner,
not bare `"PASS"` (which matches individual per-check "PASS" strings):

```bash
if [ ${rc} -eq 0 ] \
     && grep -q "PASS tb_IP_NAME_${proto}" "${log}" \
     && ! grep -q "FAIL" "${log}"; then
```

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

- `run_regression.py` exits 0 on a fully passing run (all entries `PASS` or `SKIP`).
- `run_regression.py` exits non-zero when any single test is `FAIL`.
- `regression_results.log` is regenerated fresh on every run (not appended).
- No hardcoded absolute paths.
- `uvm/xsim/IP_NAME_base_test` appears as a single entry in the table (not 5 per-test entries).
- `--skip-uvm`, `--skip-modelsim`, `--skip-xsim` skip the respective steps cleanly when tools are unavailable.
- `SKIP` entries are displayed in the summary table and counted separately; they do not cause a regression failure.
- `FATAL_ERROR` in a simulator log causes `FAIL` only when it appears *before* the PASS banner.
- A `FATAL_ERROR` appearing *after* the PASS banner (caused by process termination) does not fail the run.
- `parse_per_test_results` downgrades a claimed `PASS` to `FAIL` if any subsequent line contains `FAIL`.
