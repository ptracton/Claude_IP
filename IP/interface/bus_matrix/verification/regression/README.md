# bus_matrix Regression

How to run the full regression for the bus_matrix IP, how to read its result,
and how to add a test.

## Prerequisites

The runner adapts to the host (`hostname -f`):

| Host | Directed simulation | UVM | Formal | Lint (collected) |
|------|---------------------|-----|--------|------------------|
| `*.csun.edu` | Synopsys VCS + Cadence Xcelium (SV + VHDL) | VCS (all tests) | VC Formal (`vcf`) | SpyGlass |
| standard host | Icarus (SV), GHDL (VHDL), ModelSim, Vivado xsim | Vivado xsim | SymbiYosys | Verilator / GHDL |

A step whose tool is missing fails or is reported as `MISSING`. Use the
`--skip-*` flags for tools you don't have.

## Running from a Clean Checkout

```bash
source IP/interface/bus_matrix/setup.sh
python3 $CLAUDE_BUS_MATRIX_PATH/verification/tools/run_regression.py
# or
bash $CLAUDE_BUS_MATRIX_PATH/verification/regression/run_regression.sh
```

Lint is collected from `verification/lint/lint_results.log` but not run, so
run it first:

```bash
python3 $CLAUDE_BUS_MATRIX_PATH/verification/tools/lint_bus_matrix.py --lang all
```

Synthesis, STA, gate-level simulation and power are separate flows (see the
top-level README).

### Flags

| Flag | Effect |
|------|--------|
| `--skip-sim`      | Skip directed simulation |
| `--skip-uvm`      | Skip UVM |
| `--skip-formal`   | Skip formal (a full VC Formal run takes about 4 hours: the AXI4-Lite jobs take ~100 min each) |
| `--skip-lint`     | Don't collect the lint result |
| `--skip-modelsim` | Standard hosts: skip ModelSim |
| `--skip-xsim`     | Standard hosts: skip Vivado xsim directed simulation |

## Interpreting Results

The runner prints a table and writes it to
`verification/work/regression_results.log`:

```
============================================================
bus_matrix IP Regression Results
============================================================
  sim/vcs/ahb_sv/test_reset                    PASS
  ...
  sim/xcelium/wb_vhdl/test_arb                 PASS
  formal/vcf/bus_matrix_ahb_sv                 PASS
  ...
  uvm/vcs/all_tests                            PASS
  lint                                         PASS
------------------------------------------------------------
  Total: 108  Pass: 108  Fail: 0  Skip: 0
============================================================
REGRESSION PASSED
```

- Simulation rows are per test, per `<sim>/<proto>_<lang>` run directory. Only
  the current protocols (`apb`, `ahb`, `axi4l`, `wb`) are collected. If a run
  reports fewer than the six known tests, the missing ones count as FAIL.
- `PASS`/`FAIL` come from the first line of each `results.log`. A `PASS` whose
  log contains `FAIL` anywhere is downgraded to `FAIL`.
- `MISSING`/`SKIP` do not fail the regression. The exit code is 0 only when
  nothing failed.

`verification/regression/report.md` is a snapshot of the latest full run.

## Adding a New Test

1. Write the task in `verification/tests/test_<name>.sv`, using the
   `test_start` / `check_eq` / `test_done` helpers from `ip_test_pkg.sv`.
   Tests are protocol-neutral: they call the `write_reg` / `read_reg` tasks of
   the master BFMs `u_m0` / `u_m1`.
2. `` `include `` it in each `tb_bus_matrix_<proto>.sv` and call it from the
   stimulus block. Add the VHDL equivalent to `tb_bus_matrix_<proto>.vhd`.
3. Add the name to `KNOWN_TESTS` in `verification/tools/run_regression.py`.
4. Re-run the regression and check that the new rows appear and pass.
