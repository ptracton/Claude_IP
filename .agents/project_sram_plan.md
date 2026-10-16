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

## 0. Status snapshot (2026-10-15)

| Step | State |
|---|---|
| 0 — shared memory-bus adapters (IP/common) | **Done.** 32/32 PASS: lint 4/4, sim 20/20, formal 8/8, no waivers |
| 1 — `IP/system/sram` skeleton | **Done.** setup.md quality gate all PASS |
| 2 — SystemRDL | **Skipped by design** (no register block, D2) |
| 3 — RTL SV + VHDL, all options | **Done.** Scratch smoke tests PASS on GENERIC + all 4 PDKs, both languages |
| 4 — directed tests | **Next** |
| 5–12 | Not started |

**Nothing is committed.** The working tree also holds the SKY130 PDK move to `$HOME` and the
`CLAUDE_SKY130_PDK_PATH` env var, plus their doc and setup.sh edits (timer, bus_matrix,
.agents). Step 0 results: `IP/common/verification/mem_if/results.log`.

**Open items carried forward:**
- XILINX/ALTERA leaves are written but never elaborated (no Vivado/Quartus on csun). Verify
  on the standard host.
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

## 2. Architecture (as built, Step 3)

```
 sram_<proto> / sram_<proto>_dp            (apb, ahb, axi4l, wb; wiring only)
 ├── claude_<proto>_mem_if  (IP/common; one per port)
 └── sram_core
     ├── sram_port      x1 / x2   checks, ECC (sram_ecc_enc/dec), read-modify-write, response
     ├── sram_pwr_ctrl  per domain RUN -> enter -> sleep -> wake -> (clear) -> RUN
     ├── sram_clr       clear engine (clr_req_i, after reset with ECC, after shutdown)
     ├── sram_bist      March C- (BIST_EN)
     └── sram_array     NUM_BANKS banks x rows x columns
         └── sram_macro / sram_macro_dp -> sram_macro[_dp]_<generic|xilinx|altera|saed90|saed32|saed14|sky130>
```

- Files: 33 SV + 33 VHDL-2008 twins in `design/rtl/{verilog,vhdl}`, plus the
  transaction-level reference model `design/behavioral/sram_model.sv`. The model watches the
  memory bus and predicts every response.
- TECH selection: a `TECH` parameter dispatches through a generate block. Only the selected
  branch is elaborated (verified on VCS and Xcelium, SV and VHDL), so a host only needs its
  own macro library.
- Tiling: `sram_pkg::macro_width/depth` and the `*_dp` versions. SAED byte lanes use x8
  columns; SKY130 and the FPGA/generic leaves use native masks.
- Default 32 x 1024 with byte enables:
  - SAED90 / SAED32: 4 lanes of `8x1024` / `1024x8`.
  - SAED14: 2 rows x 4 lanes of `512x8`.
  - SKY130: 2 rows of `32x512`.
- Array ownership: BIST, then the clear engine, then the bus port(s). A pending engine stalls
  new grants and starts once the ports are idle. BIST and the clear engine never overlap
  (fixed a deadlock: a clear is still allowed while BIST waits for power).
- VHDL conventions: one-bit options are `natural` generics (for mixed-language binding).
  Derived widths come from package functions. SV derived parameters are localparams.

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
| 4 | Directed tests, SV + VHDL x 4 protos x single/dual: rw, byte enables, back2back, March sweep, AHB bursts, errors, power retention/loss/wake, clear, ECC (corr/uncorr/RMW), BIST (incl. fault injection), dual-port conflicts, config sweep incl. small DEPTHs (exercises SAED14 32x8); reference model as checker; backdoor preload/peek tasks | next |
| 5 | Formal (VC Formal): protocol checkers, `claude_mem_fv` with `INITIATOR_IS_DUT=0` on the core, symbolic-address data integrity with byte merge, power FSM legality, dual-port conflict ordering (incl. A waiting for B's RMW — not hit in smoke) | |
| 6 | UVM (VCS): random R/W + power-mode sequences, `sram_model` scoreboard | |
| 7 | Regression runner/report | |
| 8 | Lint: SpyGlass (csun) / Verilator + VHDL lint on a standard host (needs black-box stubs for the macros) | |
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
- **`DUAL_PORT`:** separate tops `sram_<proto>_dp` (ports `A_*` / `B_*`, shared clock/reset)
  on two-port macros.
  - **Changed from plan:** same-word conflicts are **serialized A then B**, not "A wins".
    B waits a cycle when either access writes, and a port waits for the other port's pending
    read-modify-write, so no write is dropped.
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
  conventions are in §2; decisions are recorded in spec.md as *[Step 3]* and in §9.
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
