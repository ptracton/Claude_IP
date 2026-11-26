# sram — Lint Waivers

Every waiver is a SpyGlass pragma in the SV RTL (`//spyglass disable_block <rule>` …
`//spyglass enable_block <rule>`) around the lines named below; line numbers are those of the
`disable_block` line. The VHDL RTL has no SpyGlass path on csun.edu (`.agents/reference_spyglass_lint.md`).
On a standard host Verilator and GHDL lint the same code; their waivers are listed in
"Standard host: Verilator and GHDL" below (the Verilator ones live in
`verification/lint/verilator_waivers.vlt`, not in the RTL).

Configurations linted (`verification/tools/lint_sram.py --list`): every top with every option on
(ECC, BANK_PG x2, BIST, READ_LATENCY 2; dual port: WIDTH_B 8, separate clocks), plus single and dual
port APB on every PDK / FPGA technology; CDC on the four dual-port tops with separate clocks.
Unused logic of options that are switched off is not linted (user decision 2026-11-23), so none
of the waivers below is for a disabled option, except where a single-port top carries the core's
port B (W1).

## RTL waivers (design/rtl/verilog/)

### W1 — single-port tops: the core's port B is unused

`sram_core` and `sram_array` always have port B; a single-port top (`DUAL_PORT = 0`) ties its
inputs to 0, leaves its outputs open, and the core's `g_no_port_b` branch drives port B's
internal nets with constants. In dual-port configurations the same lines are used, so the
waivers hide nothing there (the dual-port projects lint the same code clean).

| File | Line | Rule | Item |
|---|---|---|---|
| `sram_core.sv` | 80 | W240 | `rst_b_n` |
| `sram_core.sv` | 98 | W240 | `mem_b_we_i`, `mem_b_addr_i`, `mem_b_be_i`, `mem_b_wdata_i` |
| `sram_core.sv` | 392 | W528 | `g_no_port_b` constant drivers of the port-B nets |
| `sram_core.sv` | 626 | W528 | `b_rdata` (array port-B read data) |
| `sram_array.sv` | 63 | W240 | `b_wdata_i`, `b_lane_we_i` |
| `sram_array.sv` | 165 | W528 | `b_saddr` |
| `sram_array.sv` | 170 | W528, FlopEConst | `p_b_rd_sel` port-B read-select flops (enable tied low) |
| `sram_array.sv` | 187 | W528 | `g_bank[].b_bank_cs` |
| `sram_array.sv` | 261 | W528 | `b_bank_rdata` of a single-port bank |
| `sram_ahb.sv` 143, `sram_apb.sv` 139, `sram_axi4l.sv` 155, `sram_wb.sv` 143 | | W287b | core outputs `mem_b_gnt_o`, `mem_b_rvalid_o`, `mem_b_rdata_o`, `mem_b_err_o` left open |

### W2 — signals one configuration family does not read

| File | Line | Rule | Item / justification |
|---|---|---|---|
| `sram_core.sv` | 334 | W528 | `b_quiet`, `b_wake_a` in `g_sync` (COMMON_CLK = 1): read only by the separate-clock view |
| `sram_core.sv` | 372 | W528 | `b_idle` (read only with COMMON_CLK = 1; separate clocks use `b_quiet`) and `b_acc` (port B's copy of `sram_port.acc_o`; only port A's drives the same-word yield) |
| `sram_core.sv` | 463 | W528 | `dom_want`: input of `sram_cdc`, which exists only with separate clocks |
| `sram_core.sv` | 515 | W528 | `clr_busy`: not read by the RTL; observed by the formal checker `sram_core_fv` (`a_eng_exclusive`, `a_eng_no_grant_a`, port-B engine covers) |
| `sram_array.sv` | 135 | W528 | `a_rd_slice_q`: read only when port A is narrower than port B (slices) |
| `sram_macro_dp_saed14.sv` | 48 | W240 | `b_clk`: SAED14 SRAM2RW has one write clock (COMMON_CLK = 1 required), port B uses `a_clk` |
| `sram_macro_dp_sky130.sv` | 43 | W240 | `b_we_i`, `b_wdata_i`, `b_lane_we_i`: SKY130 OpenRAM port 1 is read-only |

### W3 — uniform leaf interface: power pins a macro family does not have

Every `sram_macro[_dp]_<tech>` has the same ports (plan §11.3); only SAED32 `sram_lp` has LS / DS / SD
pins, the others are power-gated through UPF (`ls_i`, `ds_i`, `sd_i` unused; GENERIC uses `sd_i`
for its simulation-only content loss).

| File | Line | Rule |
|---|---|---|
| `sram_macro_generic.sv` | 31 | W240 |
| `sram_macro_dp_generic.sv` | 37 | W240 |
| `sram_macro_saed90.sv` | 38 | W240 |
| `sram_macro_dp_saed90.sv` | 50 | W240 |
| `sram_macro_saed14.sv` | 43 | W240 |
| `sram_macro_dp_saed14.sv` | 59 | W240 |
| `sram_macro_sky130.sv` | 45 | W240 |
| `sram_macro_dp_sky130.sv` | 53 | W240 |
| `sram_macro_altera.sv` | 31 | W240 |
| `sram_macro_dp_altera.sv` | 38 | W240 |

