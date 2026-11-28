# Claude memory bus — initiator side: master adapters (`claude_<proto>_mst_if`)

Spec version: **1.0** (see "Change log" at the end).

Status: **specification approved by the user, 2026-11-26** (Phase 0.1 of
`.agents/IP_PLAN.md`, §3.2). Not implemented yet.

This document extends `IP_SPEC_mem_bus.md`, the spec of the existing
memory bus and its slave adapters, which is unchanged. "Rules 1–5" below are the rules in
that file. When the master adapters are implemented, this content is merged into
`IP_SPEC_mem_bus.md`, so one file describes both sides of the bus.

### Purpose

Today `mem_*` runs in one direction: a bus slave adapter **issues** requests to a memory.
The master adapters run it the other way: an IP that has to **start** transactions (DMA,
CPU, jtag2bus, uart2bus, spi_slave, VGA, NPU) issues `mem_*` requests, and the adapter
turns them into APB4 / AHB-Lite / AXI4-Lite / Wishbone B4 **master** signals.

```
 initiator IP ── mem_* ──► claude_<proto>_mst_if ──► bus (bus_matrix, bridge, or one slave)
 bus master ──► claude_<proto>_mem_if ── mem_* ──► claude_<proto>_mst_if ──► other protocol  (bridge)
 initiator IP ── mem_* ─────────────────────────────► memory target         (point to point)
```

**The bus rules (1–5 in `IP_SPEC_mem_bus.md`) do not change.** The master adapter is simply a `mem_*`
*target*, so:
- every initiator can drive a master adapter, a memory, or another target directly;
- a slave adapter followed by a master adapter is a complete protocol bridge
  (4 + 4 adapters instead of 12 bridges);
- the existing formal checker `claude_mem_fv` checks the new adapters' `mem_*` side
  unchanged.

### Port naming

The adapter's `mem_*` ports are the mirror image of the slave adapters' ports:

| Signal | Dir (master adapter) | Width |
|---|---|---|
| `mem_req_i` | in | 1 |
| `mem_gnt_o` | out | 1 |
| `mem_we_i` | in | 1 |
| `mem_addr_i` | in | `ADDR_W` |
| `mem_be_i` | in | `DATA_W/8` |
| `mem_wdata_i` | in | `DATA_W` |
| `mem_prot_i` | in | 3 (new, optional, see below) |
| `mem_rvalid_o` | out | 1 |
| `mem_rdata_o` | out | `DATA_W` |
| `mem_err_o` | out | 1 |

Bus-side ports use the protocol's standard master names and the same clock / reset names
as the slave adapters (`PCLK`/`PRESETn`, `HCLK`/`HRESETn`, `ACLK`/`ARESETn`,
`CLK_I`/`RST_I`). Parameters: `DATA_W` (default 32), `ADDR_W` (default 32), and the
protocol-specific ones listed below. The initiator runs on the bus clock. A different clock
needs the bus CDC bridge (plan §10.1); the adapter itself never crosses clocks.

### New initiator rules (add to rules 1–5 of `IP_SPEC_mem_bus.md`)

6. **Address matches the byte enables.** `mem_addr[OffW-1:0]` is the index of the
   lowest enabled byte lane, so `mem_addr` is the true byte address of the access (for
   example a halfword in lanes 2–3 of word `0x100` has address `0x102`). Full-word
   accesses are word aligned.
7. **Reads ask for exactly the lanes they need**, and those lanes are naturally aligned:
   one byte, an aligned halfword, an aligned word (up to `DATA_W/8` bytes). Peripherals
   with read side effects (FIFO pop on a byte read) depend on this. The adapter returns
   all `DATA_W` bits; only the requested lanes are defined.
8. **Writes may use any byte-enable pattern**, except that an AHB-Lite master without
   write strobes (`HAS_HWSTRB = 0`) accepts only naturally aligned patterns (rule 7). An
   illegal pattern is answered with `mem_err_o` **without** a bus access, so it cannot
   corrupt memory. RISC-V cores and the DMA only produce aligned patterns, so this
   normally never fires.
9. `mem_be` is never all zeros.

### Optional protection attribute `mem_prot` (new)

Carries the access type to the bus for the firewall and PMP checks (plan §11). AXI `AxPROT`
encoding:

