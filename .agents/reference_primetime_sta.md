---
name: PrimeTime STA on csun.edu — separate script, SAED + SKY130, accepted SAED90 timing violation
description: run_primetime_sta.py is a script separate from run_vendor_synth.py; STA covers SAED90/32/14 (one corner each) and SKY130 (ss/tt/ff); the pre-existing SV create_clock bug it surfaced; SKY130's ss-corner violation (fixed via retune) and SAED90's (accepted, not fixed)
type: reference
---

PrimeTime (`pt_shell`) became the csun.edu STA tool, added for
`IP/system/timer`, following the same per-IP pattern as
[reference_sky130_pdk](reference_sky130_pdk.md) (synthesis) and
[reference_spyglass_lint](reference_spyglass_lint.md) (lint). See
[synthesis.md](synthesis.md) (Step 10) for the full spec any new IP's STA
step should follow.

**Separate script, run after synthesis.** STA lives in its own
`synthesis/run_primetime_sta.py`, not inside `run_vendor_synth.py` — DC
synthesis and PrimeTime STA are two distinct steps run one after the other
(`run_vendor_synth.py --dc...` first, then `run_primetime_sta.py`), not one
combined tool. This was an explicit ask after the first version bundled
both into `run_vendor_synth.py`; keeping them separate also made it
natural to give STA multi-PDK coverage (see next) without further
entangling the two scripts' CLIs.

**STA covers all four PDKs, not just SKY130.** SAED90, SAED32, and SAED14
each get one STA run, against the exact same single `.db` corner
`synth.tcl` already synthesized them to (`saed90nm_max`,
`saed32rvt_ss0p95v125c`, `saed14rvt_base_ss0p72v125c`) — this is a genuine
gate-level timing recheck via PrimeTime, not a repeat of DC's own
compile-time `report_timing` estimate. SKY130 gets three STA runs, one per
PVT corner (`ss_100C_1v60`, `tt_025C_1v80`, `ff_n40C_1v95`, already
compiled to `.db` by `build_sky130_libs.py` for DC synthesis — reused here,
no separate PrimeTime-only library compile step), all three rechecking the
**one** netlist set DC produced (synthesized only to the typical corner).
SKY130 is still the only PDK with real multi-corner coverage to check
against — the user's own framing for why sky130 corners matter here: "The
SAED .db files are of mixed quality and only a few corners. The Sky130
have ff, ss and typical." Each SAED EDK only ships one `.db`, so there's
no second/third corner for them — just the one STA-vs-synthesis
cross-check per EDK.

**The flow:** any `run_vendor_synth.py --dc*` synthesis writes a `.sdc` per
variant (`write_sdc`, in `synth.tcl`'s shared `synth_variant` proc — added
alongside this work, so it applies to every PDK, not just sky130) into
`synthesis/designcompiler/netlists/<pdk>/`. `run_primetime_sta.py` then
runs `pt_shell -f synthesis/primetime/sta.tcl` once per requested target,
each pass reading all 8 variant netlists (4 SV + 4 VHDL) and their `.sdc`,
setting that target's `.db` as `target_library`/`link_library`. STA does
not re-run place-and-route or re-optimize anything — it is a pure timing
recheck of the already-synthesized gates under the target's timing arcs.
One shared `sta.tcl` handles every target (SAED or SKY130 corner) via a
generic `PT_TARGET` env var; `netlist_pdk_for(target)` in
`run_primetime_sta.py` maps a SKY130 corner name back to the single
`netlists/sky130/` directory, and a SAED target name to its own
`netlists/<target>/` directory.

**Bug found while adding this: SV variants were being synthesized fully
unconstrained.** `synth.tcl`'s SV loop called
`create_clock -period 10 clk` for every variant, but no SV top-level module
actually has a port named `clk` — each protocol names its clock
differently (`PCLK`/`HCLK`/`ACLK`/`CLK_I`), exactly like the `vhdl_clocks`
array the VHDL loop below it already used correctly. The literal `clk`
lookup failed with `Warning: Can't find object 'clk' in design '<variant>'
(UID-95)` — and, following the same "warns but exits 0" pattern documented
for sky130's `DB-1` in [reference_sky130_pdk](reference_sky130_pdk.md), the
run continued and reported `PASS`. Every SV `report_timing` showed
`Path Group: (none)` / `(Path is unconstrained)` on every path, meaning
`compile` had nothing to optimize timing against, for every SV variant,
under every PDK (SAED90/32/14 and SKY130) — since this table's introduction.

