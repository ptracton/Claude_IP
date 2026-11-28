# Standard peripheral side-band — v1.1 approved 2026-11-27

Spec version: **1.1** (see "Change log" at the end).

Location: `.agents/IP_SPEC_sideband.md` (all interface specs live in `.agents/`; the RTL
headers of components built from it point here).

Status: specification only, Phase 0.1 of `.agents/IP_PLAN.md` (§3.5). Nothing here is
implemented yet.

The side-band is the small set of non-bus, non-stream ports that **every new register IP**
has the same way, so the SoC generator can wire interrupts, debug halt, clock gating, DMA
requests and events without knowing anything about the IP. It also fixes a **standard
register block** so one C header and one test template cover these features in every IP.

Existing signed-off IP (timer, sram, bus_matrix) is not changed by this spec; it adopts
it in its planned retrofit revision (checklist "Retrofit track"), and until then the SoC
generator maps its existing ports (for example timer `irq`, `trigger_out`).

---

## Ports

| Port | Dir | Width | Present | Inactive tie-off | Section |
|---|---|---|---|---|---|
| `irq_o` | out | 1, or `IRQ_W` | always | — | Interrupts |
| `dbg_freeze_i` | in | 1 | always | 0 | Debug freeze |
| `idle_o` | out | 1 | always | — | Idle / clock gating |
| `dma_tx_req_o`, `dma_rx_req_o` | out | 1 (or per channel) | `HAS_DMA = 1` | — | DMA request / ack |
| `dma_tx_ack_i`, `dma_rx_ack_i` | in | 1 (or per channel) | `HAS_DMA = 1` | 0 | DMA request / ack |
| `evt_<name>_o` / `evt_<name>_i` | out / in | 1 or N | per IP | 0 | `IP_SPEC_event.md` |
| `s_ctl_*` / `m_ctl_*` | in / out | stream | `CTL_PORT = 1` | `s_ctl_tvalid = 0`, `m_ctl_tready = 1` | `IP_SPEC_ctl_stream.md` |
| comms back door `s_tx_*` / `m_rx_*` | in / out | stream | comms IP, `HAS_BD = 1` | `s_tx_tvalid = 0`, `m_rx_tready = 1` | plan §6.1 |
| `idle_<dom>_o`, `wake_<dom>_o` | out | 1 | per extra gateable clock domain | — | Several clock domains |
| `qreq_n_i` | in | 1 (per power domain) | `PWR_GATE = 1` | **1** (never request) | Power gating |
| `qaccept_n_o`, `qdeny_o`, `qactive_o` | out | 1 (per power domain) | `PWR_GATE = 1` | — | Power gating |
| `tick_<name>_i` | in | 1 | `TICK_SRC_<NAME>` = 1 | 0 | Tick inputs |
| `test_mode_i`, `scan_en_i` | in | 1 | always | 0 | DFT (§3.9, `Claude_IP.md`) |

General rules:

1. **Every side-band input is inactive at 0** (stream `tready` at 1, and the active-low
   Q-channel request `qreq_n_i` at 1), so a SoC that does not use a feature ties it off with
   constants and nothing else.
2. **All side-band signals are on the IP's bus clock** unless the IP spec says otherwise.
   Crossings are done outside the IP, by the SoC generator (`claude_sync` for levels,
   `claude_evt_sync` for events).
3. **Every side-band output is registered** (straight from a flop), so it is glitch-free
   and can cross a clock domain safely.
4. **Port order on every IP top** (SV and VHDL, all protocol variants): bus ports;
   IP-specific ports (pins, other clocks); `irq_o`, `dbg_freeze_i`, `idle_o` (and `idle_<dom>_o` / `wake_<dom>_o`); Q-channel; DMA
   request / ack; events; stream ports; and last the `// DFT` ports.
5. Parameters with the same names in every IP: `HAS_DMA`, `CTL_PORT`, `HAS_BD`, `IRQ_W`,
   `CLK_GATE_EN`, `PWR_GATE`, `RET_REGS`.
6. **Parameter checking** (user 2026-11-27, all specs): every parameter whose range a spec
   limits is checked at elaboration, the same way in both languages: SV
   `if (!(cond)) $error("<ip>: <PARAM> = %0d out of range ...")` in a `generate` block (or an
   elaboration-time `initial` for Icarus), VHDL `assert cond report "..." severity failure;`
   in the architecture. The message names the IP, the parameter and the allowed range; the
   lint step checks that each limited parameter has a check.

