# sram IP — Specification

Status: **final, Step 11 (2026-11-25).** Requirements agreed 2026-10-15 (see
`.agents/project_sram_plan.md`); RTL implemented 2026-10-15 (Step 3). Decisions
and results added by later steps are marked *[Step N]*. Verification and
implementation results are in the [README](../README.md).

## Overview

`sram` is a configurable on-chip static RAM with a bus slave port. It wraps
the SRAM macros of each supported technology behind one interface, so the
same RTL targets:

| `TECH` | Storage | Notes |
|---|---|---|
| `GENERIC` | behavioral array | simulation, formal, Yosys; portable inference |
| `XILINX` | `xpm_memory_spram` (block RAM: `MEMORY_PRIMITIVE "block"`, needed for the sleep pin) | used when Vivado is installed |
| `ALTERA` | `altsyncram` (M10K on Cyclone V) | used when Quartus is installed |
| `SAED90` | `SRAM<w>x<d>_1rw` macros | |
| `SAED32` | `SRAMLP1RW<d>x<w>` low-power macros | native light sleep / deep sleep / shutdown pins |
| `SAED14` | `SRAM1RW<d>x<w>` macros | |
| `SKY130` | OpenRAM `sky130_sram_*_1rw1r_*` macros | port 0 used as read/write, port 1 tied off |

Width and depth are parameters. Each ASIC technology wrapper builds the
requested size from its vendor primitives with generate loops: primitives in
parallel for width, stacked for depth, with the upper address bits selecting
the row. FPGA and generic memories are inferred whole; the tool tiles them.
Byte enables, power gating, ECC, per-bank power gating, built-in self-test
and a second port can each be turned on or off.

## Features

Always present:
- One bus slave port: APB4, AHB-Lite (bursts, HSIZE), AXI4-Lite or Wishbone B4.
  One top-level per protocol (`sram_apb`, `sram_ahb`, `sram_axi4l`, `sram_wb`),
  built on the shared `claude_<proto>_mem_if` adapters
  (`.agents/IP_SPEC_mem_bus.md`).
- Bus error for addresses beyond `DEPTH` words.
- Optional read pipeline register (`READ_LATENCY` = 1 or 2). *[Step 10]* With 2 the
  word read is registered at the array output and decoded (SECDED) in the next cycle,
  so the macro access and the decoder never share a cycle.
- Clear engine: a side-band request zeroes the whole array. It also runs
  automatically on wake-up from SHUTDOWN.
- Status outputs for a power controller / interrupt controller.

Optional (parameters, default off unless noted):
- `BYTE_EN` — byte-granular writes (default on).
- `PWR_GATE` — power modes RUN / LIGHT_SLEEP / DEEP_SLEEP / SHUTDOWN (default on).
- `ECC_EN` — SECDED per word, with error reporting and error injection.
- `BANK_PG` — an independent power mode per bank of macros.
- `BIST_EN` — March C- self-test engine.
- `DUAL_PORT` — a second bus port of the same protocol. *[Step 3]* Provided as
  separate top-levels `sram_<proto>_dp` (ports `A_*` / `B_*`). With SKY130
  port B is read-only (OpenRAM 1rw1r): writes get a bus error.
  - *[Step 3c]* Port B may have a **different width** (`WIDTH_B`, ratio a
    power of two; `DEPTH_B = WIDTH * DEPTH / WIDTH_B`, same storage,
    little-endian packing) and a **different clock** (`COMMON_CLK = 0`; each
    port has its own clock and reset pins).
  - With `COMMON_CLK = 1` same-word conflicts are **serialized A then B** (B
    waits a cycle when either writes; a port waits for the other's pending
    ECC read-modify-write), so no write is dropped. This replaces the planned
    "port A wins".
  - With `COMMON_CLK = 0` same-word collisions are undefined. The side-band
    runs on port A's clock, and port B reaches it through a CDC handshake
    (`sram_cdc`). `TECH_SAED14` needs `COMMON_CLK = 1`: its two-port macro has
    a write clock and a read clock.
  - ECC codewords are as wide as the narrower port.

There is no register block: all control and status is side-band pins.

## Parameters

