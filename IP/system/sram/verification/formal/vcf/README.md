# sram — VC Formal verification

Formal property verification of the sram IP with **Synopsys VC Formal** (FPV).
There are 13 proof jobs, and each one runs on the **SystemVerilog and on the
VHDL-2008** RTL with the same SVA checkers bound into the design (26 runs):
- 8 core-level jobs on `sram_core` (single port, ECC, dual port on one clock
  or on two clocks);
- 4 top-level jobs (`sram_apb`, `sram_ahb`, `sram_axi4l`, `sram_wb`), with the
  real bus adapter in front of the core;
- one SECDED harness (`ecc`).

The shared pieces (memory-bus checker `claude_mem_fv`, bus-protocol checkers,
Tcl run script, Python driver) are documented in
[`$IP_COMMON_PATH/verification/formal/README.md`](../../../../../common/verification/formal/README.md).
This directory holds only what is specific to the sram.

## Running

```bash
source IP/system/sram/setup.sh
python3 $CLAUDE_SRAM_PATH/verification/tools/formal_sram.py                   # all jobs, SV + VHDL
python3 $CLAUDE_SRAM_PATH/verification/tools/formal_sram.py --job core_opts --lang vhdl
python3 $CLAUDE_SRAM_PATH/verification/tools/formal_sram.py --job dp_async --trace   # FSDB per failure
python3 $CLAUDE_SRAM_PATH/verification/tools/formal_sram.py --jobs 3          # parallel runs (csun.edu: max 3)
```

| Output | Location |
|--------|----------|
| Summary (PASS/FAIL, per-job counts, failures, waivers) | `verification/formal/vcf/results.log` |
| Per-run directory (`vcf.log`, `report_fv.txt`, `results.log`, `traces/`) | `verification/work/vcf/<job>_<lang>/` |
| Generated configuration and VHDL generics file | `verification/work/vcf/cfg/<job>_<lang>/` |

Each run has a 30-minute budget (`--max-time`). VC Formal runs on csun.edu
only. There is no SymbiYosys flow, because the checkers bind into VHDL designs
and read internal signals.

Reading a counterexample without Verdi: `fsdbreport` is in
`/opt/synopsys/vc_formal/Y-2026.03-SP1/verdi/bin`:

```bash
fsdbreport traces/<prop>.fsdb -of h -s /sram_core/clk /sram_core/mem_req_i ... -o trace.txt
```

The `.fsdb.xml` next to each trace lists the signals the tool found relevant,
including "X-Injected-Signals" and "Uninitialized-Registers". Check that list
first; both findings 5 and 6 below showed up there.

## Jobs

All jobs use `TECH_GENERIC` and small sizes. A configuration that differs from
the top-level's defaults is passed as `-pvalue+` (SV) or as a generics file
with `/<TOP>/<NAME>` paths (VHDL, `-gfile`; see finding 1).

| Job | Top | Configuration | What it adds |
|-----|-----|---------------|--------------|
| `core_base` | `sram_core` | W16 D16, byte enables, power gating, RL1 | baseline: data, errors, power, bounds |
| `core_be0_err` | `sram_core` | BYTE_EN 0, partial write = error, no power gating, RL2 | partial-write error rule, read latency 2 |
| `core_be0_full` | `sram_core` | BYTE_EN 0, partial write = full word | full-word write semantics |
| `core_ecc` | `sram_core` | W16 D8, ECC (16-bit codewords) | ECC read-modify-write, alone |
| `core_opts` | `sram_core` | W16 D8, ECC, BANK_PG x2, BIST, RL2 | engines, bank power domains, ECC together |
| `dp_sync` | `sram_core` | dual port, one clock, A16/B8, ECC, BANK_PG x2, RL_B 2 | two ports, width packing, A-then-B order |
| `dp_sync_wide_b` | `sram_core` | dual port, one clock, A16/B32, ECC | read-modify-writes on both ports, conflict ordering and fairness |
| `dp_async` | `sram_core` | dual port, separate clocks (random `clk_b`), A16/B16, BANK_PG x2 | `sram_cdc` permission handshake |
| `top_apb` / `top_ahb` / `top_axi4l` / `top_wb` | `sram_<proto>` | W32 D8 | bus protocol on the bus port, adapter + core |
| `ecc` | `sram_fv_ecc_top` | K = 8, 16, 24, 32, 64 | SECDED encode / flip / decode, every word and error position |

