# Handoff — SRAM, updated 2026-11-21 (Step 6 UVM in progress, uncommitted)

## 2026-11-21 session (read first)
- **/tmp aging:** the repo is in /tmp; systemd-tmpfiles deletes files idle > 10 days. 186 tracked
  files were gone at session start and were restored from HEAD. Check `git status` for ` D` first.
- **Step 4 re-run on csun (after the Step 5 RTL edits): 80/80 PASS** after three fixes (plan §13.7
  last entries): VHDL `COVER` -> `COVER_C` and an `unsigned` reduction in `sram_clr.vhd` (Xcelium
  parse; no functional change), `test_clear` busy bound, `test_reset_busy` R3 waits for the
  wake-up clear. **Open:** `sram_ecc_dec` SV scores 75.7 in the PDK runs (target 90): the
  Verilator-salvage ECC rewrite has one condition per data bit; only GENERIC (backdoor) makes
  single errors beyond bits 0/1. Options: (a) Step 4 bench gets the UVM read-path stuck-bit knob
  (sweep every data bit on s32e/s64), (b) exclude those conditions (justified by the exhaustive
  SECDED sweep). **User chose (a), 2026-11-21:** done — `RD_FAULT(U, I, MW)` in
  `sram_tb_body.svh` (any stored bit, either value; s32e/s64/s24/dp1/dp0), `test_ecc` sweeps
  every stored bit (single errors) and, after an injected bit-0 error, every data bit (double
  errors; model told via `sram_model.set_stuck`). Spot checks PASS (VCS SV SAED32, VCS VHDL
  SKY130, Xcelium VHDL SAED14). Full regression re-run pending. Verilator not re-run (standard
  host; uses the native per-bit force).
- **Final Step 4 regression 2026-11-21: 80/80 PASS**, weakest module SV 92.95 / VHDL 92.99,
  `sram_ecc_dec` SV >= 94.32 in every run; README tables regenerated.
- **UVM open:** `claude_wb_mem_if` code coverage 89.89 / 89.93 in the WB SV dp / base UVM builds
  (target 90). Full 240-build UVM matrix running (`--jobs 1`), README UVM section has GENERIC
  results only; update when it finishes.
- **Commits:** the user commits (said 2026-11-21 "I will commit today when ready").
- **Step 6 (UVM):** bench `verification/tasks/uvm/` (plan §14), runner `uvm_sram.py`, mutation
  runner `uvm_mutants.py` (9/9 killed). `sram_model` changed (B_MODE_GUARD, set_stuck; both
  inert by default) -> Step 4 regression must be re-run once more before committing.


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

## Step 5 — formal (VC Formal), DONE 2026-11-15 (uncommitted on top of 289e342)
Runner: `formal_sram.py [--job <j>|all] [--lang sv|vhdl|all] [--jobs N<=3] [--trace] [--max-time T]`
(13 jobs x SV/VHDL; needs `source IP/system/sram/setup.sh`). Final full run 23:41: **26/26 PASS**,
`verification/formal/vcf/results.log` (waived inconclusives now listed with depth). Everything is
documented in `verification/formal/vcf/README.md` (jobs, properties, waivers, findings 1-10) and
the top-level README "Formal Verification Results". Traces: `fsdbreport` in
`/opt/synopsys/vc_formal/Y-2026.03-SP1/verdi/bin`. Never `pkill -f` a pattern that also appears in
your own shell command (kills the shell, exit 144).

Changes in this step (all uncommitted):
- **RTL (SV + VHDL):** `sram_clr` init_q (user approved); `sram_core` a_yield (port A yields a
  same-word conflict for one turn after B was held off); VHDL `sram_ecc_enc/dec` position tables.
- **Checkers:** `sram_core_fv` (a_eng_exclusive uses bist_active, self-holding sym bytes),
  new `sram_leaf_fv` (ECC lane lemma, bound only for single port via `SRAM_FV_LEAF_BIND`).
- **Runner / shared:** `-gfile` VHDL generics; jobs core_ecc and dp_sync_wide_b A16/B32;
  `claude_vcf.py` job-scoped waivers, `assume_proven` (`FV_ASSUME_PROVEN` ->
  `fml_enable_assume_proof`), report row regex fix (`inconclusive(depth=N)`), puts-line skip.
- **Waivers:** bounded inconclusive data/err (user decision "accept bounded"), dp_sync RMW
  covers uncoverable, c_rvalid_wait.
Open: csun re-runs after the RTL edits (VCS/Xcelium regression + coverage, SpyGlass, DC);
timer/bus_matrix formal could be re-run once to confirm the shared-driver regex change (it only
affects inconclusive rows). Commit when the user asks.

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

## SRAM on Verilator (2026-11-13, salvage, uncommitted)
`sim_sram.py --sim verilator --proto all`: 4/4 PASS (GENERIC, SV tops), counts equal to VCS.
SV ECC enc/dec rewritten with elaboration-time position tables (was OOM in Verilator; checked
equal to `ecc_data_pos` + SECDED sweep). Backdoor C handles Verilator (`TOP.` root, `[N]`).
Builds capped at 8 GB (systemd scope). Details: plan §13.7 last entry, README "Results
(Verilator)". **Re-run on csun:** sram VCS/Xcelium + coverage, SpyGlass, DC (ECC RTL edit,
backdoor change). Next standard-host flows not yet done: Icarus/xsim/ModelSim/GHDL for the
sram bench (`TB_NO_BACKDOOR` hook exists), XILINX/ALTERA leaves, Yosys/Vivado/Quartus.

## bus_matrix standard-host refresh (2026-11-13, uncommitted)
All bus_matrix flows pass on salvage (regression 151/151, Yosys/Vivado/Quartus SV+VHDL 8/8 each,
ModelSim/Vivado GUI scripts SV+VHDL). Small AHB RTL edits (SV + VHDL) for Yosys/Quartus; new
VHDL synth/GUI scripts. Details: `.agents/project_bus_matrix_upgrade.md` (last entry). The csun
flows (VCS/Xcelium, VCF, SpyGlass, DC/PT) need a re-run for those RTL edits.

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
4. Next plan step: Step 6 (UVM), see plan §5.