This was never independently exercised or reported on before, so it went
unnoticed until `write_sdc` was added for PrimeTime and the emitted `.sdc`
turned out to have no `create_clock` line at all. Fixed by adding an
`sv_clocks` array mirroring `vhdl_clocks` and using it in
`synth_variant`'s clock-port argument instead of the hardcoded `clk`.
Re-running `--dcsky130` after the fix changed the design's cell count
(840 → 879) and produced real `Path Group: PCLK` (etc.) timing paths with
actual slack — confirming the constraint is now live. All four PDKs were
re-synthesized after this fix (not just SKY130) since the bug lived in the
shared `synth.tcl` used by all of them; VHDL variants were unaffected.

**SKY130's worst-case violation (2026-09-20 finding) was fixed, not
accepted — by retuning what corner DC synthesizes to, not by touching STA.**
Originally DC synthesized SKY130 only to its typical corner
(`tt_025C_1v80`), so the worst-case `ss_100C_1v60` corner legitimately
violated (WNS -2.850 ns) when STA rechecked the typical-corner netlist
against it — expected, not a bug, for a netlist never optimized for that
corner. Fixed later (2026-09-26) by changing `SKY130_SYNTH_CORNER` to
`ss_100C_1v60` and upgrading `compile` to `compile_ultra -no_autoungroup`
with `synthetic_library dw_foundation.sldb`. Current result: all three
SKY130 corners meet 100 MHz (`ss_100C_1v60` +1.39 ns, `tt_025C_1v80`
+5.64 ns, `ff_n40C_1v95` +7.23 ns). Full numbers and history in
`synthesis/known_issues.md` — not duplicated here.

**SAED90 violates 100 MHz (WNS -0.40 ns) and this is accepted, not
fixed — in the hope a real place-and-route flow would close it.** The same
`compile_ultra` retune above applies to every PDK (shared `synth.tcl`), and
pushed SAED90 — already marginal before (-0.01 ns) — further into
violation. Decided (2026-10-03) to accept rather than chase: this flow is
flat, pre-layout synthesis with a generic wire-load model, so a margin this
small plausibly closes under real P&R, which this project doesn't run.
**This directly explains why SAED90 post-synthesis gate-level simulation
is unreliable** (confirmed via a real `$setuphold` violation on
`u_core/count_q_reg` when timing checks are re-enabled for diagnosis — the
normal post-syn flow runs with `+notimingcheck`, which turns that
violation into silent `X`-propagation instead of a reported error, rather
than masking it). SAED32 (+7.81 ns) and SAED14 (+4.92 ns) both meet timing
comfortably. Full numbers, the two-layer root-cause (a real clock-port
wire-load bug, fixed, plus this accepted violation), and the now-reverted
`set_register_replication` dead end are all in `synthesis/known_issues.md`.

**Pass/fail semantics mirror `write_vivado_report`, not a naive
"violated = fail."** `run_sta`'s return value means "`pt_shell` completed"
(process-level), matching `run_design_compiler`'s own "exits 0" semantics.
Whether timing was actually met at that target is a separate
`Timing: MET/VIOLATED` field inside `report_sta_<target>.txt`, parsed from
`report_qor`'s `Critical Path Slack` / `Total Negative Slack` lines.
Treating "STA ran" and "timing met" as the same boolean would make a
genuine worst-case-corner failure silently look like a script crash instead
of a timing-closure finding — keep them separate in any future STA work too.

**`--clean` is host-agnostic; running STA itself is not.** `run_primetime_sta.py`
checks `ON_CSUN` only for the actual STA path — `--clean` runs (and no-ops
safely) on any host, checked *before* the host gate, specifically so the
top-level `cleanup.sh` can call `run_primetime_sta.py --clean`
unconditionally, the same as it already does for `run_vendor_synth.py
--clean`. Reordering that check would break `cleanup.sh` on non-csun.edu
hosts (it runs under `set -e`).

**A one-time harmless startup line to ignore:** every `pt_shell` invocation
logs `Error: Library Compiler executable path is not set. (PT-063)` before
doing anything else. It does not affect the exit code or any report content
in this flow (nothing here calls into LC from PrimeTime) — do not treat it
as a failure signal.

**How to apply:** any new IP's Step 10 STA work on csun.edu should add a
`run_primetime_sta.py` the same way — a script separate from
`run_vendor_synth.py`, covering every PDK the IP synthesizes (one STA run
per SAED PDK against its single corner, three runs for SKY130 across
ss/tt/ff), reusing `synth.tcl`'s per-variant `write_sdc` output. Before
trusting any new IP's SV timing numbers, double-check its `synth.tcl`
actually resolves each variant's real clock port name rather than assuming
a shared one.
