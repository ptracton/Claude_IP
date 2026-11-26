# Handoff — SRAM, updated 2026-11-25 (Steps 10 + 12 done on csun.edu; Step 10 committed 7ba3fa7)

## Step 12 power (2026-11-25, uncommitted) — read first
- `sim_sram.py --power` (run_power / run_power_one / power_libs) + SAIF capture in
  `sram_tb_postsyn_body.svh` (`+saif`, VCS toggle tasks per netlist). Typical-corner libs incl.
  macros; DC's WLM applied by name (the .sdc's SS-library line dropped).
- 36/36 PASS (4 buses x SAED32/14/SKY130 x base/opts/dp, SV netlists), 100 % SAIF; SAED90 SKIP.
  SAED14 9.0 / 11.3 / 19.9 mW, SKY130 11.2-11.8 / 38.6-39.2 / 53.0-53.9 mW (base / opts / dp);
  macros > 95 %, from free-running macro clocks. SAED32 macro power invalid (vendor liberty
  negative input-pin internal_power) — logic only reported. README "Power Analysis",
  known_issues.md "Power analysis". Open follow-up: per-bank macro clock gating (not requested).

## Step 10 synthesis (2026-11-24/25, uncommitted) — read first
Full log and every user decision: `project_sram_plan.md` §18 (18.1-18.6).
- **DC** `synthesis/run_vendor_synth.py --dc` + `designcompiler/synth.tcl`: base / opts / dp x 4 buses
  x SV/VHDL = 24 netlists per PDK (96). SAED WLM picked from logic area; 0.2 ns setup margin
  (`set_clock_uncertainty` after `write_sdc`). SAED32 links a patched SRAMLP liberty
  (`IP/common/synthesis/designcompiler/build_saed32_sram_libs.py`, cache not committed).
  SAED32/14/SKY130 24/24 MET; SAED90 2/24 — accepted (user 2026-11-25), `synthesis/known_issues.md`.
- **RTL changes for DC (user approved):** SV untyped `INIT_FILE`; VHDL rewritten to the DC
  VHDL-2008 subset (see `VHDL2008CodingStyle.md` "Design Compiler subset"); ECC RMW registered (s2),
  RL2 register before the decoder (`sram_port` SV/VHDL, `sram_model` latency per entry).
- **Re-verified on that RTL:** Step 4 80/80, UVM 1440/1440, mutants 9/9, formal 26/26 (new lemmas
  `sram_leaf_fv a_word_ok`, `sram_port_fv`; core_ecc a_err_rule proven again), SpyGlass 24/24.
  `regression_sram.py --collect` was NOT regenerated.
- **STA** `synthesis/run_primetime_sta.py` + `primetime/sta.tcl`: 6 targets x 24, setup + hold, DC's
  per-netlist WLM. All PASS except SAED90 (accepted).
- **Gate level** `sim_sram.py --postsyn [--no-sdf]` + `testbench/sram_tb_postsyn_body.svh`: 24/24
  PASS, SAED90 8 KNOWN (pass with --no-sdf). Vendor model bugs fixed in generated copies:
  SAED90 SSR flops (`IP/common/verification/tools/pdk_cell_models.py`), SKY130 OpenRAM read delay
  (`pdk_sram_models.py gate_level=True`).
- **UPF** `design/upf/` + `verification/tools/lp_sram.py` (VC LP): 12/12 PASS.
- **Power cycle counts** checked vs SAED32-LP databook: valid to 180 MHz; kept (user).
- Open: Vivado / Quartus / Yosys flows (scripts written, standard host); timer and bus_matrix
  postsyn still compile the vendor SAED90 `saed90nm.v` (SSR-flop bug not checked there); Step 11
  cleanup / tag open (Step 12 power done since, see the top of this file). /tmp aging deleted 14 bus_matrix files again
  (restored from HEAD 2026-11-25).

## Step 9 firmware (2026-11-23 late, uncommitted) — read first
- `IP/system/sram/firmware/`: sram.h, src/sram_memtest.c, src/sram_sideband.c, src/sram_access.h,
  CMakeLists.txt, build.sh, examples/sram_example.c, test/ (fault model + test_sram.c). Plan §17.
- Runner `verification/tools/fw_sram.py` -> `verification/firmware/fw_results.log`: host 124/124,
  mutants 22/22 killed, compile 3/3, cross SKIP x2 (no compilers). Regression step `firmware`
  added; `--collect` 2749/2749. README "Firmware" written.
- Open: cross build + code size — csun `/tmp/pet43490/CrossCompilers` is gone (/tmp aging); either
  reinstall outside /tmp (setup.sh points at /tmp) or run `fw_sram.py` on a standard host.
  Next plan step: **Step 10 synthesis**.

## Step 8 lint (2026-11-23, uncommitted) — read first
- `lint_sram.py` SpyGlass: 20 lint + 4 CDC configs, **24/24 PASS**; waivers `verification/lint/waivers.md`
  (65 RTL pragma blocks); README "Lint Results"; plan §16. RTL touched: pragmas (comments) in 26 SV
  files + removal of dead `stored_overall` (sram_ecc_dec.sv). Sims re-run: 8/8 SV GENERIC VCS+Xcelium PASS.