| Parameter | Range | Default | Meaning |
|---|---|---|---|
| `TECH` | see Overview | `GENERIC` | storage implementation |
| `WIDTH` | 8..128 (multiple of 8 if `BYTE_EN`) | 32 | word width = bus data width |
| `DEPTH` | power of two | 1024 | number of words |
| `BYTE_EN` | 0/1 | 1 | byte-lane writes |
| `PARTIAL_WR_ERR` | 0/1 | 1 | `BYTE_EN = 0` only: a partial write is a bus error (1) or writes the full word (0) |
| `READ_LATENCY` | 1/2 | 1 | 2 adds a read pipeline register ahead of the ECC decoder (every response, writes too, comes `READ_LATENCY` cycles after the grant; *[Step 10]* an ECC read-modify-write with `READ_LATENCY = 1` comes one cycle later) |
| `PWR_GATE` | 0/1 | 1 | power modes |
| `ECC_EN` | 0/1 | 0 | SECDED; *[Step 3]* the array is cleared after reset so every word holds a valid codeword |
| `BANK_PG` | 0/1 | 0 | per-bank power modes |
| `BIST_EN` | 0/1 | 0 | March C- engine |
| `DUAL_PORT` | 0/1 | 0 | second bus port (core parameter; *[Step 3]* exposed as the `sram_<proto>_dp` top-levels) |
| `WIDTH_B` | 8..128, `WIDTH / WIDTH_B` a power of two | `WIDTH` | *[Step 3c]* port B width (dual port) |
| `BYTE_EN_B`, `PARTIAL_WR_ERR_B`, `READ_LATENCY_B` | as port A | port A's | *[Step 3c]* port B options. VCS-MX evaluates the VHDL default from port A's default, not its actual, when Verilog instantiates the VHDL top: set them explicitly there. *[Step 10]* VHDL: `WIDTH_B` / `READ_LATENCY_B` default 0 and `BYTE_EN_B` / `PARTIAL_WR_ERR_B` default 2, meaning "as port A" (Design Compiler rejects a generic default that names another generic) |
| `COMMON_CLK` | 0/1 | 1 | *[Step 3c]* 1: one clock; 0: port B on its own clock (not SAED14) |
| `INIT_FILE` | path | "" | FPGA / simulation preload (`$readmemh` format) |

Default synthesized configuration (DC, PrimeTime, gate-level, power):
`WIDTH = 32`, `DEPTH = 1024` (4 KB), `BYTE_EN = 1`, `PWR_GATE = 1`, other
options off. Two more netlists cover the options: ECC + BANK_PG + BIST, and
DUAL_PORT.

## Memory Map

Word `n` is at byte offset `n * S` of the slave port, where the word
stride `S` is `WIDTH / 8` rounded up to a power of two (the address decode
takes the word index from `addr[log2(S) +: log2(DEPTH)]`). For a power-of-two
byte width the SRAM occupies `DEPTH * WIDTH / 8` bytes; a 24-bit word takes 4
bytes of address, and its byte lane 3 does not exist. Accesses at or beyond
`DEPTH * S` return the protocol's bus error and do not change the contents.
*[Step 4: corrected — the earlier text said `n * WIDTH / 8`, which is wrong
for widths that are not a power-of-two number of bytes.]*

*[Step 3c]* Dual port: port B sees the same bytes at the same offsets. Its
word `j` is at byte offset `j * WIDTH_B / 8`, and it has
`DEPTH_B = WIDTH * DEPTH / WIDTH_B` words. With different widths, packing is
little-endian: narrow word `j` is bits `[(j % R) * N +: N]` of wide word
`j / R` (R = width ratio, N = narrow width).

## Register Map

None. The sram has no register block, so there is no SystemRDL source and no
`doc/sram_regs.html` (design decision D2, 2026-10-15). Every control and
status function (power modes, clear, BIST, ECC injection and events) is a
side-band port; see Side-band ports. The firmware (`firmware/`) therefore has
no register driver: it has memory tests and side-band helpers.

## Interfaces

### Bus protocol top-levels

