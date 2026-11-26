# sram Synthesis — Known Issues

## Design Compiler (csun.edu)

Configurations synthesized (24 netlists per PDK, `designcompiler/synth.tcl`):

| Config | Tops | Parameters |
|--------|------|------------|
| `base` | `sram_<proto>` | WIDTH 32, DEPTH 1024, BYTE_EN, PWR_GATE (RTL defaults) |
| `opts` | `sram_<proto>` | base + ECC_EN, BANK_PG (2 banks), BIST_EN, READ_LATENCY 2 |
| `dp`   | `sram_<proto>_dp` | opts + WIDTH_B 8, COMMON_CLK 0 (SAED14: COMMON_CLK 1) |

100 MHz on each bus clock; 30 % of the period (3 ns) budgeted outside the IP
on every port; port B pins of `dp` are timed on `clk_b`, asynchronous to
`clk_a`.

### 0.2 ns synthesis setup margin (user decision 2026-11-25)

The first PrimeTime run (below) failed 5 SKY130 `opts` netlists at the SS
corner by -0.001 to -0.027 ns on the ECC write-back path (`rd_q` -> decode
-> merge -> encode -> macro data, about 10 ns), which DC had met by +0.00 to
+0.02 ns: PrimeTime's delay calculation is about 0.03 ns more pessimistic.
`synth.tcl` now compiles with `set_clock_uncertainty -setup 0.2` on every
clock, set after `write_sdc`: DC over-constrains, while PrimeTime and
post-synthesis simulation check the unmodified constraints. DC's WNS in
`report_<pdk>.txt` includes the margin.

## PrimeTime STA (csun.edu)

Results 2026-11-25 (margin netlists): SAED32, SAED14 and SKY130 SS / TT / FF
24/24 setup and hold met; worst setup slack SAED32 +3.53, SAED14 +0.42,
SKY130 SS +0.18, TT +1.28, FF +1.42 ns; worst hold slack +0.06 (SAED32).
SAED90 2/24 (accepted, above). PrimeTime matches DC's slack (DC WNS minus
the 0.2 ns margin) to within 0.005 ns on every SAED netlist.

`run_primetime_sta.py` analyses all 24 netlists per target with
`primetime/sta.tcl`: SAED90 / SAED32 / SAED14 at the corner synthesis used
(standard cells and SRAM macros), SKY130 at ss_100C_1v60, tt_025C_1v80 and
ff_n40C_1v95 (macros at TT, see below). Ideal clocks, no parasitics: each
netlist uses the wire-load model DC chose for it (read from DC's timing
report, because `synth.tcl` picks it after writing the `.sdc`). PASS = setup
and hold met; SAED90 is the accepted setup failure above.

Design-rule rows in `report_constraint` are not part of PASS (as timer and
bus_matrix). Almost all are vendor limits on the SRAM macro pins: SAED32
read-data `max_capacitance` 0.025 (the same inconsistent value as its
`min_capacitance`, see the patched liberty below), SAED90 / SKY130 read-data
`min_capacitance`, SKY130 OpenRAM `max_transition` 0.04 ns on address and
chip-select pins. They are left to physical design (buffering at placement).

### Accepted: SAED90 does not meet 100 MHz (2/24 MET), user decision 2026-11-25

SAED32, SAED14 and SKY130 meet timing on all 24 netlists. SAED90 does not
(PrimeTime slack against the real 10 ns, 2026-11-25, netlists compiled with
the 0.2 ns margin, after the RMW / READ_LATENCY 2 change below):

| Config | WNS | Limiting paths |
|--------|-----|----------------|
| `base` (APB/AHB/WB, SV + VHDL) | -0.20 ns | macro read (CE -> O about 7 ns) straight to the bus read data at READ_LATENCY 1: no cycle to spare in RTL. AXI4-Lite registers its read response and meets (+0.09 / +0.01 ns) |
| `opts` | -0.79 to -1.33 ns | spread over many paths into and out of the 90 nm macros: BIST compare (macro -> fail index), ECC RMW write-back (rd_q -> decode -> merge -> encode -> macro data, about 12 ns), power control and clear engine -> macro controls, read data -> bus |
| `dp` APB/AHB/WB | -0.90 to -1.40 ns | same as `opts` |
| `dp` AXI4-Lite | -42.4 ns (SV), -35.0 ns (VHDL) | its logic area (about 37,000) crosses into the "70000" wire-load model, which charges each net several ns; the other `dp` variants (about 27,000) get "35000". An estimate artefact of the wire-load table, not a logic path |

The RTL change below improved `opts` from -6.5 to -7.2 ns and `dp` from
-3.2 to -3.6 ns; closing the rest needs more pipelining (registered BIST
compare, a third RMW stage), which adds latency, so SAED90 is accepted as a
known failure at 100 MHz, as the timer IP accepted its SAED90 result. STA and
post-synthesis simulation treat SAED90 the same way.