| Bit | 0 | 1 |
|---|---|---|
| `[0]` | unprivileged | privileged |
| `[1]` | secure | non-secure |
| `[2]` | data | instruction |

- An initiator with no notion of privilege ties it to `3'b000`. The firewall identifies
  masters by their bus_matrix port, not by `mem_prot`, so this default gives no extra rights.
- Mapping: APB4 `PPROT` = `mem_prot`; AXI4-Lite `AWPROT` / `ARPROT` = `mem_prot`; AHB-Lite
  `HPROT[3:0]` = `{1'b0 /*not cacheable*/, 1'b0 /*not bufferable*/, mem_prot[0], ~mem_prot[2]}`
  and, if `HAS_HNONSEC = 1`, AHB5 `HNONSEC` = `mem_prot[1]`; Wishbone has no equivalent,
  so the signal is dropped there (documented).
- Only the master adapters take `mem_prot` now. The slave adapters (signed off) gain an
  optional `mem_prot_o` in a later revision, when the firewall needs it.

### Timing (all bus-side outputs registered)

Every protocol output of a master adapter comes from a flop, so no combinational path runs
from the initiator through the adapter onto the bus. `mem_gnt_o` is high whenever the
adapter is idle (the request is captured), and `mem_rvalid_o` comes from a flop.

Latency with a zero-wait slave (handshake cycle = cycle 0):

| Protocol | Cycle 1 | Cycle 2 | `mem_rvalid_o` | Throughput (one outstanding) |
|---|---|---|---|---|
| APB4 | SETUP (`PSEL`) | ACCESS (`PENABLE`, `PREADY` = 1) | cycle 3 | 1 per 4 cycles |
| AHB-Lite | address phase (`HTRANS` = NONSEQ) | data phase (`HREADY` = 1) | cycle 3 | 1 per 4 cycles |
| AXI4-Lite | `AxVALID` (+ `WVALID`), ready = 1 | `RVALID` / `BVALID` | cycle 3 | 1 per 4 cycles |
| Wishbone B4 classic | `CYC`/`STB` | `ACK` (registered slave) | cycle 3 | 1 per 4 cycles |

That is enough for CPUs without caches, debug access and register traffic. High-bandwidth
masters (DMA, VGA, NPU, caches) get bursts and more outstanding transfers in Phase 0b
(D1). Those are added as parameters without changing the rules here.

### Protocol details

**APB4 master** (`claude_apb_mst_if`): one `PSEL` (address decoding belongs to the bus
demux or bus_matrix); `PSTRB` = `mem_be` on writes, `0` on reads (as APB4 requires);
`PSLVERR` → `mem_err_o`; waits any number of cycles on `PREADY`.

**AHB-Lite master** (`claude_ahb_mst_if`): `HBURST` = SINGLE, `HMASTLOCK` = 0,
`HTRANS` = NONSEQ then IDLE; `HSIZE` from the byte enables (rule 7); `HWSTRB` = `mem_be`
on writes when `HAS_HWSTRB = 1` (default 1, matching the existing slave adapter);
`HRESP` ERROR (two-cycle response) → `mem_err_o`. With one transfer outstanding there is
never a following transfer to cancel.

**AXI4-Lite master** (`claude_axi4l_mst_if`): a write raises `AWVALID` and `WVALID`
together and holds each until it is accepted (either order); `BRESP` / `RRESP`
`SLVERR` or `DECERR` → `mem_err_o` (the two error codes are not distinguished on
`mem_*`); `BREADY` / `RREADY` are high while a response is expected.

**Wishbone B4 classic master** (`claude_wb_mst_if`): `CYC_O` / `STB_O` until `ACK_I`,
`ERR_I` or `RTY_I`; `SEL_O` = `mem_be`; `ERR_I` → `mem_err_o`; `RTY_I` repeats the cycle
up to `MAX_RETRY` times (parameter, default 4), then returns `mem_err_o`.

**Reset:** while reset is active the adapter drives the bus idle (`PSEL`, `HTRANS`,
`AxVALID`/`WVALID`, `CYC_O` low) and `mem_gnt_o` low. A request is never half-issued
across a reset.

**DFT:** no `test_mode_i` / `scan_en_i` ports. These are shared bus cells with no clock,
reset or memory logic of their own, the same as the existing bridges.