| Top | Bus | Notes |
|---|---|---|
| `sram_apb` | APB4 | zero-wait reads/writes when the macro answers in one cycle |
| `sram_ahb` | AHB-Lite | HSIZE byte lanes, INCR/WRAP bursts, BUSY; HREADY in, HREADYOUT out |
| `sram_axi4l` | AXI4-Lite | one read and one write in flight, alternated |
| `sram_wb` | Wishbone B4 classic | ERR_O on error |
| `sram_<proto>_dp` | two of the above (`A_*`, `B_*`) | *[Step 3c]* each port has its own clock and reset pins (with `COMMON_CLK = 1` drive both from one clock); port B's data and strobes are `WIDTH_B` wide |

### Side-band ports

| Port | Dir | Meaning |
|---|---|---|
| `pwr_mode_req_i[1:0]` | in | requested mode: 0 RUN, 1 LIGHT_SLEEP, 2 DEEP_SLEEP, 3 SHUTDOWN (`BANK_PG`: one field per bank) |
| `pwr_mode_ack_o[1:0]` | out | mode now in effect (changes only once the transition is complete) |
| `clr_req_i` / `clr_done_o` | in/out | zero the array; done pulse |
| `busy_o` | out | clear, BIST, wake-up or ECC read-modify-write in progress |
| `err_irq_o` | out | pulse on bus error / ECC event (*[Step 3]* registered, one cycle after the response) |
| `ecc_corr_o`, `ecc_uncorr_o`, `ecc_inj_i[1:0]` | | `ECC_EN` only; pulses registered; injection applies to the next port-A write |
| `bist_start_i`, `bist_done_o`, `bist_fail_o`, `bist_fail_addr_o` | | `BIST_EN` only |

*[Step 3c]* All side-band ports are synchronous to port A's clock, including
in a dual-port top with `COMMON_CLK = 0`. Port B's ECC and error events reach
`ecc_*_o` / `err_irq_o` through pulse synchronizers, a few cycles later;
events closer together than about three port-A cycles merge into one pulse
(use the pulses as event flags, not exact counts).

### Power modes

| Mode | Contents | Bus access | SAED32-LP pins | Other ASIC PDKs | FPGA |
|---|---|---|---|---|---|
| RUN | kept | normal | — | — | — |
| LIGHT_SLEEP | kept | wakes automatically, with wait states | LS | chip select held off; outputs isolated (UPF) | CE / `sleep` |
| DEEP_SLEEP | kept | **bus error** | DS | chip select held off; outputs isolated (UPF) | CE / `sleep` |
| SHUTDOWN | **lost** (cleared on wake-up) | **bus error** | SD | power switched off (UPF), outputs isolated | contents marked invalid in simulation |

Transitions honour each macro's databook timing; the wake-up latency becomes
bus wait states or delays `pwr_mode_ack_o`. *[Step 10]* The SAED32-LP counts
meet the databook up to 180 MHz (deep-sleep wake: 9 cycles >= tDSFCRS 50 ns);
the IP is specified at 100 MHz (README "Power Management").

*[Step 12]* The macro clocks are not gated: the macro liberties charge clock
energy on every edge, so the macros' clock power (> 95 % of the total on
SAED14 / SKY130, README "Power Analysis") is spent in every mode in which the
supply is on. Per-bank macro clock gating is a possible improvement.

*[Step 10]* Power intent (`design/upf/`, IEEE 1801): on SAED90, SAED14 and
SKY130 each power domain's macros form a switched domain, powered while
`sd_o` of its `sram_pwr_ctrl` is low, with outputs clamped to 0 while
`awake_o` is low (any mode but RUN). LIGHT_SLEEP and DEEP_SLEEP keep the
supply on: these macros have a single supply, so DEEP_SLEEP's "periphery off"
is not expressed. SAED32-LP uses its own SD / LS / DS pins and one always-on
domain. Checked with VC LP (`verification/tools/lp_sram.py`).

## Technology Mapping

