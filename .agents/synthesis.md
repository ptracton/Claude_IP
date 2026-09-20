# Step 10 — `synthesis` Sub-Agent

## Trigger

Step 8 (`lint_IP_NAME.py`) exits 0 and Step 3 complete.

## Prerequisites

- `verification/lint/lint_results.log` contains `PASS`.
- `design/rtl/verilog/` and `design/rtl/vhdl/` are parse-clean.

**Standard hosts** (not csun.edu):
- `synthesis/yosys/`, `synthesis/vivado/`, `synthesis/quartus/` directories exist.
- Yosys 0.36+ is on `$PATH` (from `setup.sh` via OSS CAD Suite).
- `vivado` is on `$PATH` (from `setup.sh` via Vivado 2023.2 `settings64.sh`).
- `quartus_sh` is on `$PATH` (from `setup.sh` — `/opt/intelFPGA_lite/23.1std/quartus/bin`).

**On *.csun.edu** (Vivado, Quartus, and Yosys are NOT available):
- `synthesis/designcompiler/` directory exists.
- `dc_shell` is on `$PATH` (Synopsys Design Compiler).
- 90nm PDK at `/opt/ECE_Lib/SAED90nm_EDK_10072017/SAED90_EDK/SAED_EDK90nm`.
- 32nm PDK at `/opt/ECE_Lib/SAED32_EDK`.
- 14nm PDK at `/opt/ECE_Lib/SAED14nm_EDK_03_2025`.
- SKY130 PDK at `/tmp/pet43490/PDK/volare/sky130/versions/<hash>/sky130A`
  (SkyWater open-source PDK, per-user volare install — not under `/opt/ECE_Lib`).
  `lc_shell` must also be on `$PATH`: sky130 ships only ASCII `.lib`, and it
  needs compiling to `.db` before `dc_shell` can use it as a
  `target_library` (see the sky130 subsection below).

## Machine-Specific Environment: *.csun.edu

When running on `*.csun.edu`, the following tools are **not available**:
- Vivado / Xilinx tools
- Quartus / Intel/Altera tools
- Yosys

On this host the **only** supported synthesis tool is:
- Synopsys Design Compiler (`dc_shell` on `$PATH`)
- Plus Library Compiler (`lc_shell` on `$PATH`) — needed only for the sky130
  PDK, to pre-compile its ASCII `.lib` to `.db` (see sky130 subsection below)

`run_vendor_synth.py` must detect this environment at startup:

```python
import socket
ON_CSUN = socket.getfqdn().endswith(".csun.edu")
```

When `ON_CSUN` is `True`:
- Skip Vivado, Quartus, and Yosys synthesis.
- Run Design Compiler for SAED90, SAED32, SAED14, **and** SKY130.
- All Python code must work without activating a virtualenv — use only system Python packages.
  (The one exception is `volare`, now in `virtualenv/requirements.txt` for managing/fetching
  sky130 PDK versions by hand when needed — it is not imported by `run_vendor_synth.py` itself.)

## Responsibilities

### Design Compiler (csun.edu only, `synthesis/designcompiler/`)

#### `synthesis/designcompiler/synth.tcl`

The script supports all four PDKs via the `PDK_TARGET` environment variable (default: `saed90`):

| `PDK_TARGET` | Env var required | Library path |
|---|---|---|
| `saed90` | `SAED90_PDK` | `$SAED90_PDK/Digital_Standard_cell_Library/synopsys/models/saed90nm_max.db` |
| `saed32` | `SAED32_EDK` | `$SAED32_EDK/lib/stdcell_rvt/db_nldm/saed32rvt_ss0p95v125c.db` (RVT SS 0.95V 125°C) |
| `saed14` | `SAED14_EDK` | `$SAED14_EDK/SAED14nm_EDK_STD_RVT/liberty/nldm/base/saed14rvt_base_ss0p72v125c.db` (RVT SS 0.72V 125°C) |
| `sky130` | `SKY130_PDK` **and** `SKY130_STDLIB_DB` | `$SKY130_STDLIB_DB` — a pre-compiled `.db`, **not** derived from `SKY130_PDK` directly inside `synth.tcl` (see sky130 subsection below) |

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
SAED14_EDK = "/opt/ECE_Lib/SAED14nm_EDK_03_2025"

