# Timer IP Synthesis — Known Issues

## Yosys Synthesis (all variants)

Log files:
- `yosys/work/yosys_raw_apb.log`
- `yosys/work/yosys_raw_ahb.log`
- `yosys/work/yosys_raw_axi4l.log`
- `yosys/work/yosys_raw_wb.log`
- `yosys/work/synthesis_report.log`

**No known issues.** All Yosys runs completed with 0 warnings and 0 errors.
The `check` pass reported 0 problems for all variants.

## Vivado Synthesis (Zynq-7010 xc7z010clg400-1)

Run date: 2026-03-18. Tool: Vivado 2023.2.

**No RTL warnings.** Synthesis completed cleanly. WNS = +6.162 ns at 100 MHz (timing met).

### Tcl pitfalls resolved during development (not RTL issues)

| Issue | Root cause | Resolution |
|-------|-----------|------------|
| `Invalid option value SystemVerilog` | `target_language` only accepts `Verilog` or `VHDL` | Changed to `Verilog`; SV files still read with `read_verilog -sv` |
| `Invalid option value '' for 'objects'` | `get_runs synth_1` returns empty in in-memory project | Removed `set_property` block; `-mode out_of_context` passed directly to `synth_design` |
| `Too many positional options` for `read_xdc` | Stdin (`-`) not supported in batch mode | XDC written to a temp file, then read with `read_xdc <file>` |

## Quartus Synthesis (Cyclone V SE 5CSEMA4U23C6)

Run date: 2026-03-18. Tool: Quartus Prime Lite 23.1.

**No RTL warnings.** Analysis & Synthesis completed cleanly. 191 registers inferred.

Note: ALMs are reported as `N/A` in the map report — this is expected because ALM
packing is performed by the Fitter, which was not run. Running `execute_module -tool fit`
after map would populate the ALM count. For area estimation, 191 registers is the
authoritative pre-fit figure.

### Tcl pitfalls resolved during development (not RTL issues)

| Issue | Root cause | Resolution |
|-------|-----------|------------|
| `execute_flow -analysis_and_synthesis` not valid | Not a valid `execute_flow` option in Quartus Prime Lite | Changed to `execute_module -tool map` |
| `execute_module` not found | Belongs to `::quartus::flow`, not `::quartus::misc` | Changed `package require` to `::quartus::flow` |
| `report_utilization` / `report_timing_summary` not found | These are Vivado Tcl commands; Quartus Tcl has no equivalents | Removed; Python runner parses auto-generated `*.map.rpt` instead |

## Design Compiler / PrimeTime STA (csun.edu)

### Bug found and fixed: SystemVerilog variants synthesized with no clock constraint

`designcompiler/synth.tcl`'s SV loop passed the literal string `clk` as every
variant's clock port to `create_clock`, but no SV top-level module actually
has a port named `clk` — each protocol names it differently (`PCLK`, `HCLK`,
`ACLK`, `CLK_I`, exactly like the `vhdl_clocks` array already used for the
VHDL loop below it). `create_clock -period 10 clk` silently failed
(`Warning: Can't find object 'clk' in design '<variant>' (UID-95)`), so
every SV variant, under every PDK (SAED90/32/14 and SKY130), compiled and
reported timing with **no clock defined at all** — `report_timing` showed
`Path Group: (none)` / `(Path is unconstrained)` for every path, and
`compile` had no timing objective to optimize against.

This was only caught when adding `write_sdc` (for PrimeTime STA, see below)
and noticing the emitted `.sdc` had no `create_clock` line. Fixed by adding
an `sv_clocks` array mirroring `vhdl_clocks` and using it in place of the
hardcoded `clk`. Re-running `--dcsky130` after the fix changed the SV cell
count (840 → 879 cells) and produced real `Path Group: PCLK/HCLK/ACLK/CLK_I`
timing paths with actual slack values — confirming the fix took effect and
that all prior SV `report_area`/`report_timing` output (any PDK, from
before this fix) reflected an unconstrained compile, not a real timing
result. VHDL variants were unaffected — `vhdl_clocks` was always correct.