---

## Interrupts (`irq_o`)

1. **Level, active high**, held until software clears the cause. This is what the PLIC
   gateway expects (D4). New IP has **no pulse-mode interrupts**: a one-cycle "it happened"
   output is an event (`evt_*_o`), not an interrupt. (The timer's pulse `IRQ_MODE` stays as
   legacy.)
2. **Standard registers** (in the standard block below):
   - `IRQ_STATUS` (W1C): one sticky bit per cause, set by hardware, cleared by writing 1.
   - `IRQ_ENABLE` (RW, reset 0): one bit per cause.
   - `IRQ_SET` (WO): writing 1 sets the `IRQ_STATUS` bit, so software and tests can raise
     any interrupt without the hardware condition.
   - `irq_o = |(IRQ_STATUS & IRQ_ENABLE)`, registered.
3. **Set wins.** If hardware sets a cause in the same cycle software clears it, the bit
   stays set, so no interrupt is lost.
4. **Status is set even when disabled**, so software can poll with interrupts off.
5. **Causes that are themselves levels** (for example "RX FIFO above watermark") may be
   shown as a read-only `IRQ_STATUS` bit that follows the condition instead of being sticky;
   the IP spec says which bits are which. Writing 1 to such a bit does nothing.
6. **Latency:** `irq_o` rises one cycle after `IRQ_STATUS` is set, and falls one cycle after
   the clearing write. The IP spec gives the latency from its internal condition.
7. **Several outputs** (`IRQ_W > 1`, default 1): only for IP with independent agents that
   different harts or PLIC priorities serve (for example one per DMA channel). Each output
   bit is the OR of its own group of causes, documented in the IP spec.
8. Optional per-cause **overflow** bits (`IRQ_OVF`, W1C) are set when a cause fires again
   while still pending, as in the timer's `OVF`.

---

## Debug freeze (`dbg_freeze_i`)

Driven by the RISC-V Debug Module while a hart is halted (plan §9), through the SoC
generator (synchronized into the IP clock). Level: frozen while high.

