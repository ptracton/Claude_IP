# Handoff — SRAM Step 4 (directed tests), updated 2026-11-07

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
- Coverage (VCS): every module of every run >= 90 (SV min 92.95, VHDL min 92.98 as of 2026-11-07). Merged SV
  95.84 (`coverage/summary.txt`), VHDL 98.04 (`coverage/vhdl/summary.txt`, toggle = best run).

## Git state
HEAD `b6b2e17` ("SRAM VHDL testing and verification framework") has the SV bench, the VHDL
flow and the coverage work. The 2026-11-07 follow-ups below are **uncommitted**. Commit only
when asked.

## Step 4 follow-ups (2026-11-07, uncommitted)
- **bus_matrix AHB HSIZE formal (old open item 1):** `bus_matrix_ahb_fv.sv` + bind take
  `M_HSIZE`/`S_HSIZE`: master-side assumptions (<= bus size, aligned, held), slave-side
  asserts (`a_hsize_max/aligned/hold/strb`), `a_e2e_write` uses the master's HWSTRB limited
  to its HSIZE lanes, new `a_e2e_rd_lanes`, covers byte / half / sparse. New waiver:
  `a_hsize_hold` vacuous (initiator address phase never stalled).
  **RTL bug fixed** (found writing the harness): `bus_matrix_ahb_ini` (SV + VHDL) sent a
  bus-size HSIZE with an unaligned HADDR for sparse sub-word strobes; HADDR is now aligned
  to HSIZE. VCF AHB SV+VHDL PASS (88/96 proven + 8 waived vacuous, 70/78 covers + 8 waived).
  bus_matrix AHB sims 4/4, DC 4 PDKs PASS (AHB 96 FFs, now MET on SAED90), PT 6 targets PASS
  (new: SAED14 ahb_vhdl 280 min_capacitance on unloaded output-port drivers, documented as
  open), postsyn + PrimePower 4 PDKs PASS (AHB +8-14 %). bus_matrix README + formal README
  updated. Yosys/Vivado/Quartus AHB row is stale (standard host).
- **AXI pipelined master (old open item 2):** `sram_tb_axi4l_master.sv` pipelined mode
  (`set_pipelined`, `m_pipe` helper; in-order issue, R/W overlap, same-word program order).
  `test_pipeline` AXI section: interleaved 16w+16r 66 vs 128 cycles (RL1), 98 vs 160 (RL2);
  same-type streams gain nothing because `claude_axi4l_mem_if` frees its slot on B/R.
  SRAM README throughput table + bugs table updated.
- **Full SRAM regression re-run** (`--sim all --proto all --lang all --tech all --coverage
  --jobs 2`): **80/80 PASS**, SV = VHDL comparison counts (AXI now 118k/117k/91k). Coverage:
  merged SV 95.84, VHDL 98.04; weakest module of any run still 92.95 (SV) / 92.98 (VHDL);
  only `claude_axi4l_mem_if` moved (SV 96.64, VHDL 97.53). Throughput rows identical in all
  20 AXI runs. README results/coverage tables updated.

## Changes in b6b2e17 (2026-10-18/19, committed)
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
1. Xcelium coverage needs IMC (not on csun.edu) — not needed (user, 2026-11-07).
2. XILINX / ALTERA leaves are not simulated here; FPGA tools are on another PC (user,
   2026-11-07). Re-run Yosys/Vivado/Quartus for bus_matrix AHB there too.
3. Optional: deeper AW/W/AR slots in `claude_axi4l_mem_if` would let same-type AXI streams
   pipeline (not requested).
4. Next plan step: Step 5 (formal), see plan §5.