### Resolved: SKY130 worst-case (ss_100C_1v60) timing, via a synthesis retune

Originally, synthesizing SKY130 to its typical (`tt_025C_1v80`) corner left
the worst-case `ss_100C_1v60` corner violating 100 MHz (WNS -2.850 ns,
TNS -121.360 ns across the 8 variants) when rechecked via PrimeTime STA —
expected for a netlist optimized only for the typical corner, not a tool
bug. **Fixed by retuning the synthesis settings** (`synth.tcl`):
`SKY130_SYNTH_CORNER` changed from `tt_025C_1v80` to `ss_100C_1v60` (now
synthesizing directly to the worst case), and `compile` upgraded to
`compile_ultra -no_autoungroup` with `synthetic_library dw_foundation.sldb`
(DesignWare-aware timing-driven mapping). Current SKY130 STA result:
`ss_100C_1v60` +1.39 ns MET, `tt_025C_1v80` +5.64 ns MET, `ff_n40C_1v95`
+7.23 ns MET — all three corners now close. A 0.5 ns synthesis-only
clock-uncertainty margin was also tried as part of this retune; it made
SAED90 worse (-0.99 ns) for no SKY130 benefit and was reverted.

The same `compile_ultra` retune applies to every PDK (shared `synth.tcl`),
which is what exposed the SAED90 issues below.

### Accepted: SAED90 fails timing at 100 MHz (WNS -0.40 ns), and its post-syn gate-level simulation is unreliable as a direct result

After the retune above, SAED90 — previously right at the edge even under
the old settings (WNS -0.01 ns) — now violates 100 MHz by **-0.40 ns**
(TNS -25.54 ns, worst path through `timer_ahb`/`timer_wb`; `timer_apb`/
`timer_axi4l` are right at +0.01 ns, essentially zero margin). SAED32
(+7.81 ns) and SAED14 (+4.92 ns) both meet timing comfortably.

**Decision (2026-10-03): accepted, not fixed, in the hope that a real
place-and-route flow would close it.** This project's DC flow is flat,
pre-layout synthesis with a generic wire-load model — no floorplan, no
clock-tree synthesis, no real placement-aware optimization — so a -0.40 ns
violation here does not necessarily mean a real, placed-and-routed SAED90
chip would also violate; a proper P&R flow (which this repo does not run)
would very plausibly close a margin this small. Options considered before
accepting: RTL pipelining of the long paths (through `timer_core`'s
`count_q` reset/next-value mux and `u_ahb_if/rd_wait_q` → `rd_en`'s
high-fanout read mux), or per-PDK compile settings favoring SAED90's
timing over its area. Not pursued for now — revisit if SAED90 needs to be
trusted for something beyond relative PDK comparison.

**Direct, confirmed consequence: SAED90 post-synthesis gate-level
simulation (`sim_timer.py --postsyn --pdk saed90`) does not produce
correct results, on any of the four protocols.** This was root-caused in
two layers, not guessed:

1. **A real bug, fixed:** the clock port (`PCLK`/`HCLK`/`ACLK`/`CLK_I`) was
   never marked `set_ideal_network` in `synth.tcl` — only the reset port
   was (see the sky130-era fix below). SAED90's wire-load model assigned
   it an absurd **6595.71 ns** interconnect delay in the SDF (vs `0.000 ns`
   for SAED32, `0.004 ns` for SAED14, `0.001 ns` for SKY130 — a
   SAED90-library-specific blowup, not a general issue). With
   `+notimingcheck` suppressing the violation, every flop's clock edge
   silently never arrived within any realistic simulation window.
   **Fixed:** `synth_variant` now also calls
   `set_ideal_network [get_ports $clk_port]`. Re-verified: SAED90's clock
   delay is now `0.000 ns`, and SAED32/SAED14/SKY130 (already ~0 before
   the fix) are unaffected — re-ran post-syn sim for all three and they
   still pass 4/4.
