# bus_matrix Regression Report

Generated 2026-04-05 by `run_regression.py`.

## Summary

| Metric | Count |
|--------|-------|
| Total  | 23    |
| Pass   | 17    |
| Fail   | 0     |
| Skip   | 6     |

**REGRESSION PASSED**

## Detailed Results

| Test | Result |
|------|--------|
| sim/icarus/ahb_sv/test_bus_matrix_ops | PASS |
| sim/icarus/axi_sv/test_bus_matrix_ops | PASS |
| sim/icarus/wb_sv/test_bus_matrix_ops | PASS |
| sim/ghdl/ahb_vhdl/test_bus_matrix_ops | PASS |
| sim/ghdl/axi_vhdl/test_bus_matrix_ops | PASS |
| sim/ghdl/wb_vhdl/test_bus_matrix_ops | PASS |
| sim/modelsim/ahb_sv | PASS |
| sim/modelsim/axi_sv | PASS |
| sim/modelsim/wb_sv | PASS |
| sim/xsim/ahb_sv/test_bus_matrix_ops | PASS |
| sim/xsim/axi_sv/test_bus_matrix_ops | PASS |
| sim/xsim/wb_sv/test_bus_matrix_ops | PASS |
| sim/xsim/ahb_vhdl | SKIP |
| sim/xsim/axi_vhdl | SKIP |
| sim/xsim/wb_vhdl | SKIP |
| uvm/xsim/bus_matrix_base_test | PASS |
| formal/bus_matrix_arb | PASS |
| formal/bus_matrix_crossbar | PASS |
| formal/bus_matrix_decode | PASS |
| lint | PASS |
| sim/modelsim/ahb_vhdl | SKIP |
| sim/modelsim/axi_vhdl | SKIP |
| sim/modelsim/wb_vhdl | SKIP |

## Skip Reasons

- **ModelSim VHDL**: No VHDL `.do` files implemented (SV-only for ModelSim)
- **xsim VHDL**: VHDL testbenches not supported in xsim runner
