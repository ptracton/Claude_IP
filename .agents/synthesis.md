# Step 10 — `synthesis` Sub-Agent

## Trigger

Step 8 (`lint_IP_NAME.py`) exits 0 and Step 3 complete.

## Prerequisites

- `verification/lint/lint_results.log` contains `PASS`.
- `design/rtl/verilog/` and `design/rtl/vhdl/` are parse-clean.

**Standard hosts** (not ecs-vdi):
- `synthesis/yosys/`, `synthesis/vivado/`, `synthesis/quartus/` directories exist.
- Yosys 0.36+ is on `$PATH` (from `setup.sh` via OSS CAD Suite).
- `vivado` is on `$PATH` (from `setup.sh` via Vivado 2023.2 `settings64.sh`).
- `quartus_sh` is on `$PATH` (from `setup.sh` — `/opt/intelFPGA_lite/23.1std/quartus/bin`).

**On ecs-vdi.ecs.csun.edu** (Vivado, Quartus, and Yosys are NOT available):
- `synthesis/designcompiler/` directory exists.
- `dc_shell` is on `$PATH` (Synopsys Design Compiler).
- 90nm PDK at `/opt/ECE_Lib/SAED90nm_EDK_10072017/SAED90_EDK/SAED_EDK90nm`.
- 32nm PDK at `/opt/ECE_Lib/SAED32_EDK`.
- 14nm PDK at `/opt/ECE_Lib/SAED14nm_EDK_03_2025`.

## Machine-Specific Environment: ecs-vdi.ecs.csun.edu

When running on `ecs-vdi.ecs.csun.edu`, the following tools are **not available**:
- Vivado / Xilinx tools
- Quartus / Intel/Altera tools
- Yosys

On this host the **only** supported synthesis tool is:
- Synopsys Design Compiler (`dc_shell` on `$PATH`)

`run_vendor_synth.py` must detect this environment at startup:

```python
import socket
ON_ECS_VDI = socket.getfqdn() == "ecs-vdi.ecs.csun.edu"
```

When `ON_ECS_VDI` is `True`:
- Skip Vivado, Quartus, and Yosys synthesis.
- Run Design Compiler for **both** 90nm (SAED90) and 32nm (SAED32) PDKs.
- All Python code must work without activating a virtualenv — use only system Python packages.

## Responsibilities

### Design Compiler (ecs-vdi only, `synthesis/designcompiler/`)

#### `synthesis/designcompiler/synth.tcl`

The script supports both PDKs via the `PDK_TARGET` environment variable (default: `saed90`):

| `PDK_TARGET` | Env var required | Library path |
|---|---|---|
| `saed90` | `SAED90_PDK` | `$SAED90_PDK/Digital_Standard_cell_Library/synopsys/models/saed90nm_max.db` |
| `saed32` | `SAED32_EDK` | `$SAED32_EDK/lib/stdcell_rvt/db_nldm/saed32rvt_ss0p95v125c.db` (RVT SS 0.95V 125°C) |
| `saed14` | `SAED14_EDK` | `$SAED14_EDK/SAED14nm_EDK_STD_RVT/liberty/nldm/base/saed14rvt_base_ss0p72v125c.db` (RVT SS 0.72V 125°C) |

Key requirements:
- Enable SystemVerilog and VHDL-2008: `set_app_var verilog_mode 2012` and `set_app_var hdlin_vhdl_std 2008`.
- Use `analyze -format sverilog` and `analyze -format vhdl` (not `read_file` — only `analyze` honors `search_path`).
- Add both SV and VHDL source tree roots to `search_path`.
- Analyze shared interface files first: `claude_apb_if.sv`, `claude_ahb_if.sv`, `claude_axi4l_if.sv`, `claude_wb_if.sv` (and their `.vhd` counterparts).
- Synthesize four SV variants and four VHDL variants (clock port names differ per protocol):

  | Variant | VHDL clock port |
  |---|---|
  | `timer_apb` | `PCLK` |
  | `timer_ahb` | `HCLK` |
  | `timer_axi4l` | `ACLK` |
  | `timer_wb` | `CLK_I` |

- Use a `synth_variant` proc to avoid duplicating the elaborate/compile/report/write loop.
- Reports go to `reports/$PDK_TARGET/<variant>[_vhdl]_{area,timing}.rpt` via `redirect -append`.
- Netlists go to `netlists/$PDK_TARGET/<variant>[_vhdl].{v,sdf}`.
- Create output directories with `file mkdir` before the synthesis loop.
- Timing constraint: 100 MHz (`create_clock -period 10 <clk_port>`).
- Compile: `compile -map_effort low`.

#### `synthesis/run_vendor_synth.py` — Design Compiler section