### Verification plan (once, in `IP/common/verification/mst_if/`)

- **Loopback simulation:** master adapter → protocol bus → the existing slave memory
  adapter of the same protocol → memory model. Every master adapter is tested against a
  signed-off slave adapter, and random wait states, `mem_gnt` / `mem_rvalid` delays and
  error injection run on both sides. Run with SV and VHDL adapters, in every language
  pairing.
- **Formal:** `claude_<proto>_fv` in the *master-checked* role (assert the adapter's bus
  outputs, assume the slave); `claude_mem_fv` in the *target-checked* role (assume the
  initiator rules 1–2 and 6–9, assert target rules 3–5); an end-to-end transfer checker
  (each request produces exactly one bus transfer with the same address, data, byte
  enables and attributes, and exactly one response).
- **Latency:** directed tests measure the table above.
- **System test: master → bus_matrix → SRAM** (user, 2026-11-26). Shows that the master
  adapters work in a real interconnect, not only point to point:

  ```
  initiator BFM M0 ─ mem_* ─► claude_<proto>_mst_if ─┐                    ┌─ S0: claude_<proto>_mem_if ─ mem_* ─► claude_mem_model (ROM region)
                                                    ├─► bus_matrix_<proto> ┼─ S1: claude_<proto>_mem_if ─ mem_* ─► claude_mem_model (SRAM, 128 KiB)
  initiator BFM M1 ─ mem_* ─► claude_<proto>_mst_if ─┘  (default config:    ├─ S2: claude_<proto>_mem_if ─ mem_* ─► claude_mem_model (error-injecting)
                                                         2 masters, 4 slaves)└─ S3: claude_<proto>_mem_if ─ mem_* ─► claude_mem_model
  ```

  - **`claude_mem_model`** (new, `IP/common/verification/models/`, SV, testbench only): a
    simple behavioral SRAM that is a `mem_*` target. Parameters: size, base, and
    random or fixed `mem_gnt` / `mem_rvalid` delays (including the zero-wait case). It
    merges byte lanes on writes, can force `mem_err` on an address range, and gives
    backdoor `peek` / `poke` tasks for the bench. It is not the sram IP's `sram_model.sv`,
    which is a checker for the sram's own bus, not a memory.
  - The bus_matrix runs in its signed-off default configuration (`bus_matrix_pkg`:
    S1 = SRAM at `0x2000_0000`). The test only instantiates it; no bus_matrix file changes.
  - The initiator BFMs are the `mem_*` initiator tasks of Phase 0.3, driving the master
    adapters' `mem_*` ports.
  - Tests, run for each protocol (APB4, AHB-Lite, AXI4-Lite, Wishbone):
    1. Write then read back the SRAM through M0: words, halfwords and bytes on every
       lane, and sparse write strobes where the protocol allows them (rule 8).
       Back-to-back transfers. The data is checked through the bus and through the
       model's backdoor.
    2. The same from M1, then **both masters at once** on the SRAM (arbitration, no lost
       or corrupted transfers), and each master on a different slave at the same time.
    3. **Errors reach the initiator:** an unmapped address (bus_matrix decode error), and
       a forced error from the S2 model, both arrive as `mem_err` on the right master, and
       the next transfer still works.
    4. **Random traffic:** constrained-random reads and writes from both masters (sizes,
       lanes, addresses across all four regions, random delays in the models), checked
       against a reference array in the bench. A minimum transfer count and a coverage
       report of sizes × lanes × masters × slaves.
  - Languages: SV adapters and bus_matrix; VHDL adapters and bus_matrix (mixed-language
    bench, as in the existing benches); and mixed (SV master adapters with the VHDL
    bus_matrix, and the other way round).
  - Simulators: the standard set (Icarus where the code allows, xsim; GHDL is not
    possible for a mixed SV bench), and VCS + Xcelium on csun.edu.
  - Optional later run: replace the S1 model with the real sram IP (`TECH = GENERIC`)
    behind its own APB/AHB/AXI4-Lite/WB top, as an integration check of the sram as well.
- **Runner:** `IP/common/verification/tools/verify_mst_if.py` (same structure as
  `verify_mem_if.py`). It runs the loopback, formal and system tests and writes one
  results log.

---

## Change log

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-11-26 | approved |