1. **What freezes** (when the IP's `CTRL.DBG_FREEZE_EN` bit is 1; reset value **1**):
   - free-running counters, prescalers, timers and timeouts (timer, PWM counter, watchdog,
     I2C / SPI timeouts, DMA `WAIT` timeouts), so a breakpoint does not cause a timeout or a
     watchdog reset;
   - **read side effects**: a bus read of a register that normally pops or clears (an RX
     data FIFO, a read-to-clear status) returns the value without changing state, so a
     debugger view does not corrupt the IP. (While a hart is halted, bus reads come from the
     debugger.)
2. **What does not freeze**: data that is already moving on an external protocol finishes
   the current unit (UART character, SPI word, I2C byte) and then holds before starting the
   next one; streaming data paths are not stopped (they stall naturally by back-pressure
   when their source stops); register writes still work.
3. **Outputs that drive the outside world** go to a documented state on freeze. For safety
   IP (PWM driving a motor bridge) this is a register-selected safe state
   (`CTRL.FREEZE_ACTION`: hold / safe / continue). The IP spec says which, per output.
4. The watchdog always freezes while `DBG_FREEZE_EN = 1`, and its lock bit cannot clear
   `DBG_FREEZE_EN` once locked.
5. On release, everything resumes from exactly where it stopped, with no spurious event or
   interrupt caused by the freeze itself.

---

## Idle / clock gating (`idle_o`)

1. **Meaning:** "the IP needs no clock edges to make progress or to keep its promises". The
   power manager may gate the IP clock while `idle_o` is high.
2. **High only when all are true:** no operation in progress; no stream beat held or
   offered; no event pending (`PEND` policy); no DMA request asserted; no counter running;
   and no **enabled** input that must be sampled continuously (for example a UART RX that is
   enabled, a GPIO pin with its edge interrupt enabled), unless the IP has a documented
   wake path that does not need its clock.
3. **The power manager ungates first**: before any bus access, event, stream beat or
   control packet reaches a gated IP, the clock is ungated. This is the job of the bus
   clock-enable blocks and the power manager (plan §10.1, §10.3), not of the IP. An IP never
   relies on being clocked when `idle_o` is high.
4. Gating never loses state: registers, `IRQ_STATUS` and `irq_o` keep their values.
5. `idle_o` is a hint, never required: a SoC may ignore it, and a constant 0 is always
   correct (but the IP spec must justify it).
6. In test mode (`test_mode_i = 1`) `idle_o` is forced to 0 so ATPG never sees the clock
   gated by functional logic.

### Several clock domains in one IP (user 2026-11-27)

For IP with clocks that are **asynchronous to each other** (VGA bus + pixel clock, UART
with a separate baud clock, watchdog bus + LFO). For several gated branches of **one**
clock, see the next section.

1. **One idle output per gateable domain.** `idle_o` is the bus-clock domain; every other
   gateable domain has `idle_<dom>_o` (for example `idle_pix_o`), registered in its own
   clock, meaning "this domain needs no edges". The power manager may gate each domain on
   its own.
2. **Wake request from the side that sends work.** A gated domain cannot see work that
   arrives while its clock is stopped, so the domain that sends it raises
   `wake_<dom>_o`, registered in the **sending** domain's clock, while it has anything in
   flight toward `<dom>`: data in a crossing FIFO, a handshake in progress, an event
   pending. The power manager synchronizes both into its always-on clock, gates `<dom>`
   only while `idle_<dom>` = 1 and `wake_<dom>` = 0, and ungates as soon as `wake_<dom>`
   rises. Once clocked, the domain sees the work and drops its own idle output.
   There is no race: if wake rises just after idle was sampled, the power manager still
   ungates, and nothing was lost because the sender never needed the other clock to hand
   the work over (rule 3).
3. **Crossings tolerate a stopped far side.** No crossing drops, times out or overwrites
   data because the other clock is stopped: `claude_fifo_async` writes with the writer's
   clock only and the data waits; `claude_evt_sync` keeps its pending flag;
   `claude_handshake_sync` waits for the ack; `claude_pulse_sync` keeps its toggle and the
   receiver sees it when its clock resumes.
4. **Every domain is declared gateable or always-on.** Always-on domains (watchdog LFO,
   CLINT `mtime`, RTC-style counters) have no idle output and are never gated. The IP spec
   lists every domain with its idle and wake conditions, and the SoC YAML carries the same
   list so the generator wires the power manager.
5. Rules 4–6 above apply per domain: gating never loses state or resets anything, a
   constant 0 idle is always correct, all idle outputs are 0 in test mode.

| IP | Domains | Idle / wake |
|---|---|---|
| vga | bus, pixel | `idle_pix_o` while the timing generator is disabled; bus side raises `wake_pix_o` when software enables it |
| uart (separate baud clock) | bus, baud | `idle_baud_o` when TX is empty and RX is disabled; a TX FIFO write raises `wake_baud_o` |
| watchdog | bus, LFO (always-on) | only `idle_o` (bus); the LFO domain is never gated |

### Fine-grained gating inside one domain: only toggle the flops that need to (user 2026-11-27)

A power-saving approach **within** one clock domain: the IP's clock is split into
**branches** that are gated separately, so flops that have nothing to do get no clock edges.
All branches come from the same root clock, are synchronous to it, and are **not** separate
domains (no synchronizers between them, one STA clock with gating checks).

There are two levels, and an IP uses both:

**Level 1: flop-level gating by synthesis (default, no RTL cost).**

- RTL writes every register with an explicit enable (`if (en) q <= d;`, VHDL
  `if en = '1' then`), never a free-running "hold" mux written differently. Banks that share
  an enable are then turned into integrated clock gates by the tool.
- ASIC (Synopsys DC, csun.edu): `set_clock_gating_style` (latch-based ICG, minimum bank
  width 4, `-control_point before`, the test-enable pin tied to `scan_en_i | test_mode_i`)
  and `compile_ultra -gate_clock`; the report of gated / ungated flops goes in the synthesis
  results, and PrimePower (step 11) reports the saving.
- FPGA: the enables stay as flop clock enables (CE pins), which already stop the flops from
  toggling and cost nothing.
- Registers that update every cycle (pipelines in full-rate stream paths) are not worth
  gating and are left alone.

**Level 2: architectural branch gating in RTL (coarse, for whole sub-blocks).**

For a sub-block whose "nothing to do" is a block-level state the tool cannot infer: an FFT
butterfly bank between frames, idle NPU MAC rows, the unused half of a dual-channel PWM, the
coefficient update logic of a filter that is running.

1. **Only through `claude_clk_gate`** (the ICG in the technology-cell layer, §10.3). No
   other RTL may gate a clock (DFT rule 1). Each instance's test-enable input is
   `scan_en_i | test_mode_i`, so every branch clocks during scan shift and test.
2. **The enable comes from flops on an ungated branch** (the root clock or a branch that is
   on whenever the gated one may be needed). A branch never turns itself back on.
3. **The register file, the bus interface and the side-band logic stay on the ungated root
   branch**, so bus access, interrupts and wake logic always work.
4. **Functionally transparent.** Gating a branch off must have exactly the same result as
   leaving it clocked with all its flop enables at 0. Logic in a gated branch therefore
   never needs an edge while gated: the enable is raised at least one cycle before the
   branch's flops must capture, and data sent into a branch is held by the sender until the
   branch is on (or the branch is on whenever data can arrive).
5. **Parameter `CLK_GATE_EN`** (default 1). With 0, every `claude_clk_gate` in the IP is a
   pass-through and the branches run all the time. FPGA builds use 0 by default (FPGA
   global clock buffers are scarce and Level 1 clock enables already save most of the power);
   an FPGA build may set 1 for a few large branches, mapped by the tech layer to `BUFGCE`
   (Xilinx) / `ALTCLKCTRL` (Intel).
6. **Naming:** branch clocks are internal wires `clk_<branch>` with enables
   `cg_<branch>_en`, never ports. The IP spec lists each branch, what is on it, and when its
   enable is high.
7. **Constraints:** branches are generated clocks of the root in the SDC
   (`create_generated_clock -combinational`), with clock-gating setup / hold checks on every
   `claude_clk_gate` enable.

Relation to `idle_o`: branch gating is the IP saving power **while it is working**;
`idle_o` lets the power manager stop the whole domain **when it is not**. An IP whose
branches are all gated still drives `idle_o` by the rules above.

What every IP documents (added to the list below): its clock domains (gateable or
always-on, idle / wake conditions) and its gated branches (contents, enable condition,
expected saving).

---

## Power gating (user 2026-11-27)

Clock gating keeps the state; power gating loses it. So instead of the `idle_o` hint, a
power-gated IP has a **positive handshake**: the power manager asks, and the IP confirms it
has stopped safely (or refuses). The handshake is the **ARM AMBA Low Power Interface
Q-channel** (ARM IHI 0068), with ARM's signal names and active-low polarities, so standard
power controllers (PPU-style) and their VIPs connect directly (same reasoning as D2).

### Q-channel ports (`PWR_GATE = 1`, default 0)

One Q-channel per power-gateable domain of the IP (normally one; suffix `_<dom>` when an IP
has several, for example `qreq_n_mac_i`).

| Port | Dir | Meaning |
|---|---|---|
| `qreq_n_i` | in | low = the power manager requests quiescence |
| `qaccept_n_o` | out | low = the IP accepts: it is stopped and may lose clock and power |
| `qdeny_o` | out | high = the IP refuses the request (it cannot stop now) |
| `qactive_o` | out | high = the IP has work or wants to stay / become powered (wake hint) |

### Protocol (ARM Q-channel states)

| State | `qreq_n` | `qaccept_n` | `qdeny` | Meaning |
|---|---|---|---|---|
| Q_RUN | 1 | 1 | 0 | normal operation |
| Q_REQUEST | 0 | 1 | 0 | stop requested, IP is finishing |
| Q_STOPPED | 0 | 0 | 0 | stopped; clock and power may be removed |
| Q_EXIT | 1 | 0 | 0 | power / clock back, IP is resuming |
| Q_DENIED | 0 | 1 | 1 | IP refused |
| Q_CONTINUE | 1 | 1 | 1 | request withdrawn, IP returning to Q_RUN |

1. `qreq_n_i` changes only when the IP has answered: falls only in Q_RUN; rises only in
   Q_STOPPED or Q_DENIED. `qaccept_n_o` and `qdeny_o` change only in answer to `qreq_n_i`,
   and are never both active.
2. **Accept** (Q_REQUEST → Q_STOPPED) only when all are true: no operation in progress and
   none will start; no stream beat held or offered, and inputs not accepting (`tready` = 0);
   as a bus master, no outstanding transaction and no new request; DMA requests low; no
   event pending; the external protocol is at a safe point (no character / word in
   progress). New work arriving while stopped is impossible (rule 6).
3. **Deny** when stopping would break a promise the IP has made, as listed in its spec (for
   example a UART with RX enabled, a PWM driving outputs, a DMA channel mid-descriptor).
   A denying IP must deny within a bounded time (documented), never leave the request
   hanging.
4. **`qactive_o`** is high whenever the IP has or expects work (the inverse of the idle
   conditions), registered. Wake sources for an IP that is **already off** come from
   always-on logic outside it: the bus isolation fence (a pending access), the event router
   (an event routed to it), GPIO / pin wake, the PLIC.
5. **Reset:** the IP resets into **Q_STOPPED** (`qaccept_n_o` = 0, `qdeny_o` = 0); the power
   manager holds `qreq_n_i` low through reset and raises it to bring the IP to Q_RUN. A SoC
   with no power manager ties `qreq_n_i` = 1, and the IP goes Q_STOPPED → Q_EXIT → Q_RUN in
   the first cycles after reset.
6. **While Q_STOPPED** (even with power still on) the IP starts nothing; its bus slave is
   behind the isolation fence, which answers any access with an error (§10.1); event and
   stream inputs are ignored (`tready` = 0).
7. **Clock crossing:** `qreq_n_i` is synchronized into the IP clock with `claude_sync`, and
   the three outputs into the power manager's clock, by the SoC generator (rule 2 above);
   the four-phase protocol makes plain level synchronizers correct.
8. The power manager may also use the Q-channel just to stop the **clock** of the domain
   safely (Q_STOPPED with power on), for example before changing its frequency.

### Isolation, retention and the switch (UPF, not ports)

Following the sram (`IP/system/sram/design/upf/sram_power.upf`), the power intent of each
IP is a UPF file `<ip>_power.upf` plus per-PDK wrappers; the isolation enable, retention
save / restore and switch controls are **power-manager signals referenced from the UPF**,
not IP ports.

1. **Isolation:** every IP output is clamped, in the always-on parent, to its **inactive
   value**, the same values as the tie-off table: `irq_o`, `evt_*_o`, `dma_*_req_o`,
   `m_*_tvalid`, `s_*_tready` = 0; `idle_o` = 1; `qaccept_n_o` = 0, `qdeny_o` = 0,
   `qactive_o` = 0 (an off IP reads as Q_STOPPED); bus slave outputs = 0 (the fence answers
   instead); pins to the pad ring = the IP spec's safe value. The IP spec lists every clamp.
2. **Retention** (`RET_REGS`, default 0): 1 = the register file (configuration) is kept in
   retention flops (`set_retention`, save / restore from the power manager) and the
   datapath is not; after power-up the IP is in reset state except for the retained
   registers, and `STD_PARAMS` says which. 0 = nothing is kept; the driver restores the
   configuration after power-up (the C driver template has `save()` / `restore()`).
3. **Power-up order** (power manager): switch on → wait for supply good → reset the domain
   (reset controller) → restore retention → remove isolation → raise `qreq_n_i` (Q_EXIT →
   Q_RUN). Power-down is the reverse after Q_STOPPED: isolate → save → switch off.
4. **Internal power domains** (sub-blocks gated by the IP itself: sram banks, NPU MAC rows,
   FFT memories) keep the sram pattern: an internal power controller (like
   `sram_pwr_ctrl`), mode request / acknowledge on registers or ports, and the IP's own UPF.
   The sram's existing `pwr_mode_req_i` / `pwr_mode_ack_o` are not changed.

### FPGA and DFT

- FPGA builds have no power gating: the UPF is not used, and the Q-channel still works (the
  IP accepts or denies as specified; nothing is switched off), so the same software runs.
- Test mode (`test_mode_i` = 1): power on, isolation off, retention transparent; the
  Q-channel logic is ordinary scanned logic. Power-aware ATPG is SoC-level work, out of
  scope for the IP.

---

## Soft reset, halt and abort (user 2026-11-27)

One standard way to stop, reconfigure or recover any IP, in `STD_CTRL` / `STD_STAT`:

1. **`SOFT_RST`** (write 1, self-clearing): resets the IP's **core** state (counters, FIFOs,
   pipelines, stream state, pending events, DMA requests) to its reset values. Registers keep
   their configuration; status registers (`IRQ_STATUS`, `STD_STAT`, ...) are cleared.
   `STD_STAT.SOFT_RST_BUSY` is high until it has finished (a documented number of cycles).
   It never resets the bus interface, the standard block or `OWNER`, and it is a synchronous
   request inside the IP (DFT rule 2: gated by `test_mode_i`).
