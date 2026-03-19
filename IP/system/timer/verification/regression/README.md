# Timer IP Regression

This document explains how to run the full regression suite for the timer IP block,
how to interpret the generated report, and how to add new tests.

---

## Prerequisites

The following tools must be installed and available on `PATH` (or under
`/opt/oss-cad-suite/bin` as expected by the runners):

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| Python 3 | 3.9+ | Regression and tool scripts |
| Icarus Verilog (`iverilog` / `vvp`) | 12.0 | SystemVerilog simulation |
| GHDL | 4.1 | VHDL simulation |
| Verilator | 5.0 | Lint (SystemVerilog) |
| SymbiYosys / yosys-smtbmc | any recent | Formal verification |

The easiest way to satisfy the EDA-tool requirements is to install the
[OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build) release, which
bundles Icarus Verilog, GHDL, Verilator, Yosys, and SymbiYosys together.

---

## Running the Regression from a Clean Checkout

1. **Source the environment setup script** from the repository root:

   ```bash
   source IP/system/timer/setup.sh
   ```

   This sets `CLAUDE_TIMER_PATH` (and optionally `IP_COMMON_PATH`) which all
   tool scripts require.

2. **Run the regression runner**:

   ```bash
   python3 $CLAUDE_TIMER_PATH/verification/tools/regression_timer.py
   ```

   Alternatively, use the convenience shell wrapper:

   ```bash
   bash $CLAUDE_TIMER_PATH/verification/regression/run_regression.sh
   ```

3. The runner will execute, in order:
   - Simulation — Icarus Verilog (SystemVerilog) for all four bus protocols
   - Simulation — GHDL (VHDL) for all four bus protocols
   - Formal verification — SymbiYosys for all four bus protocols
   - Lint — Verilator (SV) and GHDL analysis (VHDL)

4. When it finishes, the consolidated report is at:

   ```
   $CLAUDE_TIMER_PATH/verification/regression/report.md
   ```

   The script exits with code `0` on overall PASS and `1` on any FAIL.

---

## Interpreting report.md

`report.md` contains three sections.

### Per-test simulation table

```
| Test           | Simulator | Protocol | Language | Result |
|----------------|-----------|----------|----------|--------|
| test_reset     | icarus    | apb      | SV       | PASS   |
...
```

Each row represents one named test running inside a specific simulator/protocol/
language combination.  `Result` is either `PASS` or `FAIL`.

### Step summary table

A high-level roll-up with one row per major step (simulation, formal, lint).

### Detail logs

Raw stdout/stderr captured from each sub-runner, useful for diagnosing failures.

**Reading a FAIL**: find the test row(s) that show `FAIL`, then scroll to the
matching section in **Detail Logs** to see the compiler/simulator output.

---

## Adding a New Test

Tests live inside the shared testbench files under `verification/testbench/`.
Each testbench calls a fixed sequence of named tasks defined in
`verification/tests/`.

### Steps

1. **Write the task** in `verification/tests/<test_name>_tasks.sv` (SV) or
   the equivalent `.vhd` file for VHDL.  Follow the naming convention
   `test_<verb>` (e.g., `test_overflow`).

2. **Call the task** from every testbench that should include it.  The standard
   call site is the sequential block near the end of each
   `verification/testbench/tb_timer_<proto>.sv` (and `.vhd`) file.

3. **Declare the test name** so it appears in `results.log`.  Each task is
   expected to emit lines matching:
   ```
   <test_name>: <description>
   <test_name>: PASS
   ```
   on success, or `<test_name>: FAIL` on failure, before calling `$finish`.

4. **Add the test name** to the `KNOWN_TESTS` list in
   `verification/tools/regression_timer.py` so the regression reporter
   generates a dedicated row in `report.md`:

   ```python
   KNOWN_TESTS = [
       "test_reset",
       "test_rw",
       "test_back2back",
       "test_strobe",
       "test_timer_ops",
       "test_overflow",   # <-- add here
   ]
   ```

5. Re-run the regression to confirm the new test appears and passes.