PDK_CONFIGS = {
    "saed90": {"label": "SAED90 (90nm)", "env_var": "SAED90_PDK", "path": SAED90_PDK},
    "saed32": {"label": "SAED32 (32nm)", "env_var": "SAED32_EDK", "path": SAED32_EDK},
    "saed14": {"label": "SAED14 (14nm)", "env_var": "SAED14_EDK", "path": SAED14_EDK},
    "sky130": {"label": "SKY130 (130nm, SkyWater open-source PDK)",
               "env_var": "SKY130_PDK", "path": build_sky130_libs.SKY130_PDK},
}
```

`run_design_compiler(synth_dir, pdk_target)`:
- Sets `PDK_TARGET=<pdk_target>` and the appropriate PDK path env var.
- For `pdk_target == "sky130"` **only**: also calls
  `build_sky130_libs.ensure_sky130_dbs(cfg["path"])` (imported from
  `IP/common/synthesis/designcompiler/`, see sky130 subsection below) and
  sets `SKY130_STDLIB_DB` to the typical-corner `.db` path it returns.
- Writes log to `designcompiler/dc_<pdk_target>_run.log`.
- Timeout: 1200 s per PDK run.

`write_dc_report(synth_dir, pdk_target, util)`:
- Writes `designcompiler/report_<pdk_target>.txt`.
- References `reports/<pdk_target>/` and `netlists/<pdk_target>/`.

CLI flags on csun.edu:
- `--dc` — run all four PDKs (default when no flags given on csun.edu).
- `--dc90` — 90nm only.
- `--dc32` — 32nm only.
- `--dc14` — 14nm only.
- `--dcsky130` — sky130 only.

### sky130 (SkyWater 130nm open-source PDK, csun.edu only)

Unlike the SAED PDKs, sky130 ships only ASCII `.lib` — no pre-compiled `.db`.
This Design Compiler build **cannot** read ASCII `.lib` directly as a
`target_library`/`link_library`: it fails with `Error: ... is not a DB file.
(DB-1)`, but critically **exits 0 anyway** and silently continues with
black-box/unmapped cells — a "PASS" result under this failure mode is bogus
(garbage cell counts, non-functional netlist). Always check the run log for
`black-box`, `unmapped components`, or `DB-1` after any sky130 run, not just
the exit code.

Also note: `dc_shell`'s own `read_lib` command fails on this host with
`Error: The read_lib command failed to run. Check the installation of
Library Compiler. (LCSH-3)` — compiling must go through the separate
`lc_shell` binary (Library Compiler), not `dc_shell`.

**This is solved once, centrally, for every IP** in
`IP/common/synthesis/designcompiler/build_sky130_libs.py` — not
re-implemented per IP:
- Compiles all three `sky130_fd_sc_hd` corners to `.db` via `lc_shell`
  (`read_lib "<ascii .lib>"` then `write_lib <libname> -output "<db path>"`
  in one batch script): `ss_100C_1v60` (worst-case), `tt_025C_1v80`
  (typical — `SKY130_SYNTH_CORNER`, used for synthesis), `ff_n40C_1v95`
  (best-case).
- Caches the compiled `.db` files in
  `IP/common/synthesis/designcompiler/sky130_lib/` (mtime-checked against
  the source `.lib`, so repeat runs across any IP skip recompiling).
- Exposes `ensure_sky130_dbs(pdk_path) -> {corner: db_path}`,
  `SKY130_PDK`, `SKY130_CORNERS`, and `SKY130_SYNTH_CORNER`.

Any IP's `run_vendor_synth.py` must import it rather than duplicate it:
```python
_IP_COMMON_PATH = os.environ.get("IP_COMMON_PATH") or str(
    Path(__file__).resolve().parent.parent.parent.parent / "common"
)
sys.path.insert(0, str(Path(_IP_COMMON_PATH) / "synthesis" / "designcompiler"))
import build_sky130_libs
```
(`IP_COMMON_PATH` is exported by `setup.sh`; the fallback derives the same
path relative to the script when it isn't set.)

`synthesis/designcompiler/synth.tcl`'s `sky130` branch reads `SKY130_STDLIB_DB`
directly as `STDLIB` — it does **not** build the library path itself from
`SKY130_PDK`, unlike the SAED branches.

`volare` (now in `virtualenv/requirements.txt`) is available for
fetching/managing future sky130 PDK versions by hand, but is not imported by
any script — the PDK install this repo points at
(`build_sky130_libs.SKY130_PDK`) was placed manually per-user on csun.edu,
not through volare's own bookkeeping (`volare ls --pdk-root <path>` returns
`[]` for it).

#### `synthesis/clean.sh`

A standalone bash script that removes all DC-generated files:
- Directories: `cksum_dir/`, `reports/`, `netlists/`, `ARCH/`, `ENTI/`, `PACK/` (DC VHDL library dirs).
- Files: `*.v`, `*.sdf`, `*.pvk`, `*.pvl`, `*.syn`, `*.mr`, `dc_saed90_run.log`, `dc_saed32_run.log`, `dc_saed14_run.log`, `dc_sky130_run.log`, `command.log`, `default.svf`, `report.txt`.
- Yosys: `yosys/work/`.
- Python: `__pycache__/`.
- **Never** removes `IP/common/synthesis/designcompiler/sky130_lib/` — that
  cache is shared across every IP, not a per-IP artifact; cleaning one IP's
  synthesis outputs must not force every other IP to recompile it.

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

- Accepts `--vivado`, `--quartus` (standard hosts); `--dc`, `--dc90`, `--dc32`, `--dc14`, `--dcsky130` (csun.edu).
- Default on standard hosts: run Vivado + Quartus.
- Default on csun.edu: run DC with all four PDKs (`--dc` behavior).
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

**On *.csun.edu:**

| Artifact | Description |
|----------|-------------|
| `synthesis/designcompiler/synth.tcl` | DC script (SAED90 + SAED32 + SAED14 + SKY130, SV + VHDL) |
| `synthesis/designcompiler/dc_saed90_run.log` | Raw DC output — 90nm run |
| `synthesis/designcompiler/dc_saed32_run.log` | Raw DC output — 32nm run |
| `synthesis/designcompiler/dc_saed14_run.log` | Raw DC output — 14nm run |
| `synthesis/designcompiler/dc_sky130_run.log` | Raw DC output — sky130 run |
| `synthesis/designcompiler/report_saed90.txt` | Human-readable DC summary — 90nm |
| `synthesis/designcompiler/report_saed32.txt` | Human-readable DC summary — 32nm |
| `synthesis/designcompiler/report_saed14.txt` | Human-readable DC summary — 14nm |
| `synthesis/designcompiler/report_sky130.txt` | Human-readable DC summary — sky130 |
| `synthesis/designcompiler/reports/saed90/` | Per-variant area + timing reports — 90nm |
| `synthesis/designcompiler/reports/saed32/` | Per-variant area + timing reports — 32nm |
| `synthesis/designcompiler/reports/saed14/` | Per-variant area + timing reports — 14nm |
| `synthesis/designcompiler/reports/sky130/` | Per-variant area + timing reports — sky130 |
| `synthesis/designcompiler/netlists/saed90/` | Netlists + SDF — 90nm |
| `synthesis/designcompiler/netlists/saed32/` | Netlists + SDF — 32nm |
| `synthesis/designcompiler/netlists/saed14/` | Netlists + SDF — 14nm |
| `synthesis/designcompiler/netlists/sky130/` | Netlists + SDF — sky130 |
| `synthesis/run_vendor_synth.py` | Python runner (host-aware; DC on csun.edu) |
| `synthesis/clean.sh` | Removes all DC-generated outputs |
| `synthesis/known_issues.md` | Documented warnings (may be empty) |
| `IP/common/synthesis/designcompiler/build_sky130_libs.py` | Shared sky130 `.lib`→`.db` compiler (all IPs) |
| `IP/common/synthesis/designcompiler/sky130_lib/` | Shared compiled sky130 `.db` cache (all IPs) |

## Quality Gate

**Standard hosts:**
- Yosys completes without errors for all SV and VHDL variants.
- Vivado exits 0; `utilization.rpt` and `timing_summary.rpt` written; WNS ≥ 0 at 100 MHz.
- Quartus exits 0; `*.map.rpt` is written.
- `synthesis/run_vendor_synth.py` exits 0 with all available tools passing.

**On *.csun.edu:**
- DC exits 0 for all SV and VHDL variants under SAED90, SAED32, SAED14, and SKY130.
- `netlists/saed90/`, `netlists/saed32/`, `netlists/saed14/`, and `netlists/sky130/` all
  populated with `.v` and `.sdf` files.
- sky130 run log contains no `black-box`, `unmapped components`, or `DB-1` — exit code
  alone does not prove the sky130 run actually mapped to real cells (see sky130 subsection).
- `synthesis/run_vendor_synth.py` exits 0 for all four PDK runs.

**All hosts:**
- `synthesis/known_issues.md` exists (even if empty) and all unresolved warnings are documented.
- All scripts run non-interactively from the command line.

## Known Tcl Pitfalls

| Tool | Wrong | Correct |
|------|-------|---------|
| DC | `read_file {claude_apb_if.sv ...}` | `analyze -format sverilog {claude_apb_if.sv ...}` — only `analyze` honors `search_path` |
| DC | `read_file {timer_ahb.vhd}` | `analyze -format vhdl {timer_ahb.vhd}` |
| DC | `set_app_var search_path "path1 path2"` | `set_app_var search_path [list path1 path2]` |
| DC | `target_library`/`link_library` pointed at sky130's ASCII `.lib` | Errors `File is not a DB file (DB-1)` but **exits 0** with black-box cells; pre-compile to `.db` via `lc_shell` first (`build_sky130_libs.py`) |
| DC | `read_lib` inside `dc_shell` to compile sky130's `.lib` | Fails `Check the installation of Library Compiler (LCSH-3)` on this host; use the separate `lc_shell` binary instead |
| Vivado | `set_property target_language SystemVerilog` | `set_property target_language Verilog` |
| Vivado | `read_xdc - << { ... }` (stdin, fails in batch) | Write XDC to a temp file, then `read_xdc <file>` |
| Vivado | `get_runs synth_1` in in-memory project | Omit — returns empty; pass `-mode out_of_context` directly to `synth_design` |
| Quartus | `package require ::quartus::misc` for `execute_module` | `package require ::quartus::flow` |
| Quartus | `execute_flow -analysis_and_synthesis` | `execute_module -tool map` |
| Quartus | `report_utilization` / `report_timing_summary` | Parse auto-generated `*.map.rpt` from Python |
