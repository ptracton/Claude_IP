---
name: Timer IP — post-synthesis simulation setup
description: How post-syn simulation is configured in sim_timer.py; PDK paths and SDF annotation details
type: project
---

Post-synthesis simulation was added to `IP/system/timer/verification/tools/sim_timer.py` via `--postsyn` and `--pdk` CLI flags.

**PDK cell library Verilog model paths on ecs-vdi:**
- SAED90: `/opt/ECE_Lib/SAED90nm_EDK_10072017/SAED90_EDK/SAED_EDK90nm/Digital_Standard_cell_Library/verilog/saed90nm.v`
- SAED32: `/opt/ECE_Lib/SAED32_EDK/lib/stdcell_rvt/verilog/saed32nm.v`
- SAED14 (4 files): `SAED14nm_EDK_STD_RVT/verilog/{base,cg,dlvl,iso}/saed14rvt_*.v` under `/opt/ECE_Lib/SAED14nm_EDK_03_2025/`

**DC netlist/SDF location:** `IP/system/timer/synthesis/designcompiler/netlists/<pdk>/timer_<proto>.{v,sdf}`

**SDF annotation scope:** `tb_timer_{proto}.u_dut` — `u_dut` is the DUT instance name in all testbenches.

**VCS flags for post-syn:** `-sdf typ:{scope}:{sdf_file}` at compile time; `+notimingcheck +neg_tchk` to run functional verification without PVT-matched clock.

**Why:** Always uses SV testbench (not `_vhdl` variant) and Verilog netlist regardless of RTL source language.

**How to apply:** Run with `python sim_timer.py --postsyn` (all PDKs) or `--postsyn --pdk saed90` for a specific PDK. Only works on ecs-vdi where PDK libs are installed.
