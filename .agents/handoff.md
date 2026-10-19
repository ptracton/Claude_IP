# Handoff — SRAM Step 4 (SV AHB system bench), paused 2026-10-17, updated 2026-10-18

The plan for this work is in `.agents/project_sram_plan.md` §13: the request, findings, bench
architecture, test list and work list. This file records where things stand.

## User request (2026-10-17)
Start Step 4:
- Reach the SRAMs through the **bus_matrix** IP, repairing it as needed.
- Instantiate several SRAMs with widths **8/16/24/32/64** and a range of depths.
- Show the ECC and power interfaces working; inject and detect 1-bit and 2-bit errors.
- Dual port: use different settings on ports A and B.
- Demonstrate BIST, pipelines, RMW, aligned/unaligned access and bursts.
- **SystemVerilog + AHB first**, as the model for the other protocols and VHDL.

## Git state
3b/3c were committed by the user (HEAD `fa6389c`). Everything below is **uncommitted**.
Commit only when asked.

## Done so far

### 1. bus_matrix AHB HSIZE repair (SV only)
- The matrix dropped HSIZE. Fixed in:
  - `bus_matrix_ahb_tgt.sv`: new `HSIZE` input. `core_be` = lane mask from HSIZE/HADDR, ANDed with
    HWSTRB on writes.
  - `bus_matrix_ahb_ini.sv`: new `HSIZE` output, rebuilt by `be_size(core_be, HADDR offset)`. It
    gives the aligned 2^k-lane block containing the address, otherwise the full bus size.
  - `bus_matrix_ahb.sv`: new ports `M_HSIZE` / `S_HSIZE`.
- The bench found a bug in my first version of `be_size`: a sparse strobe at a word address gave
  the wrong HSIZE. Fixed with the offset check.
- bus_matrix SV tb (`tb_bus_matrix_ahb.sv`, `bus_matrix_ahb_bfm.sv`) now drives HSIZE.
  `sim_bus_matrix.py --proto ahb --lang sv` passed on VCS and Xcelium (82 checks), **but that run
  was before the be_size fix**. Re-run it.

### 2. SRAM RTL fixes
- **Bug (found by the bench):** on an 8-bit SRAM (one lane) a zero-strobe write still wrote the
  word.
  - Cause: `sram_port` set lane enables only `if (NLANES > 1)`.
  - Fix: the condition is now `BYTE_EN`, in both `sram_port.sv` and `sram_port.vhd`.
- `sram_array.sv`: the slice write data is now generate-if instead of `?:`. This removes VCS
  out-of-bounds warnings and does not change function.
  - The VHDL twin was **not** touched: check whether it needs the same.

### 3. sram_model.sv rewritten
- Adds dual port and a second clock (`clk_b`, `mem_b_*`), WIDTH_B and per-port options.
- Adds READ_ONLY_B, per-codeword ECC faults (storage units = narrower port), expected-response
  queues, and power-of-two strides.
- Single-port use is unchanged; leave the B ports unconnected.

### 4. Bench (new files)
- `verification/testbench/sram_tb_ahb_master.sv`: AHB master BFM of any data width. It runs a
  pipelined beat list, plus helpers for single, INCR/WRAP and BUSY bursts.
- `verification/testbench/sram_tb_pkg.sv`: SB_* (instances), SL_* (slave ports), slave table, shadow
  memory.
- `verification/testbench/tb_sram_ahb.sv`: the top level:
  - 5 matrices (X32 with 2 masters; X8 on clk_b; X16; X24; X64);
  - 12 SRAM instances: s32, s32e, dp0, s8, s16, s16w, dp1, s24, s24b, s64, and direct-attached
    s32p (RL1) and s32q (RL2);
  - one `sram_model` per instance, side-band arrays and event counters.
  - `+define+TECH=n` (+ `TECH_GENERIC`); `+test=<name>` runs one test.
- `verification/tests/sram_tb_helpers.sv`:
  - reporting;
  - master dispatch `m_*`;
  - geometry, shadow, checked `wr` / `rd_chk` / `sub` / `burst` (optional `mo` = master override);
  - side-band `set_mode` / `wait_mode` / `inject` / `wait_idle`;
  - `tb_init`, `reset_all`, `finish_all` (fails on any model mismatch).
- **2026-10-18:** test_ecc done.
  - Backdoor = user choice **DPI/VPI helper**: new shared
    `IP/common/verification/dpi/claude_backdoor.c` (`claude_bd_get` / `claude_bd_put`, binary-string
    values).
  - Helpers `bd_path` / `bd_flip` / `mdl_fault` are in `sram_tb_helpers.sv`, plus `cw_bytes`.
  - `sram_model` got `set_fault(unit, kind)` for backdoor flips.
  - Compile flags: VCS `-debug_access+pp+f+r+w` plus the .c file; Xcelium `-access +rw` plus the
    .c file.
  - Full bench (7 tests: 78k comparisons, 31.8k model responses) PASS on **VCS and Xcelium**,
    GENERIC.
  - Xcelium command: `xrun -sv -timescale 1ns/1ps -access +rw -define TECH=0 -define TECH_GENERIC
    -incdir <tests> <same files> claude_backdoor.c -top tb_sram_ahb`.
