---
name: SRAM IP plan (IP/system/sram) — started 2026-10-15
description: Status, architecture as built, PDK macro facts, decisions and step plan for the configurable SRAM wrapper IP
type: project
---

# SRAM IP — plan and status

Built following the timer (gold standard) through the 12-step flow. The big
difference from the timer: SRAM is a **memory slave**, not a register-file
peripheral, so it uses the new shared `claude_<proto>_mem_if` adapters (§3)
instead of the `claude_*_if` register bridges.

## 0. Status snapshot (2026-10-17)

| Step | State |
|---|---|
| 0 — shared memory-bus adapters (IP/common) | **Done.** 32/32 PASS: lint 4/4, sim 20/20, formal 8/8, no waivers |
| 1 — `IP/system/sram` skeleton | **Done.** setup.md quality gate all PASS |
| 2 — SystemRDL | **Skipped by design** (no register block, D2) |
| 3 — RTL SV + VHDL, all options | **Done.** Scratch smoke tests PASS on GENERIC + all 4 PDKs, both languages |
| 3b — macro tiling rework (§11) | **Done 2026-10-17** (D11 = A); uncommitted |
| 3c — asymmetric / dual-clock DP (§12) | **Done 2026-10-17**, uncommitted (§12.9) |
| 4 — directed tests | **Next** |
| 5–12 | Not started |

**Nothing is committed.** The working tree also holds the SKY130 PDK move to `$HOME` and the
`CLAUDE_SKY130_PDK_PATH` env var, plus their doc and setup.sh edits (timer, bus_matrix,
.agents). Step 0 results: `IP/common/verification/mem_if/results.log`.

**Open items carried forward:**
- XILINX/ALTERA leaves are written but never elaborated (no Vivado/Quartus on csun). Verify
  on the standard host, including the 3c dual-clock modes (XPM `independent_clock`,
  altsyncram clock1/clocken1) and altsyncram `byte_size` with one lane.
- 3b/3c scratch benches (`macro/`, `smoke/tb_dp2.sv`, generators) live in session
  scratchpad b804bca1 and must become Step 4 deliverables.
- Default synthesized configs (§4) predate 3c: decide whether the dual-port netlist should
  use different widths and separate clocks (two-clock STA and CDC constraints).
- No iverilog/ghdl/Verilator/SymbiYosys on csun; VCS + Xcelium are used instead.
  Open-source flows need a standard host.
- AHB, AXI4-Lite and WB tops are only elaborated (Xcelium, both languages); functional tests
  come in Step 4.
- Power entry/wake cycle counts (`sram_pkg::pwr_*_cycles`) are conservative placeholders.
  Check them against the SAED32-LP liberty / databook at Step 10.
- SKY130 OpenRAM liberty exists only at TT for the named macros, which limits SS/FF STA.
  Decide at Step 10.
- UPF files for SAED90/SAED14/SKY130 power gating (`design/upf/`) are due at Step 10.
- The scratch smoke testbenches (session scratchpad, not in the repo) must be rebuilt as
  Step 4 deliverables.
- Two lc_shell scratch files are untracked in `IP/common/synthesis/designcompiler/sky130_lib/`
  (`compile_lib.tcl`, `lc_output.txt`). They could go in .gitignore.
- The old `/tmp/pet43490/PDK` tree (and `sky130_fd_sc_hd.damaged_2026-10-14`) is unused.
  The user has not yet said whether to delete it.
- The timer's setup.sh still adds duplicate PATH entries when re-sourced. sram's does not.
  The timer was left as it is.

## 1. PDK macro facts (verified 2026-10-15, csun.edu)

| PDK | Single-port family | Two-port family | Byte mask | Power pins | Liberty corners vs DC/STA stdcells |
|---|---|---|---|---|---|
| SAED90 | `SRAM<w>x<d>_1rw` (width x depth) | `SRAM<w>x<d>` w 4/8/16/22/32/39, d 16..128 | no | none | `_max` / `_typ` .db ✔ |
| SAED32 | `SRAMLP1RW<d>x<w>` (lib/sram_lp) | `SRAMLP2RW<d>x<w>` d 16..128 | no | SD, LS, DS (2RW: SD, LS1/2, DS1/2) + VDDL | `ss0p95v125c_i0p95v`, `tt1p05v25c_i1p05v` ✔ |
| SAED14 | `SRAM1RW<d>x<w>` d 4..512 | `SRAM2RW<d>x<w>` d 4..512 | no | none | `ss0p72v125c`, `tt0p8v25c` ✔ |
| SKY130 | OpenRAM `sky130_sram_*_1rw1r_*`, port 1 unused | same macros, port 1 (read-only) = port B | yes (`wmask0`) | none | TT only for the named macros |
| Xilinx / Altera | `xpm_memory_spram` / `altsyncram` | `xpm_memory_tdpram` / altsyncram BIDIR | yes | XPM `sleep` / none | n/a |

Pin polarities and behaviour (checked against the models and the databooks):
- SAED90 and SAED32: `CSB` and `WEB` are active low and `OEB` = 0. Read data is registered
  on `CE` and holds until the next read.
- SAED32-LP: LS/DS/SD take effect only while deselected. SD wipes the contents (X), DS forces
  O = 0 and LS holds O.
- SAED14 `SRAM1RW`: `CSB` is **active high** (databook "Primary Chip Select, Active High").
  O is 0 after any non-read cycle.
- SAED14 `SRAM2RW`: `CSB` is **active low**. Simultaneous same-address writes are undefined.
- SAED14 `SRAM1RW32x8`: `I` is **32 bits** in both the model and the liberty. The leaf
  zero-extends the 8-bit data.
- SAED14 `SRAM2RW16x16`: O is 5 bits (vendor bug). That size is never chosen.
- SKY130: `csb0` / `web0` are active low. dout is valid about 3 ns after the falling edge and
  goes X 1 ns after the next rising edge, so the simulation clock period must exceed
  ~8 ns. Set `VERBOSE = 0`.

Vendor simulation-model bugs are fixed in generated copies by
`IP/common/verification/tools/pdk_sram_models.py`; the vendor files are never edited:
- SAED14: `*_ud` registers are never declared and the outputs are never driven (1RW and 2RW).
- SKY130: `mem` is used before it is declared.

