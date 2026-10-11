# bus_matrix — VC Formal verification

Formal property verification of the bus matrix with **Synopsys VC Formal**
(FPV). It runs ten proof jobs:
- all four bus top-levels (`bus_matrix_apb`, `bus_matrix_ahb`,
  `bus_matrix_axi4l`, `bus_matrix_wb`) in **both SystemVerilog and VHDL-2008**;
- a stand-alone arbiter harness, in both languages.

The bus-protocol checkers, the Tcl run script and the Python driver are shared
IP components, documented in
[`$IP_COMMON_PATH/verification/formal/README.md`](../../../../../common/verification/formal/README.md).
This directory holds only what is specific to the bus matrix.

## Running

```bash
source IP/interface/bus_matrix/setup.sh
python3 $CLAUDE_BUS_MATRIX_PATH/verification/tools/formal_bus_matrix.py --tool vcf                 # all 10 jobs
python3 $CLAUDE_BUS_MATRIX_PATH/verification/tools/formal_bus_matrix.py --tool vcf --proto ahb --lang vhdl
python3 $CLAUDE_BUS_MATRIX_PATH/verification/tools/formal_bus_matrix.py --tool vcf --proto arb     # arbiter harness only
python3 $CLAUDE_BUS_MATRIX_PATH/verification/tools/formal_bus_matrix.py --tool vcf --trace         # FSDB per failure
```

With `--tool auto` (the default), VC Formal is used when `vcf` is on `PATH`
(csun.edu), and SymbiYosys otherwise. `run_regression.py` makes the same
choice and collects each job's result as `formal/vcf/<top>_<lang>`.

| Output | Location |
|--------|----------|
| Summary (PASS/FAIL, per-job counts, failures, waivers) | `verification/formal/vcf/results.log` |
| Per-job run directory (`vcf.log`, `report_fv.txt`, `results.log`, `traces/`) | `verification/work/vcf/<top>_<lang>/` |

The default time budget is 30 minutes per job and 3 hours for the AXI4-Lite
jobs; `--max-time` overrides both.

## Configuration

The top-level jobs check the default, synthesized configuration from
`bus_matrix_pkg`: 2 masters, 4 slaves, round robin, and the real address map.
VHDL generics are not visible to an SV `bind` (`NUM_MASTERS` arrives as 0).
So before every run `formal_bus_matrix.py` generates `bus_matrix_fv_cfg.svh`
from `bus_matrix_pkg.sv`, and the bind modules pass that configuration as
literals. Both arbitration modes, with 4 masters, are covered by the
arbiter harness.

## Files

| File | Bound to | Contents |
|------|----------|----------|
| `bus_matrix_<proto>_fv.sv` | `bus_matrix_<proto>` | common `claude_<proto>_fv` on every master port (matrix = slave) and every slave port (matrix = master, `MASTER_IS_ENV=0`), plus end-to-end checks |
| `bus_matrix_<proto>_fv_bind.sv` | — | bind-only module: binds the top-level, core and arbiter checkers |
| `bus_matrix_block_binds.svh` | — | binds shared by all four tops (`bus_matrix_core`, every `bus_matrix_arb`) |
| `bus_matrix_core_fv.sv` | `bus_matrix_core` | routing, decode-error and response properties |
| `bus_matrix_arb_fv.sv` | `bus_matrix_arb` | grant properties, both arbitration modes |
| `bus_matrix_arb_fv_top.sv` / `.vhd` | — | arbiter harness: a fixed-priority and a round-robin arbiter with 4 masters and free inputs |
| `bus_matrix_arb_fv_top_bind.sv` | — | binds `bus_matrix_arb_fv` into the harness |
| `bus_matrix_fv_cfg.svh` | — | generated configuration (do not edit) |
| `bus_matrix_fv_waivers.txt` | — | waived results with justifications |

The checkers use only the ports of the block they are bound to, so the SV
and VHDL builds get identical checks.

## What is proven

**Bus protocol** (shared checkers, every port of every top-level):
- On each master port, the solver is an unconstrained but legal master, and
  the matrix must obey every slave rule of its protocol. It must also answer
  within `M_WAIT` = 64 cycles.
- On each slave port, the solver is a legal slave that answers within
  `S_WAIT` = 4 cycles, and the matrix must obey every master rule.

**End to end** (`bus_matrix_<proto>_fv`):
- `a_e2e_write`: a write that completes at slave `j` was in progress at some
  master with the same word address, data and strobes.
- `a_slv_region_wr` / `a_slv_region_rd`: slave `j` only completes transfers
  inside its own region, so decode errors never reach a slave.