2. **`HALT_REQ`** (graceful stop): the IP finishes the current unit (stream frame, external
   protocol word, DMA descriptor), then stops accepting input (`tready` = 0), and sets
   `STD_STAT.HALTED`. Clearing `HALT_REQ` resumes from there. This is the normal way to
   reconfigure a running chain without breaking frames.
3. **`ABORT`** (write 1): stop **now**. A streaming block drops any partial frame it holds and
   stops output at a beat boundary; the frame it had partly sent is therefore **truncated** (no
   `tlast`). It then waits for the next frame start (`SOF`) on its input. `HALTED` is set.
4. **Truncated frames downstream:** a block that sees `SOF` while it is inside a frame (no
   `tlast` yet) treats it as a resynchronization: it drops its partial frame, starts the new
   one, and sets `STD_STAT.FRAME_ERR` (and an optional IRQ cause). Blocks that count frame
   length do the same for a frame that ends early or late.
5. `idle_o` is high while `HALTED` and nothing is pending, so a halted IP can be clock-gated.

## Register access errors (user 2026-11-27)

The shipped `claude_<proto>_if` bridges always answer OKAY and are signed off, so they are not
changed. New IP gets **error-capable bridge variants**:

- **`claude_<proto>_if_err`** (APB4, AHB-Lite, AXI4-Lite, Wishbone; SV and VHDL, new files,
  Phase 0.2): the same as `claude_<proto>_if` plus two regfile inputs, `wr_err` and `rd_err`
  (valid with the access), mapped to `PSLVERR`, `HRESP` (two-cycle ERROR response),
  `BRESP` / `RRESP` = SLVERR, and `ERR_O`.
