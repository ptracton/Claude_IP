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

## Flow

1. **Post-syn sim** (`run_vcs_postsyn`) — generates `vcdplus.vpd` in the work dir
2. **SAIF generation** — `vcd2saif -input vcdplus.vpd -output power.saif -scope tb_timer_{proto}/u_dut`
3. **PTPX Tcl script** — auto-generated `run_power.tcl`; reads liberty DB, netlist, SAIF; calls `update_power`
4. **pt_shell** — `pt_shell -f run_power.tcl`
5. **Reports** — 3 files + console summary

## Output files (in `work/postsyn/<pdk>/<proto>/power/`)

| File | Contents |
|---|---|
| `power.saif` | Switching activity from simulation |
| `run_power.tcl` | Auto-generated PTPX script |
| `pt_shell.log` | Raw pt_shell transcript |
| `power_overall.rpt` | `report_power -nosplit` — total power by group |
| `power_top_cells.rpt` | Top 10 instances sorted by total power |
| `power_top_nets.rpt` | Top 10 nets sorted by switching power |

## Liberty DB file paths on ecs-vdi (verified)

- **SAED90**: `.../Digital_Standard_cell_Library/synopsys/models/saed90nm_typ.db`
- **SAED32**: `.../lib/stdcell_rvt/db_nldm/saed32rvt_tt1p05v25c.db`
- **SAED14** (4 files): `.../liberty/nldm/{base,cg,dlvl,iso}/saed14rvt_{sublib}_tt0p8v25c.db`
  - `dlvl` uses the `_i0p8v` variant: `saed14rvt_dlvl_tt0p8v25c_i0p8v.db`

These paths are stored in `POSTSYN_PDK_CONFIGS[pdk]["db_libs"]` in sim_timer.py. Update them if the actual paths differ.

## PTPX Tcl key commands

```tcl
set_app_var power_enable_analysis true
set_app_var power_analysis_mode averaged
read_saif power.saif -scope tb_timer_apb/u_dut -strip_path tb_timer_apb/u_dut
update_power
report_power -nosplit
sort_collection -descending [get_cells -hierarchical *] total_power
sort_collection -descending [get_nets -hierarchical *] net_switching_power
```

## SAIF scope

Scope is always `tb_timer_{proto}/u_dut` — the DUT instance inside the SV testbench.
`-strip_path` strips this prefix so net names match the gate-level design hierarchy.
