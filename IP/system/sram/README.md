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
2. **Next cycle.** The response is formed: corrected read data, or a
   read-modify-write write-back.
3. **Response.** It is returned in the next cycle with `READ_LATENCY = 1`, or
   one cycle later with `READ_LATENCY = 2`.

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
| `READ_LATENCY` | 1/2 | 1 | 2 adds an output register |
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
| LIGHT_SLEEP | kept | wakes automatically (wait states), then re-enters LS | LS | chip select held off; UPF retention | XPM `sleep` / clock enable |
| DEEP_SLEEP | kept | bus error | DS | chip select held off; periphery off (UPF) | XPM `sleep` / clock enable |
| SHUTDOWN | lost; zeroed by the clear engine before RUN is acknowledged | bus error | SD | power switched (UPF), isolation | contents X in simulation |

Entry and wake times come from `sram_pkg::pwr_enter_cycles` /
`pwr_wake_cycles`. They default to 2/2/4/8 cycles (SAED32: 4/2/8/16) and are to
be checked against the liberty timing at synthesis. While BIST runs, every
domain is held in RUN. UPF files for SAED90, SAED14 and SKY130 belong in
`design/upf/` (Step 10).

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
runs the backdoor checks.

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
| AHB-Lite | PASS | 117,663 | 53,826 | ~5 min |
| APB4 | PASS | 117,492 | 53,762 | ~6 min |
| AXI4-Lite | PASS | 118,360 | 54,045 | ~29 min |
| Wishbone | PASS | 117,492 | 53,762 | ~5 min |

Each run simulates in 3-6 s. The build and run are capped at 8 GB
(`systemd-run --user --scope -p MemoryMax=8G`; `SRAM_VERILATOR_MEM`
overrides) and Verilator runs go one at a time; Verilator itself allocates
0.9-1.9 GB. The AXI4-Lite build is slow in Verilator's conversion step
(about 1000 s against 140 s for the other buses). Bench adaptations, all
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
VHDL run 92.99 (re-run 2026-11-21; `sram_ecc_dec` in the PDK runs is at least
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

Mixed-language (VHDL top-levels) tool behaviour found and handled in the
bench and `sim_sram.py`:

| Tool | Behaviour | Handling |
|---|---|---|
| VCS | a VHDL generic whose default refers to another generic (`READ_LATENCY_B := READ_LATENCY`, and `BYTE_EN_B`, `PARTIAL_WR_ERR_B`) takes that generic's *default* when SystemVerilog instantiates the VHDL top (pure VHDL and Xcelium are correct); found by the model's new latency check (dp2 port B answered after 1 cycle instead of 2) | instantiate the VHDL dual-port tops from Verilog with the port-B options set explicitly; the bench does so on VCS |
| Xcelium | VHDL generic maps bind Verilog parameters by position unless `-namemap_mixgen` (the SKY130 wrapper's `VERBOSE => 0` set the model's `NUM_WMASKS`) | `-namemap_mixgen` |
| VCS | SV `force` of a VHDL bit (or of a VHDL signal the bench also reads) is not supported | `$hdl_xmr_force` for the BIST stuck-at fault |
| both | VPI cannot read VHDL storage | VHPI entry points in `claude_backdoor.c` |

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
2026-11-21. One DUT per build, chosen by bus x language (SV top, or the VHDL
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

Results (`verification/work/uvm/results.log`), GENERIC, both simulators, 4 buses x
SV/VHDL x 3 configs: **288/288 test runs PASS** (272 in the sweep; the 16 runs of
the three builds compiled before two bench force fixes re-run PASS). The full
matrix with the four PDKs is in progress.

Functional coverage (VCS, covergroups per instance, coverpoints of a feature
the config lacks have weight 0), merged per configuration over the 8 GENERIC
builds: **base 100.00, full 100.00, dp 100.00** (target 100). Code coverage
per build (`verification/work/uvm/coverage/per_build.txt`): every module at least 90
in 22 of the 24 VCS builds; **open:** `claude_wb_mem_if` scores 89.89 (WB SV dp) and
89.93 (WB SV base), just under the target; the next weakest is `sram_clr` 90.19.

Mutation check (`verification/work/uvm/mutants/results.log`): **9/9 mutants
killed** — no out-of-range error, a dropped address bit, byte lane 0 always
written, no err_irq on failed writes, deep sleep accepting accesses, an
uncorrectable ECC error answering OKAY, no ecc_corr pulse, BIST never failing,
port B rejecting writes.

Found while building it: the class scoreboard needs `sram_model`'s port-B
power-error rule relaxed for separate clocks (the requested mode reaches port B
through the core's CDC), now the opt-in parameter `B_MODE_GUARD`; the Step 4
coverage hole in `sram_ecc_dec` (see Code coverage), closed with the same
read-path stuck-bit sweep in both benches.

## Lint Results

> Populated by Step 8 (lint)

[TBD]

## Firmware

> Populated by Step 9 (firmware): memory-test routines and power-mode helpers
> (there is no register-level driver).

### Code Size

[TBD]

### API Summary

[TBD]

## Synthesis Results

> Populated by Step 10 (synthesis)

[TBD]

## Power Analysis

> Populated by Step 12 (power)

[TBD]

## Directory Layout

```
sram/
├── setup.sh / cleanup.sh       environment (CLAUDE_SRAM_PATH) and artifact cleanup
├── design/
│   ├── behavioral/             reference model
│   ├── rtl/verilog, rtl/vhdl   RTL (SV and VHDL-2008)
│   └── upf/                    power intent for the PDKs without native sleep pins
├── doc/                        specification
├── firmware/                   memory-test and power-mode helpers (C99)
├── synthesis/                  Yosys, Vivado, Quartus, Design Compiler, PrimeTime
└── verification/
    ├── testbench/              SV system bench (tb_sram_<proto>.sv + shared body), BFMs
    ├── tests/                  directed tests and helpers (shared by SV and VHDL tops)
    ├── tasks/uvm/              UVM bench (agents, env, sequences, tests, tb_sram_uvm.sv)
    ├── tools/sim_sram.py       simulation and coverage runner
    ├── tools/uvm_sram.py       UVM runner; uvm_mutants.py proves the UVM tests can fail
    ├── formal/ lint/ regression/ modelsim/ vivado/   later steps
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

Standard host (Verilator, SV tops, GENERIC):

```bash
python3 sim_sram.py --sim verilator --proto all        # 4 builds, one at a time, 8 GB cap
```

Options: `--sim vcs|xcelium|verilator|all`, `--proto ahb|apb|axi4l|wb|all`,
`--lang sv|vhdl|all`, `--tech generic|saed90|saed32|saed14|sky130|all`,
`--test <name>` (see Tests), `--waves`, `--coverage`, `--jobs N`. Results and
coverage files are listed under Simulation Results.