2. **Not a bug — the accepted timing violation above, surfacing as
   functional incorrectness instead of a reported violation.** With the
   clock fixed, `COUNT` reads back `X` on every protocol (confirmed by
   re-running the AHB post-syn compile with `+notimingcheck` *removed* —
   the normal flow always passes it, which is what hides this): VCS
   reports real `$setuphold` violations by name on
   `u_core/count_q_reg[3]/[7]/[11]` at reset release. `count_q`'s D-input
   logic (reset override combined with a 4-way load/restart/underflow/
   decrement priority mux feeding a subtractor) is evidently one of the
   longer combinational cones in the design. Under the normal
   `+notimingcheck` flow this doesn't get reported — VCS just captures
   whatever is on `D`, which is why it reads as `X` instead of a timing
   error. (An initial theory blamed `compile_ultra` register duplication
   instead; disproved by checking `all_registers` directly in `dc_shell`
   before compile, which showed `u_regfile/count_q` and `u_core/count_q`
   are two distinct, correctly-written RTL registers, not a synthesis
   artifact — `set_register_replication -replicate false` was tried and
   reverted since it didn't address the real cause.)

`sim_timer.py` tags this explicitly rather than reporting a bare `FAIL`:
`POSTSYN_KNOWN_FAILURES = {"saed90"}` prints a one-line pointer back to
this section and shows `FAIL (known)` in yellow in the results summary —
still a real failure (the exit code is unaffected), just not a mystery to
re-debug.

### Resolved: the sky130 PDK source install under `/tmp` was wiped, then reinstalled (2026-10-03)

While re-verifying all four PDKs after the clock fix above, `--dc` (and
`run_primetime_sta.py`) failed on SKY130 with the ASCII `.lib` files not
found under `/tmp/pet43490/PDK/volare/sky130/.../sky130A/`. The entire tree
was gone except one unrelated file — almost certainly routine `/tmp`
cleanup on this host, not anything this project did. Not a correctness
issue while it lasted: SKY130's compiled `.db` cache
(`IP/common/synthesis/designcompiler/sky130_lib/`) was untouched, and its
existing 2026-09-26 netlists/SDC/reports remained accurate (confirmed
their clock delay was already a negligible `0.001 ns`, unaffected by the
clock-port fix above).

**Fixed:** re-fetched via `volare fetch --pdk-root /tmp/pet43490/PDK --pdk
sky130 -l all <same pinned hash>`, then pointed `build_sky130_libs.SKY130_PDK`
at a new stable symlink, `/tmp/pet43490/PDK/sky130A` (so a future re-fetch
only means repointing the symlink, not a code change). One gotcha along
the way: volare only checks whether a library's directory already exists
at the target version, so the libraries left as empty-but-present
directories by the wipe — `sky130_fd_sc_hd` included, the one this project
needs — were silently skipped as "already found" on the first `fetch`
call; removing those specific empty directories and re-fetching picked
them up correctly. Full details, including the broken project venv this
also surfaced, in `.agents/reference_sky130_pdk.md`.

Re-verified end to end: `ensure_sky130_dbs(force=True)` recompiled all
three corners, and `--dcsky130` / `run_primetime_sta.py --sky130`
reproduced the identical cell count (737) and STA numbers (ss +1.39 ns, tt
+5.64 ns, ff +7.23 ns, all MET) as the pre-wipe 2026-09-26 run — the
re-fetched content is identical, as expected for a pinned version hash.

The same STA script also checks SAED90/32/14 against the single corner
each was synthesized to — all three meet 100 MHz (WNS = +0.000 ns saed90,
+7.260 ns saed32, +3.820 ns saed14). SAED90's +0.000 ns is genuinely tight
(exact 0.00 ns critical-path slack on `timer_axi4l` and `timer_wb`), not a
display rounding artifact.