**Core** (`bus_matrix_core_fv`):
- `a_route`: a slave request carries the fields of a requesting master whose
  address decodes to that slave. This also proves the invariant behind
  `slv_req` being driven by the grant alone.
- `a_decerr`: a request that matches no slave is answered by the core, with
  an error, on the next cycle.
- `a_done_req`: a master only completes while it is requesting.
- `a_resp`: a slave completion goes back, with its read data and error flag,
  to a master that addressed that slave.
- `a_no_lost_done`: every slave completion reaches a master.

**Arbiter** (`bus_matrix_arb_fv`, every slave's arbiter and the harness):
- At most one master is granted, and a new grant goes to a requesting master.
- Fixed priority: the new grant goes to the best requester.
- Round robin: a requester waits for at most `NUM_MASTERS-1` other grants.
- The grant is held until done (or until the owner stops requesting), and it
  is dropped after that.
- A free slave with a pending request grants on the next cycle.

**Coverage.** Covers show:
- every master reaching every slave;
- decode errors;
- two slaves completing in the same cycle;
- contention for one slave;
- arbiter waits and back-to-back grants;
- the bus scenarios of the shared checkers, except the ones waived below.

## Results (2026-10-10)

All ten jobs pass, SV and VHDL: every assertion is proven, and every cover is
covered or waived. See the top-level README for the per-job table.

The AXI4-Lite master-port response bounds (`g_mst[*].u_bus.g_s_b_bounded.s_b_bounded`
and `g_s_r_bounded.s_r_bounded`, B / R within `M_WAIT` = 64 cycles) are the
slowest properties. The SV job took 6136 s. With the old 30-minute budget they
came back inconclusive, so `formal_bus_matrix.py` now defaults the AXI4-Lite
jobs to 3 hours (`AXI4L_MAX_TIME`). Every other job proves well within 30
minutes.

## Waivers

Each line of `bus_matrix_fv_waivers.txt` covers the SV and the VHDL run. The
VHDL bind adds a second `u_fv` level, which the `u_fv*` glob matches.

| Property | Result | Why |
|----------|--------|-----|
| `bus_matrix_apb.u_fv*.g_slv*.u_bus.c_back2back` | uncoverable | the arbiter leaves one idle cycle on a slave between grants, so a SETUP never directly follows a completed transfer |
| `bus_matrix_ahb.u_fv*.g_slv*.u_bus.g_m_addr_hold.*` | vacuous | the initiator presents an address phase only when no data phase is in flight, and a slave holds HREADY high outside data phases, so an address phase is never stalled |
| `bus_matrix_ahb.u_fv*.g_slv*.u_bus.c_pipelined` | uncoverable | one transfer per grant plus the idle cycle between grants: slave-side transfers never overlap |
| `bus_matrix_ahb.u_fv*.g_slv*.u_bus.c_wr_then_rd` | uncoverable | same reason as `c_pipelined` |
| `bus_matrix_axi4l.u_fv*.g_slv*.u_bus.c_b_backpressure` | uncoverable | the initiator holds BREADY high for the whole write |
| `bus_matrix_axi4l.u_fv*.g_slv*.u_bus.c_r_backpressure` | uncoverable | the initiator holds RREADY high for the whole read |
| `bus_matrix_axi4l.u_fv*.g_slv*.u_bus.c_rd_wr_overlap` | uncoverable | the initiator runs one transaction per grant |
| `bus_matrix_wb.u_fv*.g_slv*.u_bus.c_back2back` | uncoverable | the idle cycle between grants means a request never directly follows a termination |

All of them are consequences of the documented design choices (one single
transfer per grant, one idle cycle between grants). None hides a protocol
violation.

## Findings

1. **Fixed priority can starve a master for ever (design change).** The
   original default was fixed priority with the CPU (M0) first. The master-port
   response bound on M1 could not be proven: a CPU that issues back-to-back
   AHB or Wishbone transfers to the same slave keeps it busy indefinitely.
   The default is now round robin. Fixed priority is still supported, and it
   is proven on the arbiter harness.
2. **VHDL generics are invisible to an SV bind (flow fix).** The first VHDL
   jobs failed because the checkers saw `NUM_MASTERS = 0`. The configuration
   is now generated as literals (`bus_matrix_fv_cfg.svh`).
3. **Waivers did not match the VHDL hierarchy (flow fix).** The VHDL bind
   names its checker `BUS_MATRIX_<PROTO>.U_FV.u_fv…`, one level deeper than
   SV, so the SV-only waiver globs reported the waived covers as failures on
   VHDL. The globs now use `u_fv*`.
