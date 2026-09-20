---
name: SpyGlass lint on csun.edu — SV works, VHDL-2008 does not
description: SpyGlass (spyglass_vc) replaces Verilator for SV lint on csun.edu; how pass/fail is actually determined; why VHDL lint has no SpyGlass path there
type: reference
---

SpyGlass became the csun.edu SV lint tool (replacing Verilator, which isn't
installed there) — first wired up for `IP/system/timer`, following the same
per-IP pattern as [reference_sky130_pdk](reference_sky130_pdk.md) for
synthesis. See [lint.md](lint.md) (Step 8) for the full spec any new IP's
lint step should follow.

**Invocation that actually works:** `spyglass_vc -project <top>.prj -goal
lint/lint_rtl -batch -app lint`, run with `verification/lint/spyglass/` as
`cwd` so each `.prj`'s relative `read_file` paths resolve. `spyglass_vc` is
a wrapper that translates the classic Atrenta-SpyGlass project-file format
into a Synopsys VC Static (`vc_static_shell`) run — this host has no
separate standalone SpyGlass install, just this compat layer bundled inside
`/opt/synopsys/vc_static/<ver>/bin/`.

**Pass/fail must come from `moresimple.rpt`, not the exit code.** Confirmed
empirically: `spyglass_vc` can exit 0 on a run that silently produced
nothing useful, and its exit code doesn't reliably track violation count
either way. The real per-violation list is at
`vcst_rtdb/spyglass/<top>/<top>/lint/lint_rtl/spyglass_reports/moresimple.rpt`.
Every run also emits translator/environment noise that must be filtered out
before judging pass/fail, since it appears regardless of design content:
`COM_OPT009`/`COM_OPT010` (`search_path`/`link_library` not set — expected,
we pass full paths directly) and any `PrjToTclSummary` row containing
"Skipped option" (the compat translator unconditionally reports skipping
`template_info`, `overloadrules`, and `template`).

**Waiver pragma (verified working):**
```systemverilog
//spyglass disable_block <RuleName>
... code ...
//spyglass enable_block <RuleName>
```
Confirmed via a live test: wrapping a flagged port declaration made its
violation move from "Non-Waived" to "Waived" in the run's Message Summary.
Record any use of it in `waivers.md` exactly like a Verilator/GHDL waiver
(file, line, code, justification, pragma location).

**VHDL-2008 has no working path through this tool's project-file interface —
confirmed by hands-on testing, not by reading docs.** This repo's VHDL RTL
uses VHDL-2008 constructs (e.g. conditional signal assignment in
`timer_regfile.vhd`: `result(7 downto 0) := wdata(...) when strb(0)='1' else
current(...)`), which the classic-compat parser rejects as a syntax error
by default. What was tried and failed:
- `set_option vhdl2008 yes` / `enableVHDL2008` / `enable_vhdl2008` /
  `vhdl_2008` / `VHDL2008` — all silently no-op; the generated `analyze`
  call in `internal.tcl` is byte-identical with or without them.
- `read_file -type vhdl -vhdl2008 {...}` and `read_file -type vhdl2008
  {...}` — both rejected at project-file translation with a generic
  `PrjToTclSummary` parse error.
- `analyze -vhdl_opts {-vhdl08} {...}` (native vc_static command, bypassing
  the `.prj` entirely) — still fails with the same VHDL-2008 syntax errors.
- The separate legacy `spyglass`/`sg_shell` binaries under
  `SG_COMPAT/linux64/SPYGLASS_HOME/bin/` (a genuine standalone classic
  SpyGlass install, not just the vc_static compat shim) — dumped their full
  ~230-entry `set_option` list (`help -option` in `sg_shell`); there is no
  VHDL revision option at all. This parser is independent of VCS and simply
  doesn't support VHDL-2008.

**What does work, but isn't usable through the supported interface:**
`analyze -format vhdl -vcs {-vhdl08} {files}` — calling the underlying
VCS-based analyzer directly with the raw `-vhdl08` flag inside `-vcs {...}`
parses VHDL-2008 cleanly. But there's no supported way to get the
`.prj`/`read_file -type vhdl` translation layer to add that flag to its
generated `analyze` call. Forcing it (patching the generated
`.vcs_opts_vhdl.f` file, or the `internal.tcl` between translation and
execution) requires either multiple `vc_static_shell` process invocations
(which triggers the tool's automatic `vcst_rtdb` backup-and-restart between
invocations, breaking file references from the first pass) or re-sourcing
`internal.tcl` within one session (which fails — `sg_read_project` without
`-run` already partially executes setup, e.g. `enable_lint`, so re-sourcing
conflicts with that state). Tried and correctly rejected as too fragile for
a production script — see the AskUserQuestion exchange this was raised in.

**Decision (confirmed with the user):** VHDL lint is simply unavailable on
csun.edu. `lint_timer.py` logs it as `SKIPPED` with the reason, and does not
count it as a failure. GHDL (the VHDL tool on standard hosts) isn't
installed on csun.edu either, so there's no fallback there.

**How to apply:** any new IP's Step 8 lint work on csun.edu should add SV
lint via SpyGlass following the exact pattern in
`IP/system/timer/verification/lint/spyglass/*.prj` and
`IP/system/timer/verification/tools/lint_timer.py`, and should skip VHDL
lint on csun.edu the same way rather than re-attempting the VHDL-2008
investigation above.
