# Claude event interface (`evt_*`) — v1.1 approved 2026-11-27

Spec version: **1.1** (see "Change log" at the end).

Location: `.agents/IP_SPEC_event.md` (all interface specs live in `.agents/`; the RTL
headers of components built from it point here).

Status: specification only, Phase 0.1 of `.agents/IP_PLAN.md` (§2 event plane, §3.4).
Nothing here is implemented yet.

An **event** is a hardware "it happened now" / "go now" signal between blocks, with no CPU
and no bus in the path: a timer underflow starting an ADC conversion, a PWM period centre
starting a sample, a DMA finishing, a GPIO edge, a filter finishing a frame. Events are the
fastest and cheapest plane in the SoC (one wire, one cycle) and are what lets a control loop
such as PWM → ADC → PID → PWM run with no CPU in it.

---

## Events, interrupts and DMA requests are different things

| | Event (`evt_*`) | Interrupt (`irq_o`) | DMA request (`dma_*_req_o`) |
|---|---|---|---|
| Meaning | "this moment happened" | "software, look at me" | "I have data / room" |
| Shape | **one-cycle pulse** | level, held until cleared (W1C) | level, held until served |
| Counted? | each pulse is one event | no, a condition | per beat, with `ack` |
| Consumer | another IP, through the event router | IRQ controller → CPU | DMA |
| Lost if nobody is listening? | yes, by design | no | no |

An IP that has a natural "moment" may drive more than one of these (for example the timer:
an IRQ for software and an event for hardware). They are separate outputs with separate
enables. A level signal is never used as an event, and an event is never used as an IRQ.

---

## Signals and naming

| Port | Dir | Width | Meaning |
|---|---|---|---|
| `evt_<name>_o` | out | 1, or `[N-1:0]` for per-channel events | event produced by this IP |
| `evt_<name>_i` | in | 1, or `[N-1:0]` | event that makes this IP act |

- `<name>` says what happened (`evt_done_o`, `evt_period_o`, `evt_center_o`, `evt_pin_o`,
  `evt_frame_o`, `evt_err_o`) or what it starts (`evt_start_i`, `evt_step_i`, `evt_trig_i`,
  `evt_swap_i`).
- A vector is one independent event per bit (bit *k* = channel *k*); several bits may pulse
  in the same cycle.
- Ports are plain signals in SV and VHDL, no interfaces or records (`Claude_IP.md`).
- **Existing IP keeps its names.** The signed-off timer's `trigger_out` is an event in every
  sense of this spec; the SoC generator connects it under the alias `evt_trigger` and its
  RTL is not changed.

---

## Producer rules (`evt_*_o`)

1. **One cycle high = one event.** The output is high for exactly one clock cycle of the
   producer's clock per event. High on two consecutive cycles means two events.
2. **Registered.** `evt_*_o` comes straight from a flop in the producer's clock domain, with
   no logic after it, so it is glitch-free and safe to feed a crossing cell. (The timer's
   `trigger_out <= underflow & ctrl_trig_en` is the model.)
3. **Gated by an enable register.** Each event output (or each vector) has an enable bit in
   the producer's register map (`EVT_EN.<name>`, reset 0). Disabled means the output stays 0;
   it does not queue events.
4. **Low in reset**, and no event in the first cycle after reset is released.
5. **Debug freeze.** While `dbg_freeze_i` is high the producer's counters stop (sideband
   spec), so the events they would have produced do not happen. Events produced by things
   that do not freeze (a GPIO pin edge) still happen.
6. **Documented maximum rate**: the smallest number of producer cycles between two events,
   in the IP spec ("1" if it can pulse every cycle).

## Consumer rules (`evt_*_i`)

1. **Every cycle high is one event**, sampled on the consumer's clock. The input must
   already be in the consumer's clock domain (see "Clock domains").
2. **Gated by an enable register** (`EVT_EN.<name>`, reset 0). A disabled input ignores
   events completely (no action, no status).
3. **Same action as software.** An event input does exactly what the matching register bit
   does (for example `evt_start_i` = writing `CTRL.START`), so a block can be tested and
   used either way, and the event path adds no behaviour of its own.