### W4 — vendor primitive outputs not used

| File | Line | Rule | Item |
|---|---|---|---|
| `sram_macro_xilinx.sv` | 73 | W287b | `sbiterra`, `dbiterra` (XPM ECC off; the sram has its own SECDED) |
| `sram_macro_dp_xilinx.sv` | 96 | W287b | `sbiterra/b`, `dbiterra/b` |
| `sram_macro_sky130.sv` | 129, 147, 165 | W287b | `dout1`: single port uses only the 1rw port of the 1rw1r macro |
| `sram_macro_altera.sv` | 63 | W287a, W287b, TFIPC | `altsyncram` in SINGLE_PORT mode: only the ports that mode uses are connected (port-B ports have defaults in altera_mf; documented deviation in the file) |

### W5 — documented style deviations

| File | Line | Rule | Justification |
|---|---|---|---|
| all tops, `sram_core`, `sram_array`, `sram_macro`, `sram_macro_dp`, GENERIC / XILINX / ALTERA leaves | INIT_FILE parameter | VC_SYNTH_STRING | `parameter INIT_FILE` (untyped since Step 10: Design Compiler rejects `parameter string`, VER-700) with a string value: preload file name for `$readmemh` (GENERIC) and the vendor init attributes (XPM, altsyncram); the PDK flows leave it "" (14 tops/blocks + 6 leaves) |
| `sram_macro_generic.sv` | 45 | SM_IGN_INITIAL | `initial $readmemh(INIT_FILE)` preload: simulation and FPGA inference only, empty for ASIC |
| `sram_macro_dp_generic.sv` | 50 | SM_IGN_INITIAL | same |
| `sram_macro_generic.sv` | 66 | W528 | `sd_q`: read only inside `synopsys translate_off` (simulation-only content loss at shutdown) |
| `sram_macro_dp_generic.sv` | 75 | W528 | same |
| `sram_macro_dp_generic.sv` | 95 | W415 | the dual-clock true dual-port RAM template: both ports write `mem` from their own clocks (plain `always`, documented in the file; plan §5 Step 8) |
| `sram_clr.sv` | 128 | W415a | `p_pending`: default assignment then overrides in one `always_comb` (intended priority: clear on `start_pass`) |

### W6 — CDC (SpyGlass cdc_verify_struct, separate clocks)

Every crossing is registered in its source domain and goes through `claude_sync` /
`claude_pulse_sync` or the dual-clock RAM (24 synchronized crossings, no unsynchronized one).
The convergence warnings are bits of one multi-bit `claude_sync` (`u_sync_to_a`,
`u_sync_to_b` in `sram_cdc`) meeting in logic. Each bit is an independent per-domain level of
the four-phase permission handshake (hold, wake, err, busy) — no multi-bit value is decoded — so
skew between bits only delays a decision by a cycle. The handshake is proven by VC Formal job
`dp_async` (SV and VHDL, Step 5).

| File | Line | Rule | Convergence |
|---|---|---|---|
| `sram_core.sv` | 434 | Ac_conv02 | `port_idle = a_idle && (&b_quiet)` |
| `sram_core.sv` | 631 | Ac_conv01 | `busy_o` (status output, OR of busy terms) |
| `sram_pwr_ctrl.sv` | 81 | Ac_conv02 | `idle_i` (port quiet) with the wake request in the RUN state |
| `sram_port.sv` | 72 | Ac_conv02 | port B `wake_o` from the synchronized awake / err bits |
| `sram_ahb_dp.sv` | 62 | Ar_syncrst_setupcheck01 | at `B_HRESETn` deassertion `claude_ahb_mem_if.dp_mask_q` has a constant D of 1: with an 8-bit port B there is one lane, so the lane mask is always 1; the reset value 0 is overwritten by the first address phase |

## IP/common (shared adapters)

| File | Line | Rule | Justification |
|---|---|---|---|
| `IP/common/design/rtl/verilog/claude_apb_mem_if.sv` | 42 | W240 | `PENABLE` unused (Step 0; see `IP/common/verification/mem_if/`) |

## Filtered tool messages (not waivers)

`lint_sram.py` drops rows that appear on every run regardless of the RTL: COM_OPT009 / COM_OPT010
(no search_path / link_library: RTL-only, full paths), PrjToTclSummary "Skipped option", "Please
refer …" pointer rows, the vendor-cell stub bookkeeping (InfoAnalyzeBBox, SM_BB_USER,
UNMATCHED_BBNAME), and in CDC runs Setup_clockreset01 "'Resets' have not been specified"
(SpyGlass counts only asynchronous resets; the SGDC declares the IP's synchronous resets with
`-sync`).

### CDC report filter

In CDC runs only the info rules below are dropped (`_CDC_INFO_RULES` in `lint_sram.py`, reviewed
2026-11-23 on the four `*_dp_cdc` reports). Any other CDC row, info or not, is a finding until it
is reviewed and added here.