| PDK | Macro family | Byte mask | Byte-enable strategy |
|---|---|---|---|
| SAED90 | `SRAM<w>x<d>_1rw` | no | one column of 8-bit macros per byte lane |
| SAED32 | `SRAMLP1RW<d>x<w>` | no | 8-bit macro columns per lane |
| SAED14 | `SRAM1RW<d>x<w>` | no | 8-bit macro columns per lane |
| SKY130 | `sky130_sram_2kbyte_1rw1r_32x512_8` and others | yes (`wmask`) | native |
| XILINX / ALTERA / GENERIC | inferred / primitive | yes | native (ALTERA with one lane, e.g. a 39-bit ECC word: `byteena` tied high, the lane enable gates `wren`) |

*[Step 3c]* Two-port primitives and their clocking (dual port):

| PDK | Two-port family | Clocks | `COMMON_CLK = 0` |
|---|---|---|---|
| SAED90 | `SRAM<w>x<d>` (w 8/32/39, d 16..128) | CE1 port A, CE2 port B | yes |
| SAED32 | `SRAMLP2RW<d>x<w>` | CE1 port A, CE2 port B | yes |
| SAED14 | `SRAM2RW<d>x<w>` | CE1 writes of both ports, CE2 reads of both ports (liberty and model) | **no**: `sram_core` stops elaboration |
| SKY130 | OpenRAM `1rw1r` (port B read-only) | clk0 port A, clk1 port B | yes |
| XILINX / ALTERA / GENERIC | `xpm_memory_tdpram` / altsyncram BIDIR / inferred | `independent_clock` / clock0 + clock1 / two processes | yes |

With different port widths, every technology uses R slices of the narrow
width per bank; FPGA mixed-width primitives are not used.

Default 32 x 1024 on SKY130 = two 32 x 512 macros stacked in depth.
*[Step 3b]* Each `sram_macro[_dp]_<tech>` ASIC wrapper is a W x D memory of
`ROWS x COLS` primitives of one size, chosen by `sram_pkg` (`prim_width`,
`prim_depth`, `prim_width_dp`, `prim_depth_dp`): `ROWS = D / PRIM_D` selected by
the upper address bits, `COLS = ceil(W / PRIM_W)`. Example: 16 x 2048 on SAED32
= 2 rows x 2 columns of `1024x8`. `sram_array` only splits the array into
`NUM_BANKS` power-domain banks. Exact primitive lists are in the README's
Design Architecture table. Quirks handled: SAED14 single-port `CSB` is
active high (two-port and SAED90/32 active low); `SRAM1RW32x8` has a 32-bit
`I` bus; the SAED14 and SKY130 simulation models need fixes, generated by
`IP/common/verification/tools/pdk_sram_models.py`.

## Timing

*[Step 4]* **Core.** Every response, writes included, comes `READ_LATENCY` (1 or 2) cycles
after the grant on the memory bus. An ECC partial write is a read-modify-write: it reads in
the grant cycle, registers the raw word (s1), and merges, encodes and writes back in s2, so
with `READ_LATENCY = 1` it answers one cycle later than other accesses. The macro access and
the SECDED decode / encode never share a cycle. A pending clear or BIST stops new grants, and
a domain waking from light sleep adds wait states (entry / wake counts under Power).

**Bus adapters** (`.agents/IP_SPEC_mem_bus.md`; SRAM answering at full speed,
`READ_LATENCY = 1`, attached directly):

| Protocol | Read / write | 16 transfers (measured, `test_burst` / `test_pipeline`) |
|---|---|---|
| APB4 | 2 cycles, zero wait (request issued in SETUP) | 32 cycles |
| AHB-Lite | one wait state per beat, SEQ included | 16-beat INCR burst: 33 cycles |
| AXI4-Lite | AR→R and AW/W→B 3 cycles; one read and one write in flight | 64 cycles one at a time; 16 writes + 16 reads interleaved and pipelined: 66 instead of 128 |
| Wishbone B4 | ACK 1 cycle after STB (classic cycles) | 32 cycles |

With `READ_LATENCY = 2`, AXI4-Lite one at a time takes 80 cycles for 16 (one more per
transfer); pipelined and interleaved, 98. Through the
bus matrix every beat is a single transfer (AHB: 4 cycles per beat).

*[Step 10]* **Achieved clock** (target 100 MHz, 10 ns; base / opts / dp configurations x 4
buses x SV / VHDL netlists; DC with a 0.2 ns setup margin, PrimeTime setup and hold):

