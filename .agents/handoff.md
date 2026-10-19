# Handoff — SRAM Step 4 (directed tests), updated 2026-10-19

The plan and full log are in `.agents/project_sram_plan.md` §13 (request, bench architecture,
tests, §13.7 logs). The IP README "Simulation Results" holds the current results and coverage.
This file records where things stand.

## Status
Step 4 is **done** for both languages:
- One SystemVerilog system bench (`verification/testbench/tb_sram_<proto>.sv` + shared
  `sram_tb_body.svh`, BFMs, 12 tests in `verification/tests/`, one `sram_model` per SRAM).
- `--lang vhdl` runs the same bench around the VHDL tops and the VHDL bus_matrix (mixed
  language, `+define+VHDL_DUT`).
- `sim_sram.py --sim all --proto all --lang all --tech all --coverage --jobs 10`: **80/80 PASS**
  (4 buses x 2 languages x 5 technologies x VCS/Xcelium), identical comparison counts SV vs VHDL.
- Coverage (VCS): every module of every run >= 90 (SV min 92.95, VHDL min 93.00). Merged SV
  95.78 (`coverage/summary.txt`), VHDL 97.93 (`coverage/vhdl/summary.txt`, toggle = best run).

## Git state
HEAD `8b218db` ("SRAM Testing looks good") has the SV bench and coverage work. The VHDL work
below is **uncommitted**. Commit only when asked.

## Uncommitted changes (2026-10-18/19)
- **bus_matrix:** VHDL AHB HSIZE mirror (`bus_matrix_ahb{,_tgt,_ini}.vhd`, VHDL tb master
  drives HSIZE); README documents HSIZE. bus_matrix AHB sims SV+VHDL on VCS+Xcelium PASS.
- **sram RTL (VHDL, comments only):** `--synopsys coverage_off/on` around elaboration-time
  asserts (core, array, macro leaves; also `IP/common` `claude_sync.vhd`) and the generic
  leaves' INIT_FILE preload.
- **sram_model:** `READ_LATENCY` / `READ_LATENCY_B` parameters; every response's latency is
  checked.
- **claude_backdoor.c:** VHPI entry points `claude_bd_vget/vput` (`-DCLAUDE_BD_VHPI`;
  VCS also `-DCLAUDE_BD_VHPI_ROOTS`).
- **Bench:** `TB_TECH_*` constants in `sram_tb_pkg` (no `sram_pkg` import), `BM_PW`/`BM_SW`
  generic widths, `DP_B` macro (port-B options explicit on VCS + VHDL), BIST fault via
  `$hdl_xmr_force` on VCS + VHDL, VHDL backdoor paths, `bd_flip` waits for the deposit,
  dp2.B rl = 2 (the table said 1).
- **sim_sram.py:** VHDL flows (VCS vlogan/vhdlan/vlogan/vcs; Xcelium xrun `-v200x
  -namemap_mixgen`), VHDL coverage (SV twin run, `vhdl_const.el`, module toggle recompute,
  separate SV/VHDL merges, `+tree`/`-module` for the generate-nested direct SRAMs).
- **Docs:** sram README (results, coverage, tool issues, getting started), spec (port-B
  default caveat), `.agents/Claude_IP.md` ("VHDL DUTs", backdoor), `directed_tests.md`
  (shared-bench alternative, coverage target), `reference_vcs_tools.md`, memory.

## Tool findings (full list: `.agents/Claude_IP.md` "VHDL DUTs")
- VCS takes a dependent VHDL generic default (`READ_LATENCY_B := READ_LATENCY`) from the other
  generic's *default* when SV instantiates the VHDL top; pure VHDL and Xcelium are correct.
- Xcelium binds VHDL generic maps to Verilog parameters by position unless `-namemap_mixgen`.
- VCS: no SV `force` of a VHDL bit-select; `$hdl_xmr_force` works. VPI cannot read VHDL
  storage; VHPI can.
- VCS does not constant-filter VHDL toggle coverage; urg ignores INSTANCE exclusions in its
  module list and cannot carry them through a flex merge.

## How to run
`source IP/system/sram/setup.sh`, then
`python3 IP/system/sram/verification/tools/sim_sram.py [--sim vcs|xcelium|all]
[--proto ahb|apb|axi4l|wb|all] [--lang sv|vhdl|all] [--tech generic|saed90|saed32|saed14|sky130|all]
[--test <name>] [--coverage] [--waves] [--jobs N]`.
Logs: `verification/work/<sim>/<proto>_<lang>_<tech>/`; summary `verification/work/results.log`;
coverage `verification/work/coverage/`. `cleanup.sh` removes all of it.

## Open items
1. bus_matrix AHB VC Formal harness needs `M_HSIZE`; re-run its proofs. Its DC/STA/power
   results predate the HSIZE change.
2. AXI throughput: the bench's AXI4-Lite master runs one transaction at a time; an
   outstanding-transaction BFM would show pipelined throughput.
3. Xcelium coverage needs IMC (not on csun.edu).
4. XILINX / ALTERA leaves are not simulated (no vendor libraries on csun.edu).
5. Next plan step: Step 5 (formal), see plan §6.
