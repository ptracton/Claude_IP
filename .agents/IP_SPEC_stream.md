# Claude stream (`t*`) — v1.1 approved 2026-11-27

Spec version: **1.1** (see "Change log" at the end).

Location: `.agents/IP_SPEC_stream.md` (all interface specs live in `.agents/`; the RTL
headers of components built from it point here).

Status: specification only, Phase 0.1 of `.agents/IP_PLAN.md` (§3.3, decisions D2 and D9).
Nothing here is implemented yet.

The claude stream is the point-to-point data path between blocks that move samples
or bytes without going through a bus: DSP blocks, the NPU, crypto engines, the FPU stream
unit, the DMA's MM2S / S2MM channels, and the communication blocks' DMA back door. The
control stream (`IP_SPEC_ctl_stream.md`) is a claude stream with a fixed packet format on top.

It is a **subset of AMBA AXI4-Stream with the AXI4-Stream signal names** (D2), so Vivado
and Quartus AXI4-Stream IP and VIPs connect directly when the widths match.

---

## Signals

| Signal | Width | Direction (source → sink) | Present | Meaning |
|---|---|---|---|---|
| `tvalid` | 1 | → | always | the source has a beat |
| `tready` | 1 | ← | always (see `HAS_READY`) | the sink accepts; a **transfer** happens on a rising clock edge with `tvalid & tready` |
| `tdata` | `DW` | → | always | payload: one or more samples, or bytes |
| `tlast` | 1 | → | always (tie 0 if the stream has no frames) | last beat of a frame / packet |
| `tuser` | `UW` | → | `UW > 0` (default 2) | side information per beat, see "tuser bits" |
| `tid` | `IW` | → | `IW > 0` (default 0) | channel number for time-multiplexed multi-channel data |
| `tkeep` | `DW/8` | → | `HAS_KEEP = 1` (default 0) | valid bytes in a byte stream; only the `tlast` beat may be partial |

Not used from AXI4-Stream: `TSTRB`, `TDEST`, `TWAKEUP`. (The stream switch routes by
register, and the control stream carries its destination in the packet header.)

### Parameters (per stream interface; on a processing block, prefixed `S_` for the input and `M_` for the output, see "Streaming block structure")

| Parameter | Default | Meaning |
|---|---|---|
| `DW` | 16 | `tdata` width |
| `UW` | 2 | `tuser` width (0 = no `tuser` port) |
| `IW` | 0 | `tid` width (0 = no `tid` port) |
| `HAS_KEEP` | 0 | `tkeep` port present (byte streams) |
| `HAS_READY` | 1 | 0 = ready-less (fixed-rate) mode, see below |
| `REG_IN` / `REG_OUT` | 1 | 0 = combinational boundary, 1 = skid buffer (see "Boundary registering") |

Format parameters (`FRAC_W`, `SIGNED`, `CPLX`, `LANES`, `FMT`) are under "Number formats".

### Port naming

`<role>_<port>_t<signal>`, with role `s` for a stream **into** the block (sink side) and
`m` for a stream **out of** the block (source side):

```
s_data_tvalid, s_data_tready, s_data_tdata, s_data_tlast, s_data_tuser   // data in
m_data_tvalid, m_data_tready, m_data_tdata, m_data_tlast, m_data_tuser   // data out
s_ctl_tvalid ... / m_ctl_tvalid ...                                     // control stream in / responses out
s_tx_tvalid ... / m_rx_tvalid ...                                       // comms back door (TX in, RX out)
```

Every signal is an explicit port in SV and VHDL. SV `interface` and VHDL records are not
used at IP boundaries (the existing interface prohibition, `Claude_IP.md`).

### Streaming block structure: one stream in, one stream out (requirement, user 2026-11-26)

Every streaming processing block has **two separate stream interfaces**:

- **`s_data_*`**: the interface on which the block **receives** data from the previous
  block (the block is the sink).
- **`m_data_*`**: the interface on which the block **drives** its processed data to the
  next block (the block is the source).

A chain is then just the output of one block wired to the input of the next, with no glue
logic:

```
           ┌────────┐ m_data_*  s_data_* ┌────────┐ m_data_*  s_data_* ┌────────┐
 source ──►│  CIC   │───────────────────►│  FIR   │───────────────────►│  IIR   │──► ...
 s_data_*  └────────┘                    └────────┘                    └────────┘
```