- Regression `--collect` 2599/2599. Coverage tables are from before the edit (sram_ecc_dec may move
  slightly on the next `--coverage` run).
- CDC filter tightened 20:4x: only the reviewed info rules in `_CDC_INFO_RULES` (lint_sram.py) are
  dropped (was every CDC info row); waivers.md "CDC report filter". Full re-run 20:45: 24/24 PASS,
  0 findings, same filtered counts; structural CDC checks (Ac_unsync/conv/glitch, Ar_*) all 0.
- Open: standard-host lint (Verilator/GHDL) written but not run. Next plan step: **Step 9 firmware**.


## Step 7 (2026-11-23, uncommitted)
- `verification/tools/regression_sram.py` (+ `verification/regression/run_regression.sh`),
  README "Regression", plan §15. `--collect` on csun: 2598/2599, the only FAIL is lint (Step 8
  skeleton, by design). Full non-collect run not done (~4-5 h).
- Next plan step: **Step 8 lint** (SpyGlass on csun incl. CDC on the separate-clock dual port;
  Verilator/VHDL lint on a standard host). `verification/lint/spyglass/` already exists.
- Scratch in `verification/work/`: run_full_recheck.sh, run_uvm_matrix.sh, full_recheck.done,
  step4_regression.log, uvm_matrix_20261121/ (ignored, removable).


## 2026-11-23 session (read first)
- **Full UVM matrix of 2026-11-21: 1352/1440 PASS** (copy: `verification/work/uvm_matrix_20261121/`).
  Two bench bugs, no RTL bug:
  1. AXI `err_irq` count (all AXI power/stress, saed14 dp): `err_irq_q` pulses one cycle after
     the core response, but the scoreboard merged pulses by bus completion (t_end); with
     BREADY/RREADY stalls R and B complete on one edge after two core responses (or the
     reverse). Fix: monitor fills new item field `t_rsp` (AXI: edge BVALID/RVALID rose, a fixed
     delay after the core response; other buses = t_end), `irq_at(it.t_rsp)`.
  2. Xcelium SAED14 dp power (ahb/apb/wb, 6 runs): `sram_model` mismatches. With one clock,
     `p_model` (side band: wake fill) and `p_model_b` (B grant prediction) run on the same
     edge in simulator order; Xcelium ran B first, so the wake zero-fill erased a B write.
     Fix: `sram_model` parameter `COMMON_CLK`; side band moved into `side_band()` (once per
     edge), called by port B first when COMMON_CLK. Set in the UVM tb (`CC`) and the Step 4
     bench (dp0 `DP0_CC`, dp1/dp2/dp3 1).
  Spot re-runs: vcs axi4l sv generic base 5/5, vcs axi4l sv saed14 dp 6/6, xcelium apb sv
  saed14 dp 6/6 PASS.
- **`claude_wb_mem_if` 89.9 % closed:** the UVM WB driver now drives stray STB/WE/ADR with CYC
  low on ~1/4 of the idle cycles before an item (B4: must be ignored). WB SV generic base:
  module no longer weakest (sram_clr 90.19). Other uncovered conditions are unreachable here
  (gnt without req, err/rvalid without pending).
- **Running detached:** `verification/work/run_full_recheck.sh` = full UVM matrix
  (`uvm_full_matrix.log`, `work/uvm/results.log`) then the Step 4 regression
  (`work/step4_regression.log`); writes `work/full_recheck.done` at the end.
  **UVM matrix done 17:1x: 1440/1440 PASS**; functional 100 % merged per cfg (base/full/dp);
  weakest module of any build 90.19 (sram_clr), all >= 90.
  **Step 4 regression 17:26: 80/80 PASS**, per-run coverage identical to the README tables.
  README UVM section rewritten for the full matrix (+ the three fixes); Step 4 coverage note
  dated. **Step 6 open:** none from the matrix. Remaining: plan §14 wrap-up / user review, commit
  (user commits). `verification/work/uvm_matrix_20261121/` holds the failing first matrix (scratch;
  `cleanup.sh` removes work/).

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
- **Committed by the user: 5f39b32 "SRAM UVM work"** (includes the scoreboard irq-edge fix:
  err_irq_o is the OR of both ports, same-edge errors are one pulse; found on SAED14 dp).
- **Full UVM matrix running detached** (setsid, survives the session): started 2026-11-21 ~14:45,
  `verification/work/run_uvm_matrix.sh`, log `verification/work/uvm_full_matrix.log`, results
  `verification/work/uvm/results.log` + `work/uvm/coverage/{per_build,functional}.txt`
  (240 builds, 1440 runs, ~1.5-2 h). Next: read those, update the README UVM section (now
  GENERIC only), close the `claude_wb_mem_if` 89.9 % gap (WB SV base/dp).
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
4. ~~Next plan step: Step 6 (UVM)~~ — superseded; current state at the top of this file.