## Files

| File | Bound to | Contents |
|------|----------|----------|
| `sram_core_fv.sv` | `sram_core` | memory-bus rules on each port (`claude_mem_fv`), error prediction, symbolic-byte data model, engine exclusion, dual-port covers |
| `sram_array_fv.sv` | `sram_array` | no access to a bank while any sleep pin is on (port B on its own clock) |
| `sram_pwr_fv.sv` | `sram_pwr_ctrl` | power FSM: one pin at a time, enter / wake times, acknowledge, clear after shutdown |
| `sram_leaf_fv.sv` | `sram_macro_generic` | ECC lemma: a written codeword lane holds a valid SECDED codeword; `core_ecc`: every lane once the reset clear is done (`a_word_ok`) |
| `sram_port_fv.sv` | `sram_port` | `core_ecc` only: a granted read / RMW in s1 and s2 sees valid codewords (`a_s1_rd_ok`, `a_s2_rd_ok`) |
| `sram_bus_fv.sv` | `sram_<proto>` | `claude_<proto>_fv` on the bus port (solver = legal master), AHB single-slave and HSIZE assumptions |
| `sram_<proto>_fv_bind.sv` | — | bind-only module of a top-level job |
| `sram_fv_core_bind.sv` | — | bind-only module of the core-level jobs |
| `sram_fv_block_binds.svh` | — | binds shared by every job (core, array, power, leaf) |
| `sram_fv_ecc_top.sv` | — | `ecc` job harness (SV module, instantiates the SV or VHDL enc/dec) |
| `sram_fv_waivers.txt` | — | waived results with justifications |
| `cfg/<job>_<lang>/sram_fv_cfg.svh` | — | generated configuration `define`s (an SV bind cannot see VHDL generics) |

The checkers read only ports, plus a few internal signals that the SV and VHDL
cores both declare (`clr_busy`, `bist_busy`, `bist_active`, `b_cs`, `a_stall`,
`b_stall`, `a_rmw_pend`, `b_rmw_pend`, `b_dom_err`) and the leaf's `mem`. So
both languages get identical checks.

## What is proven

**Memory bus** (`claude_mem_fv`, every port of every core job): the core obeys
every target rule against a legal, unconstrained initiator. It grants within
`MAX_WAIT` cycles and responds within the read latency. In the top-level jobs
the initiator is the real bus adapter, so its rules are asserted too. The
response bounds need one environment rule (`am_sideband_quiet`): clear and BIST
requests, and power-request changes, arrive only while the port is idle.
Otherwise a stream of engine requests could hold the bus off for ever. That is
by design, because a pending engine stalls new grants.

**Errors** (`a_err_rule`, `b_err_rule`): the core predicts the error response at
the grant and checks it at the response. An error is expected for:
- an address beyond the array;
- a domain that is requested into deep sleep or shutdown;
- a partial write with BYTE_EN = 0 and PARTIAL_WR_ERR;
- a write to a read-only port B.

**Data integrity** (`a_data`, `b_data`): the model follows one symbolic byte,
the same in every cycle of a trace. A read returns that byte as it was at the
read's grant. A clear, a BIST run or a shutdown request also allows zero.
This covers byte lanes, full-word writes, port-width packing, ECC codeword
lanes and read-modify-write. With separate clocks each port has its own byte,
which the other port never touches (same-word accesses in overlapping cycles
are undefined).

