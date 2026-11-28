# Reset interface and reset controller (`reset_ctrl`, `claude_reset_sync`) — approved 2026-11-27

Spec version: **1.0**. Location: `.agents/IP_SPEC_reset.md` (all interface specs live in `.agents/`; the RTL
headers of components built from it point here).

Status: specification only, Phase 0.1 of `.agents/IP_PLAN.md` (§2 clock / reset / power
plane, §10.2, D8). Nothing here is implemented yet.

D8 fixes what a reset looks like **inside** an IP (synchronous, active low,
`claude_reset_sync` at domain boundaries). This spec fixes everything around it: which
resets exist, who may request them, how they are sequenced and recorded, and how domains in
reset coexist with domains that are running. Several specs already rely on it: the watchdog
reset, the RISC-V Debug Module's `ndmreset`, the JTAG `rst_hold` operation, Q-channel
power-up (`IP_SPEC_sideband.md`) and the TAP's own reset (`IP_SPEC_tap_tdr.md`).

---

## Reset kinds

| Kind | Source | Resets | Never resets |
|---|---|---|---|
| **POR** (power-on) | POR cell / pad, brown-out detector | everything, including the always-on domain, the TAP and `RST_CAUSE` (which then reads POR) | — |
| **Pin** | external reset pin (`rst_pin_n`) | the whole system except the always-on domain and the TAP | `RST_CAUSE`, TAP, lifecycle state |
| **System** | watchdog, software (`SYS_RST`), Debug Module `ndmreset`, JTAG `rst_hold` operation, CPU lockup | every domain in the system set (YAML), normally all but always-on and debug | TAP, Debug Module, `RST_CAUSE`, watchdog configuration lock |
| **Domain** | software (`DOM_RST`), power manager (power-up), JTAG `rst_hold` with a domain argument | one clock / power domain | anything outside it |
| **Hart** | Debug Module `hartreset`, software | one CPU core | its memories, peripherals |
| **TAP** | TRST* pin, POR, five TMS = 1 (`IP_SPEC_tap_tdr.md`) | TAP and TCK-domain front-end logic | anything in the system |
| **Soft** | `STD_CTRL.SOFT_RST` inside one IP (`IP_SPEC_sideband.md`) | that IP's core state | its registers, its bus interface |

The SoC YAML lists which domains belong to the "system" set and to each named domain.

---

## `claude_reset_sync` (Phase 0.2 component)

The only way a reset enters a clock domain.

| Parameter / port | Meaning |
|---|---|
| `STAGES` (default 2, ≥ 2) | synchronizer depth on deassertion |
| `clk_i` | destination clock |
| `rst_n_i` | reset request, any domain, may be asynchronous |
| `test_mode_i`, `scan_en_i` | DFT ports |
| `rst_n_o` | reset for the domain: **asserts asynchronously, deasserts synchronously** after `STAGES` edges of `clk_i`; driven from a flop |

- In test mode (`test_mode_i` = 1) `rst_n_o` follows `rst_n_i` directly (DFT rule 2), so the
  tester controls every reset from the reset pin.
- Inside the domain the IPs still sample it synchronously (D8). Therefore **the domain clock
  must run while reset is asserted**: the reset controller holds each domain reset for at least
  `RST_CYCLES` (default 16) cycles of that domain's clock after the clock is known to run.
- One `claude_reset_sync` per clock domain, instantiated by the SoC generator, never inside an
  IP (an IP with several clock domains gets one reset input per domain, `rst_<dom>_n_i`).

---

## Reset request interface

Every reset source drives a request into the reset controller (`reset_ctrl`, Phase 1):

| Port (controller side) | Meaning |
|---|---|
| `req_<src>_i` | level, active high, on the source's clock (the controller synchronizes it) |
| `hold_<src>_i` | level: keep the target domain(s) in reset as long as it is high (`ndmreset`, `rst_hold`) |
| `rst_<dom>_n_o` | one reset per domain, to that domain's `claude_reset_sync` |
| `rst_<dom>_active_o` | domain is in reset (for the power manager, the bus fences and status) |

Rules:

1. **Pulse sources are latched.** A one-cycle request (watchdog bite) is captured in the
   controller's always-on domain; the source does not need to hold it.
