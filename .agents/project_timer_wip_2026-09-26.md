---
name: Timer WIP handoff (2026-09-26, closed out 2026-10-03) — VC Formal + synthesis retune + SAED90 timing accepted + mass-deletion restored
description: VC Formal done, synthesis retuned, both post-synthesis simulation failures (SAED90/SAED14) root-caused and resolved, SAED90's timing violation accepted by the user, sky130 PDK reinstalled, a ~50-file mass deletion found and restored from git — everything documented, nothing committed yet
type: project
---

**State: nothing committed.** Everything below is uncommitted in the working
tree on `main` (`git status` shows it).

## Done and verified
1. **VC Formal flow** for the timer: 4 protocols × SV/VHDL, all 8 jobs PASS
   (`formal_timer.py --tool vcf`). Reusable parts are in
   `IP/common/verification/formal/` and `IP/common/verification/tools/claude_vcf.py`.
   See [reference_vc_formal](reference_vc_formal.md).
2. **RTL fixes found by formal**: VHDL `timer_core` RESTART gated by EN;
   `timer_regfile` (SV+VHDL, + yosys copy) RESTART/SNAPSHOT pulse stretch;
   common `claude_ahb_if` (SV+VHDL) late HRDATA, fixed with one read wait state
   (the user chose this). After these fixes: VCS 8/8, Xcelium 8/8 and
   SpyGlass SV lint all PASS.
3. **Synthesis retune (the user asked for options 1+2)** to fix SKY130 SS timing:
   - `IP/common/synthesis/designcompiler/build_sky130_libs.py`:
     `SKY130_SYNTH_CORNER = "ss_100C_1v60"` (was tt).
   - `synthesis/designcompiler/synth.tcl`: `synthetic_library dw_foundation.sldb`
     and `compile_ultra -no_autoungroup` (was `compile -map_effort low`).
   - A 0.5 ns synthesis-only clock-uncertainty margin was tried, made
     SAED90 worse (-0.99 ns), and was **reverted**.

## Current DC / PrimeTime numbers (reports regenerated with the settings above)
| Target | WNS | Before the retune |
|---|---|---|
| SAED90 | **-0.40 ns VIOLATED** | -0.01 |
| SAED32 | +7.81 | +7.26 |
| SAED14 | +4.92 | +3.82 |
| SKY130 ss | **+1.39 MET** | -2.85 |
| SKY130 tt | +5.64 | +3.25 |
| SKY130 ff | +7.23 | +5.66 |
Cells: SAED90 838, SAED32 675, SAED14 655, SKY130 737.
SAED90's worst path is `u_ahb_if/rd_wait_q` → `rd_en` fan-out into the regfile's
32-bit read mux (a high-fanout NBUFFX2 at 3.38 ns). SAED90 at 100 MHz is marginal.

**Timer README / known_issues.md are NOT yet updated for the retune.** The
README still shows the pre-retune synthesis numbers (from the earlier rerun).

## Open problem (where the session stopped)
`sim_timer.py --sim vcs --postsyn --proto all` on the new netlists:
- SAED32: 4/4 PASS.
- **SAED90: 4/4 FAIL.** APB/AHB fail the first test (CTRL read-back returns 0,
  expected 0x0f0f); AXI4L/WB time out. The netlist compiles, so this is
  functional. Suspect `compile_ultra`/DesignWare netlist behaviour in gate-level
  sim (e.g. scan/`DFFSSRX1` set/reset cells, SDF, X-propagation). Not yet
  investigated. **Update (2026-10-03): root-caused in two layers, see
  "SAED90 post-syn — two-layer root cause" below — layer 1 fixed, layer 2
  open, needs a decision.**