| Target | Result | Worst setup slack |
|---|---|---|
| SAED32 | 24/24 met | +3.53 ns |
| SAED14 | 24/24 met | +0.42 ns |
| SKY130 SS / TT / FF | 24/24 met at each corner (TT macro timing, see Known Limitations) | +0.18 / +1.28 / +1.42 ns |
| SAED90 | 2/24 met, accepted (user decision 2026-11-25): about 98 MHz (base, RL 1) down to about 88 MHz (opts, dp); the AXI4-Lite dual port's -35 / -42 ns is a wire-load-model artefact | -0.20 to -1.4 ns |
| Xilinx xc7z010-1 (Vivado, OOC) | 24/24 met | +0.57 ns (opts) .. +4.63 ns |
| Altera 5CSEMA4U23C6 (Quartus) | Analysis & Synthesis only (no timing run) | — |

Details: README "Synthesis Results", `synthesis/known_issues.md`.

## Resource Utilization

*[Step 10]* Three synthesized configurations, each for 4 buses x SV / VHDL
(ranges over those 8 netlists): **base** = WIDTH 32, DEPTH 1024, BYTE_EN,
PWR_GATE; **opts** = base + ECC_EN, BANK_PG (2 banks), BIST_EN, READ_LATENCY 2;
**dp** = opts + 8-bit port B on its own clock (SAED14: common clock).

ASIC (Design Compiler, SRAM macros; area in library units, µm² for SAED32,
SAED14 and SKY130; logic = total - macros; `synthesis/designcompiler/report_<pdk>.txt`):

| PDK | Config | Cells | Macros | Logic area | Total area |
|---|---|---|---|---|---|
| SAED90 | base / opts / dp | 325-760 / 1,573-2,031 / 2,524-3,965 | 4 / 10 / 64 | 2,783-8,943 / 17,290-23,594 / 26,585-41,464 | 583,351-589,511 / 830,915-837,219 / 2,059,543-2,074,421 |
| SAED32 | base / opts / dp | 367-856 / 1,528-2,019 / 2,467-3,306 | 4 / 10 / 64 | 1,052-2,546 / 4,748-6,244 / 7,795-10,173 | 478,822-480,316 / 1,199,173-1,200,669 / 1,687,054-1,689,431 |
| SAED14 | base / opts / dp | 337-701 / 1,300-1,677 / 1,492-2,137 | 8 / 10 / 16 | 127-347 / 605-828 / 633-1,010 | 211,666-211,886 / 265,029-265,252 / 699,858-700,236 |
| SKY130 | base / opts / dp | 370-738 / 1,605-1,997 / 1,874-2,950 | 2 / 10 / 16 | 2,694-7,351 / 13,200-17,657 / 14,878-24,560 | 571,771-576,428 / 2,045,933-2,050,389 / 3,267,250-3,276,932 |

The macros are at least 97 % of the total area in every netlist (lowest
per PDK: SAED90 97.2 %, SKY130 98.7 %, SAED32 99.4 %, SAED14 99.7 %). AXI4-Lite has the most
logic of the four buses in every configuration.

FPGA and open-source (standard host; `synthesis/{vivado,quartus,yosys}/report.txt`):

| Tool | base | opts | dp |
|---|---|---|---|
| Vivado (xc7z010-1): LUTs / FFs / BRAM tiles | 121-163 / 31-170 / 1 | 395-473 / 218-360 / 2 | 474-533 / 201-432 / 4 |
| Quartus (5CSEMA4U23C6): ALMs (est.) / registers / M10K bits | 100-133 / 32-170 / 32,768 | 333-398 / 222-360 / 39,936 | 422-484 / 205-434 / 53,248 |
| Yosys (generic cells): cells / memories | 284-529 / 1 (SV), 4 (VHDL) | 1,396-1,676 / 2 | 1,604-2,980 / 13 (SV), 8 (VHDL) |

## Tools and Versions