2. **Hold sources** keep the domain in reset until they drop; the release then follows the
   normal sequence.
3. A request from a domain that the request itself resets is safe: the latch is in the
   always-on domain, so the request is not lost when the source resets.
4. Every source has an **enable** in the controller (software can disable, for example, CPU
   lockup reset), except POR, pin and watchdog, which cannot be disabled.
5. The **watchdog** and the **lifecycle controller** are in a domain that only POR resets, so a
   watchdog reset cannot clear its own cause or lock.

## Sequencing

- **Assertion:** all target domains at once (default), or in a listed order with delays.
- **Release:** in the order given by the SoC YAML, each step waiting a programmable number of
  always-on cycles, by default: always-on → clock generation (PLL lock) → memories (sram
  wake / clear) → bus fabric → peripherals → CPUs. A CPU never leaves reset before the memory it
  boots from.
- **PLL lock / clock good:** a domain is released only when its clock source reports `locked`
  (or after a fixed delay for sources without lock).
- **Power-up of a switched domain** (`IP_SPEC_sideband.md`, power gating): the power manager
  requests a domain reset after supply-good and before removing isolation; the release is the
  domain's part of the sequence.

## Reset cause and registers (`reset_ctrl`, always-on)

| Register | Contents |
|---|---|
| `RST_CAUSE` | sticky bits, one per source (POR, BOR, PIN, WDT, SW, NDM, JTAG, LOCKUP, DOMAIN); W1C; only POR clears all and sets POR |
| `SYS_RST` | write the key `0x5A5A_0001` to request a system reset (other values ignored) |
| `DOM_RST` | per domain: write 1 to pulse its reset, `DOM_HOLD` per domain to hold it |
| `SRC_EN` | per-source enables (rule 4) |
| `SEQ_DLY[n]` | delay of each release step |
| `DOM_STAT` | per domain: in reset, clock good |

The register map follows the standard block rules (`claude_std_regs.rdl` at `0xFC0`).

---

## Domains in reset next to running domains (reset-domain crossing)

1. **Outputs of an IP in reset are at their reset values**, and every side-band output's reset
   value is its **inactive** value (`IP_SPEC_sideband.md`: `irq_o`, `evt_*_o`, `dma_*_req_o`,
   `m_*_tvalid` = 0), so a domain in reset never sends a false interrupt, event, request or
   stream beat.
2. **Bus access into a domain in reset** goes through the bus RDC / isolation fence (plan
   §10.1), which answers with an error instead of hanging, using `rst_<dom>_active_o`.
3. **Streams and control streams** into a domain in reset see `tready` = 0 (stall), exactly as
   for a stopped domain; ring nodes of the control stream are in the always-on parent
   (`IP_SPEC_ctl_stream.md`).
4. **Crossing cells** (`claude_evt_sync`, `claude_handshake_sync`, `claude_fifo_async`) whose two
   sides are in different reset domains reset each side with its own reset, and produce no
   spurious output when one side leaves reset (formally checked per cell).
5. SpyGlass RDC (csun.edu) runs on the SoC with the reset domains from the YAML.

## DFT

- Every internally generated reset (watchdog, software, lockup, `ndmreset`, `rst_hold`) is
  blocked in test mode; the tester drives resets through the pin, and `claude_reset_sync`
  passes it through (above).
- The reset controller's always-on state is scanned like other logic, except the `RST_CAUSE`
  capture flops, which are excluded from scan so a test-mode entry does not destroy the cause
  (documented exception class `DFT2`).

## Verification

- `claude_reset_sync`: asynchronous assertion at any time, deassertion after exactly `STAGES`
  edges, test-mode bypass; formal.
- `reset_ctrl`: every source × enable, pulse and hold sources, a request from a domain that
  it resets, sequencing order and delays, PLL-lock gating, `RST_CAUSE` across every reset kind
  (survives all but POR), the `SYS_RST` key.
- SoC level: watchdog bite during traffic, `ndmreset` from GDB, JTAG `rst_hold` of one domain
  while others run (fences answer errors, no spurious IRQ / event / stream beat), power-up
  sequence of a switched domain.

## Change log

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-11-27 | approved |
