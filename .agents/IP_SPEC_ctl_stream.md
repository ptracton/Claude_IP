# Control stream and the second register port — v1.1 approved 2026-11-27

Spec version: **1.1** (see "Change log" at the end).

Location: `.agents/IP_SPEC_ctl_stream.md` (all interface specs live in `.agents/`; the RTL
headers of components built from it point here).

Status: specification only, Phase 0.1 of `.agents/IP_PLAN.md` (§3.8, §6.1, D11). Nothing
here is implemented yet.

The **control stream** lets something other than the CPU write and read an IP's registers
over a claude stream: the DMA (the communication blocks' back door, §6.1), a sequencer
(`rv_tiny`), another DSP block (AGC → FIR gain), the NPU controller, or a `claude_cmd2bus`
host (`CTL` command). It is **optional** (`CTL_PORT`) and is **only another way into the same
registers**: the register bus can do everything it can, and the bus always wins
(`IP_SPEC_stream.md`, "Operated by the stream, configured by the bus").

```
 system bus ─► claude_<proto>_if ──────┐ port A (always wins)
                                       ├─► claude_regbus_arb ─► <ip>_regfile ─► <ip>_core
 s_ctl_* ─► [claude_ctl_ring] ─► claude_ctl2reg ─┘ port B
 m_ctl_* ◄─ [claude_ctl_ring] ◄─ responses
```

Components (Phase 0.2): `claude_ctl2reg` (packets ↔ register accesses), `claude_regbus_arb`
(merges ports A and B, bus wins, ownership), `claude_ctl_ring` (DEST-ID forwarder for rings).

---

## Packet format

A claude stream with `DW` = 32, `UW` = 3 (the packet's protection attribute, see "Privilege
and security"), one packet per command, `tlast` on its last word.
Little-endian words; bit 31 is the MSB.

### Request header (word 0)

| Bits | Field | Meaning |
|---|---|---|
| [31:28] | `CMD` | see the command table |
| [27] | `SYNC` | apply at the IP's next frame boundary instead of at once (see "SYNC") |
| [26] | `RESP` | send a response even for a write (acknowledgement) |
| [25:20] | `DEST` | destination ID (1–62; `0x3F` = broadcast; `0x00` = reserved for controllers) |
| [19:8] | `ADDR` | register byte address in the IP's 4 KiB window (word aligned, [9:8] = 0) |
| [7:0] | `LEN-1` | number of register accesses minus 1 (`LEN` = 1–256): the write data words that follow (WR, WR_FIXED) or the words to read (RD, RD_FIXED); 0 for NOP, WR_MASK, WAIT, WAIT_EVT |

### Commands

| CMD | Name | Words after the header | Action | Response data |
|---|---|---|---|---|
| `0x0` | NOP | none | nothing (a response if `RESP`) | — |
| `0x1` | WR | `LEN` data | write `LEN` registers from `ADDR`, incrementing | — |
| `0x2` | RD | none | read `LEN` registers from `ADDR`, incrementing | `LEN` words |
| `0x3` | WR_FIXED | `LEN` data | write `LEN` times to `ADDR` (FIFO data registers, `DIN`) | — |
| `0x4` | RD_FIXED | none | read `LEN` times from `ADDR` (FIFO data, `DOUT`) | `LEN` words |
| `0x5` | WR_MASK | 2: `MASK`, `DATA` | `reg = (reg & ~MASK) \| (DATA & MASK)` | — |
| `0x6` | WAIT | 3: `MASK`, `VALUE`, `TMO` | hold until `(reg[ADDR] & MASK) == VALUE` or `TMO` cycles (0 = no limit) | — (status `TIMEOUT` on time-out) |
| `0x7` | WAIT_EVT | 2: `EVT` (index of one of the IP's own event outputs), `TMO` | hold until that event fires or `TMO` | — |
| `0x8`–`0xE` | reserved | — | `BAD_CMD` | — |
| `0xF` | RSP | — | **response packet** (never sent to an IP; forwarded on rings) | — |

`LEN-1` must be 0 for NOP / WR_MASK / WAIT / WAIT_EVT. Reads have no data words; the header
is the whole packet (`tlast` on word 0).

### Response packet

Sent when the command is a read, has `RESP` set, or fails (a failed write without `RESP`
still answers, so errors are never silent on the stream side).

| Word | Bits | Field |
|---|---|---|
| 0 | [31:28] | `0xF` (RSP) |
| | [27:24] | `STATUS` |
| | [23:18] | `SRC`: ID of the responding IP |
| | [17:14] | `CMD` of the request |
| | [13:12] | reserved (0) |
| | [11:0] | `ADDR` of the request |
| 1…`LEN` | [31:0] | read data (RD / RD_FIXED only); **always the full `LEN` words**, 0 for words that failed |

**STATUS:** `0x0` OK, `0x1` BAD_ADDR (the regfile reports an unmapped address), `0x2`
NOT_OWNER, `0x3` TIMEOUT (WAIT), `0x4` BAD_CMD, `0x5` BAD_LEN (`tlast` before or after the
length the header gave), `0x6` BAD_DEST (returned by a ring controller, below), `0x7`
POWERED_OFF (the destination IP is in Q_STOPPED or powered off; answered by its ring node),
`0x8` NOT_ALLOWED (the packet's privilege / security is below what the IP requires).

---

## `claude_ctl2reg` behavior

1. **Same registers, same effects.** Every register access from port B behaves exactly as
   the same access from the bus: W1C, self-clearing command bits, FIFO pops, `DIN` pushes.
2. **Order:** packets are executed in arrival order, words in order. A packet's writes are
   performed as its words arrive (one per cycle when the bus leaves the regfile free).
3. **BAD_LEN:** a packet that ends early keeps the writes already done and answers
   BAD_LEN; a packet longer than its `LEN` has the extra words dropped up to `tlast`.
4. **WAIT / WAIT_EVT** stall the control stream at this IP (`s_ctl_tready` = 0) until the
   condition or the time-out: everything behind it waits. This is the sequencing primitive
   ("configure B only after A reports ready"). WAIT polls its register through port B every
   `WAIT_POLL` cycles (parameter, default 8), so it never blocks the bus.
5. **Throughput:** one register access per cycle when port A is idle; responses at one word
   per cycle.

### SYNC

- A packet with `SYNC` = 1 is accepted, then held (`s_ctl_tready` = 0) until the IP's **frame
  boundary** strobe, and its writes are then performed back to back.
- The frame boundary is defined per IP: the DSP shell's start of frame on `s_data_*` (SOF /
  after `tlast`), the PWM period end, the timer reload, the VGA vsync. An IP without one
  treats `SYNC` as "at once" and says so in its spec.
- Updates that must land together go in **one** packet (consecutive registers) or use the
  IP's double-buffered registers (coefficients, `IP_SPEC_stream.md` rule 4).
- With broadcast (`DEST` = `0x3F`) and `SYNC`, every block in a chain applies the update at
  its own frame boundary, so the **same frame** sees the new setting in every block, even
  though it reaches them at different times.

---

## `claude_regbus_arb`: the bus always wins

The arbiter sits on the regfile's flat access bus (`wr_en`, `wr_addr`, `wr_data`, `wr_strb`,
`rd_en`, `rd_addr` → `rd_data` valid the next cycle, as in the timer).

1. **Port A (bus) is never stalled.** The bridges answer in a fixed number of cycles and have
   no back-pressure, so port A goes straight through in every cycle it is active.
2. **Port B uses only cycles where port A has neither `wr_en` nor `rd_en`.** Otherwise it
   waits (back-pressure on `s_ctl_*`). `rd_data` is steered to whichever port issued the read
   the cycle before.
3. **Progress:** APB leaves at least one idle cycle per access (SETUP), so port B always
   progresses behind an APB bridge. Behind AHB / AXI4-Lite / Wishbone, port B progresses
   whenever the bus leaves the IP for one cycle; the IP spec states the worst case, and a
   CPU streaming continuously into one peripheral is the only way to starve it.
4. **`rd_peek`** (new regfile input, generated by the rdl step for every new IP): a read with
   `rd_peek` = 1 returns the value with **no side effect** (no FIFO pop, no read-to-clear).
   The arbiter sets it for non-owner port B reads (below); the side-band debug freeze uses
   the same input.
5. `CTL_PORT` = 0 removes the arbiter and `claude_ctl2reg`: the IP is exactly the regfile +
   bridge of today (the timer).

### Ownership

The `OWNER` register in the standard block (`0xFF0`, `IP_SPEC_sideband.md`):

| Bits | Field | Meaning |
|---|---|---|
| [1:0] | `OWNER` | 0 = SHARED (reset), 1 = BUS, 2 = STREAM, 3 = reserved (acts as SHARED) |
| [8] | `LOCK` | 1 = `OWNER` and `LOCK` cannot change until reset |
| [9] | `BUS_DENIED` | sticky W1C: a bus write was dropped because `OWNER` = STREAM |
| [31:16] | `DENY_CNT` | saturating count of dropped writes (both ports) |

Rules:

1. **IP registers** (`0x000`–`0xFBF`, including the streaming bus-mode block at `0xF80`): a write from the non-owning port is **dropped**. From
   port B it answers NOT_OWNER; from the bus the bus transfer still completes OKAY (bridges
   cannot error) and sets `BUS_DENIED`.
2. **Reads are always allowed** from both ports, so the CPU can watch a DMA-driven block.
   A read from the **non-owning** port is a **peek** (`rd_peek`): it never pops or clears
   anything.
3. **Standard block** (`0xFC0`–`0xFFF`): always writable from the bus (system control:
   interrupts, freeze, DMA enables), writable from port B unless `OWNER` = BUS.
4. **`OWNER` itself is written only from the bus**, never from port B. With `LOCK` set it
   cannot change at all until reset (for example a production setting that gives a DMA
   sequence exclusive control).
5. The watchdog and key store have no `CTL_PORT` (D11), so none of this exists in them.

---

## Topologies

Chosen per SoC in the YAML; `DEST` IDs are assigned by the generator (parameter `MY_ID`).

| Topology | Use | DEST check |
|---|---|---|
| Point-to-point | DMA channel ↔ one comms IP (back door) | off (`CHECK_DEST` = 0): every packet is for this IP |
| **Ring** | one control stream through a whole DSP chain | on |
| Through `claude_stream_switch` | run-time choice of controller | on |

### `claude_ctl_ring` (one per ring node, in front of `claude_ctl2reg`)

```
 controller ─► node 1 ─► node 2 ─► ... ─► node N ─┐
     ▲                                             │
     └──────────── responses and undelivered ◄─────┘
```

1. A **request** whose `DEST` = `MY_ID` is taken by this node; `DEST` = `0x3F` (broadcast) is
   taken **and** forwarded; any other request is forwarded.
2. **Responses** (`CMD` = RSP) are always forwarded.
3. The node inserts its own responses into the ring output **between packets** (never inside
   one), round-robin with forwarded traffic.
4. Forwarding is registered: **1 cycle per hop**.
5. **Broadcast** is for writes only: broadcast reads or `RESP` are not allowed (BAD_CMD
   from every node).
6. The ring returns to the controller. A request that comes back to it was taken by no
   node: the controller (DMA, sequencer, cmd2bus) reports **BAD_DEST** to its software.
7. **No deadlock:** a controller always accepts the response side (its response buffer holds
   at least its maximum outstanding responses, and it never issues more). WAIT stalls the
   ring by design (rule 4 above), and a WAIT without a time-out is the controller's
   responsibility.
8. **Powered-off or stopped nodes never stop the ring** (user 2026-11-27). `claude_ctl_ring`
   sits in the **always-on parent domain** of a power-gated IP (in its UPF, the ring node and
   its forwarding registers are outside the switched domain), and it sees the IP's Q-channel
   state. While the IP is in Q_STOPPED or powered off, the node keeps forwarding every packet
   for other nodes, and answers a request addressed to its IP with **POWERED_OFF** (reads with
   the full `LEN` words of 0), without passing it to `claude_ctl2reg`. A broadcast write is
   forwarded and not applied to the stopped IP. The IP's `qactive_o` is **not** raised by such
   a packet; waking the IP is the power manager's decision.

### Privilege and security of control packets (user 2026-11-27)

The control stream must not be a way around the bus firewalls.

1. **Every packet carries a protection attribute** in `tuser[2:0]` of the control stream
   (`UW` = 3), with the AxPROT encoding of `mem_prot` (`[0]` privileged, `[1]` non-secure,
   `[2]` instruction, always 0 here), constant over the packet.
2. **The controller's hardware sets it, never the packet payload:**
   - a DMA channel uses its channel protection setting (programmed by privileged / secure
     software through the DMA's own registers);
   - `claude_cmd2bus` uses its `MEM_PROT` CONFIG value, itself limited by `dbg_lock_i` and the
     lifecycle state;
   - `rv_tiny` as a sequencer uses its current privilege mode;
   - another DSP block uses a fixed value from the SoC YAML (`ctl_prot:`).
   A `claude_stream_switch` in the path passes `tuser` through, so each controller's attribute
   travels with its packets.
3. **Each IP with `CTL_PORT` has `CTL_SEC_REQ`** (parameter, and a matching read-only field in
   `STD_PARAMS`): 0 = any packet (default), 1 = privileged required, 2 = secure required,
   3 = privileged and secure. A packet below the requirement is not executed and answers
   **NOT_ALLOWED**; the IP's `OWNER.DENY_CNT` counts it.
4. Security IP (AES, SHA-256, key-store users, the lifecycle controller) is generated with
   `CTL_SEC_REQ` = 3 by default; the SoC YAML can only raise the requirement, never lower it.
5. The bus side is protected by the bus fabric's firewall (plan §10.1) on `PPROT` / `HPROT` /
   `AxPROT`; the regbus bridges themselves do not check protection.

---

## C helpers (`claude_ctl.h`)

For DMA descriptor builders, `rv_tiny` sequencer code and cmd2bus hosts (`c2b_ctl()`).
`IP/common/firmware/include/claude_ctl.h`, pure C99, header-only.

```c
/** @file claude_ctl.h  @brief Control-stream packet encoding (pure C99, header-only). */
#ifndef CLAUDE_CTL_H
#define CLAUDE_CTL_H

#include <stdint.h>

typedef enum {
    CTL_CMD_NOP = 0x0, CTL_CMD_WR = 0x1, CTL_CMD_RD = 0x2, CTL_CMD_WR_FIXED = 0x3,
    CTL_CMD_RD_FIXED = 0x4, CTL_CMD_WR_MASK = 0x5, CTL_CMD_WAIT = 0x6,
    CTL_CMD_WAIT_EVT = 0x7, CTL_CMD_RSP = 0xF
} ctl_cmd_t;

typedef enum {
    CTL_ST_OK = 0x0, CTL_ST_BAD_ADDR = 0x1, CTL_ST_NOT_OWNER = 0x2, CTL_ST_TIMEOUT = 0x3,
    CTL_ST_BAD_CMD = 0x4, CTL_ST_BAD_LEN = 0x5, CTL_ST_BAD_DEST = 0x6,
    CTL_ST_POWERED_OFF = 0x7, CTL_ST_NOT_ALLOWED = 0x8
} ctl_status_t;

#define CTL_DEST_BROADCAST 0x3Fu
#define CTL_SYNC           (1u << 27)
#define CTL_RESP           (1u << 26)

/** Request header: cmd, flags (CTL_SYNC | CTL_RESP), dest ID, byte address, data words (1..256). */
#define CTL_HDR(cmd, flags, dest, addr, words)                  \
    ((uint32_t)((((uint32_t)(cmd)   & 0xFu)  << 28) |           \
                ((uint32_t)(flags) & (CTL_SYNC | CTL_RESP)) |  \
                (((uint32_t)(dest)  & 0x3Fu) << 20) |           \
                (((uint32_t)(addr)  & 0xFFCu) << 8) |           \
                (((uint32_t)(words) - 1u) & 0xFFu)))

/* Response header fields. */
#define CTL_RSP_IS(h)      ((((uint32_t)(h)) >> 28) == CTL_CMD_RSP)
#define CTL_RSP_STATUS(h)  ((ctl_status_t)((((uint32_t)(h)) >> 24) & 0xFu))
#define CTL_RSP_SRC(h)     ((unsigned)((((uint32_t)(h)) >> 18) & 0x3Fu))
#define CTL_RSP_CMD(h)     ((ctl_cmd_t)((((uint32_t)(h)) >> 14) & 0xFu))
#define CTL_RSP_ADDR(h)    ((unsigned)(((uint32_t)(h)) & 0xFFFu))

/* Standard-block OWNER register (offset 0xFF0). */
#define CTL_OWNER_OFFSET     0xFF0u
#define CTL_OWNER_SHARED     0x0u
#define CTL_OWNER_BUS        0x1u
#define CTL_OWNER_STREAM     0x2u
#define CTL_OWNER_LOCK       (1u << 8)
#define CTL_OWNER_BUS_DENIED (1u << 9)
#define CTL_OWNER_DENY_CNT(v) ((unsigned)(((uint32_t)(v)) >> 16))

#endif /* CLAUDE_CTL_H */
```

Example, the SPI back-door sequence of plan §6.1 as DMA `CTL` descriptor payloads:

```c
static const uint32_t spi_start[] = {
    CTL_HDR(CTL_CMD_WR, 0, SPI0_CTL_ID, SPI_CS_OFFSET, 2), SPI_CS_0, 64u /* LEN */
};
static const uint32_t spi_stop[] = {
    CTL_HDR(CTL_CMD_WR, CTL_RESP, SPI0_CTL_ID, SPI_CS_OFFSET, 1), SPI_CS_NONE
};
```

---

## What every IP with `CTL_PORT` documents

1. Its frame boundary for `SYNC` (or "none: at once").
2. Its event outputs by index, for WAIT_EVT.
3. Registers whose behavior from port B differs from the bus (there should be none) and
   registers with read side effects (peeked by non-owners).
4. Port B worst-case progress behind its bus bridge.

---

## Verification

- **Formal `claude_ctl_fv`** (stream side, bound on `claude_ctl2reg` and `claude_ctl_ring`):
  packet framing (`LEN` vs `tlast`), exactly one response per read / `RESP` / failed
  command, responses never interleaved inside a packet, ring forwarding preserves order per
  destination, broadcast taken by every node.
- **`claude_regbus_arb` formal**: port A passes through unchanged in every cycle (proof that
  the bridges see exactly today's behavior); port B only in free cycles; `rd_data` steered to
  the right port; ownership drops exactly the writes the table says; non-owner reads always
  peek; `OWNER` never written from port B; `LOCK` holds until reset.
- **Shared dual-port register test template** (checklist §0.3), run on every `CTL_PORT` IP:
  every register through both ports with identical results; both ports at full rate at once
  (bus random at maximum rate, control stream back to back); every ownership × port × access
  case; read side effects with peek; SYNC landing exactly on the frame boundary; WAIT and
  WAIT_EVT with and without time-out; BAD_LEN / BAD_CMD / BAD_ADDR.
- **Power and security**: a ring with a node in Q_STOPPED / powered off keeps forwarding and
  that node answers POWERED_OFF (UPF-aware simulation); every `CTL_SEC_REQ` value × every
  protection attribute, including through a stream switch with two controllers of different
  privilege.
- **Ring bench**: N = 1, 2, 8 nodes; random destinations, broadcast, undelivered packets
  (BAD_DEST at the controller), responses from several nodes at once, WAIT stalling the ring.
- **BFMs**: control-stream driver / monitor (SV, VHDL, UVM agent), Python packet builder that
  shares its encoding with `claude_ctl.h` (C ↔ Python cross-check of the header bits).
- **SoC level**: the §6.1 SPI sequence as DMA descriptors with no CPU; a DSP chain
  retuned by broadcast + SYNC with the change landing on one frame in every block.

---

## Change log

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-11-27 | approved |
| 1.1 | 2026-11-27 | POWERED_OFF and NOT_ALLOWED status; ring nodes in the always-on domain; packet protection attribute in tuser, CTL_SEC_REQ |