- The **regfile generated for new IP** drives `wr_err` / `rd_err` for: an unmapped address, a
  write to a read-only register, a read of a write-only register, a write dropped by
  ownership (`OWNER` = STREAM), and a register the IP marks as forbidden in its current state.
- **`STD_CTRL.ERR_EN`** (reset 1) turns the bus error responses on; with 0 the IP answers OKAY
  (reads return 0) as the old bridges do, for software that probes the address map. Either
  way the access sets the sticky `STD_STAT.REG_ERR`.
- Control-stream accesses report the same cases as BAD_ADDR / NOT_OWNER (`IP_SPEC_ctl_stream.md`).
- Existing IP keeps `claude_<proto>_if` and silent OKAY until its retrofit revision.

## Tick (clock-enable) inputs (user 2026-11-27)

IP that counts time or bit periods (timer prescaler, UART baud, PWM, watchdog, debouncers,
I2C / SPI timing) can take a shared **tick** from `claude_clk_en_div` / `claude_clk_en_frac` /
`claude_clk_en_tick` (plan §10.3) instead of a private divider:

- Port **`tick_<name>_i`** (for example `tick_baud_i`, `tick_1us_i`): a one-cycle-high enable on
  the IP's own clock, at most one per cycle; inactive value 0. Ticks are not events: they are
  never routed through the event router and carry no count.
