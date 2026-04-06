# bus_matrix Regression

## Prerequisites

| Tool | Minimum Version | Purpose |
|------|----------------|---------|
| Icarus Verilog | 11.0+ | SystemVerilog directed tests |
| GHDL | 3.0+ | VHDL-2008 directed tests |
| Verilator | 5.0+ | SV linting |
| Vivado xsim | 2023.2 | xsim SV directed tests + UVM |
| ModelSim ASE | 21.1 | Mixed-language simulation (optional) |
| SymbiYosys | 0.36+ | Formal verification (optional) |

Not all tools are required. Use `--skip-*` flags to skip unavailable tools.

## Running from a Clean Checkout

```bash
# 1. Source the environment
source IP/interface/bus_matrix/setup.sh

# 2. Run the full regression (skipping tools you don't have)
python3 $CLAUDE_BUS_MATRIX_PATH/verification/tools/run_regression.py \
    --skip-modelsim --skip-formal --skip-uvm

# 3. Or run everything
python3 $CLAUDE_BUS_MATRIX_PATH/verification/tools/run_regression.py
```

### Available Flags

| Flag | Effect |
|------|--------|
| `--skip-sim` | Skip all directed simulation (Icarus, GHDL, xsim, ModelSim) |
| `--skip-uvm` | Skip UVM tests |
| `--skip-formal` | Skip formal verification |
| `--skip-lint` | Skip lint check |
| `--skip-modelsim` | Skip ModelSim simulations |
| `--skip-xsim` | Skip Vivado xsim simulations |

## Interpreting Results

The regression writes `verification/work/regression_results.log` with a table:

```
============================================================
bus_matrix Regression Results
============================================================
  sim/icarus/ahb_sv/test_bus_matrix_ops   PASS
  sim/icarus/axi_sv/test_bus_matrix_ops   PASS
  ...
  formal/bus_matrix_arb                   PASS
  formal/bus_matrix_crossbar              PASS
  formal/bus_matrix_decode                PASS
  uvm/xsim/bus_matrix_base_test          PASS
  lint                                    PASS
------------------------------------------------------------
  Total: 23  Pass: 17  Fail: 0  Skip: 6
============================================================
REGRESSION PASSED
```

- **PASS**: Test ran and succeeded.
- **FAIL**: Test ran and failed. Check the corresponding log in `verification/work/`.
- **SKIP**: Tool not installed or combination not supported. Does not count as failure.
- **NO_RUN**: Results file missing or empty.

Exit code is 0 only when all non-SKIP entries are PASS.

## Adding a New Test

1. Add the test task to `verification/tests/test_<name>.sv` using the
   `test_start` / `check_eq` / `test_done` helpers from `ip_test_pkg.sv`.
2. Include it in the testbench (`tb_bus_matrix_<proto>.sv`) via `` `include ``.
3. Call the test task from the stimulus `initial` block.
4. The regression runner automatically picks up per-test results from the
   `test_name: PASS` lines in the simulation output.

## Alternative: Shell-Based Regression

A shell-based regression script is also available:

```bash
source IP/interface/bus_matrix/setup.sh
bash $CLAUDE_BUS_MATRIX_PATH/verification/regression/run_regression.sh [--verbose] [--xsim]
```
