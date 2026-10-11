# bus_matrix Regression Report

Generated 2026-10-10 on a `*.csun.edu` host by `run_regression.py`, from the
results of the 2026-10-10 runs (VCS/Xcelium directed simulation, UVM on VCS,
VC Formal, SpyGlass lint).

**Overall: PASS**: 108/108 collected results pass.

## Summary

| Metric | Count |
|--------|-------|
| Total entries | 108 |
| Pass | 108 |
| Fail | 0 |
| Skipped / missing | 0 |

## Directed simulation (82 checks per run)

| Simulator | Run | reset | route | strobe | decode_err | contention | arb |
|---|---|---|---|---|---|---|---|
| vcs | ahb_sv | PASS | PASS | PASS | PASS | PASS | PASS |
| vcs | ahb_vhdl | PASS | PASS | PASS | PASS | PASS | PASS |
| vcs | apb_sv | PASS | PASS | PASS | PASS | PASS | PASS |
| vcs | apb_vhdl | PASS | PASS | PASS | PASS | PASS | PASS |
| vcs | axi4l_sv | PASS | PASS | PASS | PASS | PASS | PASS |
| vcs | axi4l_vhdl | PASS | PASS | PASS | PASS | PASS | PASS |
| vcs | wb_sv | PASS | PASS | PASS | PASS | PASS | PASS |
| vcs | wb_vhdl | PASS | PASS | PASS | PASS | PASS | PASS |
| xcelium | ahb_sv | PASS | PASS | PASS | PASS | PASS | PASS |
| xcelium | ahb_vhdl | PASS | PASS | PASS | PASS | PASS | PASS |
| xcelium | apb_sv | PASS | PASS | PASS | PASS | PASS | PASS |
| xcelium | apb_vhdl | PASS | PASS | PASS | PASS | PASS | PASS |
| xcelium | axi4l_sv | PASS | PASS | PASS | PASS | PASS | PASS |
| xcelium | axi4l_vhdl | PASS | PASS | PASS | PASS | PASS | PASS |
| xcelium | wb_sv | PASS | PASS | PASS | PASS | PASS | PASS |
| xcelium | wb_vhdl | PASS | PASS | PASS | PASS | PASS | PASS |

## Formal (VC Formal Y-2026.03-SP1)

| Job | Assertions proven | Covers covered | Waived | Result |
|---|---|---|---|---|
| bus_matrix_arb_fv_top_sv   | 17/17 | 14/14 | 0  | PASS |
| bus_matrix_arb_fv_top_vhdl | 17/17 | 14/14 | 0  | PASS |
| bus_matrix_apb_sv          | 88/88 | 56/60 | 4  | PASS |
| bus_matrix_apb_vhdl        | 88/88 | 56/60 | 4  | PASS |
| bus_matrix_ahb_sv          | 72/76 | 58/66 | 12 | PASS |
| bus_matrix_ahb_vhdl        | 72/76 | 58/66 | 12 | PASS |
| bus_matrix_axi4l_sv        | 96/96 | 60/72 | 12 | PASS (3 h budget; took ~100 min) |
| bus_matrix_axi4l_vhdl      | 96/96 | 60/72 | 12 | PASS (3 h budget) |
| bus_matrix_wb_sv           | 72/72 | 56/60 | 4  | PASS |
| bus_matrix_wb_vhdl         | 72/72 | 56/60 | 4  | PASS |

The waivers are justified in `verification/formal/vcf/README.md`.

## UVM (VCS, UVM 1.2)

| Test | Result |
|---|---|
| bus_matrix_base_test | PASS |
| bus_matrix_rw_test | PASS — 64 writes, 64 reads, 0 mismatches |
| bus_matrix_contention_test | PASS — 32 writes, 32 reads, 0 mismatches |
| bus_matrix_map_test | PASS — 152 writes, 148 reads, 96 decode errors, 16 slave errors, 0 mismatches; coverage 100 % |
| bus_matrix_decerr_test | PASS — 96 decode errors, guard words unchanged, 0 mismatches |

## Lint

| Language | Tool | Result |
|---|---|---|
| SV (4 top-levels) | SpyGlass Y-2026.03-SP1 | PASS — 0 findings, 0 waivers |
| VHDL | — | SKIPPED (no VHDL-2008 lint on csun.edu) |

## Not covered by this run

- Standard-host tools: Icarus, GHDL, ModelSim, xsim, Verilator, SymbiYosys.
  They are not installed on csun.edu. Their scripts are ported but untested.
- Synthesis, STA, gate-level simulation and power are separate flows. Their
  2026-10-10 results are in the top-level README: DC and PrimeTime on 4 PDKs
  (SAED90 -0.56 ns accepted), gate-level 16/16 PASS, power 16/16.