### RTL: ECC read-modify-write registered, READ_LATENCY 2 register moved (2026-11-24, user approved)

The first SAED90 / SKY130 runs failed on the read-modify-write path (macro
read -> decode -> merge -> encode -> macro write in one cycle). `sram_port`
now registers the raw read word (`rd_q`, stage s2) and decodes it in the
next cycle; READ_LATENCY 2 uses the same register in front of the decoder.
A byte-enable write under ECC is one cycle longer, so its read-back response
comes one cycle later (the mem bus allows variable latency). SKY130 `opts`
went from -0.8 to -0.95 ns to MET. Re-verified: Step 4 80/80, UVM 1440/1440,
formal 26/26 jobs (see the plan, §18).

### SAED wire-load model chosen from the logic area, not the total area

The SAED libraries select a wire-load model from each design's cell area
(`wire_load_from_area`). The SRAM macros dominate that area — 32 x 1024 is
about 580,000 on SAED90 against about 3,400 of logic — so DC picked the
largest model ("1000000") and charged a single NAND2 net 12 ns of wire
delay (SAED90 `sram_apb`: -9.31 ns). Macro area is not routing area of the
logic between the macros, so `synth.tcl` now uses one model for every net
(`set_wire_load_mode top`) and picks it after the first compile from the
cell area without the macros, using the library's own table (the model
names are their upper area bound). SKY130 has a single model ("Small", top
mode) and is unchanged.

This changes the estimate, not the design (the bus_matrix declined such a
change for its own SAED90 paths, which were genuine logic-area nets). The
chosen model is printed in each run log (`Wire-load model: ...`).

### SAED32: patched copy of the low-power SRAM liberty

The EDK's `lib/sram_lp/db_nldm/saed32sramlp_<corner>` liberty has no `SD`,
`LS`, `DS` (single port) / `SD`, `LS1`, `LS2`, `DS1`, `DS2` (two port) pins,
although the vendor LEF and Verilog model have them and the SRAM IP drives
them (power modes). DC failed to link (LINK-1). The current lc_shell also
rejects the vendor .lib itself (53 x LBDB-596 `min_capacitance` 0.1 >
`max_capacitance` 0.025 on the read-data buses, 53 x `internal_power`
without `related_pin`); the shipped .db came from an older Library Compiler.