SAED90 and SAED32 models are used as shipped. Use `model_files(pdk, work_dir)` to get the
file list.

## 2. Architecture (as built, Steps 3, 3b and 3c)

```
 sram_<proto> / sram_<proto>_dp            (apb, ahb, axi4l, wb; wiring only, generated)
 ├── claude_<proto>_mem_if  (IP/common; one per port, port B WIDTH_B wide)
 └── sram_core
     ├── sram_port      x1 / x2   checks, ECC per codeword (sram_ecc_enc/dec), RMW, response
     ├── sram_cdc       port B on its own clock (COMMON_CLK = 0): permission handshake
     │                  per domain, claude_sync / claude_pulse_sync (IP/common)
     ├── sram_pwr_ctrl  per domain RUN -> enter -> sleep -> wake -> (clear) -> RUN
     ├── sram_clr       clear engine (clr_req_i, after reset with ECC, after shutdown)
     ├── sram_bist      March C- (BIST_EN)
     └── sram_array     NUM_BANKS banks; dual port with different widths: R slices per bank
         └── sram_macro / sram_macro_dp     TECH dispatcher, any W x D
             └── sram_macro[_dp]_<tech>     ASIC: ROWS x COLS of vendor primitives (§11);
                                            generic / xilinx / altera: one inferred memory
```

- Files: 34 SV + 34 VHDL-2008 twins in `design/rtl/{verilog,vhdl}` (`sram_cdc` new in
  Step 3c), plus the transaction-level reference model `design/behavioral/sram_model.sv`.
  The model watches the memory bus and predicts every response (single port only, so far).
- Generated files, with their generators in the session scratchpad (b804bca1):
  - the 8 ASIC leaves: `gen_leaves.py`;
  - the 16 tops: `gen/gen_tops_{sv,vhd}.py` + `gen/tops_spec.py`.
  The repo files are the source of truth. Move the generators into
  `verification/tools/` if they are to be kept (Step 11).
- TECH selection: a `TECH` parameter dispatches through a generate block. Only the selected
  branch is elaborated (verified on VCS and Xcelium, SV and VHDL), so a host only needs its
  own macro library.
- Tiling (§11): `sram_pkg::prim_width/prim_depth[_dp]` pick one primitive size per ASIC
  wrapper; `tile_rows` / `lane_of` help. SAED byte lanes use x8 columns; SKY130 and the
  FPGA/generic leaves use native masks.
- Default 32 x 1024 with byte enables:
  - SAED90 / SAED32: 1 row x 4 columns of `8x1024` / `1024x8`.
  - SAED14: 2 rows x 4 columns of `512x8`.
  - SKY130: 2 rows x 1 column of `32x512`.
- Dual port (§12):
  - Port B width `WIDTH_B` (power-of-two ratio, same capacity, little-endian).
  - ECC codewords at the narrow width (`sram_pkg::ecc_cw / stored_width /
    stored_lanes`).
  - `COMMON_CLK` = 1 (one clock, A-then-B serialization) or 0 (separate
    clocks, `sram_cdc`).
  - Port B always runs on `clk_b`. RTL never muxes or derives a clock.