4. **When the consumer is busy** and cannot act on the event, it follows one documented
   policy, chosen per input:
   - `PEND` (default): one pending flag. The event is remembered and acted on as soon as
     the block is free. Further events while one is already pending set `EVT_MISS`.
   - `DROP`: the event is ignored and `EVT_MISS` is set.
   - `RESTART`: the event aborts the current operation and starts a new one (for example a
     PWM sync input).
5. **`EVT_MISS`** is a sticky W1C status bit per event input, with an optional IRQ source,
   so a missed trigger in a real-time loop is never silent.
6. **Documented minimum spacing**: the smallest number of consumer cycles between two
   events that are all acted on.

---

## Clock domains

An event is synchronous to its producer's clock. Inside one clock domain it is a direct
wire (or a route through the event router). Between domains it goes through a crossing
cell, which is always placed by the SoC generator or the event router, never inside the
producer or consumer.

| Cell | Exists? | Guarantee | Use for |
|---|---|---|---|
| `claude_pulse_sync` | yes (signed off) | none for close events: two source pulses less than about `STAGES + 1` destination cycles apart flip its toggle twice and **both can be lost** | events known to be far apart (documented producer rate vs. destination clock) |
| **`claude_evt_sync`** [NEW, Phase 0.2] | no | **never loses an event**: a source event that arrives while one is still crossing is merged into it (at least one destination pulse per burst); an optional `merge_o` pulse / counter reports merges | the default for every event crossing |

`claude_evt_sync` (planned):

- Source side: a sticky `pending` flag set by `src_evt_i`, a 4-phase req/ack handshake
  across the boundary (two `claude_sync` instances), cleared when the ack returns.
- Destination side: one `dst_evt_o` pulse per completed handshake.
- An event that arrives while `pending` is set is merged; `src_merge_o` pulses (source
  domain) so the producer side can count or flag it.
- Latency: about `STAGES + 1` destination cycles. Minimum spacing without merging: about
  `2 × STAGES + 2` cycles of the slower clock. Both are measured and documented.
- Parameters: `STAGES` (default 2, ≥ 2). Reset: each side has its own synchronous reset
  (rule D8); reset both together.
- DFT: test-mode rule 6 (synchronizer flops scannable, no special handling).

The event router uses `claude_evt_sync` on every input whose clock differs from the
router's clock (set per input in the SoC YAML), so producers and consumers never deal with
crossings.

---

## The event router (interface view)

The router itself is a Phase 4 IP with its own spec; this section only fixes what the
interface needs from it.

- `N_IN` event inputs, `N_OUT` event outputs, all on the router clock (inputs from other
  domains through `claude_evt_sync`, outputs to other domains likewise).
- Per output: `SRC_SEL` register (one input, or "none"; reset "none"), so routes are
  configured by software at run time. Optionally an OR of several inputs (`SRC_MASK`).
- **Software trigger**: a `SW_TRIG` register that injects an event on any output, for tests
  and for software-started sequences.
- **Debug counters** (parameter): a per-input event count, so software can see whether a
  trigger is happening at all.
- Routing adds **1 cycle** of latency (registered output, producer rule 2) when producer
  and consumer share the router clock.
- Static connections that never change can skip the router and be wired directly in the
  SoC YAML (same rule as the stream chains, D6).

### Scope: events only, with two bridges (user 2026-11-27)

The router routes **events**. Interrupts keep their own path (IP → PLIC / CLINT → CPU) and
DMA requests keep theirs (IP `dma_*_req_o` / `ack_i` → DMA channel `REQ_SEL`), because an
interrupt must never be lost and a DMA request is a per-beat handshake. Two extensions
connect the planes without merging them:

