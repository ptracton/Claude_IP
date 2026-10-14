---
name: bus_matrix upgrade to the timer's Synopsys / SKY130 flow (started 2026-10-09)
description: Plan, user decisions, RTL redesign notes and progress log for bringing IP/interface/bus_matrix up to the timer's infrastructure
type: project
---

## User decisions (2026-10-09)
1. Add an APB4 variant (`bus_matrix_apb`), SV + VHDL.
2. Synthesize a real address map; the RTL defaults ARE that map, so DC, PrimeTime,
   gate-level sim and power all use the parameter defaults (a netlist cannot be
   re-parameterized).
3. Remove the committed scratch files `verification/formal/transcript` and `xvlog.pb`.
4. Testbench masters use the shared BFMs in `IP/common/verification/tasks/`.

## Default configuration (real address map)
NUM_MASTERS=2 (M0 = CPU, M1 = DMA), NUM_SLAVES=4, ROUND ROBIN (changed from fixed
priority 2026-10-09: formal showed a fixed-priority CPU issuing back-to-back AHB
transfers starves the DMA forever, so the master-port response bound is unprovable;
fixed priority is still supported and proven on the stand-alone arbiter harness).

| Slave | Region | Base | Mask | Size |
|---|---|---|---|---|
| S0 | Boot ROM    | 0x0000_0000 | 0xFFFF_0000 | 64 KB |
| S1 | SRAM        | 0x2000_0000 | 0xFFFE_0000 | 128 KB |
| S2 | Peripherals | 0x4000_0000 | 0xFFFF_0000 | 64 KB |
| S3 | External    | 0x6000_0000 | 0xF000_0000 | 256 MB |

Anything else -> decode error.

## Why the RTL is being redesigned (found 2026-10-09 by reading the RTL)
The original wrappers passed their own non-standard TB masters/slaves but break
the protocols:
- AXI: decode error on a read -> mst_gnt without mst_rvalid -> read hangs forever;
  BRESP always OKAY; S_AWVALID/S_WVALID drop on grant release regardless of
  READY and stay high after the handshake (duplicate writes); slave RRESP/BRESP ignored.
- AHB: slave-side data phase gets HWDATA=0 (grant released at end of address
  phase); single-cycle HRESP (spec needs two cycles); back-to-back master
  address phases dropped; slave HRESP ignored.
- Wishbone: slave ERR ignored.
- Arbiter: fixed-priority mode can switch grant mid-transaction (valid_trx only
  froze round-robin).

New architecture:
- Core: per-slave arbiter locks a one-hot grant from grant to `slv_done`; grant
  picked only when the slave is free. Decode error -> registered one-cycle
  `mst_done` + `mst_err`.
- Internal handshake: master adapter holds `mst_req` + fields until a one-cycle
  `mst_done` (with `mst_rdata`, `mst_err`). Slave adapter runs exactly one bus
  transaction per grant and returns a one-cycle `slv_done` (+ rdata, err).
- Protocol adapters are proper slaves (master ports) and masters (slave ports),
  checked with the shared claude_<proto>_fv (MASTER_IS_ENV=1 on M ports, 0 on S ports).
- Wishbone cycle abort (dropping CYC/STB before ACK/ERR) is not supported.
- TB slaves = shared claude_<proto>_if bridge + bus_matrix_tb_mem.

## Progress log
- 2026-10-09 baseline: old RTL passes 12/12 VCS + Xcelium (3 protos x SV/VHDL).
- 2026-10-09 RTL redesigned (SV + VHDL): bus_matrix_pkg (default map), arb, core,
  per-port adapters bus_matrix_<proto>_tgt/_ini (core_* handshake ports; VHDL is
  case-insensitive so WE/we would clash), tops for ahb/apb/axi4l/wb. AXI renamed axi4l.
