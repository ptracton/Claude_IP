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

Directed simulation (Step 4), results generated 2026-10-18 on a `*.csun.edu`
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
| test_ecc | injected 1-bit (corrected, `ecc_corr_o`) and 2-bit (ERROR, `ecc_uncorr_o`) errors, RMW on clean / 1-bit / 2-bit words, backdoor flip of every stored bit and of bit pairs, dual-port codewords | 26 |
| test_power | LS auto-wake, DS (ERROR, kept), SD (ERROR, cleared), sleep-to-sleep moves, per-bank modes, PWR_GATE 0 | 28 |
| test_clear | clear on every instance, reads stall until `clr_done_o`, domains in DS skipped | 16 |
| test_bist | March C- pass, reads stall, stuck-at fault found with its address, sleeping domains woken | 10 |
| test_dp | width packing both ways, both ports busy at once, same-word races, port B under the side-band (through the CDC), clear, ECC read-modify-write from port B | 10 |
| test_reset_busy | reset during BIST, clears, stalled reads and power transitions, then full recovery | 4 |

### Results (VCS / Xcelium, thousands of comparisons per run)

The same for both languages (identical comparison counts for SV and VHDL):

| Bus | Language | GENERIC | SAED90 | SAED32 | SAED14 | SKY130 |
|---|---|---|---|---|---|---|
| AHB-Lite | SV | PASS / PASS (117k) | PASS / PASS (115k) | PASS / PASS (115k) | PASS / PASS (115k) | PASS / PASS (90k) |
| AHB-Lite | VHDL | PASS / PASS (117k) | PASS / PASS (115k) | PASS / PASS (115k) | PASS / PASS (115k) | PASS / PASS (90k) |
| APB4 | SV | PASS / PASS (117k) | PASS / PASS (115k) | PASS / PASS (115k) | PASS / PASS (115k) | PASS / PASS (90k) |
| APB4 | VHDL | PASS / PASS (117k) | PASS / PASS (115k) | PASS / PASS (115k) | PASS / PASS (115k) | PASS / PASS (90k) |
| AXI4-Lite | SV | PASS / PASS (118k) | PASS / PASS (117k) | PASS / PASS (117k) | PASS / PASS (117k) | PASS / PASS (91k) |
| AXI4-Lite | VHDL | PASS / PASS (118k) | PASS / PASS (117k) | PASS / PASS (117k) | PASS / PASS (117k) | PASS / PASS (91k) |
| Wishbone | SV | PASS / PASS (117k) | PASS / PASS (115k) | PASS / PASS (115k) | PASS / PASS (115k) | PASS / PASS (90k) |
| Wishbone | VHDL | PASS / PASS (117k) | PASS / PASS (115k) | PASS / PASS (115k) | PASS / PASS (115k) | PASS / PASS (90k) |

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
VHDL run 92.98.

Per run, SystemVerilog top-levels (`verification/work/coverage/per_run.txt`):

| Run | Score | Line | Cond | Toggle | FSM | Branch | Weakest module |
|---|---|---|---|---|---|---|---|
| AHB / GENERIC | 95.49 | 97.60 | 94.84 | 99.07 | 92.59 | 93.36 | sram_cdc (92.95) |
| AHB / SAED14 | 95.39 | 97.50 | 94.89 | 99.04 | 92.59 | 92.92 | sram_pwr_ctrl (94.18) |
| AHB / SAED32 | 95.59 | 97.56 | 95.47 | 99.02 | 92.59 | 93.29 | sram_cdc (92.95) |
| AHB / SAED90 | 95.60 | 97.56 | 95.52 | 99.02 | 92.59 | 93.29 | sram_cdc (92.95) |
| AHB / SKY130 | 95.16 | 97.56 | 93.87 | 98.51 | 92.59 | 93.29 | sram_cdc (92.95) |
| APB / GENERIC | 94.71 | 97.40 | 94.26 | 99.23 | 89.47 | 93.19 | sram_cdc (92.95) |
| APB / SAED14 | 94.61 | 97.28 | 94.36 | 99.19 | 89.47 | 92.73 | claude_apb_mem_if (93.67) |
| APB / SAED32 | 94.82 | 97.36 | 94.99 | 99.17 | 89.47 | 93.12 | sram_cdc (92.95) |
| APB / SAED90 | 94.84 | 97.36 | 95.05 | 99.17 | 89.47 | 93.12 | sram_cdc (92.95) |
| APB / SKY130 | 94.30 | 97.36 | 93.06 | 98.47 | 89.47 | 93.12 | sram_cdc (92.95) |
| AXI4-Lite / GENERIC | 95.12 | 97.54 | 93.59 | 99.17 | 91.67 | 93.61 | sram_cdc (92.95) |
| AXI4-Lite / SAED14 | 95.03 | 97.44 | 93.71 | 99.13 | 91.67 | 93.20 | sram_pwr_ctrl (94.18) |
| AXI4-Lite / SAED32 | 95.23 | 97.50 | 94.33 | 99.12 | 91.67 | 93.55 | sram_cdc (92.95) |
| AXI4-Lite / SAED90 | 95.25 | 97.50 | 94.40 | 99.12 | 91.67 | 93.55 | sram_cdc (92.95) |
| AXI4-Lite / SKY130 | 94.71 | 97.50 | 92.38 | 98.43 | 91.67 | 93.55 | sram_cdc (92.95) |
| WB / GENERIC | 94.94 | 97.40 | 95.44 | 99.23 | 89.47 | 93.16 | claude_wb_mem_if (93.33) |
| WB / SAED14 | 94.81 | 97.28 | 95.42 | 99.19 | 89.47 | 92.70 | claude_wb_mem_if (93.33) |
| WB / SAED32 | 95.02 | 97.36 | 96.02 | 99.18 | 89.47 | 93.09 | claude_wb_mem_if (93.33) |
| WB / SAED90 | 95.03 | 97.36 | 96.07 | 99.18 | 89.47 | 93.09 | claude_wb_mem_if (93.33) |
| WB / SKY130 | 94.54 | 97.36 | 94.13 | 98.67 | 89.47 | 93.09 | claude_wb_mem_if (93.33) |