| Flow | Tool | Version | Host |
|---|---|---|---|
| Directed simulation, gate-level, UVM | Synopsys VCS MX (+ URG coverage) | Y-2026.03-SP1 | csun.edu |
| Directed simulation | Cadence Xcelium | 25.03 | csun.edu |
| Formal | Synopsys VC Formal | Y-2026.03-SP1 | csun.edu |
| Lint and CDC (SV) | Synopsys SpyGlass (`spyglass_vc`, VC Static) | Y-2026.03-SP1 | csun.edu |
| Low power (UPF) | Synopsys VC LP (VC Static) | Y-2026.03-SP1 | csun.edu |
| ASIC synthesis, STA, power | Synopsys Design Compiler, PrimeTime, PrimePower, Library Compiler | csun.edu install (version not recorded in the reports) | csun.edu |
| Directed simulation (SV), lint (SV) | Verilator (OSS CAD Suite) | 5.043 | standard host |
| Directed simulation (SV + VHDL, FPGA leaves) | Vivado xsim | 2023.2 | standard host |
| Lint (VHDL) | GHDL | 6.0.0-dev | standard host |
| FPGA synthesis | Vivado / Quartus Prime Lite | 2023.2 / 23.1std.1 | standard host |
| Open-source synthesis | Yosys (slang and ghdl plugins) | 0.60 | standard host |
| Firmware cross build | arm-none-eabi-gcc / riscv-none-elf-gcc (xPack) | 13.2.1 / 15.2.0 | standard host |

## Known Limitations

- SKY130 OpenRAM macros ship liberty for the typical corner only (except the
  older `sram_1rw1r_32_256_8`), so SS/FF timing of the macros is limited.
  *[Step 10]* DC links the TT macro library with the SS standard cells, and
  PrimeTime uses the TT macro timing at SS and FF too, so the SKY130 SS / FF
  results are approximate for the macro paths (`synthesis/known_issues.md`).
- No VHDL lint on csun.edu (SpyGlass has no working VHDL-2008 path).
- *[Step 3c]* Dual port with `COMMON_CLK = 0`:
  - same-word accesses in overlapping cycles are undefined;
  - port B's clock must keep running while the core changes power modes or
    runs the clear / BIST engines (it waits for port B to acknowledge);
  - not available with `TECH_SAED14`.
  - The XPM / altsyncram dual-clock leaves are verified on the standard host
    (2026-11-25): Vivado xsim directed tests (XILINX with SV tops, ALTERA with SV
    and VHDL tops) and Vivado / Quartus synthesis. With `COMMON_CLK = 1` the
    altsyncram leaf clocks both ports on either chip select, so each port's write
    enable is gated with its own chip select.
- *[Step 10]* SAED90 does not meet 100 MHz (2/24 netlists; -0.20 to -1.4 ns,
  about 98 to 88 MHz), accepted (user decision 2026-11-25). Its gate-level
  simulation with SDF has 8 known failures that pass without SDF.
- *[Step 12]* SAED32 macro power cannot be estimated: the vendor SRAMLP liberty
  has negative input-pin internal power, so only logic power is reported. The
  macro clocks are free-running, which makes the macros over 95 % of the power.
- *[Step 10]* Vendor simulation-model bugs (SAED14 / SKY130 macros, SAED90
  set/reset flip-flops, SKY130 OpenRAM read delay) are fixed in generated copies
  under `IP/common/verification/tools/`; the vendor files are not edited.
- *[Step 11]* Standard-host simulation limits: Verilator runs the GENERIC
  technology only (the PDK models are on csun.edu). Vivado xsim has no VPI and
  cannot write or force into VHDL, so it skips the backdoor checks, the
  stuck-bit faults with a VHDL top, and XILINX with a VHDL top (synthesized in
  Vivado instead). Quartus Prime Lite reads SystemVerilog-2005 only, so it
  synthesizes generated copies of the SV (`synthesis/quartus/quartus_sv.py`).
- Formal (VC Formal) and UVM run only on csun.edu; there is no SymbiYosys or
  xsim UVM flow.

## Planned Improvements

None committed. Candidates, not requested:
- per-bank macro clock gating (the free-running macro clocks dominate power);
- deeper AW / W / AR slots in `claude_axi4l_mem_if`, so AXI4-Lite streams of
  one kind (writes only or reads only) pipeline too (`IP/common`);
- SymbiYosys formal and UVM on xsim, so the standard host covers every flow.
