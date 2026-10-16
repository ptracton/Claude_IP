# Claude memory bus (`mem_*`)

The `claude_<proto>_mem_if` adapters in `verilog/` and `vhdl/` turn an APB4,
AHB-Lite, AXI4-Lite or Wishbone B4 slave port into one simple request/response
bus for **memory-like** targets (SRAM, ROM, flash controllers). They are the
memory counterparts of the `claude_<proto>_if` register bridges, which stay
as they are for register-file IP.

What the memory adapters add over the register bridges:

| | `claude_<proto>_if` (registers) | `claude_<proto>_mem_if` (memories) |
|---|---|---|
| Address | fixed 12 bits | `ADDR_W` bits (default 32), full byte address passed on |
| Back-pressure | none — target must answer in 1 cycle | `mem_gnt_i` and `mem_rvalid_i` may each be delayed any number of cycles |
| Errors | never | `mem_err_i` becomes PSLVERR / HRESP / SLVERR / ERR_O |
| AHB bursts | NONSEQ only | NONSEQ, SEQ and BUSY (any burst type), HSIZE byte lanes |
| AXI read + write | can hit the target in the same cycle | serialized, round-robin between read and write |

## Signals

Clock and reset are the bus clock and reset of the adapter.

| Signal | Dir (adapter) | Meaning |
|---|---|---|
| `mem_req_o` | out | request valid |
| `mem_gnt_i` | in | target accepts the request this cycle (handshake = `req & gnt`) |
| `mem_we_o` | out | 1 = write, 0 = read |
| `mem_addr_o[ADDR_W-1:0]` | out | byte address, exactly as the bus master issued it |
| `mem_be_o[DATA_W/8-1:0]` | out | byte enables. Writes: lanes to write. Reads: lanes the master asked for (all ones except narrow AHB / Wishbone `SEL_I`) — a memory may ignore them on reads |
| `mem_wdata_o[DATA_W-1:0]` | out | write data (don't care on reads) |
| `mem_rvalid_i` | in | response for the outstanding request (reads **and** writes) |
| `mem_rdata_i[DATA_W-1:0]` | in | read data, valid only while `mem_rvalid_i` is high |
| `mem_err_i` | in | the request failed, valid only while `mem_rvalid_i` is high |

## Rules

Initiator (adapter):
1. Once `mem_req_o` is raised it stays high, and `we/addr/be` stay stable,
   until the cycle `mem_gnt_i` is high. `wdata` must also stay stable for a
   write; on a read it is meaningless and may change.
2. At most one request is outstanding: after the handshake, `mem_req_o`
   stays low until the cycle after `mem_rvalid_i` (it is low *during* the
   `mem_rvalid_i` cycle too).

Target (memory):
3. `mem_rvalid_i` is high for exactly one cycle per accepted request, and
   never in the handshake cycle itself (earliest: the next cycle). It may
   be delayed any number of cycles.
4. `mem_gnt_i` may be high without a request; it means nothing then.
5. `mem_rdata_i` / `mem_err_i` only need to be valid during `mem_rvalid_i`;
   adapters that need them later (AXI) capture them.

Every bus transfer becomes exactly one `mem_*` request, and every request is
answered by exactly one bus response: OKAY data/ack, or the protocol's error
response when `mem_err_i` was set.

## Latency (target answering at full speed: `gnt` with `req`, `rvalid` next cycle)

| Protocol | Read | Write | Notes |
|---|---|---|---|
| APB4 | 2 cycles (zero wait) | 2 cycles (zero wait) | request issued in SETUP |
| AHB-Lite | 1 wait state | 1 wait state | request issued in the first data-phase cycle, so every beat (including SEQ) has one wait state |
| AXI4-Lite | AR→R 3 cycles | AW/W→B 3 cycles | one read and one write in flight, alternated round-robin |
| Wishbone B4 | ACK 1 cycle after STB | ACK 1 cycle after STB | classic cycles; ERR_O on error |

## Verification

- Formal (VC Formal): `IP/common/verification/mem_if/formal/` binds the shared
  bus checker (`claude_<proto>_fv`), the memory-bus checker
  (`../../verification/formal/claude_mem_fv.sv`) and an end-to-end transfer
  checker (`claude_mem_xfer_fv.sv`) into each adapter, SV and VHDL.
- Simulation (VCS / Xcelium): `IP/common/verification/mem_if/tb/`, one
  testbench per protocol, run against both languages (VHDL through
  mixed-language simulation).
- Runner: `IP/common/verification/tools/verify_mem_if.py`.