- Tests written:
  - **PASS on GENERIC:** test_reset, test_params, test_access, test_burst, test_pipeline,
    test_contention. That is 76k comparisons and 31k model-checked responses, with 0 mismatches.
  - test_ecc PASS (see above).
  - **Stubs still** (an empty task each): test_power, test_clear, test_bist, test_dp. Their
    intended contents are in plan §13.4.

### Measured
| Path | INCR16, cycles per beat |
|---|---|
| Through the matrix | 4 (RL1) / 5 (RL2) |
| Direct | 2 (RL1) / 3 (RL2) |

RL2 adds one cycle to writes too: every response comes READ_LATENCY cycles after the grant.

## All SV protocols (2026-10-18)
- Bench split into a shared body and thin tops:
  - `testbench/sram_tb_body.svh`: instances, models, counters, test sequence.
  - `tb_sram_{ahb,apb,axi4l,wb}.sv`: wiring macros only (`XBAR_WIRES`, `XBAR`, `MST`, `SLV`,
    `CLKRST`, `LINK`, `SRAM_TOP`, `TB_NAME`/`TB_STR`/`TB_PROTO`).
  - The directly attached SRAMs use `LINK` (master port 0 wired to slave port 0) inside
    `g_direct[gp]`.
- BFMs share `testbench/sram_tb_master_common.svh` (beat list, burst builders, `lane_mask`). Per
  protocol:
  - `sram_tb_apb_master.sv`: SETUP/ACCESS back to back.
  - `sram_tb_axi4l_master.sv`: one transaction at a time, AW+W together, B/R ready held high.
  - `sram_tb_wb_master.sv`: classic, CYC held across the list.
  - Buses without a size signal get the size as strobes/SEL; reads return the whole word.
- Tests: `IS_AHB` (in helpers) gates the unaligned-HADDR check and the AHB cycles-per-beat bounds.
  test_params spaces out the range errors: a port B on its own clock merges `err_irq` pulses closer
  than ~3 cycles in `claude_pulse_sync` (documented behaviour). APB/WB failed on that until the
  spacing was added.
- `sim_sram.py`: all 4 protocols (SV) implemented, plus `--jobs N`.
  `--sim all --proto all --tech all --jobs 8` gives **40/40 PASS** in 2m10s.
- No bus_matrix repair was needed for APB/AXI4-Lite/WB: their adapters carry strobes and are
  DATA_W-generic. The AXI4-Lite cycle counts (single read 9 cycles through the matrix, 4 direct)
  reflect the BFM's one-transaction-at-a-time style. Use an outstanding-transaction BFM if AXI
  throughput is to be shown.

## Code coverage (2026-10-18)
- `sim_sram.py --proto all --tech all --coverage --jobs 8` (VCS only):
  - `-cm line+cond+fsm+tgl+branch`, with `-cm_hier` limited to the sram tops and everything below
    them, vendor macro models excluded;
  - urg merges the 20 runs with `-lca -flex_merge modules` (a plain merge keeps only the first
    design's instances);
  - output: `verification/work/coverage/summary.txt` and `dashboard.html`.
- First result: total **66.5** (line 78.5, cond 69.4, toggle 82.0, FSM 25.0, branch 77.7). The
  weakest modules match the stub tests:
  - sram_pwr_ctrl 22 (FSM 0): test_power
  - sram_bist 25: test_bist
  - sram_clr 58: test_clear
  - sram_core 56
  - sram_cdc 79
- XILINX/ALTERA leaves are not instantiated in any run, so they are not in the report.
- No coverage targets agreed with the user yet.

## Coverage push (2026-10-18)
User target: 90% for every component of each technology and bus type. **Met**, see plan
§13.7.1:
- `--sim all --proto all --tech all --coverage --jobs 8` gives 40/40 PASS;
- `coverage/per_run.txt`: every module of every run >= 92.95, totals 94.3-95.6.

All 12 tests are written; there are no stubs left.

## How to run
`source IP/system/sram/setup.sh`, then
`python3 IP/system/sram/verification/tools/sim_sram.py [--sim vcs|xcelium|all] [--tech generic|saed90|saed32|saed14|sky130|all] [--test <name>] [--waves]`.
- Logs: `verification/work/<sim>/<proto>_<lang>_<tech>/{compile,sim,results}.log`; summary in
  `verification/work/results.log`.
- Unimplemented proto/lang/sim combinations report FAIL ("not implemented yet").
- Everything: `--sim all --proto all --tech all --jobs 8`.
- 2026-10-18 (AHB only, before the protocol rollout): `--sim all --tech all` gave **10/10 PASS** (GENERIC, SAED90/32/14, SKY130 on VCS and
  Xcelium).
- Checked that a mutant of the be_size offset check is caught (FAIL reported).
- The scratch `run.sh` is retired.
- **RULE (user):** each step's tools are built in that step, not later (memory
  `feedback_tools_with_each_step.md`).