**ECC** (`ecc` job): for K = 8 to 64, any data word, and 0, 1 or 2 flipped bits
at any two codeword positions:
- with no flip, the data is returned with no flag;
- with one flip, the data is corrected and `single_o` is set;
- with two flips, `double_o` is set and the data is not miscorrected.

**ECC lemma** (`sram_leaf_fv`, ECC jobs): every codeword lane of the leaf whose
last write was a valid codeword still holds a valid codeword. The lemma is
proven, and the ECC jobs use it as an assumption (`assume_proven`, i.e. VC
Formal `fml_enable_assume_proof`). It took `core_ecc` from depth 19 to depth 25
in 30 minutes.

**Pipeline lemmas** (Step 10, `core_ecc`): with the read-modify-write
registered (stage s2), the error prediction `a_err_rule` stopped converging:
nothing tied the registered read word `rd_q` to the array. Two more proven
lemmas carry the fact through:
- `sram_leaf_fv a_word_ok`: once the reset clear (`sram_clr`, CLEAR_ON_RESET
  with ECC) has finished, every lane is known valid, and during that pass
  every word it has already written. The bind reads the clear engine's state
  by upward reference (`sram_core.u_clr`).
- `sram_port_fv a_s1_rd_ok` / `a_s2_rd_ok`: an error-free read or RMW in s1
  finds valid codewords at the array output, and in s2 in `rd_q`.

With them `a_err_rule` is proven in `core_ecc` (SV and VHDL). They are bound
only with one bank and no BIST (`SRAM_FV_LEAF_CLR_BIND`, generated by
`formal_sram.py`): `core_opts` (two power domains, BIST March C- patterns)
would need those modelled too, and keeps its bounded waivers.

**Engines:** a clear pass never overlaps the BIST march. Port A gets no grant
while an engine runs. Port B never touches the array while an engine runs (on
`clk_b` with separate clocks, i.e. the `sram_cdc` handshake).

**Array and power:** no bank is accessed with a sleep pin on. Each power FSM:
- has at most one pin on at a time;
- is awake only in RUN with every pin off;
- enters a mode only from idle;
- respects the enter and wake times;
- clears after a shutdown before it returns to RUN.

**Bus protocol** (top-level jobs): against a legal master, the sram obeys every
slave rule of its protocol and answers within `BUS_WAIT` cycles.

## Results (2026-11-25, Step 10 RTL: registered read-modify-write)

