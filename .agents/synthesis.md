# Step 10 — `synthesis` Sub-Agent

## Trigger

Step 8 (`lint_IP_NAME.py`) exits 0 and Step 3 complete.

## Prerequisites

- `verification/lint/lint_results.log` contains `PASS`.
- `design/rtl/verilog/` and `design/rtl/vhdl/` are parse-clean.
- `synthesis/yosys/`, `synthesis/vivado/`, `synthesis/quartus/` directories exist.
- Yosys 0.36+ is on `$PATH` (from `setup.sh` via OSS CAD Suite).
- `vivado` is on `$PATH` (from `setup.sh` via Vivado 2023.2 `settings64.sh`).
- `quartus_sh` is on `$PATH` (from `setup.sh` — `/opt/intelFPGA_lite/23.1std/quartus/bin`).

## Responsibilities

### Yosys (`synthesis/yosys/`)

1. Write one `.ys` script per bus-interface variant (`synth_IP_NAME_apb.ys`, `_ahb.ys`,
   `_axi4l.ys`, `_wb.ys`):
   - Reads all SV RTL sources from `design/rtl/verilog/`.
   - Runs `synth -flatten` targeting the generic cell library.
   - Emits `stat` output for cell-count parsing.
2. Write `synthesis/yosys/run_synth.py` — Python runner that:
   - Invokes Yosys on each variant.
   - Parses `stat` output for total cells and flip-flop count.
   - Writes `synthesis/yosys/work/synthesis_report.log` with a per-variant summary table.
3. Run `python3 synthesis/yosys/run_synth.py` and verify exit 0.

### Vivado (`synthesis/vivado/`)

Target device: **`xc7z010clg400-1`** (Zynq-7010, CLG400 package, speed grade -1 —
Zybo-Z7-10 board).

1. Write `synthesis/vivado/synth.tcl`:
   - Creates an **in-memory** project (`create_project -in_memory -part xc7z010clg400-1`).
   - Sets `target_language Verilog` (valid values are `Verilog` or `VHDL` — **not**
     `SystemVerilog`; SV sources are still read with `read_verilog -sv`).
   - Reads all SV RTL sources with `read_verilog -sv`.
   - **Do not** call `set_property -name {STEPS.SYNTH_DESIGN.ARGS.MORE OPTIONS} -objects
     [get_runs synth_1]` — `get_runs synth_1` returns empty in an in-memory project.
   - Writes the OOC XDC clock constraint to a temp `.xdc` file, then reads it with
     `read_xdc <file>`. **Do not** use `read_xdc - << { ... }` — stdin is not supported
     in batch mode.
   - Runs `synth_design -top IP_NAME_apb -part xc7z010clg400-1 -mode out_of_context
     -flatten_hierarchy rebuilt`.
   - Writes utilization report to `synthesis/vivado/utilization.rpt`.
   - Writes timing summary to `synthesis/vivado/timing_summary.rpt`.
2. Run via `synthesis/run_vendor_synth.py --vivado` (see below).
3. Verify WNS ≥ 0 at 100 MHz.

### Quartus (`synthesis/quartus/`)

Target device: **`5CSEMA4U23C6`** (Cyclone V SE A4 — DE0-Nano-SoC / Arrow SoCKit;
comparable to Zynq-7010 in fabric size and hard-ARM architecture).

1. Write `synthesis/quartus/synth.tcl`:
   - Loads **`package require ::quartus::project`** and **`package require ::quartus::flow`**.
   - `execute_module -tool map` belongs to `::quartus::flow` — load that package, not
     `::quartus::misc`.
   - **Do not** call `execute_flow -analysis_and_synthesis` — `-analysis_and_synthesis`
     is not a valid option for `execute_flow` in Quartus Prime Lite/Standard.
   - **Do not** call `report_utilization` or `report_timing_summary` — these are Vivado
     commands; they do not exist in Quartus Tcl.
   - Creates the project under `synthesis/quartus/work/IP_NAME_apb/`.
   - Sets `FAMILY "Cyclone V"`, `DEVICE "5CSEMA4U23C6"`, `TOP_LEVEL_ENTITY IP_NAME_apb`.
   - Adds all SV RTL sources with `SYSTEMVERILOG_FILE` assignments.
   - Writes an SDC file if it does not exist; adds it with `SDC_FILE` assignment.
   - Runs `execute_module -tool map` (Analysis & Synthesis only — no Fitter).
   - Calls `project_close` before exiting.
   - ALMs will show `N/A` in the map report — this is expected for synthesis without
     Fitter. Only `Total registers` is available from synthesis alone.
2. Run via `synthesis/run_vendor_synth.py --quartus` (see below).