## Next steps
1. ~~test_ecc~~ — done 2026-10-18; the notes below are kept for reference.
   - `ecc_inj` 1-bit / 2-bit on s32e, s24, s64 and dp0.A. Check corrected reads with
     `n_corr` / `n_irq`, and ERROR responses with `n_uncorr`; a rewrite heals the word.
   - RMW on clean, 1-bit-fault and 2-bit-fault words. Check `n_busy`, and that a failed RMW does
     not consume the injection.
   - **Backdoor finding (2026-10-18, prototypes in scratchpad `dep/`):**
     - `$deposit(u_leaf.mem[i], v)` works on Xcelium.
     - VCS rejects it at compile time with ICPD, because the leaf `mem` is written in
       `always_ff` (tried `-debug_access+all`, `-suppress`/`-error`/`+warn` and a string path;
       all fail).
     - A DPI-C helper (`vpi_handle_by_name` + `vpi_put_value`, binary-string value, like UVM's
       `uvm_hdl_deposit`) works on **both** VCS (`-debug_access+r+w`) and Xcelium
       (`-access +rw`) with no RTL change.
     - Waiting on the user to choose between the DPI helper and changing the leaf to plain
       `always`.
   - dp0: an injection on a write that does not touch codeword 0 is consumed and does nothing.
     B-port narrow reads of the injected codeword.
   - Backdoor flips of every stored bit (GENERIC). **Open problem:** the leaf `mem` is written in
     `always_ff` in `sram_macro_generic.sv`, so a write from the tb would be a second driver.
     Options: `$deposit`; changing the leaf to plain `always` (an RTL deviation, so ask the user);
     or a VCS `force`/`release` per bit. Decide before writing it.
   - Backdoor path:
     `u_<x>.u_core.u_array.g_bank[k].g_sp.u_macro.g_generic.u_leaf.mem[row]`.
2. **test_power**: LS auto-wake with wait states, DS → ERROR with data kept, SD → lost and zero
   after the auto-clear, s24b per-bank modes, ack sequencing, busy. Update the shadow with
   `sh_fill_dom` on SD (X) and on wake (0).
3. **test_clear**: `clr_req` → `clr_done`. A bus access during the clear stalls. Domains in DS/SD
   are skipped.
4. **test_bist** (s32e, s64, dp1):
   - pass, contents zero afterwards, bus stalls during the run, cycle count;
   - stuck-at fault → `bist_fail` / `bist_fail_addr`. Plan: procedural `force` / `release` of
     `u_x.u_core.arr_rdata[bit]`, only in the cycle after a read of index FA. Track
     `arr_cs` / `arr_we` / `arr_idx`; the force needs `-debug_access+f`.
5. **test_dp**:
   - widths: dp0 32/8 and dp1 16/64, little-endian;
   - concurrent async traffic on disjoint words (dp0);
   - dp1 common-clock same-word races, accepting either order at the tb and relying on the model.
     `n_dp1_hold` counts holds; it must be > 0.
   - power from the A side affecting B (DS error, LS wake from B);
   - ECC through B;
   - SKY130 read-only B;
   - dp1.B partial write → ERROR.
6. ~~PDK runs~~ 10/10 PASS 2026-10-18; re-run with `--tech all` after each new test.
7. ~~sim_sram.py~~ done 2026-10-18. Extend it as each protocol / VHDL bench lands.
8. Sanity-check the checkers with mutations, e.g. break `be_size`, or revert the sram_port fix.
9. bus_matrix follow-ups:
   - mirror the HSIZE repair in VHDL (`bus_matrix_ahb{,_tgt,_ini}.vhd`, `tb_bus_matrix_ahb.vhd`);
   - re-run the bus_matrix sims (all langs, VCS + Xcelium) and the AHB VC Formal proofs (the
     harness needs `M_HSIZE`);
   - its DC/STA/power/postsyn results now predate the RTL change. Note that, or re-run;
   - README: DATA_W is not limited to 32, and document HSIZE.
10. Docs:
    - sram spec.md/README: a 24-bit word has a **4-byte stride** (the RTL uses a power-of-two
      stride, and the spec wrongly says `n*WIDTH/8`); RL2 also delays write responses; zero-strobe
      fix; simulation results.
    - plan §0/§5 and §13 log; memory file `project_sram_plan.md`.
11. ~~SV APB/AXI4-Lite/WB~~ done 2026-10-18 (40/40). Remaining: the VHDL DUTs (the same SV bench
    driving the VHDL tops, VCS-MX / Xcelium mixed language, as the 3c smoke did).