`IP/common/synthesis/designcompiler/build_saed32_sram_libs.py` writes a
copy (vendor files untouched, cached in `saed32_lib/`) that (user approved
2026-11-24):
- adds the missing pins to all 35 SRAMLP cells as plain inputs (capacitance
  of the cell's CSB / CSB1, no timing or power arcs);
- drops the inconsistent `min_capacitance` on O / O1 / O2 (a design-rule
  limit, no timing);
- relates the read-data `internal_power` groups to CE / CE1 / CE2.
No timing value is changed (checked by diffing the .lib). Consequence: STA
treats SD / LS / DS as unconstrained inputs — their setup to CE is not
characterized in the EDK. The IP changes them only while the macro is
deselected (`sram_pwr_ctrl` enter/wake sequencing), which is what the
databook requires.

### SKY130 SRAM macros exist only at TT 1.8 V 25 C

The OpenRAM macros in `sky130_sram_macros` ship one liberty corner. DC links
the TT macro .db with the SS 1.60 V 100 C standard cells; STA at SS and FF
uses the same TT macro timing, so SKY130 SS/FF results are approximate for
every path that starts or ends at a macro pin (user decision 2026-11-24).
The .lib files are compiled to .db by
`IP/common/synthesis/designcompiler/build_sky130_libs.py`
(`ensure_sky130_sram_dbs`).

### RTL adjusted for Design Compiler (2026-11-24, user approved)

- SV: `parameter string INIT_FILE` is rejected (VER-700); it is now an
  untyped `parameter INIT_FILE`, and the XPM / altsyncram leaves use untyped
  localparams. Side effect for FPGA: `cond ? "none" : INIT_FILE` pads a file
  name shorter than "none" / "UNUSED" with leading NULs — no bench uses
  INIT_FILE; check on the standard host when preload is first used.
- VHDL: DC Y-2026.03-SP1 parses only part of VHDL-2008. The RTL was
  rewritten to VHDL-93 forms (separate if-generates instead of
  else/elsif generate, `red_xor`/`red_or`/`red_and`/`max_nat`/`pick` in
  `sram_pkg.vhd`, "same as port A" generic defaults as sentinels, no
  function calls in port maps, no `?=` on vectors). The GENERIC leaf's
  INIT_FILE loader is simulation-only (`-- pragma translate_off`). Verified
  on csun with DC, VCS and Xcelium; GHDL, Vivado and Quartus still to be run
  on the standard host.

## Post-synthesis (gate-level) simulation (csun.edu)

`verification/tools/sim_sram.py --postsyn` simulates the three netlists of
each bus (base, opts, dp) together in `tb_sram_<proto>` with
`+define+SRAM_POSTSYN` (`verification/testbench/sram_tb_postsyn_body.svh`):
the system bench cannot drive netlists (its reference models probe the
memory bus inside each top, and none of its instances has a synthesized
configuration). Same masters and wiring macros; every read is checked
against a shadow memory; access, sub-word / RMW, bursts, range errors, ECC
injection, power modes per domain, clear, BIST, dual-port width conversion
and concurrent ports (2448 checks per run). DC's SDF on every netlist, VCS
`+notimingcheck` (timing is PrimeTime's), the vendor SRAM models and the
standard-cell models. Each netlist's sub-modules are renamed per instance
in a work copy (DC names sub-designs by parameters, so two netlists can
define the same name differently).

Results 2026-11-25: SAED32, SAED14, SKY130 16 + 8 = 24/24 PASS (4 buses x
SV- and VHDL-synthesized netlists); SAED90 8/8 KNOWN (fails with SDF, passes
with `--no-sdf`, see below).

### SKY130 OpenRAM model: read delay from the liberty at gate level

The vendor model drives `dout0` `DELAY = 3` ns after the falling clock edge
("FIXME: This delay is arbitrary"), so at 100 MHz the read data is valid
only 2 ns before the next rising edge. With SDF on the logic behind it, the
BIST compare (the longest path from the macro) sampled X (`bist_fail_o` X,
5 / 8 runs). The liberty times `dout0` 0.36-0.51 ns after the falling edge.
`pdk_sram_models.model_files(..., gate_level=True)` sets `DELAY` to
`SKY130_GL_DELAY` = 0.6 ns in its generated copy; RTL simulation keeps the
model as shipped (apart from the declaration fix).

### SAED90 standard cells: synchronous set/reset flip-flops simulated wrongly

The SAED90 Verilog models of DFFSSRX1/X2 and SDFFSSRX1/X2 give reset
priority over set, while their liberty (`next_state : (RSTB*D)+(!SETB)`)
gives set priority; DC maps logic by the liberty. `sram_axi4l_dp_vhdl`
uses this on the port-A AXI interface's `sel_write_q`: in simulation the
write response was taken for a read response and the write re-issued
forever, even with zero delay. `IP/common/verification/tools/
pdk_cell_models.py` writes a copy of `saed90nm.v` with the liberty's
next-state function for those four cells (vendor file untouched); the
post-synthesis runner compiles it. With it all 8 SAED90 runs pass with
`--no-sdf` (`+delay_mode_zero`), so the remaining SAED90 failures with SDF
are the accepted timing violations (opts / dp: the clear after reset never
finishes, the bus times out). The timer and bus_matrix post-synthesis flows
compile the vendor `saed90nm.v`; their netlists were not checked for these
cells.

## Power analysis (PrimePower, Step 12)

### SAED32-LP SRAM liberty: negative macro internal power

The vendor `saed32sramlp_<corner>.lib` (the shipped `.lib`, not changed by
`build_saed32_sram_libs.py`) characterizes the input pins' internal power
(CSB, WEB, A, I) with large negative values (`rise_power` down to about
-2700 per transition at TT 1.05 V 25 C) and gives the macros no leakage.
PrimePower then reports negative memory power (e.g. -2.1 mW for the opts
netlist), which would cancel the logic. `sim_sram.py --power` flags a
negative macro share as "invalid" and reports only the logic power for
SAED32; no number is invented for the macros.

### Macro clocks are free-running

Every macro liberty here charges internal energy on each clock rise whether
the macro is selected or not, and the leaves connect the macro clocks to the
bus clock, so the macros' clock power (> 95 % of the total on SAED14 /
SKY130) is spent even when the SRAM is idle or a bank is asleep. Clock gating
per bank is a possible improvement (not done; the power modes gate the chip
select only).

### DC's `.sdc` and the typical-corner libraries

The `.sdc` names the synthesis-corner library on its `set_wire_load_model`
line (SAED), which the typical-corner power run does not load (SEL-005, and
no wire load). The power script drops that line and applies DC's per-netlist
model by name from the typical library (as STA does).

## Vivado / Quartus / Yosys (standard host)

`run_vendor_synth.py --vivado / --quartus / --yosys` synthesize the same 24
variants (TECH = XILINX / ALTERA / GENERIC). They have not been run yet:
none of these tools is installed on csun. A variant fails unless the array
maps to block RAM (Vivado: Block RAM Tile > 0; Quartus: block memory bits
> 0; Yosys: a `$mem` cell).