### `synthesis/run_vendor_synth.py`

Write a Python runner that:
- Accepts `--vivado` and `--quartus` flags (default: both).
- Locates tools with `shutil.which("vivado")` and `shutil.which("quartus_sh")`.
- Invokes each TCL script via `subprocess.run` with `stdout=PIPE, stderr=STDOUT`.
- Saves raw output to `synthesis/vivado/vivado_run.log` and
  `synthesis/quartus/quartus_run.log`.
- Parses Vivado `utilization.rpt` for LUT/FF counts (regex on `Slice LUTs` and
  `Slice Registers` table rows).
- Parses Vivado `timing_summary.rpt` for WNS by matching the `PCLK` row in the
  per-clock timing table (not the header line — the header shows `-------` dashes
  before the numeric values).
- Locates the Quartus map report by searching `synthesis/quartus/work/` for `*.map.rpt`.
- Parses `Total registers` from the Quartus map report.
- Writes `synthesis/vivado/report.txt` and `synthesis/quartus/report.txt`.
- Exits 0 only when all requested tools pass.

### Common

- All synthesis flows are batch/TCL only — no GUI, no interactive steps.
- Any synthesis warning from RTL sources must be resolved or documented in
  `synthesis/known_issues.md` (warning text, tool, line, root cause, disposition).
- Update `README.md` — **Synthesis Results** section:

  ```markdown
  ### Yosys (technology-independent)

  | Variant   | Top module   | Total cells | Flip-flops | Result |
  |-----------|--------------|-------------|------------|--------|
  | APB4      | IP_NAME_apb  | NNN         | NNN        | PASS   |
  ...

  ### Vivado (Zynq-7010 xc7z010clg400-1)

  | Variant | LUTs | FFs | BRAM | DSP | WNS     | Result |
  |---------|------|-----|------|-----|---------|--------|
  | APB4    | NNN  | NNN | 0    | 0   | +N.Nns  | PASS   |

  ### Quartus (Cyclone V SE 5CSEMA4U23C6)

  | Variant | Registers | M10K | DSP | Result |
  |---------|-----------|------|-----|--------|
  | APB4    | NNN       | 0    | 0   | PASS   |
  ```

  Include tool versions and date generated.

## Outputs

| Artifact | Description |
|----------|-------------|
| `synthesis/yosys/synth_IP_NAME_<proto>.ys` | Yosys synthesis scripts (one per variant) |
| `synthesis/yosys/run_synth.py` | Yosys runner and report generator |
| `synthesis/yosys/work/synthesis_report.log` | Yosys area summary |
| `synthesis/vivado/synth.tcl` | Vivado OOC synthesis script (target: Zynq-7010) |
| `synthesis/vivado/utilization.rpt` | Vivado LUT/FF/BRAM/DSP utilization |
| `synthesis/vivado/timing_summary.rpt` | Vivado WNS/TNS timing summary |
| `synthesis/vivado/report.txt` | Human-readable Vivado summary |
| `synthesis/quartus/synth.tcl` | Quartus Analysis & Synthesis script (target: 5CSEMA4U23C6) |
| `synthesis/quartus/work/IP_NAME_apb.map.rpt` | Quartus map report |
| `synthesis/quartus/report.txt` | Human-readable Quartus summary |
| `synthesis/run_vendor_synth.py` | Python runner for Vivado and Quartus |
| `synthesis/known_issues.md` | Documented warnings (may be empty) |

## Quality Gate

- Yosys completes without errors for all variants.
- Vivado exits 0; `utilization.rpt` and `timing_summary.rpt` are written; WNS ≥ 0 at 100 MHz.
- Quartus exits 0; `*.map.rpt` is written.
- `synthesis/run_vendor_synth.py` exits 0 with both tools passing.
- `synthesis/known_issues.md` exists (even if empty) and all unresolved warnings are documented.
- All scripts run non-interactively from the command line.

## Known Tcl Pitfalls

| Tool | Wrong | Correct |
|------|-------|---------|
| Vivado | `set_property target_language SystemVerilog` | `set_property target_language Verilog` |
| Vivado | `read_xdc - << { ... }` (stdin, fails in batch) | Write XDC to a temp file, then `read_xdc <file>` |
| Vivado | `get_runs synth_1` in in-memory project | Omit — returns empty; pass `-mode out_of_context` directly to `synth_design` |
| Quartus | `package require ::quartus::misc` for `execute_module` | `package require ::quartus::flow` |
| Quartus | `execute_flow -analysis_and_synthesis` | `execute_module -tool map` |
| Quartus | `report_utilization` / `report_timing_summary` | Parse auto-generated `*.map.rpt` from Python |