- Shared BFMs (IP/common/verification/tasks/tasks_*.sv) made handshake-correct with
  `CLAUDE_BFM_ADDR_W (default 12) and bfm_err; timer still 16/16 VCS+Xcelium.
- New SV TB (shared BFM wrappers + claude_*_if + bus_matrix_tb_mem) and VHDL TB
  (tb master entities with cmd toggle handshake); 82 checks per TB.
- sim_bus_matrix.py ported from sim_timer.py: 16/16 PASS (VCS+Xcelium x 4 protos x SV/VHDL).
- VC Formal: claude_vcf.VcfJob gained clock/reset overrides. Checkers: arb_fv, core_fv,
  per-proto top fv (shared protocol checkers on every port + end-to-end write/region).
  VHDL generics are NOT visible to an SV bind (NUM_MASTERS arrives as 0), so binds use
  bus_matrix_fv_cfg.svh generated from bus_matrix_pkg.sv by formal_bus_matrix.py.

## STATUS SNAPSHOT — 2026-10-09 (work paused here; nothing committed)

### Done and verified
- RTL redesign SV + VHDL (see above). Default ARB_MODE = round robin.
- Directed sims: `sim_bus_matrix.py --sim all --proto all --lang all` → 16/16 PASS
  (VCS + Xcelium, 4 protocols x SV/VHDL, 82 checks each).
- Shared BFMs updated; timer re-run 16/16 PASS on VCS + Xcelium (Icarus NOT re-run:
  no Icarus on csun; tasks avoid do-while for Icarus).
- VC Formal (SV only so far): arb harness PASS 17/17; apb_sv PASS 88/88; ahb_sv PASS
  72/76 (+justified waivers); wb_sv all 72 asserts proven (c_back2back waived after run).
  axi4l_sv with M_WAIT=64 was still running in background task bpecz4g0c when paused.
  VHDL jobs in that run FAILED only because binds used VHDL generics — already fixed
  (generated bus_matrix_fv_cfg.svh + literal arb-harness binds); must be re-run.
- DC SKY130 (`run_vendor_synth.py --dcsky130`): all 8 variants MET (WNS +0.15..+0.72 ns,
  3 ns I/O delays). report_sky130.txt written. DC also writes filenames*.log (in clean.sh).
- Checked: timer synth.tcl does NOT mix SV/VHDL units (DC elaborated timer SV from .sv).

### In progress when paused — SpyGlass lint (lint_bus_matrix.py, prj files written)
Result FAIL, all findings in new bus_matrix RTL (no waivers yet). Planned RTL fixes:
- W528 fp_pick unused in RR mode → arbiter: generate-if per ARB_MODE.
- W415a (multiple assignment in one block) in arb beaten/rr_pick loops, decoder
  priority loop, core p_slave_route/p_master_resp, rr_ptr_q for-loop, axi4l_tgt flags →
  loop-free forms: decoder sel = match & (~match+1); RR with one-hot last_q
  (above = ~((last<<1)-1); pick = lowest(req&above) else lowest(req)); core AND-OR via
  generate + chained accumulate assigns; axi4l_tgt _d/_q split.
- STARC05-2.11.3.1 axi4l_ini FSM in one always_ff → state_d/state_q two-process.
- STARC05-2.2.3.3 axi4l_tgt aw/w/ar_got_q → _d/_q.
Mirror every change in VHDL, then re-run sims (16), formal (all), lint, DC.
Was checking timer RTL style (timer uses per-register always_ff, no loop accumulation).

### 2026-10-10 update
- Lint fixes above DONE (SV + mirrored in VHDL): arb = generate per ARB_MODE (fp: per-master
  `beats` vector; rr: one-hot last_q), decoder `match & (~match+1)`, core generate AND-OR
  chains (fields packed {we,be,wdata,addr}), axi4l_tgt _d/_q flags, axi4l_ini two-process.
  VHDL uses `/= (x'range => '0')`, not VHDL-2008 unary reductions (DC safety).
- SpyGlass SV: 4/4 PASS (0 real findings). Sims: 16/16 PASS (VCS + Xcelium, SV + VHDL).

- 2026-10-10 DC all 4 PDKs (8 variants each). SAED32/14/SKY130 MET. SAED90 VIOLATED on
  5/8 (worst axi4l SV -1.25 ns): arbiter gnt fans out to the 69-bit {we,be,wdata,addr}
  AND-OR mux; under SAED90's 35000/8000 wire-load DC builds weak NBUFFX2 chains (~3 ns
  each) ending at slv_req. Also max_cap DRVs (SAED90 up to 489, SAED32 ~20/variant,
  SKY130 ss 0-5 marginal). DECISION PENDING with user: accept (like timer) or RTL fix.
- PrimeTime: fixed my run_primetime_sta.py port bug — per-variant WNS min()'d setup AND
  hold groups (showed hold slack as WNS). Now setup WNS / hold WNS / DRV count columns.
- Gate-level sim: SAED32 initially failed (timeout at 10 ns) because bus_matrix SV TB files
  had no `timescale and inherited a SAED32 cell model's 1ps/1ps. Added `timescale 1ns / 1ps
  to tb_*.sv, *_bfm.sv, bus_matrix_tb_mem.sv (timer TBs already have it). Now 16/16 PASS
  incl. SAED90 (82/82 checks each). Power: 16/16 PASS, 100% SAIF annotation, SAED90 at typ.
- Order requested by user: DC -> STA -> postsyn -> power -> formal LAST.
- SAED90 decision (user, 2026-10-10): synthesis fix first (set_cost_priority -delay,
  set_max_fanout 16, 2nd compile_ultra -incremental), then RTL fix (slv_req = |gnt, no
  decoder in front) -> SAED90 -1.25 -> -0.56 ns, SKY130 ss +0.84 -> +2.54. Remaining paths
  = grant -> 69-bit field / rdata mux -> output port (SAED90 WLM wire delay ~2.5-3 ns/level).
  User chose ACCEPT. Documented in synthesis/known_issues.md (+ SAED32 max_cap 168 open).