- Array ownership: BIST, then the clear engine, then the bus port(s). A pending engine stalls
  new grants (with separate clocks: withdraws port B's permission) and starts once the ports
  are idle. BIST and the clear engine never overlap (fixed a deadlock: a clear is still
  allowed while BIST waits for power).
- VHDL conventions: one-bit options are `natural` generics (for mixed-language binding).
  Derived widths come from package functions. SV derived parameters are localparams. VHDL-2008
  generic defaults may reference earlier generics (`WIDTH_B := WIDTH`; VCS and Xcelium accept
  it).

## 3. Shared code added to IP/common (Step 0)

- Why: the register bridges `claude_*_if` cannot serve a memory. They have a 12-bit address,
  no back-pressure, no error response and no AHB SEQ support, and the AXI bridge can read and
  write in the same cycle.
- Spec: `IP/common/design/rtl/mem_bus.md` (req/gnt/we/addr/be/wdata -> rvalid/rdata/err).
  One request is outstanding at a time. wdata is don't-care on reads; this was relaxed after
  formal showed AHB/AXI legitimately change it.
- RTL: `claude_{apb,ahb,axi4l,wb}_mem_if` (SV + VHDL).
  - AHB adds HSIZE byte lanes, bursts and BUSY, and has HREADY in plus HREADYOUT out.
  - AXI4-Lite serializes reads and writes round robin.
- Formal: `claude_mem_fv.sv` (`INITIATOR_IS_DUT`) and `claude_mem_xfer_fv.sv` (`WRITES` /
  `READS`), plus harnesses in `verification/mem_if/formal/`.
- Simulation: `verification/mem_if/tb/`, with a random-stall memory model.
- Runner: `verification/tools/verify_mem_if.py --lint --sim all --formal`.
- BFM: `tasks_ahb.sv` gains HSIZE plus sized and INCR4 burst tasks behind
  `CLAUDE_BFM_AHB_HSIZE`. Timer and bus_matrix are unchanged; both re-ran 16/16.
- Also new: `verification/tools/pdk_sram_models.py` (§1). `.agents/Claude_IP.md` and
  `verification/formal/README.md` document the memory adapters.

## 4. Default synthesized configuration

A netlist can't be re-parameterized, so DC/STA/post-syn/power use the RTL defaults:
`WIDTH=32, DEPTH=1024 (4 KB), BYTE_EN=1, PWR_GATE=1`, other options off (D5). Two extra
netlists cover the options: ECC + BANK_PG + BIST (single port), and dual port. Directed
simulations sweep a config matrix on GENERIC and on each PDK's macro models.

## 5. Step plan (timer flow; Synopsys order per bus_matrix: DC -> STA -> postsyn -> power -> formal last)

| Step | Work | State |
|---|---|---|
| 0 | Common `claude_<proto>_mem_if` SV+VHDL, fv checkers, BFM burst tasks; re-run timer + bus_matrix | done |
| 1 | `IP/system/sram/` tree from timer: setup.sh, cleanup.sh, README, spec, tool skeletons | done |
| 2 | RDL | skipped (D2) |
| 3 | RTL SV + VHDL, all options, 16 tops, behavioral model | done |
| 3b | Macro tiling rework: each `sram_macro[_dp]_<tech>` builds any W x D from primitives with generate (§11) | done |
| 3c | Dual port with different widths and clocks (§12) | done |
| 4 | Directed tests, SV + VHDL x 4 protos x single/dual: rw, byte enables, back2back, March sweep, AHB bursts, errors, power retention/loss/wake, clear, ECC (corr/uncorr/RMW), BIST (incl. fault injection), dual-port conflicts, config sweep incl. small DEPTHs (exercises SAED14 32x8); reference model as checker; backdoor preload/peek tasks. Also, from 3b/3c: tiler sweep (`macro/tb_macro.sv`), different widths and separate clocks on **every** protocol (AHB/AXI pipelining catches the surviving narrow-slice mutant), dual-clock `sram_model`, port-B-during-engine monitor | next |
| 5 | Formal (VC Formal): protocol checkers, `claude_mem_fv` with `INITIATOR_IS_DUT=0` on the core, symbolic-address data integrity with byte merge, power FSM legality, dual-port conflict ordering (incl. A waiting for B's RMW — not hit in smoke). From 3c: `sram_cdc` handshake ("port B never uses the array while an engine runs or pins are on"; the four-phase mutant survived simulation), codeword-lane write-back | |
| 6 | UVM (VCS): random R/W + power-mode sequences, `sram_model` scoreboard | |
| 7 | Regression runner/report | |
| 8 | Lint: SpyGlass (csun) / Verilator + VHDL lint on a standard host (needs black-box stubs for the macros). From 3c: SpyGlass CDC on the separate-clock dual port (waive the `claude_sync` first stage); documented deviations: plain `always` (SV) / shared variable (VHDL) in the generic dual-clock RAM | |
| 9 | Firmware: memory tests (March, walking 1s) + power-mode helpers; no register driver | |
| 10 | Synthesis: Yosys/Vivado/Quartus; DC x 4 PDKs with macro .db; UPF; PrimeTime with macro libs; post-syn sim using `pdk_sram_models.py` | |
| 11 | Docs, cleanup, tag | |
| 12 | PrimePower: per-mode power (RUN vs LS vs DS vs SD leakage) — the headline result | |

## 6. Decisions (user, 2026-10-15)
- D1 SKY130: install the OpenRAM `sky130_sram_macros` via volare. Done (§7).
- D2 Power control: **side-band ports only. No register block, no RDL.**
- D3 BYTE_EN=0 with partial strobes: **configurable** via `PARTIAL_WR_ERR` (1 = bus error,
  0 = write the full word).
- D4 Access in DEEP_SLEEP / SHUTDOWN: **bus error**. LIGHT_SLEEP auto-wakes with wait states.
- D5 Default synthesized config: **WIDTH=32, DEPTH=1024**, BYTE_EN=1, PWR_GATE=1.
- D6 Buses: **APB4, AHB-Lite, AXI4-Lite, Wishbone B4** (no full AXI4).
- D7 **Option A**: new `claude_<proto>_mem_if` memory adapters; the register bridges are
  untouched.
- D8 FPGA: use the vendor primitive (XPM / altsyncram) when the tool is installed, else
  GENERIC (§8).
- D9 Features 1–5 always present. ECC, BANK_PG, BIST and DUAL_PORT are optional parameters
  (§9).
- D10 SKY130 PDK lives outside /tmp, at the path in a new env var `CLAUDE_SKY130_PDK_PATH`
  exported by each IP's setup.sh (no `$HOME` fallback in Python) (§7).

## 7. SKY130 PDK and SRAM macros
- Location: `/home/users6/pet43490/PDK/sky130A` is a stable symlink to
  `.../PDK/volare/sky130/versions/0fe599b2.../sky130A`. It was moved out of /tmp on
  2026-10-15 after /tmp cleanup wiped the stdcells twice (2026-10-03, 2026-10-14).
- Env var: `CLAUDE_SKY130_PDK_PATH`, set by timer, bus_matrix and sram setup.sh on csun.
  `build_sky130_libs.SKY130_PDK` reads only this variable.
- Re-verified: timer `--dcsky130` gives 737 cells; STA ss +1.39 / tt +5.64 / ff +7.23 ns,
  identical to before.
- Macros in `libs.ref/sky130_sram_macros/`: `sky130_sram_1kbyte_1rw1r_32x256_8`,
  `sky130_sram_2kbyte_1rw1r_32x512_8`, `sky130_sram_1kbyte_1rw1r_8x1024_8`, and the older
  `sram_1rw1r_32_256_8_sky130`.
- volare is `~/.local/bin/volare` on csun.

## 8. FPGA vendor primitives
- XILINX: `xpm_memory_spram` (single port) and `xpm_memory_tdpram` (dual, common clock).
  Byte writes; `sleep` = LS|DS|SD with `WAKEUP_TIME="use_sleep_pin"`.
- ALTERA: `altsyncram` SINGLE_PORT and BIDIR_DUAL_PORT (M10K, Cyclone V). Byte enables;
  `clocken0` = chip select (no true sleep).
- GENERIC: a behavioral leaf written for block-RAM inference.
- In VHDL the vendor components are declared locally, with no `library xpm` / `altera_mf`
  clause, so the files analyze on any host.
- `INIT_FILE` maps to `MEMORY_INIT_FILE` / `init_file` / `$readmemh` (VHDL: textio hread).
- **TODO:** the Step 4/10 scripts must pick XILINX/ALTERA automatically when `vivado` /
  `quartus_sh` is on PATH. Synthesis reports must show BRAM/M10K, not LUTs/FFs.

## 9. Feature set (as implemented)

Always present:
- **`READ_LATENCY`** 1 | 2: an optional output register (s2 stage).
- **Clear engine:** `clr_req_i` / `clr_done_o`, one word per cycle, unselected domains skipped
  a whole domain at a time.
  - Runs automatically after a SHUTDOWN wake (before RUN is acknowledged) and after reset
    when ECC_EN.
  - Bus requests stall while it is pending.
- **Out-of-range address:** bus error.
- **Status:** `pwr_mode_ack_o` (per domain), `busy_o`, `clr_done_o`, and `err_irq_o`
  (registered pulse).
  - *Changed from plan:* there is no `pwr_state_o`; `pwr_mode_ack_o` plays that role.
- **Backdoor tasks** (preload / peek / poke): **still to do**, in Step 4 verification code
  (never RTL).

Optional parameters (default off), each verified in the smoke matrix:
- **`ECC_EN`:** SECDED **extended Hamming** (*changed from plan:* not Hsiao). Partial writes
  become a read-modify-write, written back in the response cycle.
  - Uncorrectable read: bus error. `ecc_corr_o` / `ecc_uncorr_o` are registered pulses.
  - *Changed from plan:* no saturating counters.
  - `ecc_inj_i[0]` / `[1]` flip stored bit 0, or bits 0 and 1, on the next **port-A** write.
- **`BANK_PG`:** one power domain per bank. *Changed from plan:* banks come from the
  `NUM_BANKS` parameter, not from tiling rows. Needs PWR_GATE. Other banks keep working.
- **`BIST_EN`:** March C- on the raw stored words, `bist_start_i` -> `bist_done_o`,
  `bist_fail_o`, `bist_fail_addr_o`.
  - Holds every domain in RUN while running, and leaves the array all-zero.
  - Detects a forced stuck-at bit at the correct word.
- **`DUAL_PORT`:** separate tops `sram_<proto>_dp` (ports `A_*` / `B_*`, each with its own
  clock and reset pins since Step 3c) on two-port macros.
  - Port B may have a different width / depth and clock (§12): `WIDTH_B`, `BYTE_EN_B`,
    `PARTIAL_WR_ERR_B`, `READ_LATENCY_B`, `COMMON_CLK`.
  - **Changed from plan:** with `COMMON_CLK = 1`, same-word conflicts are **serialized A
    then B**, not "A wins". B waits a cycle when either access writes, and a port waits for
    the other port's pending read-modify-write, so no write is dropped.
  - With `COMMON_CLK = 0`, same-word collisions are undefined. `TECH_SAED14` cannot use
    it.
  - SKY130 port B is read-only: writes get a bus error.
  - SAED90 ECC uses 39-bit two-port macros directly.

## 10. Progress log
### Step 0 — shared memory-bus adapters (2026-10-15)
- Spec: `IP/common/design/rtl/mem_bus.md` (mem_req/gnt/we/addr/be/wdata -> rvalid/rdata/err).
  One request is outstanding at a time. wdata is don't-care on reads, relaxed after formal
  showed AHB/AXI legitimately change it during a waiting read.
- RTL (SV + VHDL): `claude_{apb,ahb,axi4l,wb}_mem_if` in IP/common/design/rtl.
  - AHB port has HSIZE, HREADY (in) + HREADYOUT (out), bursts/BUSY.
  - AXI serializes R/W round robin.
- BFM: `tasks_ahb.sv` gains HSIZE and write_sized/read_sized/burst_incr4_{write,read}, behind
  `CLAUDE_BFM_AHB_HSIZE`. It is unset for timer/bus_matrix, so they are unchanged. Timer 16/16
  and bus_matrix 16/16 VCS+Xcelium re-ran PASS after the change.
- Formal: `claude_mem_fv.sv` (INITIATOR_IS_DUT) and `claude_mem_xfer_fv.sv` (WRITES/READS
  params) in IP/common/verification/formal; per-adapter harness+bind in
  IP/common/verification/mem_if/formal. All 8 jobs PASS, no waivers.
  - Formal found two issues during development; both are fixed: the wdata hold rule was too
    strict, and the per-direction AXI checks were vacuous.
- Sim: IP/common/verification/mem_if/tb (SV TB per proto, VHDL DUT mixed-language).
  Random-stall memory model with protocol checks, plus a DATA_W 8/16/64 elaboration and lane
  check. 20/20 PASS; 3/3 planted mutants detected.
- Lint: SpyGlass lint_rtl clean on all 4 SV adapters (fixed: unused PENABLE waiver, AHB
  state_d double-assign).
- Final combined run (`--lint --sim all --formal`): 32/32 PASS.
- NOT done: Icarus/GHDL/Verilator/SymbiYosys (no such tools on csun).
### Step 1 — IP/system/sram skeleton (2026-10-15)
- Tree follows the Claude_IP.md layout, without design/systemrdl (no registers, D2) and with
  design/upf/ added. Empty dirs hold .gitkeep; removed once a dir has content.
- setup.sh is the timer's: CLAUDE_SRAM_PATH, IP_COMMON_PATH, and CLAUDE_SKY130_PDK_PATH on
  csun. Its `_path_prepend` is idempotent (setup.md gate: no duplicate PATH entries).
- cleanup.sh is the timer's, but calls later-step tools only if they exist.
- doc/spec.md was written from the plan; README skeleton added.
- Tool skeletons sim/lint/formal/uvm/regression_sram.py have an env guard and the final CLI,
  and write FAIL + exit 1 until their step. Quality gate (setup.md) all items PASS.
### Step 2 — skipped by design (no register block, D2)
### Step 3 — RTL (2026-10-15)
- 33 SV + 33 VHDL files (twins) plus `design/behavioral/sram_model.sv`. Hierarchy and
  conventions are in §2 (superseded for tiling by §11); decisions are recorded in spec.md as *[Step 3]* and in §9.
- PDK quirks and model fixes: §1.
- Bugs found and fixed during Step 3:
  - BIST/clear deadlock while waiting for power.
  - TB race on ECC pulse counting.
  - ECC reads of uninitialized words → clear-on-reset.
  - Glitchy combinational status pulses → registered.
  - VHDL reserved word `access` → `do_access`.
  - SAED14 32x8 I width.
- Verified with scratch smoke testbenches (VCS; not the Step 4 deliverables):
  - Single-port APB top, SV + VHDL: GENERIC x 7 option sets; SAED90/32/14/SKY130 at default,
    ECC, no-BE and all options. Reference model 0 mismatches.
  - BIST fault injection detected.
  - Dual-port APB top, SV + VHDL: GENERIC (+ECC), SAED90 (+ECC on 39-bit macros), SAED32,
    SAED14, SKY130 (B read-only). Same-word holds exercised (17 / 25 cycles).
  - Xcelium elaborates all 16 tops (8 SV, 8 VHDL).
- Style: no line over 100 columns, no tabs, no trailing spaces in any RTL file.
- README (architecture, parameters, interfaces, power) and spec.md updated.

## 11. Macro tiling rework (Step 3b, 2026-10-17; implemented, see §11.9)

### 11.1 Problem (user review, 2026-10-17)
Each `sram_macro[_dp]_<tech>` drops in **one** vendor cell picked by a size `if`
chain. It `$fatal`s on any MAC_W x MAC_D that is not exactly one catalogue cell,
so it cannot be used as a memory of the configured size. The tiling into rows and
columns is buried in `sram_array`, mixed with banking. The user wants the macro
wrappers themselves to build a memory of the requested width and depth from as
many primitives as needed, with generate statements:
- **Width:** primitives side by side. Example: 16 bits wide = two 8-bit
  primitives in parallel.
- **Depth:** primitives stacked. Example: 2048 deep = two 1024-deep primitives,
  with the upper address bit selecting the bank (row).

### 11.2 Target hierarchy
```
sram_array                    banks only: NUM_BANKS power domains, bank decode + read mux
└── sram_macro / sram_macro_dp        TECH dispatcher; now any W x D
    └── sram_macro[_dp]_<tech>        W x D memory for that tech:
        ├── g_row[r]  (ROWS = D / PRIM_D)   chip select from addr[AW-1:PRIM_AW]
        │   └── g_col[c] (COLS = ceil(W / PRIM_W))  wdata/rdata/wbe slices
        │       └── vendor cell, picked by PRIM_W x PRIM_D (existing size chain)
        └── registered row select -> read mux
```

### 11.3 Wrapper interface (all techs, SP and DP, SV and VHDL)
- Parameters: `W` (any width >= 1, e.g. 39 with ECC), `D` (power of two >= 2),
  `NLANES` (write lanes, divides W), `INIT_FILE` (GENERIC/FPGA only).
  *Changed:* `MAC_W`/`MAC_D` become `W`/`D`, and `wbe_i[MAC_W/8]` becomes
  `lane_we_i[NLANES]`. Byte enables only exist for widths that are a multiple of
  8, so lanes are the general form (ECC words are 1 lane, D3 still holds).
- Ports otherwise unchanged: `clk, cs_i, we_i, addr_i[$clog2(D)], wdata_i[W],
  lane_we_i, ls_i, ds_i, sd_i, rdata_o[W]` (DP: `a_*`, `b_*`, shared sleep pins).
- Timing contract unchanged: rdata valid in the cycle after a read and held until
  the next read of the same wrapper.

### 11.4 Primitive selection (sram_pkg, SV + VHDL twins)
`macro_width/depth[_dp]` are renamed `prim_width/prim_depth[_dp](tech, w, nlanes, d)`
and now take the wrapper's own W x D (not the bank). Rules carried over:
- **PRIM_W:** mask-less SAED cells use 8 when NLANES > 1 or W % 32 != 0, else 32.
  SKY130 uses 32 when W % 32 == 0, else 8. SAED90 DP keeps the native 39.
- **PRIM_D:** the deepest catalogue cell <= D (fewest rows). If D is smaller than
  the smallest cell: one row, top address bits tied to 0.
- **Derived:** `ROWS = max(1, D / PRIM_D)`, `COLS = ceil(W / PRIM_W)`. The top
  column is zero-padded and its unused read bits are dropped.
- **New elaboration checks:** D is a power of two. On mask-less techs, every
  column lies inside one write lane (implicit today). The size chain still
  `$fatal`s if no cell exists, but that is now unreachable for legal W x D.

Worked examples (single port, BYTE_EN=1 unless noted):

| TECH | W x D | PRIM | ROWS x COLS |
|---|---|---|---|
| SAED32 | 16 x 1024 | 1024x8 | 1 x 2 (the user's width example) |
| SAED32 | 8 x 2048 | 1024x8 | 2 x 1 (the user's depth example, addr[10] selects) |
| SAED32 | 32 x 1024 (default) | 1024x8 | 1 x 4 (same as today) |
| SAED32 | 32 x 4096 | 1024x8 | 4 x 4 |
| SAED32 | 32 x 1024, BYTE_EN=0 | 512x32 | 2 x 1 |
| SAED14 | 32 x 1024 | 512x8 | 2 x 4 (same as today) |
| SAED90 | 39 x 256 (ECC) | 256x8 | 1 x 5 (one padded) |
| SKY130 | 32 x 2048 | 32x512 | 4 x 1 |
| SAED90 DP | 32 x 1024 | 128x8 | 8 x 4 |

### 11.5 Per-tech plan
- **SAED90, SAED32, SAED14, SKY130 (SP and DP):** rewrite as tilers (§11.2).
  - The vendor-cell size chain moves inside `g_row/g_col` unchanged. Pin
    polarities, the SAED14 32x8 zero-extend and the SKY130 VERBOSE=0 setting are
    kept as they are.
  - Read mux: `rd_row_q` is updated only on a read (SAED14 drives O=0 after
    non-reads; the others hold). Per port in DP.
  - Sleep pins fan out to every primitive in the wrapper (one wrapper = one bank
    = one power domain).
  - SKY130 DP: port B stays read-only (row decode for B uses `addr1`/`csb1`).
- **GENERIC, XILINX, ALTERA:** keep **one** inferred array / `xpm_memory_*` /
  `altsyncram` of W x D, because these primitives already accept any size and
  the tool cascades block RAMs itself. Hand tiling would block BRAM cascade
  optimizations. Changes are only the W/D/NLANES interface (XPM/altsyncram
  byte-write width = W / NLANES; GENERIC per-lane write loop). See D11.
- **sram_array:** drops rows/columns and keeps banks. One wrapper of
  MW x (DEPTH / NUM_BANKS) per bank, bank select = top index bits, a registered
  bank-read mux, and `lane_we_i` passed straight through (the `lane_of` byte
  mapping moves into the ASIC tilers).
- **Dispatchers** `sram_macro[_dp]`: parameter rename only.

### 11.6 Verification for 3b (before Step 4 resumes)
- **Scratch smoke**, rebuilt on the existing APB SP and DP benches, SV and VHDL,
  VCS. Reference model must show 0 mismatches. Sweep:
  - W in {8, 16, 32, 64} plus ECC (39 / 72).
  - D in {16, 32, 64, 512, 1024, 2048, 4096}.
  - BYTE_EN 0 and 1, NUM_BANKS 1 and 2.
  - Every tech: GENERIC + 4 PDKs, SP and DP.
- **Directed checks:** last word of row r vs first word of row r+1 (row-decode
  aliasing); byte enables that straddle columns; a read in row r followed by a
  write in another row (read mux holds); sleep with more than one row (all
  primitives see LS/DS/SD).
- **Structure check:** count primitive instances in the elaborated hierarchy
  (VCS `-debug_access` / Xcelium `-hier`) and compare with ROWS x COLS from
  §11.4. A small script will print the table so the user can eyeball it.
- Regression: default config still elaborates on Xcelium for all 16 tops.
  Default-config tiling is unchanged (table above), so later DC area should not
  move.
- Mutants: swap row select bits, drop the padded column write, register the
  read mux on every cycle. Each must be caught by the sweep.

### 11.7 Files touched
- **SV + VHDL twins:**
  - `sram_pkg`, `sram_array`, `sram_macro`, `sram_macro_dp`.
  - The 14 tech leaves: `sram_macro[_dp]_{generic,xilinx,altera,saed90,saed32,saed14,sky130}`.
- **Docs:** README §Tiling and hierarchy, spec.md byte-enable/tiling table, and
  this plan's §2 and §9.
- **No new files** unless D11 picks option B.

### 11.8 Decision (user, 2026-10-17)
- **D11 = A.** Tiling lives in each ASIC tech leaf. FPGA/GENERIC stay single
  inferred instances ("let Vivado/Quartus deal with it").
- Options as presented:
- **D11: where the row/column logic lives.**
  - **A (recommended):** inside each ASIC `sram_macro[_dp]_<tech>`, as the user
    described. Each wrapper is a standalone W x D memory for its tech, at the cost
    of about 40 duplicated lines of decode and mux in 8 SV + 8 VHDL files.
  - **B:** one shared tiler in `sram_macro[_dp]`, plus per-tech single-cell
    `sram_prim[_dp]_<tech>` files (the current leaves, renamed). Less
    duplication, but the tech files stay single instances.
  - Also confirm: FPGA/GENERIC stay single inferred instances (§11.5).

### 11.9 Implementation log (2026-10-17)
- **sram_pkg (SV + VHDL):** `macro_*` renamed `prim_width/prim_depth[_dp]`, which
  now take the wrapper's own W x D. Added `tile_rows` and `lane_of`. Removed
  `round_up8` (no longer used). Non-tiled techs return w and d.
- **ASIC wrappers (8 SV + 8 VHDL):** rewritten as tilers. They are generated by
  a scratch script (`gen_leaves.py`, session scratchpad b804bca1) from the same
  cell catalogues and pin quirks as before. The output files are the source of
  truth. Instances are named `u_prim` under `g_row[r].g_col[c].g_<w>x<d>`.
  Elaboration checks: D power of two, NLANES divides W, and a column (SAED) or
  byte (SKY130) does not cross a lane.
- **GENERIC / XILINX / ALTERA (SV + VHDL):** still one inferred memory each,
  now with a W/D/NLANES interface:
  - per-lane write loop;
  - XPM `BYTE_WRITE_WIDTH = W / NLANES`;
  - altsyncram `width_byteena = NLANES`, `byte_size = W / NLANES` (8 with one
    lane).
  XPM and altsyncram are still unelaborated (no Vivado/Quartus on csun).
- **Dispatchers:** `MAC_W/MAC_D/wbe_i` became `W/D/NLANES/lane_we_i`.
- **sram_array:** banks only. One wrapper of MW x DEPTH/NUM_BANKS per bank, the
  top index bits select the bank, and there is a registered bank read mux.
  BIST force paths change: `u_array.g_bank[k].g_sp.u_macro.g_<tech>.u_leaf...`.
- **Verification (scratch, VCS):** `macro/tb_macro.sv` + `run_macro.py` unit-test
  `sram_macro[_dp]` directly. The sweep covers 5 techs x (13 SP + 8 DP) configs:
  - W 8..72 (incl. 39 ECC), D 2..4096, NLANES 1/2/4/8;
  - ascending fill, read-all, 3000 random lane-write/read ops (both ports for
    DP), and LS/DS retention on SAED32 and GENERIC.
  A `bind` counter in the expected vendor cell checks the elaborated primitive
  count against an independent Python copy of the selection rules.
  **SV 105/105 PASS, VHDL 105/105 PASS.**
- **Full-core APB smoke** (`smoke/run_core.py`; the Step 3 benches rebuilt with
  a DEPTH define and the new BIST force path). Matrix: GENERIC + 4 PDKs x
  {default, ECC, no-BE, all} x DEPTH {256, 1024, 4096}, GENERIC extras
  (bank-PG, BIST, RL2, BIST fault), DP {default, ECC} x DEPTH {512, 1024, 4096}.
  **SV 84/84, VHDL 83/83 PASS** (VHDL omits the BIST fault force). Every SP run
  has the reference model at 0 mismatches.
- **Xcelium:** all 16 tops elaborate (8 SV, 8 VHDL).
- **Mutants** (SAED32 SP tiler, run on the saed32 sweep): 4/5 caught.
  - Caught: unregistered read mux, row CS ignores the row, lane off-by-one,
    address shift.
  - Survived: "row register updates on writes too". This mutant is
    equivalent: read data is only defined in the cycle after the read (SAED14
    already zeroes O after non-reads), and the mutant changes the mux only
    after that cycle. Not a test gap.
- **Not done:** lint (Step 8), XPM/altsyncram elaboration (no Vivado/Quartus on
  csun), and synthesis checks that DC infers the same cells (Step 10).

## 12. Asymmetric, dual-clock dual port (Step 3c, 2026-10-17, implemented)

### 12.1 Requirement (user, 2026-10-17)
In the dual-port configuration, ports A and B can have **different widths,
different depths and different clocks**.

### 12.2 Facts checked
- **Separate clocks:** every two-port primitive already has one clock pin per
  port, and each port has its own always block in the models:
  SAED90 `SRAM<w>x<d>` (CE1/CE2), SAED32 `SRAMLP2RW` (CE1/CE2), SAED14
  `SRAM2RW` (CE1/CE2), SKY130 1rw1r (clk0/clk1). Today both pins are tied to
  `clk`.
- **Different widths:** no ASIC primitive supports them (both ports have the
  same width), so they must be built in RTL. XPM `xpm_memory_tdpram` supports
  different widths and `CLOCKING_MODE="independent_clock"` natively.
  altsyncram supports mixed width and dual clock (clock0/clock1), with
  M10K restrictions to confirm on a Quartus host.
- **Core today assumes one clock:** same-word conflicts are serialized A then B
  (§9). The clear engine, BIST and power FSMs stall both ports
  combinationally. One `clk`/`rst_n`, and the tops have one PCLK/PRESETn.

### 12.3 Proposed array organisation (different widths)
- **Same capacity on both ports:** `WIDTH_A x DEPTH_A == WIDTH_B x DEPTH_B`,
  and the ratio `R = WIDE / NARROW` is a power of two. DEPTH_B is derived from
  WIDTH_B (D12).
- **Little-endian packing:** narrow word `j` is bits `[(j % R)*N +: N]` of wide
  word `j / R` (N = narrow width). This is the XPM / altsyncram convention.
- **Physical layout:** R **slices**, each N wide and DEPTH_wide deep. Each slice
  is an ordinary two-port W x D memory, tiled into rows x columns exactly as in
  §11.
  - Wide port: same address to every slice; slice k carries data bits
    `[k*N +: N]`.
  - Narrow port: slice = `addr % R`, slice address = `addr / R`. Its write
    enables only reach that slice, and a registered slice select (in the
    narrow port's clock domain) drives its read mux.
- **Banks:** the top address bits are the same for both ports (`j/R` keeps
  them), so NUM_BANKS and BANK_PG still work.
- **Symmetric case:** R = 1 gives today's structure with no added logic.

### 12.4 Proposed clocking (different clocks)
- **Clocks and resets:** `clk_a`/`rst_a_n` and `clk_b`/`rst_b_n` reach the
  array; each port's row/slice registers run on its own clock. The tops get
  `A_PCLK`/`A_PRESETn` and `B_PCLK`/`B_PRESETn` (and the same for AHB, AXI and
  WB).
- **Side-band control domain:** power, clear, BIST, status, ECC pulses and
  IRQ run on `clk_a` (D15). Port B crosses the boundary through synchronizers
  and four-phase handshakes:
  - **Engine ownership:** clear/BIST raise `own_req` (A to B). B stops
    granting and returns `own_ack` once idle; the engine starts after the
    synced ack. B resumes when `own_req` drops.
  - **Power:** a B request to a domain in LIGHT_SLEEP raises a synced wake
    request. B waits for the synced RUN status. In DEEP_SLEEP / SHUTDOWN, B
    returns a bus error using the synced mode, and its in-flight state must
    drain before the A-side FSM asserts the sleep pins (B-idle handshake).
  - Every crossing uses `claude`-style 2-FF synchronizers (to add to
    IP/common if missing) with a VC/SpyGlass CDC waiver list.
- **Same-word collisions (D13):** the A-then-B serialization cannot work
  across asynchronous clocks.
  - Proposal: parameter `COMMON_CLK`. With 1 (the default, today's behaviour)
    the serialization is kept. With 0, same-word access in overlapping cycles
    is **undefined**, as on any true dual-port RAM: write/write gives an
    undetermined value, and a read during a write returns old or new data.
  - Collisions are flagged by a simulation-only checker; the RTL does not
    detect them.
  - ECC read-modify-write on one port racing a write on the other is also a
    collision.

### 12.5 ECC with different widths (D14)
- **Proposal:** codewords at the narrow granularity. Each N-bit slice word
  carries its own check bits (stored width N + ecc(N) per slice). The narrow
  port encodes and decodes one codeword. The wide port uses R encoders and
  decoders in parallel; correctable/uncorrectable is the OR over the R
  codewords. A narrow write never needs a read-modify-write of the wide word.
- **Cost:** more check bits than one wide codeword (32-bit A with 8-bit B:
  4 x 5 = 20 bits instead of 7).
- **Alternative:** disallow ECC when WIDTH_A != WIDTH_B.

### 12.6 Per-port options
BYTE_EN, PARTIAL_WR_ERR and READ_LATENCY become per port (`*_B` parameters
default to the A value). Out-of-range checks use each port's own depth. SKY130
port B stays read-only.

### 12.7 Work list
1. sram_pkg: B-side derived widths, ratio, and slice/ECC sizing (SV + VHDL).
2. `sram_macro_dp_<tech>`: separate clocks, plus the R-slice wrapper (or the
   slice loop in `sram_array`; to decide during implementation, keeping
   leaves per D11). Two-clock ports on the leaves.
3. GENERIC DP: two always blocks, one per clock (dual-clock inference
   template). XPM: `independent_clock` with asymmetric widths. altsyncram:
   width_a/width_b, clock0/clock1.
4. sram_core / sram_port: B on clk_b; CDC block (`sram_cdc`); handshakes for
   engine ownership, wake and idle; COMMON_CLK serialization kept.
5. The 8 `_dp` tops: per-port clocks/resets and B widths. The four
   `claude_<proto>_mem_if` adapters are already width-generic; B uses its own
   instance.
6. `sram_model`: dual-clock, per-port widths, collision-aware.
7. Verification: the tiler unit test with two unrelated clocks (e.g. 20 ns /
   27 ns; SKY130 needs > 8 ns on each) and R in {1, 2, 4}, both wider sides.
   Core smoke with async clocks covering engines, wake and errors from B. CDC
   lint. Formal of the handshakes in Step 5.
8. Docs: README, spec, and this plan's §2 and §9 (the "A then B" text becomes
   COMMON_CLK-only).

### 12.8 Decisions (user, 2026-10-17): all as recommended
- **D12** equal capacity, power-of-two ratio. **D13** COMMON_CLK parameter.
- **D14** narrow-granularity ECC codewords. **D15** side-band on clk_a.
- Options as presented:
- **D12:** equal capacity with power-of-two ratio (recommended), or different
  capacities?
- **D13:** collision policy with independent clocks (COMMON_CLK parameter,
  recommended).
- **D14:** ECC with different widths: narrow-granularity codewords
  (recommended), or not allowed.
- **D15:** side-band control on clk_a with CDC to B (recommended), or a
  separate control clock.

### 12.9 Implementation log (2026-10-17)
- **New finding: SAED14 `SRAM2RW` is not per-port clocked.** CE1 clocks both
  ports' writes and CE2 both ports' reads; liberty arcs and the model agree.
  `TECH_SAED14` therefore needs `COMMON_CLK = 1`, and `sram_core` stops
  elaboration otherwise. The leaf ties CE1 = CE2 = a_clk. SAED90, SAED32 and
  SKY130 liberty/models are per port (CE1/CE2, clk0/clk1).
- **No clock muxing or derived clocks in RTL.** Port B always runs on
  clk_b / B_<clock>. `COMMON_CLK = 1` is a contract that both clock pins are
  driven by the same clock. Reason: in VHDL, `b_clk <= clk` adds a delta
  cycle, which races flops on the copy against flops on the original. A
  clock mux is also bad for synthesis and STA.
- **IP/common, new:** `claude_sync` (N-flop level synchronizer) and
  `claude_pulse_sync` (toggle pulse synchronizer), SV + VHDL.
- **sram_pkg:** `ecc_cw`, `stored_width`, `stored_lanes`. The VHDL
  `mem_width` and `num_lanes` are removed.
- **sram_port:** generic `CW`; one SECDED encoder/decoder per codeword, one
  write lane per codeword. A whole-codeword write needs no read-modify-write,
  and a read-modify-write only writes back the strobed codewords.
- **sram_cdc (new):** per-domain four-phase allow/hold handshake (allow only
  changes when allow == hold; quiet = !allow & !hold). Also crosses err
  (A to B), wake/busy (B to A) and three pulses. Every crossing is registered
  at its source.
- **sram_core:** `WIDTH_B`, `BYTE_EN_B`, `PARTIAL_WR_ERR_B`,
  `READ_LATENCY_B`, `COMMON_CLK`; `clk_b` / `rst_b_n`.
  - COMMON_CLK: today's serialization, with indices compared at wide-word
    granularity.
  - Separate clocks: `dom_want` (RUN, staying RUN, no engine pending); B's
    wake is masked by `dom_wakeable`; domain busy / engine idle wait for
    `b_quiet`.
- **sram_array:** R slices per bank, wide port to all slices, narrow port to
  one (registered slice select on its own clock), lanes expanded per slice;
  the bank/slice read registers are per port clock.
- **DP leaves:** `a_clk` / `b_clk`.
  - GENERIC: two clocked processes on a shared array (SV plain `always`,
    VHDL shared variable; both documented deviations).
  - XPM: `independent_clock`. altsyncram: clock1 / clocken1. Neither is
    elaborated yet (no Vivado/Quartus on csun).
- **Tops (8 DP, SV + VHDL):** regenerated with the updated
  `gen/gen_tops_{sv,vhd}.py` (session scratchpad b804bca1). Clocks
  `A_<clk>/A_<rst>/B_<clk>/B_<rst>`, the B bus is `WIDTH_B` wide, and there
  are new parameters. The SP tops only tie `clk_b`/`rst_b_n`.
- **Verification (scratch, VCS):**
  - Tiler sweep: plus 16 dual-clock configs (A 20 ns / B 27 ns, disjoint
    halves), giving **SV 121/121, VHDL 121/121**.
  - Core matrix, plus `smoke/tb_dp2.sv`:
    - widths 32/8, 8/32, 32/32, 64/16, 16/64, 32/16, 16/32;
    - async and sync; ECC; no byte enables on A; BIST.
    - Sequence: fills/cross reads, then 3000 concurrent ops on interleaved
      byte ownership (no lost updates, codeword-lane write-back), then
      LS/DS/SD and clear driven from A while B accesses, then ECC pulses
      from B crossing to clk_a, then BIST while B reads.
    - Results: **SV 122/122, VHDL 121/121** (38 dp2 runs each, 28 async).
- **tb_dp2 strengthened after weak mutant results (2/6 at first):**
  - Hot-word phase: both ports on one wide word, 2500 ops each.
  - Port-B writes during a clear, checked against `clr_done` timing.
  - White-box monitor (SV DUT): port B never selects the array while a
    clear/BIST pass runs or sleep pins are on.
  - dp2 rerun: **SV 38/38, VHDL 38/38**.
- **Mutants (`mut3c/run_mut3c.sh`, GENERIC dp2): stable 4/6 over 3 runs.**
  - Caught: RMW writes back all codewords, CDC quiet ignores hold, slice
    order reversed, want ignores engines.
  - Survive:
    - (a) No four-phase rule in `sram_cdc`: needs a want pulse shorter than
      the sync round trip. **Step 5 formal target:** "B never accesses the
      array while an engine runs or pins are on".
    - (b) Narrow-port read mux on the live slice select: equivalent under
      APB (address held through the response). **Step 4:** DP benches on
      AHB/AXI, where the next address can arrive in the response cycle.
- **Xcelium:** all 16 tops elaborate (SV + VHDL).
- **Not done:**
  - CDC lint (SpyGlass CDC, Step 8).
  - XPM / altsyncram dual clock and mixed width: unelaborated (no
    Vivado/Quartus on csun).
  - `sram_model` is still single-clock, same width; DP checking is
    tb_dp2's own scoreboard.