Rules:

1. **Same names on every block.** The chain ports are always called `s_data_*` and
   `m_data_*`, with the same signal set, so the SoC and chain generators connect any block
   to any other block the same way.
2. **The two interfaces are independent.** Each has its own handshake. The block takes a
   beat on `s_data_*` when `s_data_tvalid & s_data_tready`, processes it, and offers the
   result on `m_data_*` when it is ready. Back-pressure on `m_data_tready` reaches the input
   only through the block's own `s_data_tready`, after its internal buffering. The latency
   between the two is documented (see "What every streaming block documents").
3. **Both interfaces are on the block's one clock.** A clock change between blocks is a
   separate `claude_fifo_stream` placed between them, never inside the chain ports.
4. **The input and output formats may differ.** For example a CIC widens its samples and a
   `mag_log` turns complex into real. The format parameters therefore exist once per
   interface, prefixed `S_` and `M_` (`S_W`, `S_FRAC_W`, `S_CPLX`, …, `M_W`, `M_FRAC_W`,
   `M_CPLX`, …, and likewise `S_DW` / `M_DW`, `S_UW` / `M_UW`, `S_IW` / `M_IW`). Each `M_*`
   parameter defaults to its `S_*` value for blocks that do not change the format. **The
   generator checks that block N's `M_*` format equals block N+1's `S_*` format.**
   Links may also be `fmt: auto` (the generator computes each block's lossless output
   width), capped with `max_w`, or marked `lossless: true`; quantizing at every block or
   letting precision grow and quantizing once at the end are both allowed
   (`IP_SPEC_fx.md`, "Precision through a chain").
5. **Bypass** (in the DSP shell) connects `s_data_*` to `m_data_*` straight through. It is
   allowed only when the two formats are the same, or the shell's spec says how it
   converts.
6. **Other stream ports are not part of the chain** and have their own names:
   - `s_ctl_*` / `m_ctl_*`: the control stream and its responses (`IP_SPEC_ctl_stream.md`);
   - a second data input that a block needs, for example the local oscillator of a mixer,
     the feedback of a PID, or the second operand of an FPU elementwise operation:
     `s_<name>_*` (for example `s_lo_*`, `s_fb_*`, `s_b_*`). These are fed by a separate
     connection (stream switch output, NCO, DMA). The chain itself stays one in, one out;
   - comms back-door ports `s_tx_*` / `m_rx_*` (plan §6.1).
7. **Pure sources and sinks at the ends of a chain** (PDM input, NCO, I2S output, DMA S2MM)
   have only the interface they need: `m_data_*` for a source, `s_data_*` for a sink.

The same rule applies to every processing block that streams, not only DSP: the NPU's
pre- and post-processing, AES / SHA in stream mode, the FPU stream unit and
`claude_stream_fmt`.

### Operated by the stream, configured by the bus (requirement, user 2026-11-26)

A streaming block is **operated** through its stream interfaces and **configured** through
its regular register bus interface:

1. **Every streaming block has a register-bus slave** (`claude_<proto>_if`, same as the
   timer), even when it is only ever used in a chain. All configuration lives in that
   register file: mode, enable, bypass, run-time format choices, coefficients and tables
   (through the register window or the coefficient memory port), decimation / interpolation
   ratios, frame length, interrupt enables, and status / statistics read-back.
2. **The data stream carries only data.** `s_data_*` / `m_data_*` beats are samples or
   bytes. No configuration is ever encoded in `tdata`, `tuser`, `tid` or `tlast`; `tuser`
   carries only per-beat data attributes (SOF, SAT, and data-format fields such as the
   block-floating-point exponent), and `tlast` only marks frames.
3. **Operation is driven by the stream.** Once configured and enabled, the block processes
   whatever arrives on `s_data_*` and drives `m_data_*`; no per-sample or per-frame bus
   access is needed. Flow control is the stream handshake, not a register poll.
4. **Configuration takes effect at a defined point.** Registers that change processing
   (coefficients, ratios, formats) are double-buffered and swap at the next frame boundary
   (`tlast`), or at once when idle, so the stream never sees a half-applied configuration.
   Each block's spec lists which registers are safe to change while running.