- **Parameter `TICK_SRC_<NAME>`**: 0 = use the IP's internal divider (default), 1 = use the
  tick input. With 1, the internal divider is not built.
- A tick from another clock domain is not allowed (generate it in the IP's domain); the SoC
  generator checks it.
- The tick is a clock **enable**, never a clock (DFT rule 1). `dbg_freeze_i` stops counting
  on ticks like any other counter.

## IP boundary timing (user 2026-11-27)

So that IPs close timing together in a SoC:

1. **Every output of an IP is driven from a flop** (bus responses of the bridges excepted:
   APB `PRDATA` / `PREADY` and the other bridges' read paths are documented combinational
   paths from the regfile flops). Any other combinational input → output path is listed in the
   IP spec with its logic depth.
2. **Default IP-level constraints** (SDC written by the synthesis step): input delay and output
   delay of **40 %** of the clock period on every port of the IP's clock, so a SoC can join two
   IPs with 20 % margin for wiring. An IP may tighten its own budget, never loosen it without a
   documented reason.
3. Stream boundaries follow `REG_IN` / `REG_OUT` (`IP_SPEC_stream.md`); with both at 1 every
   stream port is registered.

## DMA request / acknowledge (`dma_*_req_o`, `dma_*_ack_i`)

Used when the DMA reaches the peripheral **over the system bus**. Communication IP also has
the back door (plan §6.1), which uses stream handshakes instead.

1. **`dma_tx_req_o`** (level): the TX FIFO has room for at least one DMA unit;
   **`dma_rx_req_o`** (level): the RX FIFO has at least one DMA unit to read.
2. **DMA unit** = `DMA_CTRL.BURST` beats (1, 2, 4, 8; reset 1). The request means "a whole
   unit fits / is available", against `DMA_CTRL.TX_WM` / `RX_WM` watermarks.
3. **Handshake:** the DMA sees the request, does one unit of bus transfers to the
   peripheral's data register, then pulses `ack` for one cycle **after the last beat has
   completed on the bus**. The DMA re-samples the request no earlier than
   `REQ_HOLDOFF` cycles after the ack (DMA parameter, default 2, larger when the request
   crosses a clock domain).
4. **The peripheral updates its request within `REQ_HOLDOFF` cycles** of the ack (it already
   sees the bus transfers, so the request normally drops in the cycle after the last
   beat). This rule is what prevents a DMA from overrunning a FIFO by one extra unit.
5. **Enables:** `DMA_CTRL.TX_EN` / `RX_EN` (reset 0); disabled means the request is held 0.
6. `ack` is a pulse; an ack with no request outstanding is ignored and sets
   `DMA_STAT.ACK_ERR` (sticky), a protocol bug indicator.
7. Clock crossing (DMA in another domain): the SoC generator puts `claude_sync` on the
   request and `claude_evt_sync` on the ack, and sets `REQ_HOLDOFF` to cover both.

---

## Standard register block

Every new register IP places these at the **top of its 4 KiB window** (12-bit regbus
address), so the IP's own registers start at 0x000 and the standard block never moves. Streaming
IP also reserve `0xF80`–`0xFBF` for the bus-mode block (`IP_SPEC_stream.md`), so their
own registers end at `0xF7F`. A
register that an IP does not need reads 0 and ignores writes. One C header
(`claude_std_regs.h`) and one Python / UVM register model cover all IP.

| Offset | Register | Access | Contents |
|---|---|---|---|
| `0xFC0` | `STD_ID` | RO | IP type code (from the IP catalog) and instance options |
| `0xFC4` | `STD_VERSION` | RO | major / minor / patch of the IP |
| `0xFC8` | `STD_PARAMS` | RO | which side-band features exist (`HAS_DMA`, `CTL_PORT`, `HAS_BD`, `BUS_PORT`, `IRQ_W`, number of events, `CLK_GATE_EN`, `PWR_GATE`, `RET_REGS`) |
| `0xFCC` | `STD_CTRL` | RW | `[0] DBG_FREEZE_EN` (reset 1), `[2:1] FREEZE_ACTION` (where used), `[3] ERR_EN` (register error responses, reset 1), `[8] SOFT_RST` (write 1, self-clearing), `[9] HALT_REQ` (stop at the next frame boundary), `[10] ABORT` (write 1: stop now, drop partial frames) |
| `0xFD0` | `IRQ_STATUS` | W1C / RO | interrupt causes |
| `0xFD4` | `IRQ_ENABLE` | RW | interrupt enables |
| `0xFD8` | `IRQ_SET` | WO | software-set causes |
| `0xFDC` | `IRQ_OVF` | W1C | optional overflow per cause |
| `0xFE0` | `EVT_EN` | RW | event output and input enables (`IP_SPEC_event.md`) |
| `0xFE4` | `EVT_MISS` | W1C | missed event per input |
| `0xFE8` | `DMA_CTRL` | RW | `TX_EN`, `RX_EN`, `BURST`, `TX_WM`, `RX_WM` |
| `0xFEC` | `DMA_STAT` | RO / W1C | FIFO levels, `ACK_ERR` |
| `0xFF0` | `OWNER` | RW | control-stream ownership / lock (`IP_SPEC_ctl_stream.md`) |
| `0xFF4` | `STD_STAT` | RO / W1C | `[0] HALTED`, `[1] SOFT_RST_BUSY`, `[2] FRAME_ERR` (sticky W1C: a truncated or malformed frame was seen or produced), `[3] REG_ERR` (sticky W1C: an access to an unmapped / forbidden register) |
| `0xFF8`–`0xFFC` | reserved | — | read 0 |

`STD_ID` / `STD_VERSION` / `STD_PARAMS` let firmware and the SoC test discover what is at
each address. The register descriptions live in a shared SystemRDL include
(`claude_std_regs.rdl`) that every IP's `.rdl` pulls in at `0xFC0`, so the rdl step generates
them the same way everywhere.

---

## What every IP documents

1. Its interrupt causes (bit, sticky or level-following, latency) and `IRQ_W` grouping.
2. What freezes on `dbg_freeze_i`, the output states, and the registers with read side
   effects.
3. The `idle_o` conditions and any wake path; every clock domain (gateable or always-on,
   `idle_<dom>_o` / `wake_<dom>_o` conditions); every gated branch (contents, enable).
4. Power gating (if `PWR_GATE` = 1): power domains, accept and deny conditions with the
   bound on the answer time, `qactive_o` conditions, the clamp value of every output, what
   `RET_REGS` keeps, and the UPF files.
4. DMA: data registers, unit sizes supported, watermark meaning.
5. Events (per `IP_SPEC_event.md`).

---

## Verification

- **Shared side-band test template** (directed and UVM), run on every new IP:
  - `IRQ_STATUS` / `IRQ_ENABLE` / `IRQ_SET` / W1C, set-wins race, `irq_o` latency, per-cause
    overflow;
  - debug freeze: counters stop and resume exactly, read side effects suppressed, output
    states, no spurious interrupt or event on release;
  - `idle_o`: formal property "while `idle_o` = 1 and no input is active, no state changes
    on the next clock" (so gating is safe), and `idle_o` = 0 in test mode;
  - several domains: a power-manager BFM gates each gateable domain at random whenever
    its `idle_<dom>` = 1 and `wake_<dom>` = 0, while traffic crosses in every direction; no
    data, event or interrupt is lost and results equal the never-gated run;
  - branch gating: every directed and UVM test passes with `CLK_GATE_EN` = 0 and = 1 with
    identical outputs (cycle-exact on all ports); a formal sequential-equivalence check
    (VC Formal SEQ) of the two settings where it fits; an assertion that no gated-branch flop
    would have changed value while its branch was off;
  - power gating: a Q-channel power-manager BFM (request at random, including during
    traffic and back-to-back requests), accept only under the accept conditions, deny
    within the bound, reset into Q_STOPPED, tie-off `qreq_n_i` = 1 build; UPF-aware
    simulation (VCS NLP) with random power cycles under traffic, checking clamp values,
    corruption of non-retained state, retained values after restore, and that the fence
    errors accesses while off; VC LP static checks clean (as for the sram);
  - DMA: a DMA BFM serving `req` / `ack` with random `REQ_HOLDOFF` and clock ratios; the FIFO
    never overflows or underflows; `ACK_ERR`;
  - standard block: reset values, `STD_*` contents match the parameters, unused registers
    read 0;
  - tie-off build: every side-band input at its inactive value, the IP still passes its
    own functional tests.
- **Soft reset / halt / abort, error responses, ticks**: `SOFT_RST` resets exactly the core
  state; `HALT_REQ` stops on a frame boundary and resumes cleanly; `ABORT` truncates and the
  next block resynchronizes on `SOF` with `FRAME_ERR`; every error case of the
  `claude_<proto>_if_err` bridges, with `ERR_EN` = 1 and = 0; `TICK_SRC` = 0 and = 1 give the
  same timing for the same divider setting.
- **Formal checker `claude_sideband_fv`**: registered outputs, `irq_o` equation, set-wins,
  DMA request drops within `REQ_HOLDOFF` of an ack.
- **Formal checker `claude_qch_fv`**: the Q-channel state machine (legal transitions only,
  `qaccept_n` and `qdeny` never both active, outputs change only in answer to `qreq_n`),
  plus the IP-specific property "Q_STOPPED implies no activity", bound per IP.

---

## Change log

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-11-27 | approved |
| 1.1 | 2026-11-27 | soft reset / halt / abort and STD_STAT; error-capable bridges and ERR_EN; tick inputs; IP boundary timing; parameter checking |
