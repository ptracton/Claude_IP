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

### Finding: timer fails timing at the SKY130 worst-case (ss_100C_1v60) corner

PrimeTime STA (`synthesis/run_primetime_sta.py` + `synthesis/primetime/`,
see `.agents/reference_primetime_sta.md`) — a script separate from DC
synthesis, run afterward — runs the SKY130 gate-level netlists (synthesized
to the `tt_025C_1v80` typical corner) through all three SKY130 PVT corners.
At the worst-case `ss_100C_1v60` corner, the design **does not** meet the
100 MHz (10 ns) target: worst-case WNS = -2.850 ns, TNS = -121.360 ns
across the 8 variants. `tt_025C_1v80` (WNS = +3.250 ns) and `ff_n40C_1v95`
(WNS = +5.660 ns) both meet timing. This is expected for a design
synthesized to the typical corner without multi-corner optimization — it
is a genuine timing result, not a tool or script issue, and is not the
SDF/`set_ideal_network` reset-net issue documented for gate-level
simulation elsewhere. Re-synthesizing with `ss_100C_1v60` as the DC target
(or with multi-corner DC optimization) would be the next step if
worst-case timing closure is required; out of scope for this pass, which
focuses on getting the multi-corner STA capability in place.

The same STA script also checks SAED90/32/14 against the single corner
each was synthesized to — all three meet 100 MHz (WNS = +0.000 ns saed90,
+7.260 ns saed32, +3.820 ns saed14). SAED90's +0.000 ns is genuinely tight
(exact 0.00 ns critical-path slack on `timer_axi4l` and `timer_wb`), not a
display rounding artifact.
