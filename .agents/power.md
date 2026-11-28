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

## Gate-level models for SAED90 / SKY130 (2026-11-25)
Gate-level runs that feed PrimePower should compile the corrected vendor models: SAED90
`saed90nm.v` from `IP/common/verification/tools/pdk_cell_models.py` (DFFSSR/SDFFSSR set-priority
fix) and, for SRAM macros, `pdk_sram_models.model_files(pdk, dir, gate_level=True)`. The timer and
bus_matrix flows still compile the vendor `saed90nm.v` (not re-checked for the SSR cells).

## IPs with several netlists in one gate-level run / SRAM macros (sram, 2026-11-25)
- One bench simulating several netlists: write a backward SAIF per instance from VCS instead of a
  VPD + vcd2saif (`$set_gate_level_monitoring("on"); $set_toggle_region(u_a, u_b);` at time 0,
  `$toggle_start` after reset, `$toggle_stop; $toggle_report("a.saif", 1.0e-9, u_a);` at the end,
  behind a `+saif` plusarg). PrimePower then uses `read_saif <f> -strip_path tb/u_a`. 100 % of nets
  annotated on every sram run; no multi-GB VPDs.
- DC's `.sdc` names the synthesis-corner library on `set_wire_load_model -library ...`: with
  typical-corner libraries that is SEL-005 and no wire load. Drop the line and apply DC's model by
  name (`run_primetime_sta.dc_wire_load`).
- Link the macro `.db` files at the typical corner too (SAED90 `SRAM*_typ.db`, SAED14
  `saed14sram_tt0p8v25c.db`, SAED32 patched `tt1p05v25c_i1p05v`, SKY130 TT).
- Check the power groups for **negative** values: the SAED32-LP SRAM liberty has negative input-pin
  internal power (vendor data); report logic and macro power separately and flag a negative macro
  share instead of adding it up. Require >= 99 % SAIF annotation.
- Macro liberties charge clock energy on every clock edge, selected or not: with free-running macro
  clocks the macros are > 95 % of the total even when idle (sram finding; clock gating is the fix).
- Runner: `IP/system/sram/verification/tools/sim_sram.py --power` (`run_power`, `run_power_one`,
  `power_libs`).


## Clock- and power-gated IP (new IP, user 2026-11-27)

Rules in `.agents/IP_SPEC_sideband.md`. For every new IP:

- **Clock-gating saving:** run power twice on the same stimulus, netlist synthesized with
  `CLK_GATE_EN` = 1 and with level-1 gating disabled (`-gate_clock` off, `CLK_GATE_EN` = 0),
  and report both and the difference per PDK in the README "Power Analysis" table. Use a
  stimulus with realistic idle periods (the IP's spec names it), not only full activity.
- **Idle power:** one more run with the IP idle (`idle_o` = 1) for at least 1000 cycles, to
  show the leakage-plus-clock-tree floor that the power manager would remove by gating.
- **Power-gated IP (`PWR_GATE` = 1):** the gate-level simulation is UPF-aware (VCS NLP with
  the IP's UPF), runs a power-down / power-up cycle through the Q-channel, and power is
  reported per power domain, including the switched-off state.
- **Gotcha:** the SAIF must include the clock-gate cells' enable activity; annotate at the
  `u_dut` scope as for the timer and check the annotation percentage stays at 100 %.
