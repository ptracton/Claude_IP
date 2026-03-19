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