**1. Level inputs (`N_LVL` inputs, parameter, default 0).** Any interrupt or DMA-request
line can also feed the router, so a level condition (for example "UART RX FIFO above its
watermark") can trigger hardware directly.

- The line is **tapped**, not taken over: the same wire still goes to the PLIC or the DMA
  unchanged, and the router input has no effect on it.
- Each level input passes through an edge detector in the router: one event on the rising
  edge (0 → 1), per input `LVL_EDGE` register: rising (default), falling or both.
- Inputs from another clock domain are first synchronized with `claude_sync` (it is a level,
  so a plain 2-flop synchronizer is correct), then edge-detected in the router clock. A
  level that goes high and low again faster than the synchronizer can see is not an event,
  which is documented.
- After the edge detector, a level input is an ordinary router input: it can be selected by
  any output's `SRC_SEL` / `SRC_MASK` and is counted by the debug counters.

**2. Router interrupt output (`irq_o`, parameter `IRQ_EN`, default 1).** Software can be
told about an event that the producing IP does not turn into an interrupt itself (for
example a filter's frame-done).

- Per router **output** *k*: a sticky `EVT_STATUS[k]` bit set whenever output *k* fires
  (from its route or from `SW_TRIG`), W1C, and an `EVT_IRQ_EN[k]` bit (reset 0).
- `irq_o = |(EVT_STATUS & EVT_IRQ_EN)`, a level, active high, following the standard
  side-band rules (§3.5): it goes to the PLIC like any other peripheral interrupt.
- An output that is routed only to raise an interrupt (no IP connected) is allowed and is
  the normal way to watch an event from software.
- An optional `EVT_OVF[k]` sticky bit is set when output *k* fires again while
  `EVT_STATUS[k]` is still set, so software can tell it missed events.

What the router never does: it does not replace the PLIC (no priorities, no claim /
complete), it does not drive any `dma_*_ack_i` or take part in the DMA handshake, and it
does not turn an event back into a level request for the DMA (a DMA channel that should
start on an event uses its own event-trigger input).

---

## Stopped or powered-off consumers and producers (user 2026-11-27)

- An event into an IP in Q_STOPPED or powered off is **lost** (the isolation clamp holds the
  IP's view at 0); it does not wake the IP. When the event must wake it, route it also to the
  power manager's wake inputs (the event router can drive them).
- An IP that is off produces no events (outputs clamped to 0). `claude_evt_sync` crossing from
  a domain that is powered off holds its state in the always-on side or is reset with the
  domain, as the SoC UPF says; it never produces a spurious event on power-up.

## DFT

Events are ordinary logic: registered outputs and gated inputs, scanned like any other
flops (§3.9). No event logic may drive a clock or an asynchronous reset (DFT rules 1–2), so
an event never starts an oscillator or resets a block directly; a "reset" event input is a
synchronous request into the IP's own reset logic. The crossing cells follow rule 6.

---

## What every IP with events documents

In its spec and README, for each event port:

1. Outputs: when exactly it pulses (which cycle relative to the internal state change), the
   enable bit, and the maximum rate.
2. Inputs: the action (and the register bit with the same action), the enable bit, the
   busy policy (`PEND` / `DROP` / `RESTART`), the minimum spacing, and the latency from the
   event to the action starting.
3. For vectors: what each bit means.

---

## Verification

- **Formal checker `claude_evt_fv`** (bound like `claude_mem_fv`): producer outputs are 0 in
  reset and are flop outputs (structural lint check); a disabled output never pulses; for
  `PEND` inputs, an event while idle always causes the action within the documented latency,
  and an event while pending always sets `EVT_MISS`.
- **`claude_evt_sync` formal**: every source event (or merged burst) gives exactly one
  destination pulse within the latency bound; no destination pulse without a source event;
  `src_merge_o` pulses exactly when an event is merged. Simulated across clock ratios 1:4
  to 4:1 with random phase.
- **BFMs**: an event driver (single, back-to-back, random spacing, while busy) and an event
  monitor / counter, in SV, VHDL and a UVM agent (`claude_evt_agent`), plus the Python
  helpers used by cocotb-style benches.
- **Every IP with events**, directed and UVM:
  - each output pulses exactly once per moment, and never while disabled;
  - each input gives the same result as its register bit;
  - the busy policy, including `EVT_MISS`;
  - back-to-back events at the documented maximum rate / minimum spacing.
- **Router extensions:** a tapped interrupt / DMA line still reaches the PLIC / DMA
  unchanged; each `LVL_EDGE` setting gives exactly one event per edge, across clock ratios;
  `EVT_STATUS` / `EVT_IRQ_EN` / `irq_o` / `EVT_OVF` behave as specified, including W1C and
  `SW_TRIG`.
- **SoC level** (§16): end-to-end event chains (for example timer → router → adc_seq) with
  latency measured against the budget, and the motor-control loop with no CPU in it.

---

## Change log

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-11-27 | approved |
| 1.1 | 2026-11-27 | stopped / powered-off consumers and producers |