Constants:
```python
SAED90_PDK = "/opt/ECE_Lib/SAED90nm_EDK_10072017/SAED90_EDK/SAED_EDK90nm"
SAED32_EDK = "/opt/ECE_Lib/SAED32_EDK"

PDK_CONFIGS = {
    "saed90": {"label": "SAED90 (90nm)", "env_var": "SAED90_PDK", "path": SAED90_PDK},
    "saed32": {"label": "SAED32 (32nm)", "env_var": "SAED32_EDK", "path": SAED32_EDK},
}
```

`run_design_compiler(synth_dir, pdk_target)`:
- Sets `PDK_TARGET=<pdk_target>` and the appropriate PDK path env var.
- Writes log to `designcompiler/dc_<pdk_target>_run.log`.
- Timeout: 1200 s (two back-to-back PDK runs).

`write_dc_report(synth_dir, pdk_target, util)`:
- Writes `designcompiler/report_<pdk_target>.txt`.
- References `reports/<pdk_target>/` and `netlists/<pdk_target>/`.

CLI flags on ecs-vdi:
- `--dc` — run all three PDKs (default when no flags given on ecs-vdi).
- `--dc90` — 90nm only.
- `--dc32` — 32nm only.
- `--dc14` — 14nm only.

#### `synthesis/clean.sh`

A standalone bash script that removes all DC-generated files:
- Directories: `cksum_dir/`, `reports/`, `netlists/`, `ARCH/`, `ENTI/`, `PACK/` (DC VHDL library dirs).
- Files: `*.v`, `*.sdf`, `*.pvk`, `*.pvl`, `*.syn`, `*.mr`, `dc_saed90_run.log`, `dc_saed32_run.log`, `command.log`, `default.svf`, `report.txt`.
- Yosys: `yosys/work/`.
- Python: `__pycache__/`.

Must be called from the top-level `cleanup.sh` in addition to `run_vendor_synth.py --clean`.

### Yosys (`synthesis/yosys/`)

Write one `.ys` script per bus-interface variant for both SV and VHDL:

**SV variants** (`synth_IP_NAME_<proto>.ys`):
- `read_verilog -sv` all RTL sources including `claude_<proto>_if.sv`.
- `synth -top IP_NAME_<proto> -flatten`, `stat`, `write_verilog -noattr`.

**VHDL variants** (`synth_IP_NAME_<proto>_vhdl.ys`):
- Load the ghdl plugin: `plugin -i ghdl`.
- `ghdl --std=08 <interface.vhd> <common.vhd> ... <variant.vhd> -e IP_NAME_<proto>`.
- `synth -top IP_NAME_<proto> -flatten`, `stat`, `write_verilog -noattr work/IP_NAME_<proto>_vhdl_synth.v`.

Write `synthesis/yosys/run_synth.py`:
- Invokes Yosys on each SV and VHDL variant script.
- Parses `stat` output for total cells and flip-flop count.
- Writes `synthesis/yosys/work/synthesis_report.log` with a per-variant summary table.

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
2. Run via `synthesis/run_vendor_synth.py --vivado`.
3. Verify WNS ≥ 0 at 100 MHz.

### Quartus (`synthesis/quartus/`)

Target device: **`5CSEMA4U23C6`** (Cyclone V SE A4 — DE0-Nano-SoC / Arrow SoCKit).

1. Write `synthesis/quartus/synth.tcl`:
   - Loads **`package require ::quartus::project`** and **`package require ::quartus::flow`**.
   - `execute_module -tool map` belongs to `::quartus::flow` — load that package, not
     `::quartus::misc`.
   - **Do not** call `execute_flow -analysis_and_synthesis`.
   - **Do not** call `report_utilization` or `report_timing_summary`.
   - Creates the project under `synthesis/quartus/work/IP_NAME_apb/`.
   - Sets `FAMILY "Cyclone V"`, `DEVICE "5CSEMA4U23C6"`, `TOP_LEVEL_ENTITY IP_NAME_apb`.
   - Adds all SV RTL sources with `SYSTEMVERILOG_FILE` assignments.
   - Writes an SDC file if it does not exist; adds it with `SDC_FILE` assignment.
   - Runs `execute_module -tool map`.
   - Calls `project_close` before exiting.
2. Run via `synthesis/run_vendor_synth.py --quartus`.

### `synthesis/run_vendor_synth.py` — Common

- Accepts `--vivado`, `--quartus` (standard hosts); `--dc`, `--dc90`, `--dc32` (ecs-vdi).
- Default on standard hosts: run Vivado + Quartus.
- Default on ecs-vdi: run DC with both PDKs (`--dc` behavior).
- Locates tools with `shutil.which`.
- Invokes each TCL script via `subprocess.run` with `stdout=PIPE, stderr=STDOUT`.
- Exits 0 only when all requested tools pass.

### Common

- All synthesis flows are batch/TCL only — no GUI, no interactive steps.
- Any synthesis warning from RTL sources must be resolved or documented in
  `synthesis/known_issues.md` (warning text, tool, line, root cause, disposition).
- Update `README.md` — **Synthesis Results** section with actual numbers and dates.

## Outputs

**On standard hosts:**