- ~~**SAED14: compile FAILS**~~ **FIXED (2026-10-03), now 4/4 PASS.** Root
  cause confirmed from the log, not guessed: the `Unresolved modules` errors
  point at lines *inside* `saed14rvt_base.v` itself (e.g. line 25664), not
  the timer netlist — every SAED14 cell's main `.v` is a timing-check
  wrapper whose body instantiates a `_func`-suffixed primitive
  (`SAEDRVT14_EO2_2` wraps `SAEDRVT14_EO2_2_inst` of type
  `SAEDRVT14_EO2_2_func`), and that `_func` body is defined in a *separate*
  companion file, `saed14rvt_base_udp.v`, which the post-syn file list
  didn't include. Confirmed the same base/cg/dlvl/iso split exists for all
  four subtrees (`saed14rvt_{base,cg,dlvl,iso}_udp.v` all exist alongside
  their main `.v`). Fix: added all four `_udp.v` files to
  `POSTSYN_PDK_CONFIGS["saed14"]["cell_libs"]` in `sim_timer.py`. Verified
  live: `sim_timer.py --sim vcs --postsyn --pdk saed14 --proto all` → 4/4
  PASS. SAED90/32 don't need this — they ship one self-contained model per
  cell instead of splitting out `_func` primitives.
- Full log: `IP/system/timer/verification/work/postsyn/postsyn_run_2026-09-26.log`
  (SAED14 section is now stale/fixed; re-run to get a current combined log).

## SAED90 post-syn — two-layer root cause (2026-10-03)

**Layer 1 — FIXED: clock port had a ~6.6 µs wire-load delay.** Checked the
SDF directly rather than guessing. `synth.tcl` already marks the reset port
`set_ideal_network` (committed before this session, with its own comment
explaining why — high-fanout nets get absurd wire-load RC estimates), but
never did the same for the **clock** port. SAED90's `timer_apb.sdf` showed:
```
(INTERCONNECT PCLK u_core/count_q_reg[0]/CLK (6595.710:...) (6257.243:...))
```
— i.e. every flop in `u_core`/`u_regfile` saw its clock edge arrive ~6.6 µs
late. For comparison, the same net in SAED32's SDF is `0.000 ns` and
SAED14's is `0.004 ns` — this is a SAED90-library-specific wire-load
blowup, not a general bug. With `+notimingcheck` suppressing the violation
report, this doesn't show up as an error — it just means no flop's
functional clock edge ever arrives within any realistic simulation window.
That fully explains the observed symptoms: APB/AHB "pass" `test_reset`
(reset is async and already ideal, so it independently forces 0) but then
fail `test_rw`'s write-then-read-back (the write's clocked capture never
happens); AXI4L/WB hang outright (their handshake FSMs need a real clock
edge to leave the initial state, and never get one).

**Fix:** `synth.tcl`'s shared `synth_variant` proc now also calls
`set_ideal_network [get_ports $clk_port]` (added right next to the existing
reset-port call). Applies to all PDKs via the shared proc; re-synthesized
all of SAED90 and confirmed its PCLK interconnect delay is now `0.000 ns`
and the SDF's largest remaining delay anywhere is `~5.4 ns` (sane, within
the 10 ns period). **Re-verified (2026-10-03):** SAED32/SAED14's clock
delay was already `0.000 ns`/`0.004 ns` before the fix (confirmed no
regression — full `--dc` re-run, both still 4/4 PASS on post-syn). SKY130's
was already `0.001 ns` (checked directly in its existing SDF, not
re-synthesized — see the SKY130 PDK note further down).

**Layer 2 — root-caused and corrected (2026-10-03), still OPEN, needs a
decision.** After the layer-1 fix, `sim_timer.py --sim vcs --postsyn --pdk
saed90 --proto all` moved past the old failure into a new one: `test_reset`'s
"COUNT reset value" check now reads `0xXXXXXXX0` (ahb/wb) or `0xXXXXXXXX`
(axi4l) instead of `0`. APB alone passes this specific check.

