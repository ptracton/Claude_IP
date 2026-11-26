# sram

## Overview

Configurable on-chip SRAM with a bus slave port. One RTL source targets
every supported technology by wrapping its SRAM primitives: the SAED90,
SAED32 and SAED14 macros, SkyWater SKY130 OpenRAM macros, Xilinx XPM block
RAM, Intel/Altera `altsyncram`, and a generic behavioral array.

Key features:
- **Bus interfaces:** APB4, AHB-Lite (bursts, HSIZE), AXI4-Lite and Wishbone B4,
  one top-level each, built on the shared `claude_<proto>_mem_if` adapters.
- **Configurable size:** width and depth are parameters. Each ASIC technology
  wrapper builds the requested width x depth from its vendor primitives, with
  generate loops: primitives side by side for width, stacked for depth (the
  upper address bits pick the row). FPGA and generic memories are inferred
  whole and the tool does the tiling.
- **Byte enables (optional):** native byte masks where the macro has them,
  otherwise one column of 8-bit primitives per byte lane.
- **Power gating:** RUN / LIGHT_SLEEP / DEEP_SLEEP / SHUTDOWN through a
  side-band request/acknowledge pair. These map onto the SAED32 low-power
  macros' LS/DS/SD pins, or onto UPF power domains with isolation on the
  other ASIC PDKs.
- **Always present:** bus error for out-of-range addresses and for access to a
  deep-sleeping or shut-down array, optional output register, clear engine,
  status outputs.
- **Optional, each switchable by a parameter:** SECDED ECC, per-bank power
  gating, March C- built-in self-test, and a second bus port. The second port
  may have a different width (and so depth) and its own clock.

There is **no register block** and therefore no SystemRDL step: all control
and status uses side-band pins (design decision D2, 2026-10-15).

Full requirements: [doc/spec.md](doc/spec.md).

## Design Architecture

Eight top-levels: one per bus protocol, each single-port or dual-port. All of
them share one protocol-independent core. A top-level contains only wiring.

```
 sram_<proto>  /  sram_<proto>_dp            (apb, ahb, axi4l, wb)
 ├── claude_<proto>_mem_if   (IP/common; one per port)   bus -> Claude memory bus
 └── sram_core
     ├── sram_port            per bus port: checks, ECC, read-modify-write, response
     │   ├── sram_ecc_enc / sram_ecc_dec   SECDED, one per codeword (ECC_EN)
     ├── sram_cdc             port B on its own clock (COMMON_CLK = 0): permission
     │                        handshake, claude_sync / claude_pulse_sync (IP/common)
     ├── sram_pwr_ctrl        one power state machine per domain (whole array or bank)
     ├── sram_clr             clear engine (clr_req_i, after reset with ECC, after shutdown)
     ├── sram_bist            March C- engine (BIST_EN)
     └── sram_array           NUM_BANKS banks (power domains), bank select + read mux;
                              dual port with different widths: R slices per bank
         └── sram_macro / sram_macro_dp      TECH dispatcher (single- / two-port), any W x D
             └── sram_macro[_dp]_<tech>      saed90 | saed32 | saed14 | sky130: rows x columns
                                             of vendor primitives; generic | xilinx | altera:
                                             one inferred memory
```

**Request flow.** The bus adapter turns each transfer into one memory-bus
request (`IP/common/design/rtl/mem_bus.md`). `sram_port` handles it in three
stages:

1. **Request cycle.** The request is checked. It is held back (no grant) while
   an engine owns the array, or while its power domain is waking from light
   sleep. It is granted with an error response when:
   - the address is beyond `DEPTH` words;
   - it is a partial write with `BYTE_EN = 0` and `PARTIAL_WR_ERR = 1`;
   - its domain is requested into deep sleep or shutdown;
   - it is a write on SKY130's read-only port B.

   Otherwise it accesses the array. An ECC partial write reads the word first.
2. **Next cycle (s1).** With `READ_LATENCY = 1` the word read is decoded and
   the response returned. With `READ_LATENCY = 2`, and for every ECC partial
   write, the raw word is registered at the array output instead.
3. **s2** (`READ_LATENCY = 2`, ECC partial writes). The registered word is
   decoded and the response returned; a read-modify-write merges the strobed
   bytes, encodes and writes back in this cycle, so with `READ_LATENCY = 1` it
   answers one cycle later than other accesses. The macro access and the
   SECDED decode / encode never share a cycle (Step 10 timing closure).

**Array ownership.** Self-test has priority over the clear engine, and the
clear engine over the bus port(s). A pending engine stops new grants, and
starts once the ports are idle.

**Dual port.** Ports A and B run in parallel on two-port macros.
- *Widths.* Port B has `WIDTH_B` bits (`WIDTH / WIDTH_B` a power of two
  either way) and `DEPTH_B = WIDTH * DEPTH / WIDTH_B` words of the same
  storage. Both ports use the same byte addresses: narrow word `j` is bits
  `[(j % R) * N +: N]` of wide word `j / R` (little-endian, `R` = ratio, `N` =
  narrow width). `sram_array` builds each bank from `R` slices of the narrow
  width: the wide port drives all slices, the narrow port one.
- *ECC.* Codewords are as wide as the narrower port, and each codeword is one
  write lane. A narrow write never needs a read of the wide word, and a wide
  read-modify-write only writes back the codewords it strobes.
- *Clocks.* Each port has its own clock and reset pins.
  - `COMMON_CLK = 1` (default): drive both clock pins from the same clock.
    Same-word conflicts complete in the order A then B: B waits a cycle if
    either access writes, and a port waits while the other port's
    read-modify-write of that word is pending. Conflicting writes are
    serialized, never dropped.
  - `COMMON_CLK = 0`: the clocks are unrelated, and same-word accesses in
    overlapping cycles are undefined (as on any true dual-port RAM). Power,
    clear, BIST and status stay on port A's clock. Port B reaches them
    through `sram_cdc`: a four-phase permission handshake per power domain,
    built from 2-flop synchronizers (`claude_sync`, `claude_pulse_sync` in
    IP/common). The core takes the permission back, and waits for port B's
    last access to finish, before a domain sleeps or an engine starts. Port
    B's clock must keep running while that happens.
  - SAED14's two-port macro (`SRAM2RW`) has a write clock and a read clock,
    not one clock per port (liberty and model agree), so `TECH_SAED14` needs
    `COMMON_CLK = 1`. SAED90, SAED32, SKY130 and the FPGA/generic memories
    support both modes.

**Tiling.** `sram_array` splits the array into `NUM_BANKS` banks of
`DEPTH / NUM_BANKS` words, one `sram_macro` wrapper each. Each ASIC wrapper
(`sram_macro[_dp]_<tech>`) builds its W x D bank from vendor primitives:
- `sram_pkg::prim_width` / `prim_depth` (and the `_dp` versions) pick one
  primitive size `PRIM_W x PRIM_D`: the deepest available one that is not
  deeper than D.
- `ROWS = D / PRIM_D` primitives are stacked in depth. The address bits above
  the primitive address drive the rows' chip selects, and a registered row
  select steers the read multiplexer. If D is smaller than every primitive,
  there is one row and the top address bits are tied to 0.
- `COLS = ceil(W / PRIM_W)` primitives sit side by side. The last column is
  zero-padded when `PRIM_W` does not divide W.
- SAED primitives have no byte mask, so each column must lie inside one write
  lane (byte lanes use 8-bit primitives). This is checked at elaboration.
  SKY130 primitives have a native byte mask.

For example, 16 x 2048 on SAED32 uses `1024x8` primitives in 2 rows x 2
columns, with `addr[10]` selecting the row. GENERIC, XILINX and ALTERA
infer one W x D memory per bank (`xpm_memory_*` / `altsyncram` accept any
size) and leave block-RAM cascading to Vivado / Quartus.

| TECH | Single-port macros | Two-port macros | Byte mask |
|---|---|---|---|
| GENERIC | behavioral array | behavioral array | yes |
| XILINX | `xpm_memory_spram` | `xpm_memory_tdpram` | yes |
| ALTERA | `altsyncram` SINGLE_PORT | `altsyncram` BIDIR_DUAL_PORT | yes |
| SAED90 | `SRAM{8,32}x{64..1024}_1rw` | `SRAM{8,32}x{16..128}`, `SRAM39x32` | no (x8 lanes) |
| SAED32 | `SRAMLP1RW{64..1024}x{8,32}` | `SRAMLP2RW{16..128}x{8,32}` | no (x8 lanes) |
| SAED14 | `SRAM1RW{16..512}x{8,32}` | `SRAM2RW{16..512}x{8,32}` | no (x8 lanes) |
| SKY130 | OpenRAM `sky130_sram_*_1rw1r_*` (port 1 unused) | same macros, port B read-only | yes (`wmask`) |

Default configuration (32 x 1024, byte enables): SAED90/SAED32 use 1 row x 4
columns of `8x1024` / `1024x8`; SAED14 uses 2 rows x 4 columns of `512x8`;
SKY130 uses 2 rows x 1 column of `32x512`.

**Macro and model quirks handled:**
- The SAED14 single-port macros have an active-high `CSB`. The two-port macros
  have an active-low `CSB`, as do SAED90 and SAED32.
- `SRAM1RW32x8` has a 32-bit `I` bus, in the model and in the liberty.
- The SAED14 SRAM simulation models never drive their outputs, and the SKY130
  OpenRAM models use their memory array before declaring it. Both are fixed in
  generated copies by `IP/common/verification/tools/pdk_sram_models.py`; the
  vendor files are not modified.

## Parameters and Memory Map

| Parameter | Range | Default | Meaning |
|---|---|---|---|
| `TECH` | `sram_pkg::TECH_*` (0..6) | GENERIC | storage implementation |
| `ADDR_W` | >= log2(DEPTH x WIDTH/8) | 32 | bus byte-address width |
| `WIDTH` | 8..128, multiple of 8 | 32 | word width = bus data width |
| `DEPTH` | power of two >= 2 | 1024 | words |
| `BYTE_EN` | 0/1 | 1 | byte-lane writes |
| `PARTIAL_WR_ERR` | 0/1 | 1 | `BYTE_EN = 0`: a partial write is a bus error (1) or writes the whole word (0) |
| `READ_LATENCY` | 1/2 | 1 | 2 adds a read pipeline register ahead of the ECC decoder |
| `PWR_GATE` | 0/1 | 1 | power modes |
| `ECC_EN` | 0/1 | 0 | SECDED; the array is cleared after reset |
| `BANK_PG` | 0/1 | 0 | one power domain per bank (needs `PWR_GATE`) |
| `NUM_BANKS` | power of two, <= DEPTH/2 | 1 | banks |
| `BIST_EN` | 0/1 | 0 | March C- engine |
| `INIT_FILE` | path | "" | preload, GENERIC / FPGA, `NUM_BANKS = 1` |
| `RST_POL` | 0 | 0 | documents the reset polarity, which is carried by the bus reset pin |

Dual port is a separate top-level (`sram_<proto>_dp`), not a parameter of the
single-port top-levels. The dual-port top-levels add:

| Parameter | Range | Default | Meaning |
|---|---|---|---|
| `WIDTH_B` | 8..128, multiple of 8, `WIDTH / WIDTH_B` a power of two | `WIDTH` | port B data width; port B has `WIDTH * DEPTH / WIDTH_B` words |
| `BYTE_EN_B`, `PARTIAL_WR_ERR_B`, `READ_LATENCY_B` | as for port A | port A's | port B options (VHDL top instantiated from Verilog on VCS: set them explicitly, VCS takes the default from port A's *default*) |
| `COMMON_CLK` | 0/1 | 1 | 1: the B clock is the A clock; 0: unrelated clocks (not `TECH_SAED14`) |