| Job | Language | Assertions proven | Covers covered | Waived | Bounded (depth reached) | Result |
|-----|----------|-------------------|----------------|--------|-------------------------|--------|
| `core_base` | SV | 26/26 | 18/19 | 1 | — | PASS |
| `core_base` | VHDL | 26/26 | 18/19 | 1 | — | PASS |
| `core_be0_err` | SV | 9/9 | 13/13 | 0 | — | PASS |
| `core_be0_err` | VHDL | 9/9 | 13/13 | 0 | — | PASS |
| `core_be0_full` | SV | 26/26 | 19/20 | 1 | — | PASS |
| `core_be0_full` | VHDL | 26/26 | 19/20 | 1 | — | PASS |
| `core_ecc` | SV | 43/44 | 22/22 | 1 | `a_data` 23 | PASS |
| `core_ecc` | VHDL | 43/44 | 22/22 | 1 | `a_data` 26 | PASS |
| `core_opts` | SV | 49/52 | 30/30 | 3 | `t_gnt_bounded` 184, `a_data` 21, `a_err_rule` 20 | PASS |
| `core_opts` | VHDL | 49/52 | 30/30 | 3 | `t_gnt_bounded` 181, `a_data` 20, `a_err_rule` 20 | PASS |
| `dp_sync` | SV | 49/51 | 36/40 | 6 | `a_data` 18, `b_data` 17 | PASS |
| `dp_sync` | VHDL | 49/51 | 36/40 | 6 | `a_data` 18, `b_data` 18 | PASS |
| `dp_sync_wide_b` | SV | 29/33 | 33/33 | 4 | `a_data` 16, `a_err_rule` 15, `b_data` 15, `b_err_rule` 15 | PASS |
| `dp_sync_wide_b` | VHDL | 29/33 | 33/33 | 4 | `a_data` 15, `a_err_rule` 15, `b_data` 14, `b_err_rule` 14 | PASS |
| `dp_async` | SV | 45/47 | 34/36 | 4 | `a_data` 38, `b_data` 38 | PASS |
| `dp_async` | VHDL | 45/47 | 34/36 | 4 | `a_data` 38, `b_data` 38 | PASS |
| `top_apb` | SV | 29/29 | 22/23 | 1 | — | PASS |
| `top_apb` | VHDL | 29/29 | 22/23 | 1 | — | PASS |
| `top_ahb` | SV | 31/31 | 23/24 | 1 | — | PASS |
| `top_ahb` | VHDL | 31/31 | 23/24 | 1 | — | PASS |
| `top_axi4l` | SV | 37/37 | 24/25 | 1 | — | PASS |
| `top_axi4l` | VHDL | 37/37 | 24/25 | 1 | — | PASS |
| `top_wb` | SV | 31/31 | 22/23 | 1 | — | PASS |
| `top_wb` | VHDL | 31/31 | 22/23 | 1 | — | PASS |
| `ecc` | SV | 15/15 | 10/10 | 0 | — | PASS |
| `ecc` | VHDL | 15/15 | 10/10 | 0 | — | PASS |

All 26 runs pass; no property is falsified. "Bounded" lists the waived
inconclusive assertions and the depth (cycles from reset) to which each
was proven within the 30-minute budget. Every other assertion is a full
(unbounded) proof. Tool: VC Formal Y-2026.03-SP1, generated 2026-11-15
(`results.log`).

## Waivers

Each line of `sram_fv_waivers.txt` covers the SV and the VHDL run. A
`<job>:` prefix limits a line to one job (with or without the `_sv` / `_vhdl`
suffix).