**First theory (wrong, corrected after further digging — recorded here so
it isn't re-investigated):** initially looked like `compile_ultra` register
duplication (`timer_core`'s `count_q` duplicated to drive `hw_count_val`,
with SAED32/14 getting a reset-capable duplicate cell and SAED90 not).
Tried `set_register_replication -replicate false [all_registers]` in
`synth.tcl` on the user's "try option 1" — **this did not fix it and was
reverted.** Checking `all_registers` directly in `dc_shell` (right after
`elaborate`+`link`, before `compile`) showed `u_regfile/count_q_reg[*]` and
`u_core/count_q_reg[*]` as two **already-distinct RTL registers**, not a
DC-introduced duplicate: `timer_regfile.sv` has its own `count_q` (an
RO mirror of `hw_count_val`, `always_ff @(posedge clk) if (!rst_n) count_q
<= TIMER_COUNT_RESET; else count_q <= hw_count_val;` — completely standard,
identical in shape to `ctrl_q`/`load_q` which reset correctly). So there
was never a duplication bug to disable in the first place.

**Actual root cause, confirmed (not inferred) by re-running the SAED90/AHB
post-syn compile with `+notimingcheck` removed** (the normal flow always
passes `+notimingcheck`, which is exactly what was hiding this):
```
"saed90nm.v", 7493: Timing violation in tb_timer_ahb.u_dut.u_core.\count_q_reg[3]
    $setuphold( posedge CLK &&& D_DEFCHK:5000, negedge D:4921, limits: (139,-17) );
```
— real `$setuphold` violations, reported by name, on `u_core/count_q_reg[3]`,
`[7]`, `[11]` at the reset-release edge. **This is the same SAED90 timing
violation already on record (WNS -0.40 ns pre-layer-1-fix), not a separate
bug** — `count_q`'s D-input mux (reset-override combined with a 4-way
load/restart/underflow/decrement priority mux feeding a subtractor) is
evidently one of the longer combinational cones in the design, and under
`+notimingcheck` a genuine setup violation there doesn't get reported — VCS
just silently captures whatever value happens to be on `D`, which is why
it shows as X instead of a timing error. Why APB alone doesn't show it:
each protocol's netlist is synthesized independently, so the specific gate
delays on this cone differ slightly per protocol; APB's happens not to
violate by enough to actually flip a bit, not that its timing is safe.

**This folds layer 2 back into the one open decision already on record
("decide how to handle SAED90 timing"), not a second independent problem.**
Fixing the timing (closing the violation) would fix both the STA number and
this functional symptom together.

## Decision (2026-10-03): SAED90's timing violation is accepted, not fixed

User's call: accept the -0.40 ns violation, document it, in the hope that a
real place-and-route flow (not run by this project — flat, pre-layout DC
synthesis with a generic wire-load model only) would close a margin this
small. Not pursuing RTL pipelining or per-PDK compile settings for now.
Documented in `synthesis/known_issues.md`, `README.md` (Design Compiler,
PrimeTime STA, and new Post-Synthesis Gate-Level Simulation sections), and
`.agents/reference_primetime_sta.md`. `sim_timer.py` now tags this
explicitly — `POSTSYN_KNOWN_FAILURES = {"saed90"}` prints a one-line
pointer to `known_issues.md` and shows `FAIL (known)` in yellow in the
results summary (still a real failure for the exit code — not hidden, not
a fake pass).

