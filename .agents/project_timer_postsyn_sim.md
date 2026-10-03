---
name: Timer IP — post-synthesis simulation setup
description: How post-syn simulation is configured in sim_timer.py; PDK paths, SDF annotation details, the SAED14 _udp.v fix, and the SAED90 known-failure handling
type: project
---

Post-synthesis simulation was added to `IP/system/timer/verification/tools/sim_timer.py` via `--postsyn` and `--pdk` CLI flags. Covers SAED90/32/14 only — SKY130 isn't wired into this capability (not in `SUPPORTED_PDKS`).

**PDK cell library Verilog model paths on csun.edu** (`POSTSYN_PDK_CONFIGS[pdk]["cell_libs"]`):
- SAED90 (1 file, self-contained): `/opt/ECE_Lib/SAED90nm_EDK_10072017/SAED90_EDK/SAED_EDK90nm/Digital_Standard_cell_Library/verilog/saed90nm.v`
- SAED32 (1 file, self-contained): `/opt/ECE_Lib/SAED32_EDK/lib/stdcell_rvt/verilog/saed32nm.v`
- SAED14 (**8 files**, not 4): `SAED14nm_EDK_STD_RVT/verilog/{base,cg,dlvl,iso}/saed14rvt_*.v` **and** each subtree's `saed14rvt_*_udp.v` companion, under `/opt/ECE_Lib/SAED14nm_EDK_03_2025/`. Every SAED14 cell's main `.v` is a timing-check wrapper whose body instantiates a `_func`-suffixed primitive (e.g. `SAEDRVT14_EO2_2` wraps an instance of `SAEDRVT14_EO2_2_func`), and that `_func` body lives in the separate `_udp.v` file — omitting it fails compile with `Error-[URMI] Unresolved modules` for essentially every cell in the design, found and fixed 2026-10-03 (see `synthesis/known_issues.md`). SAED90/32 don't need this since they ship one self-contained model per cell.

**DC netlist/SDF location:** `IP/system/timer/synthesis/designcompiler/netlists/<pdk>/timer_<proto>.{v,sdf}` — also has a `.sdc` per variant now (used by PrimeTime STA, not post-syn sim).

**SDF annotation scope:** `tb_timer_{proto}.u_dut` — `u_dut` is the DUT instance name in all testbenches.

**VCS flags for post-syn:**
- Compile: `-sdf typ:{scope}:{sdf_file}`; `+notimingcheck +neg_tchk` to evaluate functional correctness without a PVT-matched clock period (this is what turns a genuine SAED90 setup violation into silent `X` instead of a reported error — see below); `+vcs+initreg+random` to enable the initreg mechanism.
- Runtime: `+vcs+initreg+0` initializes gate-level flip-flops to 0 at time 0, to avoid X before the testbench's own reset is applied.

**SAED90 post-syn results are unreliable, and this is accepted, not a bug to
keep chasing.** SAED90 has a real -0.40 ns timing violation at 100 MHz
(accepted by the user 2026-10-03 rather than fixed — this flow is flat,
pre-layout DC synthesis with a generic wire-load model, no real
place-and-route). With `+notimingcheck`, that violation doesn't get
reported — it just means some flop captures whatever's on `D` at the
clock edge, showing up as `X` on reads (confirmed via a real `$setuphold`
violation reported on `u_core/count_q_reg` when timing checks are
re-enabled for diagnosis). `POSTSYN_KNOWN_FAILURES = {"saed90"}` makes this
visible rather than a bare `FAIL`: the results summary shows `FAIL (known)`
in yellow with an inline pointer to `synthesis/known_issues.md` — still a
real failure for the exit code (not hidden, not a fake pass). A separate,
now-fixed bug (the clock port missing `set_ideal_network`, causing a
~6.6 µs SDF clock delay) used to make SAED90 fail even more severely
(hangs, not just wrong reads) — see `synthesis/known_issues.md` for the
full two-layer history.

**Why:** Always uses SV testbench (not `_vhdl` variant) and Verilog netlist regardless of RTL source language.

**How to apply:** Run with `python sim_timer.py --postsyn` (all PDKs) or `--postsyn --pdk saed90` for a specific PDK. Only works on csun.edu where PDK libs are installed. Expect SAED32/SAED14 to pass 4/4; SAED90 to show `FAIL (known)` 4/4 — that's the accepted state, not something to re-debug.
