# bus_matrix Synthesis — Known Issues

## Design Compiler / PrimeTime STA (csun.edu)

Configuration synthesized: the `bus_matrix_pkg` defaults (2 masters, 4
slaves, round robin), 100 MHz, 30 % of the period budgeted outside the
matrix on each side of every port (`IO_DELAY` in `designcompiler/synth.tcl`).

### Accepted: SAED90 fails timing at 100 MHz (worst WNS -0.56 ns)

| Variant | SAED90 setup WNS (ns) |
|---------|-----------------------|
| `bus_matrix_apb`        | -0.56 |
| `bus_matrix_ahb`        | -0.20 |
| `bus_matrix_axi4l`      | -0.44 |
| `bus_matrix_wb`         | +0.00 |
| `bus_matrix_apb_vhdl`   | -0.54 |
| `bus_matrix_ahb_vhdl`   | -0.40 |
| `bus_matrix_axi4l_vhdl` | +0.01 |
| `bus_matrix_wb_vhdl`    | -0.46 |

PrimeTime agrees with DC. SAED32, SAED14 and all three SKY130 corners meet
timing with at least +1.83 ns of setup slack; hold slack is positive on
every target.

**Cause.** The failing paths start at an arbiter's registered grant and go
through the slave routing mux (the owner's 69-bit `{we, be, wdata, addr}`)
or the read-data return mux to an output port. Under SAED90's wire-load
models a net's wire delay grows much faster than its fan-out (measured in
PrimeTime on the original netlist: ~0.3 ns at fan-out 2, 2.4–2.9 ns at
fan-out 5–7), so every buffer level in the grant's fan-out tree costs
2.5–3 ns. No other PDK's wire-load model behaves like this.

**What was done (2026-10-10):**
1. `synth.tcl`: `set_cost_priority -delay` (DC's default lets design-rule
   fixing outrank delay, which left the timing-critical sinks at the
   leaves of the grant's buffer tree), `set_max_fanout 16`, and a second
   `compile_ultra -incremental` pass. `-timing_high_effort_script` was
   tried and is ignored by this DC version (OPT-1342).
2. RTL: `slv_req` is driven from the registered grant alone instead of
   `grant & request`. The owner holds its request until done and the grant
   clears on the done edge, so this is equivalent (formally checked by
   `a_route` in `bus_matrix_core_fv`), and it removes the address decoder
   and `mst_req` from the slave-request paths.

Together these took SAED90 from -1.25 ns (5/8 variants failing) to
-0.56 ns, and raised SKY130's worst-corner slack from +0.84 to +2.54 ns.

**Decision (2026-10-10): accepted.** Closing the rest needs registering the
slave-side request fields (+276 flops, about 2x area) and probably the
read-data return path (+1 cycle per read). This is not worth it for a
pre-layout wire-load artefact on the oldest PDK. Options considered and not
taken: those two RTL changes; duplicating the grant flops (shorter nets
still cost ~0.3 ns per level and DC tends to merge them); and changing the
wire-load mode (that would change the estimate rather than the design).

**Gate-level simulation is not affected:** SAED90 post-synthesis simulation
passes all 4 protocols (82/82 checks each). The violating paths end at
output ports against an assumed 3 ns external budget. The testbench's
slaves capture those ports directly into flops with no logic in between,
so they get almost the whole 10 ns period rather than 7 ns, and the
violation never turns into wrong data in simulation. The timer's SAED90
violation was reg-to-reg and did.

### Open: SAED32 max_capacitance violations

PrimeTime's `report_constraint -all_violators` lists about 20
`max_capacitance` violators per SAED32 variant (168 in total). They are
inside `u_core` and the arbiters, on the same high-fan-out grant/select
nets, with 19.7 fF actual against a 16 fF limit. Setup and hold are met
with large margin (+3.58 ns / +0.22 ns worst) and gate-level simulation
passes. The count was the same (178) before the `set_cost_priority -delay`
change, so that change did not cause them. Not fixed yet. SAED90, SAED14
and all SKY130 corners have no design-rule violations.

### Fixed: SAED32 gate-level simulation timed out at 10 ns

The SV testbench files had no `` `timescale `` directive. In the gate-level
build they come after the SAED32 cell models, so they inherited a cell
model's `` `timescale 1ps/1ps ``. That made the testbench clock 1000x too
fast, and the BFM's 1000-cycle timeout fired after 10 ns. Fixed by adding
`` `timescale 1ns / 1ps `` to every SV testbench file
(`tb_bus_matrix_*.sv`, `bus_matrix_*_bfm.sv`, `bus_matrix_tb_mem.sv`),
the same directive the timer's testbenches carry.

### Fixed: PrimeTime summary reported hold slack as WNS

`run_primetime_sta.py` took the minimum `Critical Path Slack` over every
`report_qor` section, which includes the `min_delay/hold` groups. On every
target except SAED90 the "WNS" column was therefore the hold slack. The
summary now reports setup WNS, hold WNS and the `report_constraint`
violator count separately.

## Other tools

Yosys, Vivado and Quartus have not been re-run since the 2026-10-09 RTL
redesign. They run on standard hosts only, and their scripts still list the
old file set.