| Property | Result | Jobs | Why |
|----------|--------|------|-----|
| `*.u_mem_?.c_rvalid_wait` | uncoverable | RL1 jobs without read-modify-write | with read latency 1 the response always comes in the cycle after the grant (an ECC byte write's registered RMW responds a cycle later, so `core_ecc` and `dp_sync_wide_b` reach the cover) |
| `*.g_c_ecc.c_a_rmw`, `*.c_a_waits_b_rmw`, `*.c_b_waits_a_rmw` | uncoverable | `dp_sync` | 8-bit codewords: a byte write never needs a read-modify-write (`dp_sync_wide_b` covers them) |
| `a_data`, `b_data` | inconclusive | `core_ecc`, `core_opts`, `dp_sync`, `dp_sync_wide_b`, `dp_async` | bounded proof only, see below |
| `a_err_rule`, `b_err_rule` | inconclusive | `core_opts`, `dp_sync_wide_b` | bounded proof only, see below |
| port A `t_gnt_bounded` | inconclusive | `core_opts` | bounded (more than 3 x MAX_WAIT cycles) with BIST, clear and power engines |

**Bounded results (decision 2026-11-15).** End-to-end data integrity does not
converge in the ECC and dual-port jobs. There is no counterexample; the depth
each run reached is in the table above. A 3-hour `core_opts` run only went from
depth 20 to 21, and the ECC lemma helped the search but did not produce a full
proof. Other evidence covers these properties:
- `a_data` and `a_err_rule` are fully proven without ECC (`core_base`,
  `core_be0_*`);
- the SECDED code is proven exhaustively (`ecc`);
- every written ECC lane is proven to hold a valid codeword (`sram_leaf_fv`);
- the simulation regression (4 buses x 2 languages x 5 technologies x 2
  simulators) checks every read against `sram_model`.

Only `inconclusive` is waived, so a counterexample in a future run still fails
the job.

## Findings

1. **`-gv` sets a generic in every VHDL instance (flow fix).** `-gv WIDTH=16`
   also set port B's `sram_port` WIDTH, so every dual-port VHDL job failed to
   elaborate (and single-port VHDL jobs could silently prove a different
   configuration). VHDL jobs now pass a generics file with `/SRAM_CORE/<NAME>`
   paths (`-gfile`).
2. **Clear after reset could skip a domain for good (RTL fix, SV + VHDL
   `sram_clr`).** With ECC, `CLEAR_ON_RESET` zeroes the array before the first
   access, but the pass skips a domain that is requested into deep sleep or
   shutdown. If software withdrew the request before the domain ever shut down,
   nothing cleared it, and a read decoded an uninitialised word as an
   uncorrectable error (`a_err_rule`, depth 10). Now a domain stays marked
   uninitialised (`init_q`) until a pass writes its last word. It is pending,
   with a combinational bus stall, whenever it may be woken.
3. **Port B could be starved by port A (RTL fix, SV + VHDL `sram_core`).** With
   one clock and read-modify-writes, a stream of port-A byte writes to the word
   port B wanted kept B waiting for ever: A's grant, then A's write-back, then
   A's next grant (port B `t_gnt_bounded`, depth 73). When B was held off by a
   same-word conflict in the previous cycle, A now yields that word for one
   turn (`a_yield`). The first conflict still goes to A.
4. **VHDL SECDED encoder/decoder too slow to prove (RTL change, VHDL).** The
   VHDL twins still searched `ecc_data_pos()` per bit, and the `ecc` job timed
   out at depth 0 for K >= 24. They now use elaboration-time position tables,
   like the SV rewrite of 2026-11-13: 15/15 proven.
5. **Symbolic bytes were not constant with a random clock (checker fix).**
   `sym_a` / `sym_b` were undriven nets held by `$stable` on `clk`. VC Formal
   X-injects undriven nets, so with a random `clk_b` the solver changed them
   between two `clk` edges. Port B's "never touch the other byte" assumption
   then referred to a different byte, giving a false `a_data` counterexample
   (depth 5). They are now self-holding registers without reset: free at the
   start, constant after that.
6. **An `initial` block is not a formal start state (checker note).** After its
   reset simulation, VC Formal leaves registers without a reset free. The leaf
   lemma's state therefore resets from `sram_core.rst_n` (upward reference in
   the bind, because the leaf has no reset).
7. **Engine exclusion was over-specified (checker fix).** `a_eng_exclusive`
   used `bist_busy`, which includes BIST's waiting states, during which a clear
   may legally run (otherwise BIST would wait for ever after a shutdown). It
   now checks the BIST march (`bist_active`).
8. **Dual-port RMW ordering was not reachable (job change).** `dp_sync_wide_b`
   was A8/B16: its 8-bit codewords never need a read-modify-write, so the
   ordering covers were unreachable. It is now A16/B32. That change exposed
   finding 3.
9. **Depths were not parsed, so `inconclusive` waivers never matched (shared
   driver fix, `claude_vcf.py`).** `report_fv` writes `inconclusive(depth=22)`
   with no space. The row parser expected a space, so it read the whole token
   as the status. An inconclusive result therefore never equalled
   `inconclusive` in the waiver file, and its depth was lost. This affects every
   IP that uses the shared driver; before this, none had an inconclusive waiver.
10. **The leaf bind needs a target (flow fix).** A dual-port core has no
    `sram_macro_generic`. The SV runs ignore a bind with no target, but VHDL
    elaboration fails (`SVABIND`). The leaf bind is now emitted only for
    single-port configurations (`SRAM_FV_LEAF_BIND` in the generated
    configuration).