All 20 SV runs merged (`verification/work/coverage/summary.txt`), total
**95.84** (line 97.81, cond 94.23, toggle 99.19, FSM 93.75, branch 94.21):

| Module | Score | Line | Cond | Toggle | FSM | Branch |
|---|---|---|---|---|---|---|
| `claude_wb_mem_if` | 93.33 | 100.00 | 73.33 | 100.00 | -- | 100.00 |
| `claude_apb_mem_if` | 93.67 | 100.00 | 74.67 | 100.00 | -- | 100.00 |
| `sram_clr` | 94.29 | 92.79 | 89.75 | 94.62 | -- | 100.00 |
| `sram_pwr_ctrl` | 94.65 | 97.44 | 100.00 | 92.86 | 87.50 | 95.45 |
| `sram_port` | 95.40 | 98.51 | 93.45 | 98.66 | -- | 90.97 |
| `claude_axi4l_mem_if` | 96.64 | 100.00 | 84.35 | 98.83 | 100.00 | 100.00 |
| `claude_ahb_mem_if` | 96.80 | 100.00 | 85.11 | 98.89 | 100.00 | 100.00 |
| `sram_cdc` | 97.12 | 100.00 | 100.00 | 88.46 | -- | 100.00 |
| `claude_sync` | 97.22 | 100.00 | -- | 91.67 | -- | 100.00 |
| `sram_bist` | 98.18 | 100.00 | 100.00 | 100.00 | 90.91 | 100.00 |
| `sram_core` | 98.19 | 100.00 | 93.64 | 99.12 | -- | 100.00 |
| `sram_ahb_dp` | 98.50 | -- | -- | 98.50 | -- | -- |
| `sram_macro_dp_sky130` | 98.87 | 100.00 | 100.00 | 95.48 | -- | 100.00 |
| `sram_ahb` | 98.96 | -- | -- | 98.96 | -- | -- |
| `sram_macro_sky130` | 99.06 | 100.00 | 100.00 | 96.24 | -- | 100.00 |
| `sram_macro` | 99.45 | -- | -- | 99.45 | -- | -- |
| `sram_macro_dp` | 99.46 | -- | -- | 99.46 | -- | -- |
| `sram_macro_dp_saed14` | 99.59 | 100.00 | 100.00 | 98.36 | -- | 100.00 |
| `sram_macro_dp_saed32` | 99.60 | 100.00 | 100.00 | 98.40 | -- | 100.00 |
| `sram_macro_dp_saed90` | 99.64 | 100.00 | 100.00 | 98.57 | -- | 100.00 |
| `sram_axi4l` | 99.74 | -- | -- | 99.74 | -- | -- |
| `sram_macro_generic` | 99.82 | 100.00 | -- | 99.45 | -- | 100.00 |
| `sram_macro_saed90` | 99.82 | 100.00 | 100.00 | 99.29 | -- | 100.00 |
| `sram_macro_saed32` | 99.82 | 100.00 | 100.00 | 99.29 | -- | 100.00 |
| `sram_macro_dp_generic` | 99.82 | 100.00 | -- | 99.47 | -- | 100.00 |
| `sram_macro_saed14` | 99.85 | 100.00 | 100.00 | 99.41 | -- | 100.00 |
| `sram_array` | 99.87 | 100.00 | 100.00 | 99.49 | -- | 100.00 |
| `sram_ecc_enc` | 100.00 | 100.00 | 100.00 | 100.00 | -- | -- |
| `sram_ecc_dec` | 100.00 | 100.00 | 100.00 | 100.00 | -- | -- |
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