**Final verification (2026-10-03), full `--dc` + full `--postsyn` re-run:**
SAED90 838 cells / SAED32 675 / SAED14 655 (SKY130 unchanged at 737, see
PDK note below). Post-syn: SAED32 4/4 PASS, SAED14 4/4 PASS, SAED90 4/4
`FAIL (known)` on **all** protocols including APB (APB's earlier single
pass was luck from one specific compile's gate delays, not a safe
protocol — a fresh synthesis run made it fail too, consistent with "the
whole design carries this risk").

**Side discovery, unrelated to SAED90: the SKY130 PDK install was gone —
found, reinstalled, and fixed (2026-10-03).** While re-running the full
`--dc`, SKY130 failed — its ASCII `.lib` source under
`/tmp/pet43490/PDK/volare/sky130/.../sky130A/` had been wiped down to one
unrelated file (almost certainly routine `/tmp` cleanup, ~13 days after it
was placed). The compiled `.db` cache in
`IP/common/synthesis/designcompiler/sky130_lib/` was untouched throughout
(it's under the repo), and SKY130's existing 2026-09-26 results were
confirmed still valid before the fix (its clock delay was already
`0.001 ns`, so the layer-1 fix was a non-issue for it).

The user then pointed me at `/tmp/pet43490/PDK/sky130A` as the intended
location — also empty on inspection, not a path mix-up. Re-fetched via
`volare fetch --pdk-root /tmp/pet43490/PDK --pdk sky130 -l all <same
pinned hash>` (after first bootstrapping the project venv, which turned
out to have no `pyvenv.cfg`/local `pip` at all despite existing on disk,
and restoring `virtualenv/requirements.txt` via `git checkout HEAD --`
since it was one of the files found missing from the working tree — see
the mass-deletion note in the main conversation, not otherwise tracked in
this file). One real gotcha: volare only checks whether a library's
directory exists at the target version, so empty-but-present directories
left by the wipe (`sky130_fd_sc_hd` included) were skipped as "already
found" on the first fetch; removing those specific directories and
re-fetching picked them up. `build_sky130_libs.SKY130_PDK` now points at a
new stable symlink, `/tmp/pet43490/PDK/sky130A`, so a future re-fetch only
means repointing the symlink. Re-verified end to end: `--dcsky130` and
`run_primetime_sta.py --sky130` reproduce the identical cell count (737)
and STA numbers (ss +1.39/tt +5.64/ff +7.23 ns, all MET) as the pre-wipe
run. Full details in `.agents/reference_sky130_pdk.md` and
`synthesis/known_issues.md`.

## A much larger mass-deletion was found and restored (2026-10-03)

While doing a full README.md accuracy pass (the user explicitly called it
"an important document"), found the working tree had ~50 tracked files
deleted — predating all of the above, not something this session or the
09-26 session did. Scope: the **entire firmware subsystem**
(`CMakeLists.txt`, `build.sh`, all of `src/`/`include/`/`examples/`),
`design/systemrdl/timer.rdl` (the SystemRDL single source of truth),
`doc/spec.md` and `doc/timer_regs.html` (generated register docs),
`verification/lint/waivers.md` (!) and `verilator.flags`, the entire
`verification/tasks/uvm/` directory, `verification/regression/` (report +
runner), all of `verification/modelsim/` and `verification/vivado/` (GUI
project scripts), `verification/tools/run_sims.sh`, plus — outside
`IP/system/timer/` entirely — a duplicate top-level `common/design/rtl/`
tree (superseded by `IP/common/`, presumably dead even restored) and
`systemrdl/Ordt-230719.01.jar`.

Asked the user how to handle it (restore / rewrite docs to match / just
flag) rather than guess — this exact mass-deletion had been surfaced once
already a few turns earlier in the conversation with no action taken, so
it needed an explicit decision this time. **Answer: restore from git**
(treat as accidental). Did `git checkout HEAD -- <all ~50 paths>` in one
shot; `git status` confirms zero `D` entries remain anywhere in the repo.
Re-ran the full regression after restoring (`run_regression.py`) — 86/88
PASS, 2 non-fatal `MISSING` (both explained, not caused by the restore):
`lint` was MISSING only because `cleanup.sh` (run immediately before,
deletes `lint_results.log`) had just wiped it — `lint_timer.py` itself was
run separately earlier and passed clean; `formal/vcf/timer_wb_sv` was
MISSING because `formal_timer.py` failed to write `results.log` for that
one job — checked the raw VC Formal report directly
(`work/vcf/timer_wb_sv/report_fv.txt`) and every property shows `proven`,
so the actual verification passed, it's a separate, minor, pre-existing
`formal_timer.py` results-reporting bug, not investigated further (out of
scope for a README accuracy pass).

**New open item, low priority:** `formal_timer.py` doesn't always write
`results.log` for `timer_wb_sv` specifically — worth a look if it recurs,
but not blocking (the underlying VC Formal verdict is retrievable from
`report_fv.txt` regardless).

## Remaining

Only the user's own call on whether to commit all of this (VC Formal + 3
RTL fixes + synthesis retune + SAED90 acceptance + two real post-syn bugs
found and fixed + the sky130 PDK reinstall + the mass-deletion restore +
documentation) — nothing technical is outstanding.

Side note: `synth.tcl` writes DC `reports/<pdk>/*_timing.rpt` with
`redirect -append` and never clears them, so the first entry in each file is
stale. Delete `synthesis/designcompiler/reports/` before reading them.