| Artifact | Description |
|----------|-------------|
| `synthesis/yosys/synth_IP_NAME_<proto>.ys` | Yosys SV synthesis scripts (one per variant) |
| `synthesis/yosys/synth_IP_NAME_<proto>_vhdl.ys` | Yosys VHDL synthesis scripts (one per variant) |
| `synthesis/yosys/work/synthesis_report.log` | Yosys area summary |
| `synthesis/vivado/synth.tcl` | Vivado OOC synthesis script (target: Zynq-7010) |
| `synthesis/vivado/utilization.rpt` | Vivado LUT/FF/BRAM/DSP utilization |
| `synthesis/vivado/timing_summary.rpt` | Vivado WNS/TNS timing summary |
| `synthesis/vivado/report.txt` | Human-readable Vivado summary |
| `synthesis/quartus/synth.tcl` | Quartus Analysis & Synthesis script |
| `synthesis/quartus/work/IP_NAME_apb.map.rpt` | Quartus map report |
| `synthesis/quartus/report.txt` | Human-readable Quartus summary |
| `synthesis/run_vendor_synth.py` | Python runner for all tools |
| `synthesis/clean.sh` | Removes all DC-generated outputs |
| `synthesis/known_issues.md` | Documented warnings (may be empty) |

**On ecs-vdi.ecs.csun.edu:**

| Artifact | Description |
|----------|-------------|
| `synthesis/designcompiler/synth.tcl` | DC script (SAED90 + SAED32, SV + VHDL) |
| `synthesis/designcompiler/dc_saed90_run.log` | Raw DC output — 90nm run |
| `synthesis/designcompiler/dc_saed32_run.log` | Raw DC output — 32nm run |
| `synthesis/designcompiler/dc_saed14_run.log` | Raw DC output — 14nm run |
| `synthesis/designcompiler/report_saed90.txt` | Human-readable DC summary — 90nm |
| `synthesis/designcompiler/report_saed32.txt` | Human-readable DC summary — 32nm |
| `synthesis/designcompiler/report_saed14.txt` | Human-readable DC summary — 14nm |
| `synthesis/designcompiler/reports/saed90/` | Per-variant area + timing reports — 90nm |
| `synthesis/designcompiler/reports/saed32/` | Per-variant area + timing reports — 32nm |
| `synthesis/designcompiler/reports/saed14/` | Per-variant area + timing reports — 14nm |
| `synthesis/designcompiler/netlists/saed90/` | Netlists + SDF — 90nm |
| `synthesis/designcompiler/netlists/saed32/` | Netlists + SDF — 32nm |
| `synthesis/designcompiler/netlists/saed14/` | Netlists + SDF — 14nm |
| `synthesis/run_vendor_synth.py` | Python runner (host-aware; DC on ecs-vdi) |
| `synthesis/clean.sh` | Removes all DC-generated outputs |
| `synthesis/known_issues.md` | Documented warnings (may be empty) |

## Quality Gate

**Standard hosts:**
- Yosys completes without errors for all SV and VHDL variants.
- Vivado exits 0; `utilization.rpt` and `timing_summary.rpt` written; WNS ≥ 0 at 100 MHz.
- Quartus exits 0; `*.map.rpt` is written.
- `synthesis/run_vendor_synth.py` exits 0 with all available tools passing.

**On ecs-vdi.ecs.csun.edu:**
- DC exits 0 for all SV and VHDL variants under SAED90, SAED32, and SAED14.
- `netlists/saed90/`, `netlists/saed32/`, and `netlists/saed14/` all populated with `.v` and `.sdf` files.
- `synthesis/run_vendor_synth.py` exits 0 for all three PDK runs.

**All hosts:**
- `synthesis/known_issues.md` exists (even if empty) and all unresolved warnings are documented.
- All scripts run non-interactively from the command line.

## Known Tcl Pitfalls

| Tool | Wrong | Correct |
|------|-------|---------|
| DC | `read_file {claude_apb_if.sv ...}` | `analyze -format sverilog {claude_apb_if.sv ...}` — only `analyze` honors `search_path` |
| DC | `read_file {timer_ahb.vhd}` | `analyze -format vhdl {timer_ahb.vhd}` |
| DC | `set_app_var search_path "path1 path2"` | `set_app_var search_path [list path1 path2]` |
| Vivado | `set_property target_language SystemVerilog` | `set_property target_language Verilog` |
| Vivado | `read_xdc - << { ... }` (stdin, fails in batch) | Write XDC to a temp file, then `read_xdc <file>` |
| Vivado | `get_runs synth_1` in in-memory project | Omit — returns empty; pass `-mode out_of_context` directly to `synth_design` |
| Quartus | `package require ::quartus::misc` for `execute_module` | `package require ::quartus::flow` |
| Quartus | `execute_flow -analysis_and_synthesis` | `execute_module -tool map` |
| Quartus | `report_utilization` / `report_timing_summary` | Parse auto-generated `*.map.rpt` from Python |