**Memory map.** Word `n` sits at byte offset `n * S` of the slave port,
where the word stride `S` is `WIDTH / 8` rounded up to a power of two (a
24-bit word takes 4 bytes of address; its byte lane 3 does not exist).
Addresses at or beyond `DEPTH * S` get the bus error response, and the
contents are unchanged. Narrow AHB transfers use the byte lanes given
by HSIZE/HADDR. In a dual-port top, port B sees the same bytes at the same
offsets (its word `j` is at `j * WIDTH_B / 8`, `DEPTH_B` words).
Every response, writes included, comes `READ_LATENCY` cycles after the grant.

## Interfaces

### Bus ports

| Top-level | Bus signals | Notes |
|---|---|---|
| `sram_apb` | `PCLK PRESETn PSEL PENABLE PADDR PWRITE PWDATA PSTRB PRDATA PREADY PSLVERR` | PSLVERR on error |
| `sram_ahb` | `HCLK HRESETn HSEL HADDR HTRANS HWRITE HSIZE HWDATA HWSTRB HREADY HRDATA HREADYOUT HRESP` | bursts, BUSY, HSIZE; HREADY in / HREADYOUT out |
| `sram_axi4l` | `ACLK ARESETn AW* W* B* AR* R*` | BRESP/RRESP = SLVERR on error |
| `sram_wb` | `CLK_I RST_I CYC_I STB_I WE_I ADR_I DAT_I SEL_I DAT_O ACK_O ERR_O` | classic cycles; ERR_O on error |
| `sram_<proto>_dp` | the above, twice: `A_*` and `B_*`, each with its own clock and reset (`A_PCLK`/`B_PCLK`, ...); port B's data and strobes are `WIDTH_B` wide | side-band on port A's clock |

The bus adapter timing is described in `IP/common/design/rtl/mem_bus.md`.

### Side-band ports (all top-levels)

| Port | Dir | Width | Description |
|---|---|---|---|
| `pwr_mode_req_i` | in | 2 x NPD | requested power mode per domain (0 RUN, 1 LS, 2 DS, 3 SD); NPD = NUM_BANKS with BANK_PG, else 1 |
| `pwr_mode_ack_o` | out | 2 x NPD | mode in effect per domain (changes when a transition completes) |
| `clr_req_i` | in | 1 | clear the array (pulse) |
| `clr_done_o` | out | 1 | clear pass finished (pulse) |
| `busy_o` | out | 1 | clear, BIST, power transition or read-modify-write in progress |
| `err_irq_o` | out | 1 | bus error or ECC event (registered pulse) |
| `ecc_inj_i` | in | 2 | ECC: arm a 1-bit [0] / 2-bit [1] error on the next port-A write |
| `ecc_corr_o` | out | 1 | ECC: corrected error (registered pulse) |
| `ecc_uncorr_o` | out | 1 | ECC: uncorrectable error (registered pulse) |
| `bist_start_i` | in | 1 | BIST: start March C- (pulse) |
| `bist_done_o` | out | 1 | BIST: finished (pulse) |
| `bist_fail_o` | out | 1 | BIST: a word failed (valid from `bist_done_o` until the next start) |
| `bist_fail_addr_o` | out | log2(DEPTH) | BIST: first failing word |

Inputs of disabled options must be tied to 0. Their outputs stay 0. All
side-band ports are synchronous to port A's clock; with `COMMON_CLK = 0`,
port B's events reach `ecc_*_o` / `err_irq_o` through pulse synchronizers.

### `sram_core`

| Port group | Signals |
|---|---|
| clock / reset | `clk`, `rst_n` (synchronous, active low); `clk_b`, `rst_b_n` for port B (single port: tie to `clk` / `rst_n`) |
| memory bus, port A | `mem_req_i mem_gnt_o mem_we_i mem_addr_i mem_be_i mem_wdata_i mem_rvalid_o mem_rdata_o mem_err_o` |
| memory bus, port B | the same names with `mem_b_`, `WIDTH_B` wide (DUAL_PORT; tie off otherwise) |
| side-band | as the table above |

## Power Management

Each power domain (the whole array, or one bank with `BANK_PG`) has its own
state machine: RUN -> enter -> sleep -> wake -> (clear) -> RUN. A domain only
enters a sleep mode when no access to it is in flight. `pwr_mode_ack_o`
changes only once a transition is complete.

| Mode | Contents | Bus access | SAED32-LP pins | Other ASIC PDKs | FPGA |
|---|---|---|---|---|---|
| RUN | kept | normal | none | none | none |
| LIGHT_SLEEP | kept | wakes automatically (wait states), then re-enters LS | LS | chip select held off; supply on, outputs isolated (UPF) | XPM `sleep` / clock enable |
| DEEP_SLEEP | kept | bus error | DS | chip select held off; supply on, outputs isolated (UPF) | XPM `sleep` / clock enable |
| SHUTDOWN | lost; zeroed by the clear engine before RUN is acknowledged | bus error | SD | power switched (UPF), isolation | contents X in simulation |

Entry and wake times come from `sram_pkg::pwr_enter_cycles` /
`pwr_wake_cycles`. They default to 2/2/4/8 cycles (SAED32: 4/2/8/16).
*[Step 10]* The SAED32 values were checked against the SAED32-LP databook
(Table 1.10; each count holds its state for count + 1 cycles):

| Requirement | Needed | Count | At 100 MHz | Valid up to |
|---|---|---|---|---|
| pin active to low-leakage state (tLSI 1.8, tDSI / tSDI 2.5 ns) | 2.5 ns | enter 4 | 50 ns | > 333 MHz |
| LS release to next access (tLSFCRS) | 1.8 ns | wake 2 | 30 ns | > 333 MHz |
| DS release to next access (tDSFCRS) | 50 ns | wake 8 | 90 ns | **180 MHz** |
| SD release to next access (tSDFCRS) | 50 ns | wake 16 (then the clear) | 170 ns | 340 MHz |

The IP is specified at 100 MHz (the macro allows 333 MHz); above 180 MHz the
deep-sleep wake count must grow. The liberty has no arcs on SD / LS / DS (see
`synthesis/known_issues.md`), so STA does not check these times; the counts
are the guarantee. The other PDKs' counts are placeholders (no sleep pins; no
power-switch ramp data for the UPF switch). While BIST runs, every
domain is held in RUN.

### Power intent (UPF, Step 10)

`design/upf/sram_<pdk>.upf` (IEEE 1801) sets the PDK's voltage and loads the
shared `sram_power.upf` at the scope of a bus top-level, after the caller sets
`SRAM_NPD` and `SRAM_NUM_BANKS` for the configuration:

| PDK | Power intent |
|---|---|
| SAED90, SAED14, SKY130 | the macros have no sleep pins: always-on `PD_TOP` (bus interfaces, core control, bank multiplexers) and one switched domain `PD_MEM<d>` per power domain (its macro wrappers). Switch `SW_MEM<d>` on while `u_core/dom_sd[d]` is low (SHUTDOWN only); isolation `ISO_MEM<d>` clamps the domain's outputs to 0 while `u_core/dom_awake[d]` is low (any mode but RUN: it brackets the switch-off). SAED14 connects the single-rail macros' VDD/VSS explicitly |
| SAED32-LP | one always-on domain: the SRAMLP macros take SD / LS / DS from `sram_pwr_ctrl` |

LIGHT_SLEEP and DEEP_SLEEP keep the supply on (these macros have one supply,
so "periphery off" cannot be expressed); the core never accesses a domain
outside RUN. Checked with VC LP by `verification/tools/lp_sram.py` (UPF and
design stages, 4 PDKs x base / opts / dp): 12/12 PASS, 0 errors; the only
findings are the isolation cells synthesis has not inserted yet (expected at
RTL, listed in `verification/lp/lp_results.log`). A copy without the
isolation strategy fails with 78 `ISO_STRATEGY_MISSING` errors. The DC / STA
/ post-synthesis netlists are synthesized without the UPF (no isolation or
switch cells; user decision 2026-11-25).

## Simulation Results

Directed simulation (Step 4), results generated 2026-10-18 and re-run 2026-11-21
(after the Step 5 RTL fixes) on a `*.csun.edu`
host with Synopsys VCS Y-2026.03-SP1 and Cadence Xcelium 25.03. One
SystemVerilog testbench verifies both the SystemVerilog and the VHDL
top-levels: with `--lang vhdl` the SRAM tops and the bus matrices are the
VHDL-2008 twins (mixed-language simulation), and the BFMs, tests and reference
models are unchanged.

```bash
source IP/system/sram/setup.sh
python3 verification/tools/sim_sram.py --sim all --proto all --lang all --tech all --coverage --jobs 10
```

Results: `verification/work/results.log` (one line per run),
`verification/work/<sim>/<proto>_<lang>_<tech>/{compile,sim,results}.log`, and coverage
in `verification/work/coverage/` (below).

### Test bench

`verification/testbench/tb_sram_<proto>.sv` (one per bus, sharing
`sram_tb_body.svh`) reaches the SRAMs through `bus_matrix_<proto>`
(`IP/interface/bus_matrix`), one matrix per data width, plus two SRAMs
attached directly to a master:

| Instance | Width (A / B) | Depth | Options | Reached through |
|---|---|---|---|---|
| s32 | 32 | 1024 | default | 32-bit matrix (2 masters) |
| s32e | 32 | 512 | ECC, BIST, BANK_PG x2, READ_LATENCY 2 | 32-bit matrix |
| dp0 | 32 / 8 | 256 | dual port, port B on its own clock, ECC (8-bit codewords), BIST | 32-bit / 8-bit matrices |
| dp2 | 32 / 32 | 256 | dual port, one clock, ECC, BANK_PG x2, RL 2 (B inherits A's) | 32-bit matrix (CPU on A, DMA on B) |
| s8 | 8 | 2048 | READ_LATENCY 2, second clock domain | 8-bit matrix |
| dp3 | 8 / 8 | 4096 | dual port, one clock (several primitive rows per leaf) | 8-bit matrix |
| s16 | 16 | 4096 | BYTE_EN 0, partial write = ERROR | 16-bit matrix |
| s16w | 16 | 64 | BYTE_EN 0, partial write = full word, PWR_GATE 0 | 16-bit matrix |
| dp1 | 16 / 64 | 1024 | dual port, one clock, B: BYTE_EN 0, RL 2; BIST | 16-bit / 64-bit matrices |
| s24 | 24 | 256 | ECC | 24-bit matrix |
| s24b | 24 | 128 | BANK_PG x4 | 24-bit matrix |
| s64 | 64 | 512 | ECC, BIST, READ_LATENCY 2 | 64-bit matrix |
| s32p / s32q | 32 | 256 | READ_LATENCY 1 / 2 | direct (no matrix) |

Masters (`sram_tb_<proto>_master.sv`) run a beat list one transfer at a
time; AHB pipelines address and data phases. The AXI4-Lite master also has a
pipelined mode (`set_pipelined(1)`): beats issue in order without waiting for
earlier responses, reads and writes overlap, and a beat waits while a
transaction of the other direction to the same word is in flight (program
order, as a real AXI master keeps it).

Checking: every read is compared with a byte-level shadow memory at the
master, and one `sram_model` per SRAM (`design/behavioral/sram_model.sv`)
checks every response on the memory bus inside the top-level: its data, its
error flag, and its timing (READ_LATENCY / READ_LATENCY_B cycles after the
grant, on each port). A run passes only with zero model mismatches. GENERIC
runs also flip stored bits through a backdoor
(`IP/common/verification/dpi/claude_backdoor.c`: VPI for SV storage, VHPI for
VHDL storage).

### Tests

| Test | What it checks | Checks (AHB, GENERIC) |
|---|---|---|
| test_reset | every port answers after reset; ECC arrays cleared; second reset with data | 20 |
| test_params | data and address walks, power-of-two boundaries, full sweep of every port, range error (SRAM) and decode error (matrix), `err_irq_o` | 18 rows, 90k comparisons |
| test_access | every size at every aligned offset, all write-strobe patterns, unaligned address (AHB), unaligned stores/loads split into legal transfers, BYTE_EN 0 behaviour | 54 |
| test_burst | INCR4/8/16, WRAP4/8/16, undefined-length INCR, BUSY, byte bursts (AHB); same address sequences back to back on the other buses | 68 |
| test_pipeline | READ_LATENCY 1 vs 2, pipelined write→read of one word, an error beat followed at once by a good one; AXI4-Lite: the master's pipelined mode (16 writes / 16 reads / 16 writes interleaved with 16 reads, faster than one at a time; same-word write→read keeps its order) | 6 (AHB), more on AXI4-Lite |
| test_contention | two masters on one SRAM and on two SRAMs at once | 3 |
| test_ecc | injected 1-bit (corrected, `ecc_corr_o`) and 2-bit (ERROR, `ecc_uncorr_o`) errors, RMW on clean / 1-bit / 2-bit words, backdoor flip of every stored bit and of bit pairs, read-path stuck bit on every stored bit (single errors) and, with an injected error, on every data bit (double errors) on every technology, dual-port codewords | 30 |
| test_power | LS auto-wake, DS (ERROR, kept), SD (ERROR, cleared), sleep-to-sleep moves, per-bank modes, PWR_GATE 0 | 28 |
| test_clear | clear on every instance, reads stall until `clr_done_o`, domains in DS skipped | 16 |
| test_bist | March C- pass, reads stall, stuck-at fault found with its address, sleeping domains woken | 10 |
| test_dp | width packing both ways, both ports busy at once, same-word races, port B under the side-band (through the CDC), clear, ECC read-modify-write from port B | 10 |
| test_reset_busy | reset during BIST, clears, stalled reads and power transitions, then full recovery | 4 |

### Results (VCS / Xcelium, thousands of comparisons per run)

The same for both languages (identical comparison counts for SV and VHDL):

| Bus | Language | GENERIC | SAED90 | SAED32 | SAED14 | SKY130 |
|---|---|---|---|---|---|---|
| AHB-Lite | SV | PASS / PASS (121k) | PASS / PASS (120k) | PASS / PASS (120k) | PASS / PASS (120k) | PASS / PASS (94k) |
| AHB-Lite | VHDL | PASS / PASS (121k) | PASS / PASS (120k) | PASS / PASS (120k) | PASS / PASS (120k) | PASS / PASS (94k) |
| APB4 | SV | PASS / PASS (121k) | PASS / PASS (119k) | PASS / PASS (119k) | PASS / PASS (119k) | PASS / PASS (94k) |
| APB4 | VHDL | PASS / PASS (121k) | PASS / PASS (119k) | PASS / PASS (119k) | PASS / PASS (119k) | PASS / PASS (94k) |
| AXI4-Lite | SV | PASS / PASS (122k) | PASS / PASS (120k) | PASS / PASS (120k) | PASS / PASS (120k) | PASS / PASS (95k) |
| AXI4-Lite | VHDL | PASS / PASS (122k) | PASS / PASS (120k) | PASS / PASS (120k) | PASS / PASS (120k) | PASS / PASS (95k) |
| Wishbone | SV | PASS / PASS (121k) | PASS / PASS (119k) | PASS / PASS (119k) | PASS / PASS (119k) | PASS / PASS (94k) |
| Wishbone | VHDL | PASS / PASS (121k) | PASS / PASS (119k) | PASS / PASS (119k) | PASS / PASS (119k) | PASS / PASS (94k) |

80/80 runs pass. SKY130 runs make fewer comparisons because port B of its
dual-port macro is read-only (B writes are checked to get ERROR); only GENERIC
runs the backdoor checks. Re-run 2026-11-24 on the Step 10 RTL (registered
ECC read-modify-write, VHDL rewritten to the Design Compiler subset): 80/80
PASS.

Throughput, 32-bit SRAM at READ_LATENCY 1, attached directly: AHB 16-beat
INCR burst 33 cycles (2 per beat); APB 32 and Wishbone 32 cycles for 16
transfers; AXI4-Lite 64 cycles with one transaction at a time.

AXI4-Lite with the bench master in pipelined mode (several transactions in
flight; `test_pipeline`), cycles:

| SRAM | 16 writes | 16 reads | 16 writes + 16 reads interleaved | same-word write→read x8 |
|---|---|---|---|---|
| s32p (RL 1), one at a time | 64 | 64 | 128 | 64 |
| s32p (RL 1), pipelined | 64 | 64 | 66 | 50 |
| s32q (RL 2), one at a time | 80 | 80 | 160 | 80 |
| s32q (RL 2), pipelined | 80 | 80 | 98 | 66 |

A mixed read/write stream runs about twice as fast: `claude_axi4l_mem_if`
holds one write and one read at once, so the read and write channels
overlap. Writes alone (or reads alone) gain nothing: the adapter frees its
AW/W (or AR) slot only on the B (or R) handshake, so it accepts the next
request of the same kind only after the previous response. Deeper slots
would be an adapter change (`IP/common`), not made. Through a bus matrix every beat is a single transfer (AHB: 4
cycles per beat).

### Results (Verilator, standard host)

The SV bench also runs on Verilator 5.043 (`--sim verilator`, SV tops,
GENERIC only: the PDK cell models are on csun.edu). 4/4 pass with the same
comparison counts as VCS / Xcelium:

| Bus | Result | Comparisons | Model-checked responses | Build (wall) |
|---|---|---|---|---|
| AHB-Lite | PASS | 121,280 | 54,462 | ~5 min |
| APB4 | PASS | 121,109 | 54,398 | ~6 min |
| AXI4-Lite | PASS | 121,977 | 54,681 | ~50 min (C++ compiled one file at a time) |
| Wishbone | PASS | 121,109 | 54,398 | ~5 min |

Each run simulates in 3-6 s. The build and run are capped at 8 GB
(`systemd-run --user --scope -p MemoryMax=8G`; `SRAM_VERILATOR_MEM`
overrides) and Verilator runs go one at a time; Verilator itself allocates
0.9-1.9 GB. The AXI4-Lite build is slow in Verilator's conversion step
(about 1000 s against 140 s for the other buses), and it becomes 191 MB of C++ in 64
files (the largest 40 MB). One g++ on such a file takes up to about 3.7 GB, so two at
once can reach the 8 GB cap: with 4 and with 2 compile jobs the build was OOM-killed in
3 of 4 tries (2026-11-25). `sim_sram.py` therefore compiles AXI4-Lite with
`--build-jobs 1` (`VERILATOR_BUILD_JOBS_PROTO`; Verilator's own `-j 4` is kept): peak
4.8 GB, conversion ~17 min plus compile ~32 min. The other buses keep 4 jobs. Source
`setup.sh` first: it puts the
OSS CAD Suite Verilator (5.043) ahead of a distribution one (Debian's 5.020 rejects
the simulation-only X fill of the macro models, `BLKLOOPINIT`). Bench adaptations, all
inactive on VCS / Xcelium:

- drives 1 ns after the clock edge (`sram_tb_drv.svh`): with `--timing`, a
  nonblocking assignment from a process resumed by the edge reaches flops
  clocked by that same edge;
- `sram_model` tracks known bits explicitly (two-state, no X);
- the leaf arrays are public (`sram_tb.vlt`) and the backdoor retries a
  path under Verilator's `TOP.` root and resolves a trailing `[N]` with
  `vpi_handle_by_index`.

The ECC encoder / decoder build their Hamming position tables at
elaboration (constant functions, O(K)). Calling the 1024-step
`sram_pkg::ecc_data_pos()` per bit in `always_comb` ran on every evaluation
in Verilator, and unrolling it ran Verilator out of memory (> 10 GB).

### Results (Vivado xsim, standard host)

`--sim xsim` (Vivado 2023.2 simulator, free) runs the same bench with the SV
tops and, mixed language, with the VHDL tops, on GENERIC and on the two FPGA
leaves: **XILINX** elaborates `xpm_memory_spram` / `xpm_memory_tdpram` from
Vivado's precompiled `xpm` library, **ALTERA** compiles Quartus'
`altera_mf` model (Verilog for the SV tops, VHDL for the VHDL tops). This is
the first simulation of the XILINX / ALTERA leaves, including their
dual-clock modes (XPM `independent_clock`, altsyncram `clock1`). 20/20 runs
pass, 12 tests each (2026-11-25):

| Tops | GENERIC | XILINX | ALTERA | Comparisons per run |
|---|---|---|---|---|
| SV, 4 buses | 4/4 | 4/4 | 4/4 | 119,438 - 120,306 |
| VHDL, 4 buses | 4/4 | SKIP | 4/4 | 115,820 - 116,688 |

```bash
python3 sim_sram.py --sim xsim --proto all --lang all --tech all --jobs 4   # ~10 min
```

What xsim cannot do, and how the run handles it (all reported in the log, none
silently dropped):

- no VPI / VHPI: the backdoor bit flips of `test_ecc` (GENERIC) report
  SKIPPED (`+define+TB_NO_BACKDOOR`, already in the bench);
- no write from SV into a VHDL object (XSIM 43-4618/4619): with a VHDL top the
  read-path stuck-bit faults (`test_ecc` stuck-bit sweeps, `test_bist`
  stuck-at) report SKIPPED (`BF_OK = 0` in the bench); the reference models
  still check every response;
- no force on a port connected to VHDL (XSIM 43-4289), which the XPM model
  itself does: XILINX with a VHDL top is SKIP (Vivado synthesis elaborates
  that leaf from VHDL, 12/12);
- no `force` on a bit-select of a variable, and a released variable keeps the
  forced value until its driver changes: on xsim the bench forces the array
  output once, through a clear / set mask (`sram_tb_body.svh`,
  `` `ifdef XILINX_SIMULATOR ``);
- kernel faults ("exceptional condition", "engine not responding") on two
  fork patterns: a second fork in one task whose branches declare automatic
  variables, and a fork branch that ends while its `join_none` children run.
  `test_dp` and `test_reset_busy` were restructured without either pattern
  (same transfers, same checks; see Bench changes below).

Bench changes for xsim (2026-11-25; none changes what VCS / Xcelium / Verilator
check): the `XILINX_SIMULATOR` force body and `BF_OK` (= 1 elsewhere) in
`sram_tb_body.svh`; the `BF_OK` guards in `test_ecc.sv` / `test_bist.sv`;
`test_dp.sv` runs its two concurrent A/B blocks through a helper task
(`dp_both_busy`, one fork per call); `test_reset_busy.sv` forks the eight
stalled reads as plain calls and no longer has a `wait fork` — the old one was a
no-op (the reads were grandchildren of the task, and `wait fork` waits for
immediate children only), which also hid that a reset drops a read the
AXI4-Lite adapter has already accepted (that BFM thread stays waiting; it is
not part of the check).

### Code coverage

VCS code coverage (line, condition, toggle, FSM, branch) of the sram RTL:
the top-levels and everything below them, including the shared bus adapters
and synchronizers, but not the testbench, the bus matrix or the vendor SRAM
macro models. Logic that is constant by construction (`-cm_noconst
-cm_seqnoconst`, e.g. ECC outputs of an instance without ECC) is reported
as unreachable. Runs are merged by module definition with
`urg -lca -flex_merge modules`.

**Target: at least 90% score for every component in every bus x language x
technology run.** Met: the weakest module of any SV run scores 92.95, of any
VHDL run 92.99 (re-run 2026-11-21, again 2026-11-23 after the `sram_model`
COMMON_CLK change: 80/80 PASS, identical coverage; `sram_ecc_dec` in the PDK runs is at least
94.32 thanks to the read-path stuck-bit sweep in `test_ecc`).

Per run, SystemVerilog top-levels (`verification/work/coverage/per_run.txt`):

| Run | Score | Line | Cond | Toggle | FSM | Branch | Weakest module |
|---|---|---|---|---|---|---|---|
| AHB / GENERIC | 95.69 | 97.77 | 95.50 | 99.12 | 92.59 | 93.47 | sram_cdc (92.95) |
| AHB / SAED14 | 95.38 | 97.68 | 94.46 | 99.11 | 92.59 | 93.04 | sram_clr (93.65) |
| AHB / SAED32 | 95.32 | 97.74 | 93.78 | 99.11 | 92.59 | 93.40 | sram_cdc (92.95) |
| AHB / SAED90 | 95.33 | 97.74 | 93.83 | 99.11 | 92.59 | 93.40 | sram_cdc (92.95) |
| AHB / SKY130 | 94.99 | 97.74 | 92.57 | 98.66 | 92.59 | 93.40 | sram_cdc (92.95) |
| APB / GENERIC | 94.96 | 97.59 | 95.11 | 99.31 | 89.47 | 93.31 | sram_cdc (92.95) |
| APB / SAED14 | 94.66 | 97.48 | 94.18 | 99.29 | 89.47 | 92.86 | sram_clr (93.65) |
| APB / SAED32 | 94.58 | 97.55 | 93.38 | 99.29 | 89.47 | 93.23 | sram_cdc (92.95) |
| APB / SAED90 | 94.60 | 97.55 | 93.44 | 99.29 | 89.47 | 93.23 | sram_cdc (92.95) |
| APB / SKY130 | 94.15 | 97.55 | 91.95 | 98.56 | 89.47 | 93.23 | sram_cdc (92.95) |
| AXI4-Lite / GENERIC | 95.38 | 97.72 | 94.55 | 99.25 | 91.67 | 93.71 | sram_cdc (92.95) |
| AXI4-Lite / SAED14 | 95.13 | 97.62 | 93.83 | 99.23 | 91.67 | 93.31 | sram_clr (93.65) |
| AXI4-Lite / SAED32 | 95.06 | 97.68 | 93.08 | 99.23 | 91.67 | 93.65 | sram_cdc (92.95) |
| AXI4-Lite / SAED90 | 95.07 | 97.68 | 93.14 | 99.23 | 91.67 | 93.65 | sram_cdc (92.95) |
| AXI4-Lite / SKY130 | 94.63 | 97.68 | 91.65 | 98.51 | 91.67 | 93.65 | sram_cdc (92.95) |
| WB / GENERIC | 95.12 | 97.59 | 96.00 | 99.28 | 89.47 | 93.28 | claude_wb_mem_if (93.33) |
| WB / SAED14 | 94.81 | 97.48 | 95.03 | 99.26 | 89.47 | 92.83 | claude_wb_mem_if (93.33) |
| WB / SAED32 | 94.74 | 97.55 | 94.21 | 99.26 | 89.47 | 93.21 | claude_wb_mem_if (93.33) |
| WB / SAED90 | 94.75 | 97.55 | 94.26 | 99.26 | 89.47 | 93.21 | claude_wb_mem_if (93.33) |
| WB / SKY130 | 94.36 | 97.55 | 92.74 | 98.82 | 89.47 | 93.21 | claude_wb_mem_if (93.33) |

All 20 SV runs merged (`verification/work/coverage/summary.txt`), total
**96.10** (line 97.96, cond 95.22, toggle 99.25, FSM 93.75, branch 94.30):

| Module | Score | Line | Cond | Toggle | FSM | Branch |
|---|---|---|---|---|---|---|
| `claude_wb_mem_if` | 93.33 | 100.00 | 73.33 | 100.00 | -- | 100.00 |
| `sram_clr` | 93.65 | 94.43 | 85.58 | 94.60 | -- | 100.00 |
| `claude_apb_mem_if` | 93.67 | 100.00 | 74.67 | 100.00 | -- | 100.00 |
| `sram_port` | 95.40 | 98.51 | 93.45 | 98.66 | -- | 90.97 |
| `sram_pwr_ctrl` | 96.08 | 97.44 | 100.00 | 100.00 | 87.50 | 95.45 |
| `claude_axi4l_mem_if` | 96.64 | 100.00 | 84.35 | 98.83 | 100.00 | 100.00 |
| `claude_ahb_mem_if` | 96.80 | 100.00 | 85.11 | 98.89 | 100.00 | 100.00 |
| `sram_cdc` | 97.12 | 100.00 | 100.00 | 88.46 | -- | 100.00 |
| `claude_sync` | 97.22 | 100.00 | -- | 91.67 | -- | 100.00 |
| `sram_bist` | 98.18 | 100.00 | 100.00 | 100.00 | 90.91 | 100.00 |
| `sram_ahb_dp` | 98.50 | -- | -- | 98.50 | -- | -- |
| `sram_ecc_dec` | 98.76 | -- | 97.51 | 100.00 | -- | -- |
| `sram_core` | 98.76 | 100.00 | 95.62 | 99.42 | -- | 100.00 |
| `sram_macro_dp_sky130` | 98.87 | 100.00 | 100.00 | 95.48 | -- | 100.00 |
| `sram_ahb` | 98.96 | -- | -- | 98.96 | -- | -- |
| `sram_macro_sky130` | 99.17 | 100.00 | 100.00 | 96.68 | -- | 100.00 |
| `sram_macro_dp` | 99.46 | -- | -- | 99.46 | -- | -- |
| `sram_macro` | 99.52 | -- | -- | 99.52 | -- | -- |
| `sram_macro_dp_saed14` | 99.59 | 100.00 | 100.00 | 98.36 | -- | 100.00 |
| `sram_macro_dp_saed32` | 99.60 | 100.00 | 100.00 | 98.40 | -- | 100.00 |
| `sram_macro_dp_saed90` | 99.64 | 100.00 | 100.00 | 98.57 | -- | 100.00 |
| `sram_axi4l` | 99.74 | -- | -- | 99.74 | -- | -- |
| `sram_macro_dp_generic` | 99.82 | 100.00 | -- | 99.47 | -- | 100.00 |
| `sram_macro_saed90` | 99.83 | 100.00 | 100.00 | 99.33 | -- | 100.00 |
| `sram_macro_saed32` | 99.83 | 100.00 | 100.00 | 99.33 | -- | 100.00 |
| `sram_macro_generic` | 99.84 | 100.00 | -- | 99.52 | -- | 100.00 |
| `sram_macro_saed14` | 99.86 | 100.00 | 100.00 | 99.45 | -- | 100.00 |
| `sram_array` | 99.88 | 100.00 | 100.00 | 99.54 | -- | 100.00 |
| `sram_ecc_enc` | 100.00 | -- | 100.00 | 100.00 | -- | -- |
| `claude_pulse_sync` | 100.00 | 100.00 | 100.00 | 100.00 | -- | 100.00 |
| `sram_apb_dp` | 100.00 | -- | -- | 100.00 | -- | -- |
| `sram_apb` | 100.00 | -- | -- | 100.00 | -- | -- |
| `sram_axi4l_dp` | 100.00 | -- | -- | 100.00 | -- | -- |
| `sram_wb` | 100.00 | -- | -- | 100.00 | -- | -- |
| `sram_wb_dp` | 100.00 | -- | -- | 100.00 | -- | -- |

#### VHDL top-levels

The same bench, tests and reference models drive the VHDL top-levels and the
VHDL `bus_matrix` (`--lang vhdl`, mixed language). Measured the same way, with
three differences forced by VCS's VHDL support:

- VCS filters constants out of VHDL line and condition coverage but **not out
  of VHDL toggle coverage**. `sim_sram.py` excludes a VHDL bit that did not
  toggle when the SV twin of the same instance, compiled with the same
  parameters, reports it Unreachable (urg exclusion file
  `verification/work/vcs/<run>/vhdl_const.el`, every exclusion listed in
  `vhdl_const_excl.txt`). A VHDL coverage run therefore also runs its SV twin.
  urg applies those instance exclusions per parameter set but not in its
  module list, so the runner recomputes each VHDL module's toggle (and score)
  from its parameter sets.
- The elaboration-time generic checks (concurrent `assert`s) and the
  `INIT_FILE` preload are excluded with `--synopsys coverage_off/on`
  (the SV twins' `initial` checks are removed as constants). The untoggled bits
  of the GENERIC leaf's storage array `mem` are excluded (SV memories are not
  toggle-covered).
- VHDL arrays of vectors (e.g. `sram_array`'s per-bank read data) are toggle
  covered; their SV twins are unpacked arrays, which VCS does not toggle-cover
  by default. That is why `sram_array` has the lowest VHDL toggle (85%).

**Target met:** the weakest VHDL module of any run scores 92.99.

| Run | Score | Line | Cond | Toggle | FSM | Branch | Weakest module |
|---|---|---|---|---|---|---|---|
| AHB / GENERIC | 97.69 | 98.55 | 98.03 | 98.01 | 96.30 | 97.55 | sram_array (93.64) |
| AHB / SAED14 | 96.73 | 98.35 | 96.40 | 96.32 | 96.30 | 96.28 | sram_array (93.64) |
| AHB / SAED32 | 97.38 | 98.48 | 98.20 | 96.35 | 96.30 | 97.55 | sram_array (93.64) |
| AHB / SAED90 | 97.39 | 98.48 | 98.20 | 96.40 | 96.30 | 97.55 | sram_array (93.64) |
| AHB / SKY130 | 96.88 | 98.48 | 96.28 | 95.81 | 96.30 | 97.55 | sram_array (93.00) |
| APB / GENERIC | 97.53 | 98.69 | 98.47 | 98.01 | 94.74 | 97.74 | sram_array (93.65) |
| APB / SAED14 | 96.56 | 98.50 | 96.75 | 96.44 | 94.74 | 96.37 | sram_array (93.65) |
| APB / SAED32 | 97.24 | 98.62 | 98.61 | 96.47 | 94.74 | 97.74 | sram_array (93.65) |
| APB / SAED90 | 97.25 | 98.62 | 98.61 | 96.52 | 94.74 | 97.74 | sram_array (93.65) |
| APB / SKY130 | 96.84 | 98.62 | 97.36 | 95.72 | 94.74 | 97.74 | sram_array (93.01) |
| AXI4-Lite / GENERIC | 97.52 | 98.65 | 97.48 | 97.93 | 95.83 | 97.70 | sram_array (93.65) |
| AXI4-Lite / SAED14 | 96.66 | 98.47 | 96.00 | 96.47 | 95.83 | 96.52 | sram_array (93.65) |
| AXI4-Lite / SAED32 | 97.26 | 98.58 | 97.68 | 96.49 | 95.83 | 97.70 | sram_array (93.65) |
| AXI4-Lite / SAED90 | 97.27 | 98.58 | 97.68 | 96.54 | 95.83 | 97.70 | sram_array (93.65) |
| AXI4-Lite / SKY130 | 96.74 | 98.58 | 95.87 | 95.74 | 95.83 | 97.70 | sram_array (92.99) |
| WB / GENERIC | 97.48 | 98.69 | 98.21 | 98.03 | 94.74 | 97.72 | sram_array (93.64) |
| WB / SAED14 | 96.50 | 98.50 | 96.52 | 96.42 | 94.74 | 96.34 | sram_array (93.64) |
| WB / SAED32 | 97.18 | 98.62 | 98.38 | 96.44 | 94.74 | 97.72 | sram_array (93.64) |
| WB / SAED90 | 97.19 | 98.62 | 98.38 | 96.49 | 94.74 | 97.72 | sram_array (93.64) |
| WB / SKY130 | 96.83 | 98.62 | 97.12 | 95.93 | 94.74 | 97.72 | sram_array (93.01) |

All 20 VHDL runs merged (`verification/work/coverage/vhdl/summary.txt`), total
**97.94** (line 98.67, cond 98.11, toggle 98.03, FSM 96.88, branch 98.02). The
merge cannot apply per-instance exclusions (its instances are the first run's),
so the merged toggle of each VHDL module is its best single run: a lower
bound of the merged value.

| Module | Score | Line | Cond | Toggle | FSM | Branch |
|---|---|---|---|---|---|---|
| `sram_array` | 93.65 | 94.87 | 100.00 | 85.00 | -- | 94.74 |
| `sram_cdc` | 95.50 | 100.00 | -- | 86.49 | -- | 100.00 |
| `claude_sync` | 95.56 | 100.00 | -- | 86.67 | -- | 100.00 |
| `sram_bist` | 97.32 | 98.48 | 100.00 | 100.00 | 90.91 | 97.22 |
| `claude_axi4l_mem_if` | 97.53 | 98.46 | 93.22 | 98.15 | 100.00 | 97.83 |
| `sram_core` | 97.65 | 100.00 | 96.72 | 93.88 | -- | 100.00 |
| `claude_ahb_mem_if` | 97.87 | 97.22 | 96.55 | 99.17 | 100.00 | 96.43 |
| `sram_pwr_ctrl` | 98.00 | 95.12 | 100.00 | 100.00 | 100.00 | 94.87 |
| `sram_macro_dp_sky130` | 98.16 | 100.00 | 100.00 | 92.62 | -- | 100.00 |
| `claude_wb_mem_if` | 98.33 | 100.00 | 93.33 | 100.00 | -- | 100.00 |
| `sram_clr` | 98.46 | 100.00 | 100.00 | 93.85 | -- | 100.00 |
| `sram_ahb_dp` | 98.84 | -- | -- | 98.84 | -- | -- |
| `sram_port` | 98.86 | 100.00 | 98.32 | 99.06 | -- | 98.08 |
| `sram_ahb` | 99.23 | -- | -- | 99.23 | -- | -- |
| `sram_macro_generic` | 99.49 | 100.00 | -- | 98.46 | -- | 100.00 |
| `sram_macro_dp` | 99.52 | -- | -- | 99.52 | -- | -- |
| `sram_macro_dp_saed14` | 99.53 | 100.00 | 100.00 | 98.10 | -- | 100.00 |
| `sram_macro_dp_saed32` | 99.57 | 100.00 | 100.00 | 98.29 | -- | 100.00 |
| `sram_macro_sky130` | 99.61 | 100.00 | 100.00 | 98.45 | -- | 100.00 |
| `sram_macro_dp_saed90` | 99.69 | 100.00 | 100.00 | 98.77 | -- | 100.00 |
| `sram_macro` | 99.71 | -- | -- | 99.71 | -- | -- |
| `sram_axi4l` | 99.72 | -- | -- | 99.72 | -- | -- |
| `sram_ecc_dec` | 99.83 | 100.00 | 100.00 | 99.31 | -- | 100.00 |
| `sram_macro_saed90` | 99.84 | 100.00 | 100.00 | 99.36 | -- | 100.00 |
| `sram_macro_saed32` | 99.84 | 100.00 | 100.00 | 99.36 | -- | 100.00 |
| `sram_macro_saed14` | 99.87 | 100.00 | 100.00 | 99.47 | -- | 100.00 |
| `sram_macro_dp_generic` | 99.88 | 100.00 | -- | 99.65 | -- | 100.00 |
| `sram_apb` | 100.00 | -- | -- | 100.00 | -- | -- |
| `sram_wb` | 100.00 | -- | -- | 100.00 | -- | -- |
| `sram_axi4l_dp` | 100.00 | -- | -- | 100.00 | -- | -- |
| `sram_apb_dp` | 100.00 | -- | -- | 100.00 | -- | -- |
| `sram_wb_dp` | 100.00 | -- | -- | 100.00 | -- | -- |
| `sram_ecc_enc` | 100.00 | 100.00 | -- | 100.00 | -- | 100.00 |
| `claude_pulse_sync` | 100.00 | 100.00 | -- | 100.00 | -- | 100.00 |
| `claude_apb_mem_if` | 100.00 | 100.00 | 100.00 | 100.00 | -- | 100.00 |

SV and VHDL percentages are not directly comparable: VCS counts VHDL
conditions and FSM transitions differently (e.g. the APB adapter's condition
coverage is 75% in SV and 100% in VHDL with the same stimulus).

Below 90% inside modules that pass (SV): condition coverage of the APB / Wishbone
adapters (73-75%; AHB 85, AXI4-Lite 84), `sram_pwr_ctrl` FSM 87.5%,
`sram_cdc` toggle 88.5%, `sram_clr` condition 85.6% (the Step 5 `init_q` terms).

Not covered: the XILINX and ALTERA leaves (no vendor simulation libraries on
csun.edu). Coverage is collected with VCS only: Xcelium can write a coverage
database (`xrun -coverage all -covfile`), but csun.edu has no IMC to merge or
report it, so the Xcelium runs are functional checks.

### Bugs found by these tests

| Where | Bug | Fix |
|---|---|---|
| `bus_matrix_ahb` | HSIZE was not carried through the matrix, so a 64-bit slave saw 4 lanes and sub-word transfers lost their size | `M_HSIZE` / `S_HSIZE`; the initiator rebuilds HSIZE from the lanes and the address |
| `bus_matrix_ahb_ini` (first version of that fix) | sparse write strobes at a word address became a byte transfer at the wrong lane | HSIZE must contain the address offset, else the bus size with the lanes in HWSTRB |
| `bus_matrix_ahb_ini` (found 2026-11-07 while adding HSIZE to the bus_matrix formal harness) | a sub-word write whose strobes are not an aligned block (halfword at offset 2, only byte 3 on) went out as a word transfer at an unaligned HADDR | HADDR is aligned to the HSIZE sent (SV and VHDL); proven by VC Formal |
| `sram_port` (SV and VHDL) | an all-zero-strobe write to an 8-bit SRAM wrote the word | lane enables follow the strobes whenever BYTE_EN = 1 |
| `sram_macro[_dp]_xilinx` (SV and VHDL; found 2026-11-25, xsim) | `MEMORY_PRIMITIVE "auto"` with `WAKEUP_TIME "use_sleep_pin"`: XPM DRC 40-42 rejects the sleep pin unless the primitive is block RAM / UltraRAM | `MEMORY_PRIMITIVE "block"` |
| `sram_macro_dp_altera` (SV and VHDL; found 2026-11-25, xsim ALTERA, test_dp dp2) | with COMMON_CLK both ports are clocked when either is selected, but the write enables were the array's shared `we_i`: a port-A write to one bank while port B read another also wrote the other bank | `wren_a/b` gated with the port's chip select |
| `sram_macro[_dp]_altera` (found 2026-11-25, Quartus) | one lane (39-bit ECC word, 13-bit ECC slice) with a driven `byteena` and `byte_size 8`: Quartus error 272006 (open item since Step 3) | one lane: `byteena` tied high, the lane enable gates the write enable |
| `sram_macro_altera.vhd` (found 2026-11-25, Quartus) | the local `altsyncram` component had no port-B generics; Quartus sized `data_b` / `q_b` from 0 (error 287087) | `width_b`, `widthad_b`, `numwords_b` declared (default 1) |

Mixed-language (VHDL top-levels) tool behaviour found and handled in the
bench and `sim_sram.py`:

| Tool | Behaviour | Handling |
|---|---|---|
| VCS | a VHDL generic whose default refers to another generic (`READ_LATENCY_B := READ_LATENCY`, and `BYTE_EN_B`, `PARTIAL_WR_ERR_B`) takes that generic's *default* when SystemVerilog instantiates the VHDL top (pure VHDL and Xcelium are correct); found by the model's new latency check (dp2 port B answered after 1 cycle instead of 2) | instantiate the VHDL dual-port tops from Verilog with the port-B options set explicitly; the bench does so on VCS |
| Xcelium | VHDL generic maps bind Verilog parameters by position unless `-namemap_mixgen` (the SKY130 wrapper's `VERBOSE => 0` set the model's `NUM_WMASKS`) | `-namemap_mixgen` |
| VCS | SV `force` of a VHDL bit (or of a VHDL signal the bench also reads) is not supported | `$hdl_xmr_force` for the BIST stuck-at fault |
| both | VPI cannot read VHDL storage | VHPI entry points in `claude_backdoor.c` |
| xsim | no SV write to a VHDL object, no force on a port connected to VHDL (also inside the XPM model) | stuck-bit faults SKIPPED with a VHDL top; XILINX + VHDL top SKIP (see xsim results) |
| xsim | Verilog port defaults are not applied when a VHDL component binds a Verilog module (the ALTERA leaves leave altsyncram's unused ports out) | VHDL tops use Quartus' VHDL `altera_mf` model |

Behaviour confirmed and documented while writing the tests: every response
(writes too) comes READ_LATENCY cycles after the grant; a clear requested
during a pass joins it; a read on a port B with its own clock can complete
just before a clear starts; error pulses from such a port merge when closer
than about three port-A cycles (`claude_pulse_sync`).

## Formal Verification Results

### Synopsys VC Formal (csun.edu) — SV and VHDL

Formal property verification of the core (single port, ECC, BIST, bank power
gating, dual port on one or two clocks), all four bus top-levels and the
SECDED code, in **both SystemVerilog and VHDL-2008**. The same SVA checkers
are bound into both languages. For the jobs, the properties, waivers and the
bugs found, see
[verification/formal/vcf/README.md](verification/formal/vcf/README.md).
Re-run 2026-11-25 on the Step 10 RTL: 26/26 jobs PASS; new proven lemmas
(`sram_leaf_fv a_word_ok`, `sram_port_fv`) make `core_ecc a_err_rule` a full
proof again.

```
python3 verification/tools/formal_sram.py --jobs 3
```

| Job | Language | Assertions proven | Covers covered | Waived | Bounded (depth reached) | Result |
|-----|----------|-------------------|----------------|--------|-------------------------|--------|
| `core_base` | SV | 26/26 | 18/19 | 1 | — | PASS |
| `core_base` | VHDL | 26/26 | 18/19 | 1 | — | PASS |
| `core_be0_err` | SV | 9/9 | 13/13 | 0 | — | PASS |
| `core_be0_err` | VHDL | 9/9 | 13/13 | 0 | — | PASS |
| `core_be0_full` | SV | 26/26 | 19/20 | 1 | — | PASS |
| `core_be0_full` | VHDL | 26/26 | 19/20 | 1 | — | PASS |
| `core_ecc` | SV | 33/34 | 20/21 | 2 | `a_data` 26 | PASS |
| `core_ecc` | VHDL | 33/34 | 20/21 | 2 | `a_data` 20 | PASS |
| `core_opts` | SV | 49/52 | 30/30 | 3 | `t_gnt_bounded` 180, `a_data` 22, `a_err_rule` 22 | PASS |
| `core_opts` | VHDL | 49/52 | 30/30 | 3 | `t_gnt_bounded` 172, `a_data` 21, `a_err_rule` 21 | PASS |
| `dp_sync` | SV | 49/51 | 36/40 | 6 | `a_data` 17, `b_data` 17 | PASS |
| `dp_sync` | VHDL | 49/51 | 36/40 | 6 | `a_data` 17, `b_data` 17 | PASS |
| `dp_sync_wide_b` | SV | 29/33 | 31/33 | 6 | `a_data` 15, `a_err_rule` 15, `b_data` 15, `b_err_rule` 14 | PASS |
| `dp_sync_wide_b` | VHDL | 29/33 | 31/33 | 6 | `a_data` 15, `a_err_rule` 14, `b_data` 14, `b_err_rule` 14 | PASS |
| `dp_async` | SV | 45/47 | 34/36 | 4 | `a_data` 35, `b_data` 35 | PASS |
| `dp_async` | VHDL | 45/47 | 34/36 | 4 | `a_data` 37, `b_data` 37 | PASS |
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

All assertions are full proofs except the "Bounded" ones: end-to-end data
integrity (and, in two jobs, error prediction) in the ECC and dual-port
configurations did not converge in 30 minutes. They have no counterexample
to the depth shown and are waived as inconclusive only. They are fully
proven without ECC (`core_base`, `core_be0_*`), the SECDED code is proven
exhaustively (`ecc`), every written ECC lane is proven to hold a valid
codeword, and the simulation regression checks every read against the
reference model. The waived covers are unreachable by construction (read
latency 1; 8-bit codewords in `dp_sync` never need a read-modify-write).

Formal found and fixed two RTL bugs (SV + VHDL): a clear-on-reset pass that
could leave a power domain uninitialised, and port-B starvation by port-A
read-modify-writes on a shared word.

Tool: VC Formal Y-2026.03-SP1. Results generated: 2026-11-15.

## UVM Verification Results

Constrained-random UVM bench (Step 6), `verification/tasks/uvm/`, VCS Y-2026.03-SP1
(`-ntb_opts uvm-1.2`) and Xcelium 25.03 (`-uvm`, CDNS-1.2) on csun.edu,
2026-11-21 / 2026-11-23. One DUT per build, chosen by bus x language (SV top, or the VHDL
top in mixed language) x technology x configuration:

| Config | DUT |
|---|---|
| `base` | 32 x 1024, default options |
| `full` | 32 x 1024, ECC, BANK_PG (2 banks), BIST, READ_LATENCY 2 |
| `dp` | dual port, A 32 x 1024 / B 8 x 4096, port B on its own clock (13.7 vs 10 ns; SAED14 one clock); SKY130 port B read-only |

Structure: one protocol-neutral bus agent per port (APB, AHB-Lite with
INCR/WRAP bursts and BUSY, AXI4-Lite with several transfers in flight and
random BREADY/RREADY, Wishbone), a side-band agent (power modes per domain,
clear, ECC injection, BIST, read-path stuck-bit knob), a virtual sequencer,
and two independent checkers: a UVM scoreboard at the bus (contents, every
error cause, power / clear / BIST / ECC effects, err_irq / ecc pulse counts)
and `sram_model` on the memory bus. Accesses whose outcome the
specification leaves open (a mode change or an engine start while they are in
flight) are counted as ambiguous and accept either legal answer.

Tests: `smoke`, `random`, `power`, `clear`, `stress` (every config), `ecc`,
`bist` (full), `dp` (dp).

```bash
python3 verification/tools/uvm_sram.py --sim all --proto all --lang all --tech all --cfg all --coverage --jobs 3
python3 verification/tools/uvm_mutants.py        # every mutant must make a test fail
```

Results (`verification/work/uvm/results.log`), full matrix 2026-11-23: 4 buses x
SV/VHDL x 5 technologies x 3 configs x VCS/Xcelium = 240 builds, **1440/1440 test
runs PASS** (seed 1). Re-run 2026-11-24 on the Step 10 RTL: 1440/1440 PASS.

Functional coverage (VCS, covergroups per instance, coverpoints of a feature
the config lacks have weight 0), merged per configuration over its 40 VCS
builds (`verification/work/uvm/coverage/functional.txt`): **base 100.00, full
100.00, dp 100.00** (target 100). Single builds: 96.35-97.08 for SKY130 dp (port B
read-only), 99.31-99.71 for WB, 100 for the rest. Code coverage per build
(`verification/work/uvm/coverage/per_build.txt`): **every module at least 90 in
all 120 VCS builds**; the weakest is `sram_clr` 90.19 (base / dp) and
`sram_bist` 90.96 (full). Merged code score per config: base 93.07, full
93.54, dp 93.47.

Mutation check (`verification/work/uvm/mutants/results.log`): **9/9 mutants
killed** — no out-of-range error, a dropped address bit, byte lane 0 always
written, no err_irq on failed writes, deep sleep accepting accesses, an
uncorrectable ECC error answering OKAY, no ecc_corr pulse, BIST never failing,
port B rejecting writes. Re-run 2026-11-25 on the Step 10 RTL (registered read-modify-write): 9/9
killed.

Found while building it: the class scoreboard needs `sram_model`'s port-B
power-error rule relaxed for separate clocks (the requested mode reaches port B
through the core's CDC), now the opt-in parameter `B_MODE_GUARD`; the Step 4
coverage hole in `sram_ecc_dec` (see Code coverage), closed with the same
read-path stuck-bit sweep in both benches.

Fixed after the first full matrix (1352/1440, 2026-11-21; bench bugs, no RTL
change):
- AXI4-Lite `err_irq` count: the pulse follows the core response by one cycle,
  but the scoreboard merged pulses by bus completion; with BREADY/RREADY
  stalls a B and an R complete on one edge after two core responses (or the
  reverse). The monitor now records `t_rsp`, the edge BVALID/RVALID rose (a
  fixed delay after the core response), and the scoreboard counts by it.
- Xcelium, SAED14 dp (one clock): `sram_model` ran port A's side band (wake-up
  zero fill) and port B's grant prediction in two always blocks on the same
  edge, in simulator order; Xcelium predicted a B write first and then zeroed
  it. New `sram_model` parameter `COMMON_CLK`: the side band of an edge always
  runs before port B's prediction (set in both benches).
- `claude_wb_mem_if` was at 89.9: the WB driver now drives stray STB / WE /
  ADR with CYC low in idle cycles (Wishbone B4: ignored by the slave).

## Regression

`verification/tools/regression_sram.py` (wrapper `verification/regression/run_regression.sh`)
runs every sub-runner and writes one report: `verification/regression/report.md` on csun.edu,
`verification/regression/report_standard_host.md` on a standard host (each host keeps its own
report; console table: `verification/work/regression_results.log`). Exit status 0 only when every
entry passes; an expected result that is missing counts as FAIL.

| Step | csun.edu | Standard host | Entries |
|---|---|---|---|
| sim | `sim_sram.py`, VCS + Xcelium, 4 buses x SV/VHDL x 5 techs, `--coverage` | `sim_sram.py --sim all`: Verilator SV GENERIC (4) + xsim SV/VHDL x GENERIC/XILINX/ALTERA (20) | one per directed test (12 per run) |
| uvm | `uvm_sram.py`, full matrix, `--coverage` | — | one per test run (1440) |
| mutants | `uvm_mutants.py --mutant all` | — | one per mutant (must be killed) |
| formal | `formal_sram.py --job all --lang all` | — | one per VC Formal job |
| lint | `lint_sram.py --lang all` (SpyGlass) | same (Verilator + GHDL) | one |
| firmware | `fw_sram.py` (host unit tests, mutants, host compile; cross build SKIP without compilers) | same, plus the ARM / RISC-V cross build | one per PASS / FAIL row of `verification/firmware/fw_results.log` |
| synth | — (DC / PrimeTime run on their own, Synthesis Results) | `run_vendor_synth.py`: Vivado, Quartus, Yosys | one per netlist (3 x 24) |
| coverage | from the sim / uvm coverage reports | — | every module >= 90 per directed run and UVM build; UVM functional 100 per config |

```bash
source IP/system/sram/setup.sh
python3 $CLAUDE_SRAM_PATH/verification/tools/regression_sram.py            # run everything (~4-5 h on csun.edu)
python3 $CLAUDE_SRAM_PATH/verification/tools/regression_sram.py --collect  # report on existing results only
#   --skip-sim --skip-uvm --skip-mutants --skip-formal --skip-lint --skip-firmware
#   (standard host: --skip-synth), --jobs N (default 3)
```

The report lists each source file's timestamp, so stale results are visible in `--collect`
mode. Last report (2026-11-23, `--collect` on csun.edu): **2599/2599 entries pass** — sim
960/960, UVM 1440/1440, mutants 9/9, formal 26/26, lint 1/1 (24 SpyGlass configurations),
coverage 163/163. The Step 10 RTL was re-verified run by run (directed 80/80,
UVM 1440/1440, mutants 9/9, formal 26/26, lint 24/24, 2026-11-24/25); the
regression report was not regenerated after it.

Standard host (2026-11-25, `report_standard_host.md`): **513/513 entries pass** — sim 288/288
(Verilator 4 runs + xsim 20 runs, 12 tests each), lint 1/1 (Verilator 20 + GHDL 40
configurations), firmware 152/152 (with the ARM / RISC-V cross builds), synth 72/72
(Vivado, Quartus, Yosys 24 each); uvm, mutants and formal SKIP (csun.edu flows). A full run
takes about 100 min, most of it the four Verilator builds (one at a time, 8 GB cap).
Step 11 (2026-11-25): `cleanup.sh`, then the full regression from the clean tree: 501/513,
the 12 failures all the AXI4-Lite Verilator build, OOM-killed at the cap. Fixed in the flow
(one compile job for that build, see Verilator results), re-run, report rebuilt with
`--collect`: 513/513.

## Lint Results

`verification/tools/lint_sram.py` (Step 8), 2026-11-23 on csun.edu, SpyGlass
(`spyglass_vc`, VC Static Y-2026.03-SP1): **24/24 configurations clean, PASS**.

| Language | Tool | Configurations | Un-waived findings | Waivers | Result |
|---|---|---|---|---|---|
| SV | SpyGlass `lint/lint_rtl` | 20 | 0 | 60 RTL pragma blocks (`waivers.md` W1-W5) | PASS |
| SV | SpyGlass `cdc/cdc_verify_struct` | 4 | 0 | 5 RTL pragma blocks (`waivers.md` W6) | PASS |
| VHDL | — | — | — | — | SKIPPED: no GHDL on csun.edu and no VHDL-2008 path in SpyGlass (`.agents/reference_spyglass_lint.md`) |

What is linted (user decision 2026-11-23): every top with every option on, because a reduced
configuration only adds findings for logic it switches off.

| Configurations | Top | TECH | Parameters |
|---|---|---|---|
| `<proto>_generic` (4) | `sram_ahb/apb/axi4l/wb` | GENERIC | ECC_EN, BANK_PG, NUM_BANKS 2, BIST_EN, READ_LATENCY 2 |
| `<proto>_dp_generic` (4) | `sram_<proto>_dp` | GENERIC | same + WIDTH_B 8, COMMON_CLK 0 |
| `apb_<tech>`, `apb_dp_<tech>` (12) | `sram_apb`, `sram_apb_dp` | SAED90, SAED32, SAED14, SKY130, XILINX, ALTERA | same (SAED14 dual port: COMMON_CLK 1) |
| `<proto>_dp_cdc` (4) | `sram_<proto>_dp` | GENERIC | as `_dp_generic`; clocks and synchronous resets in an SGDC |

The vendor cells are black boxes (`set_option stop`): the XPM / altsyncram ports are
hand-written stubs (`verification/lint/stubs/`), the PDK cells are generated from the
wrappers' own instantiations into `verification/work/lint_stubs/` (no vendor file content).
Each configuration has its own SpyGlass directory `verification/lint/spyglass/<cfg>/`
(project and SGDC written by the runner), so up to three run in parallel (`--jobs`, capped by
free memory; ~1.8 GB each). Pass/fail comes from each `moresimple.rpt`; translator and
black-box bookkeeping rows are filtered (listed in `waivers.md`).

CDC: every crossing between the port-A and port-B clocks is synchronized (24 synchronized
crossings per top, through `claude_sync` / `claude_pulse_sync` or the dual-clock RAM, none
unsynchronized); the convergence of independent handshake bits of one multi-bit synchronizer
is waived with the formal proof of the `sram_cdc` handshake (VC Formal `dp_async`).
CDC reports its crossings and constraint checks as info rows. Only seven reviewed info
rules are filtered out (`waivers.md`, "CDC report filter"); any other CDC row counts as a
finding. This was re-run with that filter on 2026-11-23 20:45: 24/24 PASS.
Re-run 2026-11-25 (Step 10 RTL: registered read-modify-write, untyped `INIT_FILE`): SV 24/24
PASS, 0 findings.

Fixed while linting: `sram_ecc_dec.sv` had a dead `stored_overall` net (SV only; no
functional change — directed sims of all four buses on VCS and Xcelium re-run PASS with
identical comparison counts). Everything else is configuration-dependent (single-port tops
carry the core's port B; leaves share one interface; SKY130 port B read-only, SAED14 one
write clock) or a documented style deviation (`INIT_FILE` file name, untyped since Step 10, `$readmemh` preload, the
dual-clock RAM template, `sram_clr` default-then-override).

```bash
source IP/system/sram/setup.sh
python3 $CLAUDE_SRAM_PATH/verification/tools/lint_sram.py --lang all        # ~6 min on csun.edu
python3 $CLAUDE_SRAM_PATH/verification/tools/lint_sram.py --list            # the configurations
python3 $CLAUDE_SRAM_PATH/verification/tools/lint_sram.py --cfg apb_dp_cdc  # one configuration
```

Standard host (2026-11-25, Verilator 5.043, GHDL 6.0.0-dev): the same 20 SV configurations
through Verilator `--lint-only -Wall` (`verification/lint/verilator.flags`, `-G` overrides)
and every VHDL file through `ghdl -a --std=08`: **SV 20/20 clean, VHDL 40/40 clean, PASS**
(the 4 CDC configurations are SpyGlass-only, SKIPPED). Verilator does not read the SpyGlass
pragmas, so its waivers are in `verification/lint/verilator_waivers.vlt` — by file, rule
and signal, not in the RTL — mapped onto the same W1-W5 classes, plus the port-only stubs;
GHDL needs `-frelaxed` for the shared-variable dual-clock RAM (W5) and has two `-Whide`
waivers (W7). All are listed in `waivers.md` ("Standard host"). A planted unused signal in
`sram_core` / `sram_array` fails the run.

## Firmware

C99, bare-metal, no OS, no dynamic allocation, no global state. There is no
register driver, because the IP has no registers (D2). The firmware has two
parts:

- **Memory tests** (`firmware/src/sram_memtest.c`) run directly on the memory
  through a base address and a size.
- **Side-band helpers** (`firmware/src/sram_sideband.c`) handle power modes,
  clear, BIST and ECC error injection. They only do the sequencing: the
  integrator wires the side-band pins to something software can reach (GPIO,
  a system-control register) and passes the pin access as a table of callbacks
  (`sram_hooks_t`). No address map is assumed.
  `firmware/examples/sram_example.c` shows one possible wiring (a single
  system-control register) and a power-on self test.

Memory accesses go through `SRAM_RD8/16/32` and `SRAM_WR8/16/32` in
`firmware/src/sram_access.h`. These are volatile pointers by default; define
them before the include to port the tests. Nothing from IP/common is needed.

### Build Targets

| Target | Toolchain | Library output |
|---|---|---|
| ARM Cortex-M33 | `arm-none-eabi-gcc` (`-mcpu=cortex-m33 -mthumb`) | `firmware/lib/arm-cortex-m33/libsram.a` |
| RISC-V 32-bit | `riscv-none-elf-gcc` (`-march=rv32imac_zicsr -mabi=ilp32`) | `firmware/lib/riscv32/libsram.a` |

`bash firmware/build.sh [arm|riscv|clean]`, the same as the timer. The toolchain files are in
`IP/common/firmware/cmake/`. `-DSRAM_BUILD_EXAMPLE=ON` also links the example, which needs a
board linker script and startup file.

### Verification

`verification/tools/fw_sram.py` writes `verification/firmware/fw_results.log` and is
the `firmware` step of the regression.

| Step | What | Result (2026-11-23, csun.edu, gcc 11.5.0) |
|---|---|---|
| host | `firmware/test/test_sram.c` with host gcc (`-std=c99 -Wall -Wextra -Werror -pedantic`): every test on fault-free memories (4 B to 16 KiB, three fills), argument checks, 39 fault/test pairs (34 must detect, 5 must stay blind) on a fault-injecting model, 24 side-band checks on a fake IP | 124/124 PASS (plus the build row). ASan/UBSan are used where the host can link them; csun.edu cannot (libasan/libubsan not installed). Standard host (2026-11-25, gcc 13.3.0, with ASan/UBSan): 152/152 PASS. |
| mutants | 22 deliberate bugs in `src/` (`fw_sram.py --list-mutants`); `test_sram` must fail for each one | 22/22 killed (both hosts) |
| compile | library and example compiled without the test model (real volatile accessors) | 3/3 PASS (both hosts) |
| cross | `build.sh` for ARM and RISC-V | standard host 2026-11-25: ARM Cortex-M33 (arm-none-eabi-gcc 13.2.1) and RV32 (riscv-none-elf-gcc 15.2.0) PASS, `-Werror`. SKIP on csun.edu (no cross compilers there). |

Faults in the model (`firmware/test/sram_test_mem.c`), and which test is meant
to catch each one. "Blind" pairs are checked too, to show the limits of each test:

| Fault | Caught by | Not caught by |
|---|---|---|
| stuck-at 0 / 1 bit | walking, address-in-address, March C- | |
| transition (cannot rise) | walking, March C- | |
| address bit stuck at 0 / 1, two address bits shorted | address bus, address-in-address, March C- | walking (single word) |
| decoder multiple access (a write also hits another word) | address bus (both phases) | |
| coupling between words, rising or falling aggressor, either order | March C- (the falling case only through its final read element) | walking |
| bridge inside a word (wired-AND) | walking, March C- with background 0x55555555 | March C- with background 0 |
| pattern-sensitive bit (0 between two 1s reads 1) | walking 0s, March C- with background 0x55555555 | March C- with background 0, walking 1s |
| byte lane: full-word narrow write, swapped lanes, halfword in the wrong half, last word only | byte lanes | word tests |

### Code Size

`libsram.a`, `-O2` Release (`fw_sram.py`, 2026-11-25, standard host):

| Target | text | data | bss |
|---|---|---|---|
| ARM Cortex-M33 (arm-none-eabi-gcc 13.2.1) | 2000 B | 0 | 0 |
| RISC-V RV32IMAC (riscv-none-elf-gcc 15.2.0) | 2228 B | 0 | 0 |

`.data` and `.bss` are 0 by design, since there is no global state.

### API Summary

Declared in `firmware/include/sram.h`. Return codes: `SRAM_OK` 0, `SRAM_ERR_FAIL`,
`SRAM_ERR_ARG`, `SRAM_ERR_TIMEOUT`, `SRAM_ERR_STATE`, `SRAM_ERR_NOHOOK`.

**Memory tests.** Each test takes `base` (4-byte aligned), `size` (bytes, a non-zero
multiple of 4) and `sram_fail_t *fail` (first failure: `addr`, `expected`, `actual`;
may be NULL). The tests are destructive. The running program's stack, code and data
must be outside the tested range.

| Function | Accesses | Finds |
|---|---|---|
| `sram_test_addr_bus(base, size, fail)` | ~2 log2(words) + log2(words)^2 | stuck, shorted or multiply-selecting address lines |
| `sram_test_walking(base, size, fail)` | 128 per word | stuck, bridged or pattern-sensitive data bits (size 4 = data-bus test) |
| `sram_test_addr_in_addr(base, size, fail)` | 4 per word | address-decoder faults over the whole range |
| `sram_test_march_c(base, size, bg, fail)` | 10 per word | March C- with background `bg`: stuck-at, transition, decoder and coupling faults |
| `sram_test_byte_lanes(base, size, fail)` | first and last word | byte / halfword write merge and read lanes (needs `BYTE_EN = 1`, or `PARTIAL_WR_ERR = 0`) |
| `sram_test_all(base, size, tests, fail)` | | the `SRAM_TEST_*` selection in that order (March C- with backgrounds 0 and 0x55555555); stops at the first failure |

**Side band.** `sram_init(&dev, &hooks, num_domains, timeout)` binds an instance.
`set_pwr_req`, `get_pwr_ack` and `get_status` are required. `pulse_clr`, `pulse_bist`,
`get_bist_fail_addr` and `pulse_ecc_inj` may be NULL when the option is not built; a
helper that needs a missing hook returns `SRAM_ERR_NOHOOK`. Each wait polls at most
`timeout` times.

| Function | Sequence |
|---|---|
| `sram_pwr_set_mode(dev, domain, mode)` | drive the request, wait until `pwr_mode_ack_o` shows it. A move between two sleep modes passes through RUN in hardware. Leaving SHUTDOWN also waits for the zeroing pass. |
| `sram_pwr_set_mode_all(dev, mode)` | request every domain first, then wait for each, so the transitions run in parallel |
| `sram_pwr_get_mode(dev, domain)` | mode in effect |
| `sram_pwr_domain_range(dev, size, domain, &off, &len)` | byte range of one bank with `BANK_PG` (equal slices, domain 0 lowest), e.g. to test only the banks that are awake |
| `sram_wait_idle(dev)` | wait for `busy_o` low |
| `sram_clear(dev)` | refused (`SRAM_ERR_STATE`) unless every domain is in RUN or LIGHT_SLEEP, because the engine skips the others; then pulse `clr_req_i` and wait for `busy_o` low |
| `sram_bist_run(dev, &fail_word)` | pulse `bist_start_i`, wait for `busy_o` low, then read `bist_fail_o` / `bist_fail_addr_o`. Destroys the contents. |
| `sram_ecc_inject(dev, bits)` | pulse `ecc_inj_i` (1 = one stored bit, corrected; 2 = two bits, uncorrectable) on the next port-A write |

Rules the hardware imposes. A bus access to a domain in DEEP_SLEEP or SHUTDOWN
is a bus error, so do not test such a domain. LIGHT_SLEEP wakes on an access.
A `pulse_*` hook must return only after the pulse has reached the IP, so that
the next `get_status` sees `busy_o`.

## Synthesis Results

Step 10, csun.edu and a standard host, 2026-11-25. Details: `synthesis/known_issues.md`
and the per-target reports.

| Flow | Runner | Result |
|---|---|---|
| Design Compiler (24 netlists per PDK: base / opts / dp x 4 buses x SV / VHDL, SRAM macros, 0.2 ns setup margin) | `synthesis/run_vendor_synth.py --dc` | SAED32, SAED14, SKY130 24/24 met; SAED90 2/24 (accepted known failure) |
| PrimeTime STA (setup and hold; SKY130 at SS / TT / FF with TT macros) | `synthesis/run_primetime_sta.py` | SAED32, SAED14, SKY130 SS / TT / FF 24/24; worst setup +3.53 / +0.42 / +0.18 / +1.28 / +1.42 ns; SAED90 accepted |
| Gate-level simulation (3 netlists per bus, SDF, 2448 checks per run) | `verification/tools/sim_sram.py --postsyn` | 24/24 PASS (SAED32, SAED14, SKY130 x 4 buses x SV / VHDL netlists); SAED90 8 known (pass with `--no-sdf`) |
| UPF (VC LP) | `verification/tools/lp_sram.py` | 12/12 PASS |
| PrimePower (Step 12) | `verification/tools/sim_sram.py --power` | 36/36 PASS (SAED90 skipped); see Power Analysis |
| Vivado 2023.2 (xc7z010clg400-1, OOC, 100 MHz, TECH = XILINX) | `synthesis/run_vendor_synth.py --vivado` (standard host) | 24/24: every array in block RAM, every netlist meets 100 MHz |
| Quartus Prime Lite 23.1 (5CSEMA4U23C6, Analysis & Synthesis, TECH = ALTERA) | `synthesis/run_vendor_synth.py --quartus` (standard host) | 24/24: every array in M10K |
| Yosys 0.60 (generic cells, TECH = GENERIC) | `synthesis/run_vendor_synth.py --yosys` (standard host) | 24/24: every array inferred as memory |

FPGA and Yosys results per configuration (ranges over 4 buses x SV / VHDL; every netlist in
`synthesis/{vivado,quartus,yosys}/report.txt`):

| Config | Vivado LUTs / FFs | BRAM tiles | WNS (ns) | Quartus ALMs (est.) / registers | M10K bits | Yosys cells | Yosys memories |
|---|---|---|---|---|---|---|---|
| base (32 x 1024) | 121-163 / 31-170 | 1 | +3.36 .. +4.63 | 100-133 / 32-170 | 32,768 | 284-529 | 1 (SV), 4 (VHDL, one per lane) |
| opts (ECC, 2 banks, BIST, RL 2) | 395-473 / 218-360 | 2 | +0.57 .. +0.92 | 333-398 / 222-360 | 39,936 | 1,396-1,676 | 2 |
| dp (opts + 8-bit port B, 2 clocks) | 474-533 / 201-432 | 4 | +1.94 .. +3.56 | 422-484 / 205-434 | 53,248 | 1,604-2,980 | 13 (SV), 8 (VHDL) |

Getting there needed four FPGA-leaf RTL fixes (XPM sleep pin with `MEMORY_PRIMITIVE "auto"`,
ALTERA dual-port write enables, ALTERA one-lane byte enables, ALTERA VHDL port-B generics;
see "Bugs found by these tests"; no csun.edu flow elaborates these leaves) and three tool
work-arounds outside the RTL: Quartus Lite reads SystemVerilog-2005 copies of the SV made by
`synthesis/quartus/quartus_sv.py` (explicit generate regions, genvars, header localparams);
Yosys reads SV through the yosys-slang plugin; the VHDL dual-port netlists skip Yosys' memory
pass (an assert in `memory_collect` on the ghdl plugin's dual-clock RAM).

SAED90 misses 100 MHz by -0.20 ns (base, read latency 1) to -1.4 ns (options,
dual port), and -35 / -42 ns on the AXI4-Lite dual port (wire-load model
artefact); accepted (user decision 2026-11-25). Gate-level simulation found
two vendor model bugs, fixed in generated copies: SAED90 SSR flip-flop
priority (`IP/common/verification/tools/pdk_cell_models.py`) and the SKY130
OpenRAM read delay (`pdk_sram_models.py`, gate level).

## Power Analysis

Step 12, csun.edu, 2026-11-25: `python3 verification/tools/sim_sram.py --power
--proto all --pdk all --jobs 3`. Each gate-level run (`--postsyn` bench, SV
netlists, SDF) records a backward SAIF per netlist with VCS (`+saif`, from the
end of the post-reset clear to the end of the sequence); PrimePower
(`report_power`, averaged mode) reads the netlist, DC's constraints and
wire-load model, the SAIF, and the **typical-corner** standard-cell and SRAM
macro libraries. 36/36 analyses PASS, 100 % of nets annotated; SAED90 SKIP
(its gate-level activity is not valid: accepted timing failure). Results:
`verification/work/power/results.log`, reports in
`verification/work/power/<proto>_sv_<pdk>/power/<netlist>/`.

Average power over the gate-level test sequence (mW, 100 MHz; ranges over
the four buses — the macro power does not depend on the bus):

| PDK | Netlist | Logic | SRAM macros | Total |
|---|---|---|---|---|
| SAED14 | base (32 x 1024) | 0.007-0.030 | 8.99 | 9.00-9.02 |
| SAED14 | opts (ECC, 2 banks, BIST, RL2) | 0.076-0.100 | 11.24 | 11.31-11.34 |
| SAED14 | dp (opts + 8-bit port B) | 0.093-0.136 | 19.81 | 19.90-19.94 |
| SKY130 | base | 0.13-0.68 | 11.08 | 11.21-11.76 |
| SKY130 | opts | 0.99-1.55 | 37.65 | 38.64-39.20 |
| SKY130 | dp | 0.92-1.73 | 52.13 | 53.05-53.86 |
| SAED32 | base | 0.12-0.46 | not valid | — |
| SAED32 | opts | 0.70-1.05 | not valid | — |
| SAED32 | dp | 0.95-1.48 | not valid | — |

Findings:
- **The macros dominate (> 95 %), and almost all of it is their clock.** The
  macro liberties charge internal energy on every clock rise, selected or not
  (SKY130 OpenRAM: 13.8 pJ per `clk0` rise in every `csb0` / `web0` state,
  ~5.5 mW per macro at 100 MHz), and the leaves connect each macro's clock to
  the bus clock. Gating the macro clocks while a bank is deselected or asleep
  would remove most of it; LIGHT_SLEEP / DEEP_SLEEP hold the chip select
  off but leave the clock running (follow-up, not done; spec "Power modes").
- **SAED32 macro power is not usable:** the SAED32-LP SRAM liberty's
  input-pin `internal_power` tables are negative (to about -2700 per
  transition, in the vendor file itself) and its leakage is 0, so PrimePower
  reports negative memory power. The logic columns are valid; the macro share
  is flagged and not added up (`synthesis/known_issues.md`).
- The logic share is mostly leakage on SAED32 and register clock-pin power on
  SKY130; AXI4-Lite is the largest bus adapter.

## Directory Layout

```
sram/
├── setup.sh / cleanup.sh       environment (CLAUDE_SRAM_PATH) and artifact cleanup
├── design/
│   ├── behavioral/             reference model
│   ├── rtl/verilog, rtl/vhdl   RTL (SV and VHDL-2008)
│   └── upf/                    power intent (UPF): sram_power.upf + sram_<pdk>.upf
├── doc/                        specification
├── firmware/                   memory-test and power-mode helpers (C99)
├── synthesis/                  run_vendor_synth.py (DC, Vivado, Quartus, Yosys), run_primetime_sta.py,
│                               known_issues.md, report_<pdk>.txt, primetime/report_sta_*.txt,
│                               {vivado,quartus,yosys}/report.txt, quartus/quartus_sv.py (SV-2005 copies)
└── verification/
    ├── testbench/              SV system bench (tb_sram_<proto>.sv + shared body), BFMs
    ├── tests/                  directed tests and helpers (shared by SV and VHDL tops)
    ├── tasks/uvm/              UVM bench (agents, env, sequences, tests, tb_sram_uvm.sv)
    ├── tools/sim_sram.py       simulation and coverage runner
    ├── tools/uvm_sram.py       UVM runner; uvm_mutants.py proves the UVM tests can fail
    ├── tools/formal_sram.py, lint_sram.py, lp_sram.py (VC LP), fw_sram.py, regression_sram.py
    ├── testbench/sram_tb_postsyn_body.svh  gate-level bench (sim_sram.py --postsyn)
    ├── formal/ lint/ lp/ regression/ modelsim/ vivado/   per-step configuration and results
    │                           (lint/: verilator.flags, verilator_waivers.vlt, waivers.md)
    └── work/                   run outputs (results, logs, coverage); removed by cleanup.sh
```

## Getting Started

```bash
source IP/system/sram/setup.sh      # sets CLAUDE_SRAM_PATH, IP_COMMON_PATH (and on
                                    # csun.edu CLAUDE_SKY130_PDK_PATH)
bash $CLAUDE_SRAM_PATH/cleanup.sh   # remove generated files
```

Directed simulation (csun.edu: VCS and Xcelium):

```bash
cd $CLAUDE_SRAM_PATH/verification/tools
python3 sim_sram.py                                    # VCS, AHB, SV top, GENERIC
python3 sim_sram.py --lang vhdl --tech sky130          # VHDL top under the same SV bench
python3 sim_sram.py --sim xcelium --proto wb --test ecc
python3 sim_sram.py --sim all --proto all --lang all --tech all --coverage --jobs 10
                                                       # all 80 runs + coverage reports
```

Standard host (Verilator: SV tops, GENERIC; Vivado xsim: SV and VHDL tops, GENERIC /
XILINX / ALTERA):

```bash
python3 sim_sram.py --sim verilator --proto all        # 4 builds, one at a time, 8 GB cap
python3 sim_sram.py --sim xsim --proto all --lang all --tech all --jobs 4   # 20 runs + 4 SKIP
python3 sim_sram.py --sim all --proto all --lang all --tech all --jobs 3    # both
python3 lint_sram.py                                   # Verilator + GHDL
python3 fw_sram.py                                     # host tests, mutants, ARM / RISC-V build
python3 $CLAUDE_SRAM_PATH/synthesis/run_vendor_synth.py --jobs 3   # Vivado, Quartus, Yosys (72 netlists)
python3 regression_sram.py --jobs 3                    # all of the above -> report_standard_host.md
```

Options: `--sim vcs|xcelium|verilator|xsim|all`, `--proto ahb|apb|axi4l|wb|all`,
`--lang sv|vhdl|all`, `--tech generic|saed90|saed32|saed14|sky130|xilinx|altera|all`,
`--test <name>` (see Tests), `--waves`, `--coverage`, `--jobs N`. Results and
coverage files are listed under Simulation Results.

Synthesis, STA, gate-level simulation, UPF checks (Step 10) and power (Step 12), csun.edu:

```bash
python3 $CLAUDE_SRAM_PATH/synthesis/run_vendor_synth.py --dc --jobs 3     # 96 netlists, ~1 h
python3 $CLAUDE_SRAM_PATH/synthesis/run_primetime_sta.py                  # 6 targets, ~1 min
python3 $CLAUDE_SRAM_PATH/verification/tools/sim_sram.py --postsyn --proto all --lang all --pdk all --jobs 3
python3 $CLAUDE_SRAM_PATH/verification/tools/lp_sram.py                   # VC LP, 12 runs
python3 $CLAUDE_SRAM_PATH/verification/tools/sim_sram.py --power --proto all --pdk all --jobs 3
                                                    # Step 12: SAIF + PrimePower, 36 analyses
```