5. **Control stream (`s_ctl_*`), where present, is only another way to write the same
   registers.** It goes through `claude_ctl2reg` into the same register file, with the bus
   winning any conflict (`IP_SPEC_ctl_stream.md`). It does not add configuration that the
   bus cannot reach, and a block is fully usable with the control stream tied off. The
   control stream stays **optional** (user 2026-11-26), set by `CTL_PORT`.
6. **Bus operation mode (requirement, user 2026-11-26).** The CPU can also *operate* the
   block's math through the register bus, with no stream connected. This lets software use
   one block as an accelerator, and lets tests exercise a single block in isolation. See
   below.

### Bus operation mode (`BUS_PORT`)

Built into the common streaming shell (the DSP shell, and the same wrapper for NPU pre/post,
AES / SHA stream mode, the FPU stream unit and `claude_stream_fmt`), so every block gets it
the same way. Parameter `BUS_PORT` (default 1; 0 removes the logic).

```
            SRC_SEL                                  DST_SEL
 s_data_* ──►┐                                  ┌──► m_data_*
             ├──► kernel (block math) ──────────┤
 DIN reg ──►[in FIFO]┘                          └──►[out FIFO]──► DOUT reg
```

Registers: a **fixed bus-mode block at `0xF80`–`0xFBF`** of every streaming IP's 4 KiB window,
just below the standard block (`0xFC0`, `IP_SPEC_sideband.md`), so one driver
(`claude_busmode.h`) and one test template cover bus mode in every streaming IP
(user 2026-11-27). An IP with `BUS_PORT` = 0 reads 0 there and ignores writes; the IP's
own registers use `0x000`–`0xF7F`.

| Offset | Register | Meaning |
|---|---|---|
| `0xF80` | `BUS_CTRL` | `[0] SRC_SEL`: 0 = input from `s_data_*` (default), 1 = input from `DIN`; `[1] DST_SEL`: 0 = output to `m_data_*` (default), 1 = output to `DOUT`; `[2] FLUSH` (write 1: empty both bus FIFOs, self-clearing) |
| `0xF84` | `BUS_STAT` | in-FIFO free count, out-FIFO fill count, `DIN_OVF` and `DOUT_UNF` sticky flags (write 1 to clear) |
| `0xF88` | `DIN_CTL` | the `tlast` / `tuser` / `tid` (and `tkeep`) for the **next** `DIN` push; sticky until rewritten |
| `0xF8C` | `DOUT_CTL` | `tlast` / `tuser` / `tid` of the beat at the head of the out FIFO; read **before** `DOUT` |
| `0xF90` | `DOUT_THRESH` | out-FIFO level that raises `DOUT_AVAIL` |
| `0xFA0`–`0xFAC` | `DIN[0..3]` | write: pushes one input beat (`tdata`); for `S_DW` > 32 the beat is written as consecutive words `DIN[0]`, `DIN[1]`, …, and the write to the last word it needs pushes |
| `0xFB0`–`0xFBC` | `DOUT[0..3]` | read: pops one output beat; wide beats read `DOUT[0]`, `DOUT[1]`, …, and the read of the last word pops |

Beats up to 128 bits fit the four-word windows; wider beats are not supported in bus mode.

Rules:

1. **The bus never stalls.** The register bus has no back-pressure, so the two FIFOs
   (`BUS_FIFO_DEPTH`, default 4, at least the block's latency to keep full rate) absorb it.
   A `DIN` write into a full FIFO is dropped and sets `DIN_OVF`; a `DOUT` read of an empty
   FIFO returns 0 and sets `DOUT_UNF`. Software checks `BUS_STAT` (or waits for the IRQ).
2. **Same math, bit-exact.** The kernel does not know where its beats come from: a sample
   sequence pushed through `DIN` gives exactly the same output (data and `tuser` / `tlast`)
   as the same sequence on `s_data_*`. The golden model is the same one.
3. **Source and destination are independent**, so the mixes are useful: stream in, read
   results by bus (a tap for debug), or bus in, stream out (CPU-fed generator).
4. **Change `SRC_SEL` / `DST_SEL` only while idle** (block disabled, or after `FLUSH`). When
   `DST_SEL` = 1, `m_data_tvalid` stays 0; when `SRC_SEL` = 1, `s_data_tready` stays 0.
5. **Interrupts and events:** `DOUT_AVAIL` (out FIFO reached `DOUT_THRESH`) and `DIN_SPACE`
   (in FIFO has room) are IRQ sources and events, so a DMA in memory mode can feed `DIN` and
   drain `DOUT` without the CPU.
6. **Verification:** every streaming block's directed test and UVM env include a bus-mode
   test that runs the same vectors as the stream test through `DIN` / `DOUT` and compares
   against the golden model, plus overflow / underflow flag tests.

---

## Handshake rules (AXI4-Stream)

1. A **transfer** happens at a rising clock edge where `tvalid` and `tready` are both high.
2. **`tvalid` never waits for `tready`.** A source must not let `tvalid` depend on `tready`,
   combinationally or by waiting for it. (Otherwise two blocks can deadlock.)
3. Once `tvalid` is high, it stays high, and `tdata`, `tlast`, `tuser`, `tid` and `tkeep`
   stay stable, until the transfer happens.
4. `tready` may go high before, with or after `tvalid`, and may go low again without a
   transfer. It may depend combinationally on `tvalid` (allowed by AXI4-Stream). Each block
   documents whether it does.
5. **Reset:** while reset is active, `tvalid` is low. A source may raise `tvalid` from the
   first rising edge after reset is released. `tready` is don't-care during reset.
6. A stream is in **one clock domain**. Crossing to another clock always goes through
   `claude_fifo_stream` in async mode (plan §10.4).

### Ready-less mode (`HAS_READY = 0`)

For fixed-rate paths (for example 48 kHz audio on a 100 MHz clock) where back-pressure
costs area and adds combinational paths for no benefit:

- The `tready` port is still present, so wiring stays uniform. A ready-less **sink** drives
  it high, and a ready-less **source** ignores it.
- A ready-less sink must accept every beat. If it cannot (internal overflow), it drops the
  beat and sets a sticky `OVERRUN` status bit. It never stalls the source.
- Connections:

  | Source | Sink | Allowed |
  |---|---|---|
  | ready | ready | yes |
  | ready | ready-less | yes (the sink is always ready) |
  | ready-less | ready | only if the sink can never stall at the source's maximum rate; otherwise the SoC generator inserts a `claude_fifo_stream` with an overflow flag |
  | ready-less | ready-less | yes |

  The SoC generator checks every connection against this table.

### Boundary registering (`REG_IN`, `REG_OUT`)

- `REG_IN = 1`: a skid buffer (`claude_skid_buffer`, 2 entries) on the input. `s_*_tready`
  comes from a flop, and the input adds 1 cycle of latency. Throughput stays at one beat
  per clock.
- `REG_OUT = 1`: a skid buffer on the output. `m_*_tvalid` and the payload come from
  flops, `m_*_tready` goes only into a flop, and the output adds 1 cycle.
- `0` = combinational boundary (no added latency). Timing closure is then the integrator's
  problem.
- Default 1/1, so any two blocks can connect with no combinational path between them. A
  chain that needs the lowest possible delay sets 0 where timing allows.

---

## Frames: `tlast` and `tuser`

### `tlast`

- `tlast` marks the last beat of a **frame**. What a frame is belongs to the stream's
  producer: an FFT block (N samples), a packet (UART idle, SPI chip-select release, I2C
  STOP), an NPU tensor or row, a video line.
- **Every block keeps `tlast` aligned with its data.** A block with latency L outputs
  `tlast` on the output beat that corresponds to the input beat that carried it.
- **Rate changes:**
  - A **decimator by R** outputs `tlast` on the first output beat whose input window
    includes the input `tlast` beat. A frame that is not a multiple of R samples is allowed;
    the block documents what happens to the partial window (default: it is flushed).
  - An **interpolator by L** outputs `tlast` on the last of the L output beats made from
    the input `tlast` beat.
- A block that **forms frames** itself (for example the FFT input) takes a `FRAME_LEN`
  parameter or register and ignores, counts or checks incoming `tlast` as its spec says.
- Streams without frames tie `tlast` to 0.

### `tuser` bits

| Bit | Name | Meaning | Propagation |
|---|---|---|---|
| `[0]` | `SOF` | first beat of a frame (video: first pixel of a frame; other streams: optional) | aligned with the data, like `tlast` |
| `[1]` | `SAT` | this sample, or any sample it was computed from, was saturated, overflowed or invalid | **OR**ed through every block: a block sets it if its own result saturated, and keeps it set if any input sample that fed this output had it set |
| `[2 +: BFP_EW]` | `BFP_EXP` | only when `BFP` = 1: the frame's shared exponent, constant over the frame (`IP_SPEC_fx.md` R9) | set by the producer, used or applied by the consumer |
| above those | block-defined | defined by the producing block and documented in its spec | a block that does not use these bits passes them through aligned with the data, or drops them if its output `UW` is 2 |

`UW = 0` is allowed for streams that need neither. `SAT` is per beat. The sticky "a
saturation happened" status register in each DSP shell is separate.

### `tid` (multi-channel)

- Several channels share one stream in time-division order (for example 8 microphones).
  Each beat carries its channel number in `tid`.
- Blocks with per-channel state (filters, PID) index that state by `tid`.
- Output `tid` = the `tid` of the input beat the output came from.
- The channel order is not fixed by this spec. A block that needs a fixed order
  (round-robin 0..N-1) documents it and flags violations.

### `tkeep` (byte streams)

- Used where bytes are packed into wider beats, for example the communication blocks'
  back door (4 UART bytes per 32-bit beat) and DMA byte transfers.
- **Packed only:** every beat has all bytes valid, except the `tlast` beat, whose valid
  bytes are contiguous from byte lane 0 (`tkeep` = `0…01…1`). No holes, no null beats.
- Byte order: byte lane 0 is the earliest byte.

---

## Number formats (`tdata` contents, D9)

Each stream port declares its format by parameters. The format is fixed at elaboration:
**there is no format tag on the wire**. The SoC generator checks that both ends of every
connection declare the same format, and a mismatch is an elaboration error, not a run-time
surprise. Converting between formats is an explicit block (`claude_stream_fmt`, below).

| Parameter | Default | Meaning |
|---|---|---|
| `FMT` | `FIXED` | `FIXED` (two's complement or unsigned fixed point / integer), `FLOAT` (IEEE 754), `BYTES` (opaque bytes, uses `tkeep`) |
| `W` | 16 | width of one real sample (`FIXED`: any; `FLOAT`: set by `FLT`) |
| `FLT` | `fp32` | `FLOAT` only: `fp64`, `fp32`, `fp16`, `bf16`, `fp8_e4m3`, `fp8_e5m2` (`IP_SPEC_float_formats.md`); block-scaled MX / NVFP4 data is not a stream format |
| `FRAC_W` | 15 | fractional bits (`FIXED` only); **0 = plain integer** |
| `SIGNED` | 1 | `FIXED`: 1 = two's complement, 0 = unsigned |
| `CPLX` | 0 | 1 = complex sample = `{Q, I}`, I in the low half (2·`W` bits) |
| `LANES` | 1 | samples per beat; sample *k* (earliest = 0) is at `tdata[k·S +: S]`, S = sample width |
| `BFP` / `BFP_EW` | 0 / 8 | block floating point: one shared exponent per frame in `tuser[2 +: BFP_EW]`, constant over the frame; needs `UW` ≥ 2 + `BFP_EW` (`IP_SPEC_fx.md` R9) |

- **Default: real, signed, Q1.15** (`W = 16`, `FRAC_W = 15`, `DW = 16`).
- `DW` must equal `LANES · W · (CPLX ? 2 : 1)` for `FIXED` and `FLOAT`. For `BYTES`, `DW` is a
  multiple of 8.
- Value of a `FIXED` sample = integer value of its bits / 2^`FRAC_W`. Q*m.n* naming: *m* =
  `W − FRAC_W` integer bits including the sign, *n* = `FRAC_W`.
- `LANES > 1` is for throughput above one sample per clock (for example a wideband ADC).
  A block may support only `LANES = 1`, and must say so in its spec.
- `tid`, `tlast` and `tuser` belong to the whole beat. With `LANES > 1`, all lanes of a beat
  have the same channel and frame position.

### `claude_stream_fmt` (new common component)

A small converter block that changes `W`, `FRAC_W`, `SIGNED` or `LANES` with the shared
`claude_fx_conv` modes (`IP_SPEC_fx.md`: five rounding modes, wrap / saturate /
symmetric saturate), and sets `tuser[SAT]` when it saturates. Options (`IP_SPEC_fx.md`
R4, R8, R9): TPDF / RPDF dither and noise shaping at the final narrowing, offset-binary /
sign-magnitude codes at the chain edge, and applying a block-floating-point exponent. Float ↔ fixed conversion is
**not** done here; the FPU stream unit does that (plan §8.2).

---

## Reconfiguration, abort and power-down (user 2026-11-27)

- **Reconfigure** a running chain with `STD_CTRL.HALT_REQ` on the first block (it stops at a
  frame boundary, and the blocks behind it drain and go idle), change the settings, then clear
  `HALT_REQ`. Or use `SYNC` control packets / double-buffered registers for changes that must
  land on a frame boundary without stopping.
- **Abort** (`STD_CTRL.ABORT`) truncates the current frame; downstream blocks resynchronize on
  the next `SOF` and flag `STD_STAT.FRAME_ERR` (`IP_SPEC_sideband.md`). Streams that must
  survive aborts therefore carry `SOF` (`UW` ≥ 1).
- **Stopped or powered-off block** (Q_STOPPED): its `s_*_tready` is 0 (isolation clamp), so the
  chain upstream **stalls**; a ready-less (`HAS_READY` = 0) source feeding it loses data and must
  be stopped first. The power manager stops a chain from its source end (`HALT_REQ`, then
  Q-channel) and restarts it from the sink end.

## What every streaming block documents

In its spec, for each stream port:

1. The format parameters (above) and which values are supported.
2. **Latency:** cycles from a beat entering to the corresponding beat leaving, with
   `REG_IN` / `REG_OUT` = 0 and = 1.
3. **Throughput:** cycles per beat (1 = full rate), and the input-to-output rate ratio.
4. **Back-pressure:** when and why the block drops `s_*_tready`, and the maximum number of
   beats it can hold internally.
5. Whether `s_*_tready` depends combinationally on `s_*_tvalid` (rule 4).
6. `tlast`, `tuser` and `tid` behavior if it differs from the defaults above.

And once per block: the register map, plus which registers may be changed while the
stream is running and when each change takes effect ("Operated by the stream, configured
by the bus", rule 4).

Blocks never lose or duplicate data when back-pressured in `HAS_READY = 1` mode.

---

## Test vectors (shared by golden models, benches and the regression)

One text format, so a Python golden model can write the expected output and every
simulator (SV and VHDL benches) can read and compare it:

```
# claude stream vectors v1
# fields: tdata tlast tuser tid tkeep   (hex, no 0x; tuser/tid/tkeep only if present)
# FMT=FIXED W=16 FRAC_W=15 SIGNED=1 CPLX=0 LANES=1 DW=16 UW=2 IW=0 HAS_KEEP=0
7fff 0 1
c000 0 0
0123 1 2
```

- One beat per line. `#` starts a comment. The format header line is required and is
  checked against the bench's parameters.
- Comparisons are bit-exact on every field.

---

## Verification (once, in `IP/common/verification/stream/`)

- **Formal checker `claude_stream_fv`** (port-only, bindable to SV and VHDL ports in either
  role, like the existing protocol checkers): rules 2, 3 and 5; `tkeep` packed rule; and in
  ready-less mode, that a ready-less sink holds `tready` high.
- **BFM tasks** (SV, no `interface`; VHDL equivalents): a source that reads a vector file
  with random or fixed `tvalid` gaps, and a sink that writes or compares a vector file with
  random or fixed `tready` back-pressure.
- **UVM agent** (xsim) for the same.
- **Python** reader / writer for the vector format, used by every golden model.
- **First users:** `claude_skid_buffer`, `claude_fifo_stream` and `claude_stream_fmt`
  (Phase 0.2), each run under the checker with random back-pressure.

---

## Change log

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-11-27 | approved |
| 1.1 | 2026-11-27 | bus-mode block fixed at 0xF80; tuser BFP field; reconfiguration / abort / power-down rules |