**Target met:** the weakest VHDL module of any run scores 92.98.

| Run | Score | Line | Cond | Toggle | FSM | Branch | Weakest module |
|---|---|---|---|---|---|---|---|
| AHB / GENERIC | 97.90 | 98.51 | 99.19 | 97.99 | 96.30 | 97.49 | sram_array (93.64) |
| AHB / SAED14 | 96.97 | 98.30 | 97.80 | 96.29 | 96.30 | 96.18 | sram_array (93.64) |
| AHB / SAED32 | 97.56 | 98.43 | 99.27 | 96.31 | 96.30 | 97.49 | sram_array (93.64) |
| AHB / SAED90 | 97.57 | 98.43 | 99.27 | 96.36 | 96.30 | 97.49 | sram_array (93.64) |
| AHB / SKY130 | 97.14 | 98.43 | 97.72 | 95.75 | 96.30 | 97.49 | sram_array (93.00) |
| APB / GENERIC | 97.71 | 98.66 | 99.44 | 98.05 | 94.74 | 97.67 | sram_array (93.64) |
| APB / SAED14 | 96.77 | 98.45 | 97.98 | 96.39 | 94.74 | 96.27 | sram_array (93.64) |
| APB / SAED32 | 97.38 | 98.58 | 99.49 | 96.40 | 94.74 | 97.67 | sram_array (93.64) |
| APB / SAED90 | 97.39 | 98.58 | 99.49 | 96.45 | 94.74 | 97.67 | sram_array (93.64) |
| APB / SKY130 | 96.96 | 98.58 | 98.16 | 95.67 | 94.74 | 97.67 | sram_array (93.01) |
| AXI4-Lite / GENERIC | 97.70 | 98.61 | 98.50 | 97.94 | 95.83 | 97.64 | sram_array (93.64) |
| AXI4-Lite / SAED14 | 96.87 | 98.43 | 97.27 | 96.41 | 95.83 | 96.43 | sram_array (93.64) |
| AXI4-Lite / SAED32 | 97.41 | 98.54 | 98.64 | 96.42 | 95.83 | 97.64 | sram_array (93.64) |
| AXI4-Lite / SAED90 | 97.42 | 98.54 | 98.64 | 96.47 | 95.83 | 97.64 | sram_array (93.64) |
| AXI4-Lite / SKY130 | 96.98 | 98.54 | 97.18 | 95.69 | 95.83 | 97.64 | sram_array (92.98) |
| WB / GENERIC | 97.65 | 98.66 | 99.16 | 98.02 | 94.74 | 97.66 | sram_array (93.64) |
| WB / SAED14 | 96.71 | 98.45 | 97.73 | 96.39 | 94.74 | 96.23 | sram_array (93.64) |
| WB / SAED32 | 97.32 | 98.58 | 99.24 | 96.40 | 94.74 | 97.66 | sram_array (93.64) |
| WB / SAED90 | 97.34 | 98.58 | 99.24 | 96.46 | 94.74 | 97.66 | sram_array (93.64) |
| WB / SKY130 | 96.95 | 98.58 | 97.90 | 95.86 | 94.74 | 97.66 | sram_array (93.00) |