- Final netlists: lint PASS, RTL sims 16/16, postsyn 16/16 (82/82 each incl SAED90),
  power 16/16. Formal final run started (task b46e69p0w).

- 2026-10-10 (later): tops use bus_matrix_pkg::BM_* (no header import; Yosys) — lint/sims
  PASS, SKY130 DC identical. Formal waivers widened to u_fv* (VHDL bind adds a u_fv level);
  VHDL apb/ahb FAILs in the final run are only that — re-run VHDL jobs after the run ends.
- Docs written: README (all timer sections), doc/spec.md, formal/vcf/README.md,
  synthesis/known_issues.md, regression/README.md. Templates updated (directed_tests,
  synthesis, reference_vc_formal, uvm).
- Standard-host scripts ported (UNVERIFIED, tools absent on csun): yosys .ys x8 (old
  .tcl removed), vivado/quartus synth_<top>.tcl x4, modelsim tb_*.do + _wave.do,
  verification/vivado/create_project_/wave_ (xsim/*.sh removed), SymbiYosys
  bus_matrix_core.sby (rr/fp tasks) + new bus_matrix_props.sv (VCS compiles it).
- UVM: env/ was never committed (root .gitignore `env/`; exception added). Wrote env,
  scoreboard, coverage; TB on bus_matrix_axi4l defaults; driver now idles from t=0.
  uvm_bus_matrix.py --sim vcs --test all: 3/3 PASS on VCS. run_regression runs it on csun.

- Formal final: 8/10 PASS (VHDL apb/ahb/wb re-run after waiver fix). axi4l SV+VHDL: 94/96,
  s_b_bounded/s_r_bounded (M_WAIT=64) INCONCLUSIVE at 30M (no cex, depth 105-149);
  re-running with --max-time 2H (started ~19:00 2026-10-10).
- Docs updated for that state: README formal table, vcf/README "Results", regression/report.md
  (marked "not final" — run_regression counts MISSING as skip, so its PASSED is misleading).

- 2026-10-10 ~22:00: axi4l SV+VHDL 96/96 PROVEN with 2H (SV 6136 s). formal_bus_matrix.py now
  defaults axi4l to 3H (AXI4L_MAX_TIME), others 30M; run_regression FORMAL_TIMEOUT 10 h.
  All 10 formal jobs PASS; regression collects 108/108 PASS. Docs updated to final state.

### Remaining plan
1. Commit (needs user approval) — nothing committed yet. Optional: v1.0.0-style tag.
2. Standard-host scripts (Yosys/Vivado/Quartus/ModelSim/xsim/sby/Icarus/GHDL/Verilator) are
   ported but unverified — run on a standard host.
3. Open: SAED32 max_capacitance (168 violators).
- 2026-10-11 UVM coverage upgrade DONE: S2/S3 = new bus_matrix_tb_axi4l_slave (random waits,
  SLVERR page 0xE00-0xEFF); scoreboard predicts OKAY/decerr/slverr, keyed {slave, addr[11:2]};
  new map_seq/map_test (100 % coverage) + decerr_seq/decerr_test (guards); 5/5 PASS on VCS;
  mutation-checked (tgt drops errors; decoder leaks bit 16) — both caught, old tests miss them.
- 2026-10-11 standard host (salvage) bring-up DONE, nothing committed. Every standard-host flow
  passes: sims 24/24 (Icarus, GHDL, ModelSim SV+VHDL, xsim SV+VHDL), Verilator+GHDL lint,
  SymbiYosys rr+fp, UVM 5/5 on xsim, Yosys 8/8, Vivado 4/4 (all MET), Quartus 4/4, ModelSim .do
  and Vivado create_project GUI scripts, regression 147/147. Fixes: tests (unmapped_addr()
  function; test_contention task-level k0/k1 because xsim crashes on decls in >1 fork);
  RTL (explicit genvar + generate/endgenerate for Quartus Std; enum ?: -> if/else for Icarus;
  verilator UNUSEDSIGNAL pragmas on HTRANS[0]/BRESP[0]/RRESP[0]); runners (yosys stat parse,
  Vivado WNS parse, sby --prefix for multi-task, regression collects formal/results.log);
  GUI (.do loads _wave.do via ${BM} not [info script]; create_project add_files -fileset sim_1;
  xsim wave uses u_core/gnt). RTL edits postdate the csun runs: re-run VCS/Xcelium/SpyGlass/
  VCF/DC there. Timer has the same [info script] and -sim_only bugs (not fixed).