| Rule | Per run | Content |
|---|---|---|
| Ac_sync02 | 24 | Synchronized crossings: 8 through `claude_sync` (`sram_cdc` handshake `u_sync_to_a` / `u_sync_to_b`, corr / uncorr / irq flags), 16 dual-clock RAM reads (`sram_macro_dp_generic` `a_rdata_o` / `b_rdata_o` from `mem`, method "Recirculation flop": the read register loads only when enabled; same-word collisions are the core's arbitration, covered by simulation and formal `dp_async`) |
| Setup_port01 | 22–27 | Port constraint coverage: 0 ports not fully constrained |
| Reset_info01 | 7–31 | Candidate synchronous set / clear signals (reset pins and derived terms) |
| Clock_info03b | 3–7 | Flops with a constant D, e.g. `claude_axi4l_mem_if` `bresp_q[0]` / `rresp_q[0]` (only OKAY / SLVERR) |
| Propagate_Clocks | 2 | SGDC clocks `A_*` / `B_*` propagated |
| Clock_info01 | 1 | Pointer to the inferred-clock report |
| Reset_check12 | 1 | No asynchronous reset in the SGDC (the IP has none) |

The structural checks (Ac_unsync01/02, Ac_conv01–04, Ac_glitch03, Ac_sync01, Ar_sync01,
Ar_unsync01, Clock_sync05/06) report 0 in every run; the Ac_conv rows are 0 because of the W6
pragmas.

## Standard host: Verilator and GHDL (2026-11-25)

`lint_sram.py` on a standard host lints the same 20 SV configurations with Verilator
`--lint-only -Wall` and analyses every VHDL file with `ghdl -a --std=08`. The SpyGlass pragmas
above are not read by Verilator, so its waivers are kept **outside the RTL**, in
`verification/lint/verilator_waivers.vlt` (passed after `verilator.flags`): the RTL signed off
on csun.edu is not touched. Each entry names the file, the rule and the signal (`-match` on
the message), so a new finding on another signal is still reported. Result: 20/20 SV
configurations clean, 41/41 VHDL files clean (CDC is SpyGlass-only, SKIPPED).

| Class | Verilator rule | Items (all in `design/rtl/verilog/` unless noted) |
|---|---|---|
| stubs | all | the port-only vendor-cell stubs (`verification/lint/stubs/`, `verification/work/lint_stubs/`): black boxes, not linted |
| W1 | UNUSEDSIGNAL, PINCONNECTEMPTY | `sram_core` port B inputs / `rst_b_n` and the `g_no_port_b` constants (`b_busy`, `b_stall`, `b_ecc_corr`, `b_ecc_uncorr`, `b_irq`, `b_rdata`, `b_dom_awake`, `b_dom_err`); `sram_array` `b_wdata_i`, `b_lane_we_i`, `b_saddr`, `b_bank_cs`; the four single-port tops' open `mem_b_*` outputs |
| W2 | UNUSEDSIGNAL | `sram_core` `b_quiet`, `b_wake_a`, `b_idle`, `b_acc`, `dom_want`, `clr_busy`; `sram_array` `a_rd_slice_q` and its port-B twin `b_rd_slice_q` (read only when port B is the narrower port); `sram_macro_dp_saed14` `b_clk`; `sram_port` `mem_addr_i[1:0]` (byte address bits: words are addressed, lanes come from `mem_be_i`; SpyGlass does not report part-selects); `IP/common/.../claude_ahb_mem_if.sv` `HTRANS[0]` (SEQ / NONSEQ need no distinction: every beat is one memory request) |
| W4 | PINCONNECTEMPTY, PINMISSING | XPM `sbiterr*` / `dbiterr*`, SKY130 `dout1`, `altsyncram` `q_b` in SINGLE_PORT mode |
| W5 | WIDTHEXPAND, MULTIDRIVEN | the untyped `INIT_FILE` `"" -> "none" / "UNUSED"` substitution in the XPM / altsyncram leaves (string literals of different lengths); the dual-clock RAM template's two writing processes (`sram_macro_dp_generic` `mem`) |

GHDL waivers (`_GHDL_WAIVERS` in `lint_sram.py`; only the matching diagnostic is dropped):

| Class | File | Diagnostic | Justification |
|---|---|---|---|
| W5 | `sram_macro_dp_generic.vhd` | `type of a shared variable must be a protected type` (analysed with `-frelaxed`, which makes the VHDL-2008 error a warning) | the dual-clock RAM template is a plain shared variable, the documented deviation above (Vivado / Quartus infer block RAM from it; a protected type would not be inferred). Yosys' ghdl plugin needs the same `-frelaxed` (`run_vendor_synth.py --yosys`). |
| W7 | `sram_macro_altera.vhd`, `sram_macro_dp_altera.vhd` | `declaration of "w" / "nlanes" hides generic` (`-Whide`) | `byte_size_of(w, nlanes)` is only called with the generics of the same name |

Negative check (2026-11-25): an unread `logic` added to `sram_core.sv` and to `sram_array.sv`
in a copy of the tree is reported (`UNUSEDSIGNAL`, configuration FAIL). Note that Verilator
ignores signals whose name matches its default `--unused-regexp` (`*unused*`).

## Testbench waivers (verification/)

None.
