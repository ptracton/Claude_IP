---
name: Power analysis — PrimePower (PTPX) flow
description: How --power works in sim_timer.py; PTPX flow, liberty DB paths, report structure
type: project
---

Power analysis was added to `IP/system/timer/verification/tools/sim_timer.py` via the `--power` CLI flag.

## Usage

```
python sim_timer.py --power               # all PDKs, all protocols
python sim_timer.py --power --pdk saed90  # SAED90 only
python sim_timer.py --power --proto apb   # APB only
```

`--power` implies `--postsyn` — it runs the gate-level simulation first, then power analysis.

**SAED90 caveat:** SAED90 has an accepted (not fixed) timing violation that
makes its post-syn gate-level simulation functionally unreliable (reads
`X`, not real counting/timing — see
[project_timer_postsyn_sim.md](project_timer_postsyn_sim.md)). `--power`
therefore skips it: any PDK/protocol whose post-syn sim does not pass gets
`SKIP` instead of power numbers. SAED32/SAED14 are unaffected.

**First successful run: 2026-10-09** (SAED32 + SAED14, all 4 protocols,
100% SAIF annotation). Results are in the timer README's "Power Analysis"
section. Before that date the flow had never produced a report — it
reported PASS with no output because of the bugs listed under "Gotchas".

## Flow

1. **Post-syn sim** (`run_vcs_postsyn`) — generates `vcdplus.vpd` in the work dir
2. **SAIF generation** — `vcd2saif -input vcdplus.vpd -output power.saif -instance tb_timer_{proto}/u_dut`
3. **PTPX Tcl script** — auto-generated `run_power.tcl`; reads liberty DB, netlist, SDC, SAIF; calls `update_power`
4. **pt_shell** — `pt_shell -f run_power.tcl`
5. **Reports** — 5 files + console summary

## Output files (in `work/postsyn/<pdk>/<proto>/power/`)

| File | Contents |
|---|---|
| `power.saif` | Switching activity from simulation |
| `run_power.tcl` | Auto-generated PTPX script |
| `pt_shell.log` | Raw pt_shell transcript |
| `power_annotation.rpt` | `report_switching_activity -list_not_annotated` — SAIF coverage |
| `power_overall.rpt` | `report_power -unit mW` — total power by group |
| `power_hierarchy.rpt` | `report_power -hierarchy -levels 2` — per block |
| `power_top_cells.rpt` | `report_power -cell_power -leaf -nworst 10 -sort_by total_power` |
| `power_top_nets.rpt` | `report_power -net_power -leaf -nworst 10 -sort_by net_switching_power` |

## Liberty DB file paths on csun.edu (verified)

- **SAED90**: `.../Digital_Standard_cell_Library/synopsys/models/saed90nm_typ.db`
- **SAED32**: `.../lib/stdcell_rvt/db_nldm/saed32rvt_tt1p05v25c.db`
- **SAED14** (4 files): `.../liberty/nldm/{base,cg,dlvl,iso}/saed14rvt_{sublib}_tt0p8v25c.db`
  - `dlvl` uses the `_i0p8v` variant: `saed14rvt_dlvl_tt0p8v25c_i0p8v.db`
- **SKY130**: `IP/common/synthesis/designcompiler/sky130_lib/sky130_fd_sc_hd__tt_025C_1v80.db`
  — sky130 ships no `.db`; `run_power_analysis` calls
  `build_sky130_libs.ensure_sky130_dbs()` first, which compiles it with
  `lc_shell` if missing (see [reference_sky130_pdk](reference_sky130_pdk.md)).
  SKY130 netlists are synthesized at `ss_100C_1v60` but power uses tt.

## SKY130 gate-level simulation in VCS (added 2026-10-09)

Power needs a passing post-syn sim, so SKY130 power required wiring SKY130
into `run_vcs_postsyn` first. The PDK's Verilog doesn't compile in VCS as
shipped; the workarounds (no PDK files are modified) are config keys in
`POSTSYN_PDK_CONFIGS["sky130"]`:
- `cell_libs_nettype_wire`: `primitives.v` is copied into the work dir with
  `` `default_nettype none `` → `wire`. VCS reports the UDPs' non-ANSI port
  declarations as undeclared identifiers (Error-[IND]) otherwise, in both
  `-sverilog` and plain-Verilog mode.
- `cell_libs_v`: `sky130_fd_sc_hd.v` is passed with `-v`, so only cells the
  netlist uses are elaborated. `lpflow_bleeder_1`'s timing model references
  an undeclared `VPWR` (a PDK bug) and fails a full compile. UDPs are **not**
  resolved from `-v` files (Error-[CFCILFBI]), which is why `primitives.v`
  must be a normal source.
- Don't define `USE_POWER_PINS` (DC netlists have no supply pins) or
  `FUNCTIONAL` (that drops the specify blocks the SDF annotates).

Results 2026-10-09: all 4 protocols PASS post-syn and power, 100% SAIF
annotation; ~0.81 mW (APB), 94% clock-pin internal power, ~3 nW leakage.

These paths are stored in `POSTSYN_PDK_CONFIGS[pdk]["db_libs"]` in sim_timer.py. Update them if the actual paths differ.

## PTPX Tcl key commands

```tcl
set_app_var power_enable_analysis true
set_app_var power_analysis_mode averaged
read_sdc timer_apb.sdc
read_saif power.saif -strip_path tb_timer_apb/u_dut
update_power
report_power -nosplit -unit mW
report_power -nosplit -unit mW -cell_power -leaf -nworst 10 -sort_by total_power
report_power -nosplit -unit mW -net_power  -leaf -nworst 10 -sort_by net_switching_power
```

## Gotchas (PrimePower / vcd2saif Y-2026.03)

- `vcd2saif` takes `-instance`, not `-scope`, and **exits 0 on a bad option**
  without writing a file — check that the SAIF exists.
- `read_saif` has no `-scope` option; `-strip_path` alone is right.
- `pt_shell -f` **exits 0 even when the script aborts** on an error, so
  pass/fail is judged from `Error:` lines in the log plus non-empty reports.
  `Error: Library Compiler executable path is not set. (PT-063)` is printed
  at every startup and is harmless (only compiled `.db` files are read).
- `net_switching_power` is a `-sort_by` value, not a net attribute;
  `get_attribute <net> net_switching_power` fails (ATTR-1). Power attributes
  on cells are in W. Use `report_power -cell_power/-net_power` instead.
- `get_cells -hierarchical *` includes hierarchical blocks, which swamp a
  top-10 list; use `-leaf` (or `-filter is_hierarchical==false`).
- With `-unit mW`, the net report's total line still says "Watt"; the
  values are mW.

## SAIF scope

Scope is always `tb_timer_{proto}/u_dut` — the DUT instance inside the SV testbench.
`-strip_path` strips this prefix so net names match the gate-level design hierarchy.