All 20 VHDL runs merged (`verification/work/coverage/vhdl/summary.txt`), total
**98.04** (line 98.64, cond 98.67, toggle 98.05, FSM 96.88, branch 97.98). The
merge cannot apply per-instance exclusions (its instances are the first run's),
so the merged toggle of each VHDL module is its best single run: a lower
bound of the merged value.

| Module | Score | Line | Cond | Toggle | FSM | Branch |
|---|---|---|---|---|---|---|
| `sram_array` | 93.64 | 94.87 | 100.00 | 84.96 | -- | 94.74 |
| `sram_cdc` | 95.50 | 100.00 | -- | 86.49 | -- | 100.00 |
| `claude_sync` | 95.56 | 100.00 | -- | 86.67 | -- | 100.00 |
| `claude_axi4l_mem_if` | 97.53 | 98.46 | 93.22 | 98.15 | 100.00 | 97.83 |
| `sram_bist` | 97.32 | 98.48 | 100.00 | 100.00 | 90.91 | 97.22 |
| `claude_ahb_mem_if` | 97.87 | 97.22 | 96.55 | 99.17 | 100.00 | 96.43 |
| `sram_pwr_ctrl` | 98.00 | 95.12 | 100.00 | 100.00 | 100.00 | 94.87 |
| `sram_macro_dp_sky130` | 98.16 | 100.00 | 100.00 | 92.62 | -- | 100.00 |
| `claude_wb_mem_if` | 98.33 | 100.00 | 93.33 | 100.00 | -- | 100.00 |
| `sram_core` | 98.41 | 100.00 | 100.00 | 93.64 | -- | 100.00 |
| `sram_clr` | 98.61 | 100.00 | 100.00 | 94.42 | -- | 100.00 |
| `sram_ahb_dp` | 98.84 | -- | -- | 98.84 | -- | -- |
| `sram_port` | 98.86 | 100.00 | 98.32 | 99.05 | -- | 98.08 |
| `sram_ahb` | 99.23 | -- | -- | 99.23 | -- | -- |
| `sram_macro_generic` | 99.49 | 100.00 | -- | 98.47 | -- | 100.00 |
| `sram_macro_dp` | 99.52 | -- | -- | 99.52 | -- | -- |
| `sram_macro_dp_saed14` | 99.53 | 100.00 | 100.00 | 98.10 | -- | 100.00 |
| `sram_macro` | 99.56 | -- | -- | 99.56 | -- | -- |
| `sram_macro_dp_saed32` | 99.57 | 100.00 | 100.00 | 98.29 | -- | 100.00 |
| `sram_macro_sky130` | 99.59 | 100.00 | 100.00 | 98.38 | -- | 100.00 |
| `sram_macro_dp_saed90` | 99.69 | 100.00 | 100.00 | 98.77 | -- | 100.00 |
| `sram_axi4l` | 99.72 | -- | -- | 99.72 | -- | -- |
| `sram_macro_saed32` | 99.82 | 100.00 | 100.00 | 99.28 | -- | 100.00 |
| `sram_macro_saed90` | 99.82 | 100.00 | 100.00 | 99.28 | -- | 100.00 |
| `sram_macro_saed14` | 99.85 | 100.00 | 100.00 | 99.40 | -- | 100.00 |
| `sram_macro_dp_generic` | 99.88 | 100.00 | -- | 99.65 | -- | 100.00 |
| `sram_apb` | 100.00 | -- | -- | 100.00 | -- | -- |
| `sram_wb` | 100.00 | -- | -- | 100.00 | -- | -- |
| `sram_axi4l_dp` | 100.00 | -- | -- | 100.00 | -- | -- |
| `sram_apb_dp` | 100.00 | -- | -- | 100.00 | -- | -- |
| `sram_wb_dp` | 100.00 | -- | -- | 100.00 | -- | -- |
| `sram_ecc_enc` | 100.00 | 100.00 | -- | 100.00 | -- | 100.00 |
| `sram_ecc_dec` | 100.00 | 100.00 | 100.00 | 100.00 | -- | 100.00 |
| `claude_pulse_sync` | 100.00 | 100.00 | -- | 100.00 | -- | 100.00 |
| `claude_apb_mem_if` | 100.00 | 100.00 | 100.00 | 100.00 | -- | 100.00 |

SV and VHDL percentages are not directly comparable: VCS counts VHDL
conditions and FSM transitions differently (e.g. the APB adapter's condition
coverage is 75% in SV and 100% in VHDL with the same stimulus).

Below 90% inside modules that pass (SV): condition coverage of the APB / Wishbone
adapters (73-75%; AHB 85, AXI4-Lite 84), `sram_pwr_ctrl` FSM 87.5%,
`sram_cdc` toggle 88.5%, `sram_clr` condition 89.8%.

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

> Populated by Step 5 (formal)

[TBD]

## UVM Verification Results

> Populated by Step 6 (uvm)

[TBD]

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
    ├── tools/sim_sram.py       simulation and coverage runner
    ├── formal/ lint/ regression/ tasks/uvm/ modelsim/ vivado/   later steps
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

Options: `--sim vcs|xcelium|all`, `--proto ahb|apb|axi4l|wb|all`,
`--lang sv|vhdl|all`, `--tech generic|saed90|saed32|saed14|sky130|all`,
`--test <name>` (see Tests), `--waves`, `--coverage`, `--jobs N`. Results and
coverage files are listed under Simulation Results.
