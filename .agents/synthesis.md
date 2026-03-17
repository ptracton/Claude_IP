# Step 10 — `synthesis` Sub-Agent

## Trigger

Step 8 (`lint_IP_NAME.py`) exits 0 and Step 3 complete.

## Prerequisites

- `verification/lint/lint_results.log` contains `PASS`.
- `design/rtl/verilog/` and `design/rtl/vhdl/` are parse-clean.
- `synthesis/yosys/`, `synthesis/vivado/`, `synthesis/quartus/` directories exist.
- Yosys 0.36+, Vivado 2023.1+, and Quartus Prime 22.1+ are on `$PATH` (from `setup.sh`).

## Responsibilities

### Yosys (`synthesis/yosys/`)

1. Write `synthesis/yosys/synth.ys`:
   - Reads all SV RTL sources from `design/rtl/verilog/`.
   - Runs `synth` targeting a generic cell library.
   - Writes JSON netlist to `synthesis/yosys/IP_NAME.json`.
2. Run synthesis and capture stdout/stderr to `synthesis/yosys/report.txt`.
3. Report must include: cell count, logic levels (critical path estimate), any warnings.

### Vivado (`synthesis/vivado/`)

1. Write `synthesis/vivado/synth.tcl`:
   - Targets representative Xilinx part: `xc7a35tcpg236-1`.
   - Runs out-of-context synthesis only (no implementation).
   - Exports utilization report and timing summary.
2. Run non-interactively: `vivado -mode batch -source synthesis/vivado/synth.tcl`.
3. Save utilization and timing reports to `synthesis/vivado/report.txt`.
4. Verify timing closure at 100 MHz (WNS ≥ 0 at a 10.0 ns period constraint).

### Quartus (`synthesis/quartus/`)

1. Write `synthesis/quartus/synth.tcl`:
   - Targets representative Intel part: `5CSEBA6U23I7`.
   - Runs synthesis and fit.
2. Run non-interactively: `quartus_sh --script synthesis/quartus/synth.tcl`.
3. Save area and Fmax summary to `synthesis/quartus/report.txt`.
4. Verify Fmax ≥ 100 MHz.

### Common

4. All synthesis flows are batch/TCL only — no GUI, no interactive steps.
5. Any synthesis warning originating from RTL sources must be either resolved or documented
   in `synthesis/known_issues.md`:
   - Warning text, tool, and line reference.
   - Root cause analysis.
   - Disposition: fixed, accepted with justification, or tracked for future fix.

## Outputs

| Artifact | Description |
|----------|-------------|
| `synthesis/yosys/synth.ys` | Yosys synthesis script |
| `synthesis/yosys/report.txt` | Yosys area and critical-path report |
| `synthesis/vivado/synth.tcl` | Vivado OOC synthesis script |
| `synthesis/vivado/report.txt` | Vivado utilization and timing summary |
| `synthesis/quartus/synth.tcl` | Quartus synthesis and fit script |
| `synthesis/quartus/report.txt` | Quartus area and Fmax summary |
| `synthesis/known_issues.md` | Documented synthesis warnings (may be empty) |

## Quality Gate

- Yosys completes without errors.
- Vivado timing report shows WNS ≥ 0 at 100 MHz.
- Quartus Fmax ≥ 100 MHz.
- `synthesis/known_issues.md` exists (even if empty) and all un-resolved warnings are documented.
- All scripts run non-interactively from the command line.
