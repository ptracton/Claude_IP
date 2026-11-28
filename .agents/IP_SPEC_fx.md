# Fixed-point formats, rounding and saturation (`claude_fx`) — approved 2026-11-27

Spec version: **1.0** (see "Change log" at the end).

Location: `.agents/IP_SPEC_fx.md` (all interface specs live in `.agents/`; the RTL
headers of components built from it point here).

Status: specification only, Phase 0.1 of `.agents/IP_PLAN.md` (§3.10, D9). Nothing here is
implemented yet.

Every math IP (DSP blocks, PID, CORDIC, NCO, div / sqrt, mag_log, stats, the NPU) does its
arithmetic in integers and quantizes at defined points. This spec defines, **once and
exactly**, what a format is and what every rounding and saturation mode computes, so that
the RTL primitives (`claude_fx_*`, SV and VHDL), the Python package (`claude_fx.py`), the C
helpers (`claude_fx.h`) and the TFLite / PyTorch references all give **the same bits**.
Requirement D9: default Q1.15, other formats and plain integers supported, and an accurate
quantized Python golden model for every math IP.

Floating-point and block-scaled formats (fp32, fp16, bf16, FP8, FP4, MX, ...) are not covered
here: they are in `IP_SPEC_float_formats.md`, shared by the FPU, the NPU and the stream's
`FMT = FLOAT`.

---

## Formats

A fixed-point format is three numbers:

| Name | RTL parameter | Meaning |
|---|---|---|
| `W` | `W` (`*_W`) | total width in bits, 2–64 |
| `F` | `FRAC_W` (`*_FRAC_W`) | fractional bits, 0 ≤ `F` ≤ `W` + 16 (F > W is allowed for very small values); **0 = plain integer** |
| `S` | `SIGNED` | 1 = two's complement, 0 = unsigned |

- **Value** of a stored integer *q*: `q / 2^F` (*q* read as two's complement when `S` = 1).
- **Range:** signed `[-2^(W-1), 2^(W-1) - 1] / 2^F`; unsigned `[0, 2^W - 1] / 2^F`.
- **Names:** `Qm.n` for signed, with *m* = `W - F` integer bits **including** the sign and
  *n* = `F` (Q1.15 = 16 bits, range [-1, 1 - 2^-15]); `UQm.n` for unsigned. Integer formats
  are written `int16`, `uint8`, and so on (`F` = 0).
- **Default everywhere: Q1.15** (`W` = 16, `F` = 15, `S` = 1). This matches the stream
  spec's `W` / `FRAC_W` / `SIGNED` parameters (`IP_SPEC_stream.md`).
- Complex values are a pair of the same format (I in the low half, as in the stream spec);
  every rule here applies to I and Q independently.

### Named formats (requirement, user 2026-11-27)

Every math IP and every tool **must support** these formats (the 4-bit formats where the
block's spec says it handles 4-bit data, normally the NPU), under these names (case does
not matter; `intN` is accepted as an alias of `sintN`):

| Name | `W` | `F` | `S` | Range | Typical use |
|---|---|---|---|---|---|
| `uint4` | 4 | 0 | 0 | 0 … 15 | NPU 4-bit weights (asymmetric), packed two per byte |
| `sint4` | 4 | 0 | 1 | −8 … 7 | NPU 4-bit weights (symmetric, GPTQ / AWQ style), packed two per byte |
| `uint8` | 8 | 0 | 0 | 0 … 255 | bytes, pixels, NPU activations (asymmetric) |
| `sint8` | 8 | 0 | 1 | −128 … 127 | NPU weights / activations (TFLite, PyTorch int8) |
| `uint16` | 16 | 0 | 0 | 0 … 65 535 | counters, ADC codes |
| `sint16` | 16 | 0 | 1 | −32 768 … 32 767 | PCM audio as integers |
| `uint32` | 32 | 0 | 0 | 0 … 2^32 − 1 | addresses, wide counters |
| `sint32` | 32 | 0 | 1 | −2^31 … 2^31 − 1 | NPU accumulators / bias |
| `q1.15` | 16 | 15 | 1 | −1 … 1 − 2^−15 | **default** DSP sample / coefficient |
| `q1.31` | 32 | 31 | 1 | −1 … 1 − 2^−31 | high-precision samples, biquad state, TFLite multipliers |
| `q16.16` | 32 | 16 | 1 | −32 768 … 32 768 − 2^−16 | general-purpose real numbers (PID gains, control loops) |

(`Qm.n` counts the sign in *m*, so `q16.16` is 32 bits and `q1.31` is 32 bits.)

**4-bit packing** (`sint4`, `uint4`, user 2026-11-27): in memory and on byte streams, two
values per byte, **element 0 in bits [3:0]**, element 1 in [7:4] (the PyTorch / ml_dtypes
`int4` order); an odd count leaves the last high nibble 0. 4-bit weights are normally used
with a **group scale** (one scale and, for `uint4`, one zero point per group of `G` weights
along the reduction dimension, `G` = 32, 64 or 128); the scales are stored as a separate
array in the format the NPU spec gives (`fp16`, `bf16` or a fixed-point format).

**Integer operation modes that the NPU must match** (TFLite / PyTorch):

| Mode | Activations | Weights | Accumulator | Requantization |
|---|---|---|---|---|
| int8 | `sint8` (zero point) or `uint8` (PyTorch `quint8`) | `sint8` per-channel / per-tensor | `sint32` | TFLite `srdhm` + `rdbpot`, or PyTorch float scale + `FX_CONVERGENT` |
| **TFLite 16x8** | `sint16`, symmetric (zero point 0) | `sint8` symmetric | **`sint64`** (conv / fully connected; `sint32` is not enough), bias `sint64` | `srdhm` + `rdbpot` to `sint16`, `FX_SAT` |
| int4 weights | `sint8` / `uint8` | `sint4` / `uint4` + group scales | `sint32` | as int8, with the group scale applied before or after accumulation as the NPU spec says |

**Companded audio** (G.711 μ-law and A-law, 8 bits): **storage formats only**, never used for
arithmetic. A small stream converter block, `claude_g711` (μ-law / A-law ↔ `sint16` / `q1.15`,
exact per ITU-T G.711), converts at the edge of an audio chain; its golden model is the
G.711 reference tables.

The names are defined once and used everywhere:

- **RTL:** `claude_fx_pkg` (SV and VHDL) has integer constants per format,
  `FX_<NAME>_W`, `FX_<NAME>_F`, `FX_<NAME>_S` (for example `FX_Q1_15_W = 16`,
  `FX_SINT8_S = 1`), for use in parameter lists (integers, so mixed-language instances map
  one to one).
- **Python:** `Fmt.parse("q1.15")`, `Fmt.parse("uint8")`, and module constants `UINT4`,
  `SINT4`, `UINT8`, `SINT8`, ..., `Q1_15`, `Q1_31`, `Q16_16`.
- **C:** `FX_FMT_UINT4`, `FX_FMT_SINT4`, `FX_FMT_UINT8`, ..., `FX_FMT_Q16_16` initializers in `claude_fx.h`.
- **SoC YAML and the chain generator:** a stream port's format may be given by name
  (`fmt: q1.15`) or custom (`fmt: {w: 24, frac: 23, signed: 1}`).

### Custom formats and operations

Anything else is a **custom format**: any `W` from 2 to 64, any `F` from −16 to `W` + 16
(negative `F` = a scaled integer, value `q · 2^|F|`), signed or unsigned, for example
`q1.23` (24-bit audio), `q2.30` (biquad coefficients), `sint18` / `sint25` (DSP48 operands),
`uq0.8`, `q8.24`. Python also accepts the generic spelling `q<m>.<n>` / `uq<m>.<n>` /
`sint<w>` / `uint<w>` for any sizes.

- **Operands may have different formats.** `mul`, `add`, `sub` and `convert` take each
  operand's format separately (for example `sint16` × `q1.15`, or `uint8` activations ×
  `sint8` weights into a `sint32` accumulator); the exact result format follows the rules
  below, and only the final `convert` chooses the output format.
- **Product widths** (all exact): signed × signed and signed × unsigned products are signed
  `Wa + Wb` bits; unsigned × unsigned products are unsigned `Wa + Wb` bits.
- **Width limits**: RTL operands up to 64 bits and exact intermediates up to 128 bits;
  Python unbounded; C operands up to 32 bits with 64-bit intermediates (signed products in
  `int64_t`, `uint32 × uint32` through the unsigned 64-bit path, see the C helpers).
- Every block spec says which named and custom formats it supports; **all math IP support
  every named format at its ports unless the block's spec gives a reason it cannot** (for
  example an NCO phase accumulator is unsigned by nature).

## Exact arithmetic first, one quantization point

The rule that makes bit-exactness easy:

1. **Inside a block, arithmetic is exact** (full-width integers): a product of
   `(Wa, Fa)` × `(Wb, Fb)` is `(Wa + Wb, Fa + Fb)`; a sum of N terms needs
   `ceil(log2 N)` guard bits.
2. **Accumulators may wrap internally** (two's complement modular arithmetic). The result is
   still exact as long as the final value fits, so `ACC_W` = product width + guard bits
   with no per-step saturation. Blocks size `ACC_W` so their defaults cannot overflow.
3. **Quantization happens only at points the block's spec lists** (normally the output;
   recursive blocks such as IIR also at their state registers), and each one is one
   `convert` (below) with a stated rounding and saturation mode.
4. Different but exact implementations (direct vs. transposed FIR, 3- vs. 4-multiplier
   complex multiply, any `CYCLES_PER_SAMPLE`) therefore give identical bits, and the model
   does not need to know the micro-architecture.

---

## Precision through a chain: quantize at every block, or let it grow (user 2026-11-27)

Each link of a chain chooses. Every streaming block has separate input and output formats
(`S_*` / `M_*`, `IP_SPEC_stream.md`), so a block's output can be as wide as its exact
internal result, and the next block takes that width at its input. Nothing forces a
rounding between blocks.

| Pattern | How | When |
|---|---|---|
| Quantize at every block | every `M_*` = q1.15 (or the chain format) | smallest hardware; each block adds its rounding noise |
| Grow, quantize once at the end | every `M_*` = the block's lossless format; one `claude_stream_fmt` (or the last block's `M_*`) at the end | best accuracy; widest data paths |
| Wide carry (usual compromise) | links in a moderate wide format (`q1.23`, `q1.31`, `sint32`) with headroom, final quantization at the end | most of the accuracy, DSP-block-friendly widths |

Limits that apply whatever the choice:

1. **Recursive blocks quantize internally** (IIR state, PID integrator, NCO phase): without
   it the state would grow without bound. The state format is a parameter and a listed
   quantization point, even when the output is wide.
2. **Blocks that must grow internally do so** (CIC: full Hogenauer growth inside; FFT:
   log2 N bits, with full growth / per-stage scaling / block floating point as the spec's
   options). Their output may still be wide or narrow.
3. **Width costs hardware**: wider inputs mean wider multipliers (one Xilinx DSP48 is
   25 × 18 / 27 × 18; Intel DSP blocks 18 × 18 / 27 × 27), wider streams and FIFOs. RTL
   operands stop at 64 bits.

### Lossless output format of a block

Each math block defines its **lossless output format**: the narrowest format that holds
every exact output value for the given input format and parameters (`FRAC_W` = the internal
fractional bits, width from the worst-case magnitude, not just from bit counting). An
output `convert` to that format, or to anything at least as wide in both integer and
fractional bits, is **exact**: no rounding, never `sat_flag`.

- Worst case is computed from the **actual coefficients** when they are fixed at
  elaboration (FIR: input range × Σ|h|), and from the **coefficient format** when they are
  reloadable (taps × max |coefficient|), unless the SoC YAML declares a tighter bound
  (`coef_bound: 1.0`, "software guarantees Σ|h| ≤ 1"). A declared bound is checked at run
  time by the saturation flag (below).

### 1. Automatic link formats (`fmt: auto`)

Every math IP's Python model provides a growth function:

```python
def out_fmt(in_fmt: Fmt, params: dict) -> Fmt:
    """Lossless output format of this block for this input format and these parameters."""
```

In the SoC / chain YAML a link may say `fmt: auto`, and the generator propagates formats
from the chain input, block by block, calling each `out_fmt`:

```yaml
chain:
  input: {fmt: q1.15}
  blocks:
    - {name: cic0, ip: cic, params: {R: 64, N: 4}, out: {fmt: auto, max_w: 32}}
    - {name: fir0, ip: fir, params: {taps: 63, coef: fir0.coef}, out: {fmt: auto, max_w: 32}}
    - {name: iir0, ip: iir_biquad, params: {state: q2.30}, out: {fmt: q1.31}}
    - {name: out,  ip: stream_fmt, out: {fmt: q1.15, round: convergent, sat: sat}}
```

- `max_w` (optional) caps the width. When the lossless format is wider, the generator keeps
  **all integer bits** (so the cap never saturates) and drops fractional bits with the
  link's `round` mode (default `convergent`). If even the integer bits do not fit, it keeps
  the top `max_w` bits only when `cap: saturate` is given, and otherwise stops with an error.
- Every capped link is a **documented truncation point** in the generated chain report.
- The resolved formats are written into the generated top-level parameters, the chain
  documentation, the C `soc.h` (format of each link) and the chain model.
- Explicit formats (`fmt: q1.31`) and `auto` can be mixed freely in one chain.

### 2. Per-link precision report

The chain model (bit-exact blocks + float references, plan §3.10) runs the chain on a set
of stimuli and writes `chain_report.md` and `.csv` next to the generated SoC:

- Stimuli: the YAML `stimulus:` list, or the default set: full-scale sine at several
  frequencies, white noise at −3 dBFS and −40 dBFS, impulse, a step, and a sweep; plus any
  user vector files.
- Per link: format, **SQNR** (dB) against the float chain, worst error (LSB of that link),
  effective bits, **headroom** (peak |value| against the format range, in bits),
  saturation count, and whether the link is lossless, capped or quantized.
- **What-if sweep** (`--sweep link=fir0.out widths=16..32`): rerun with candidate widths at
  one or more links, so the cost in accuracy of narrowing a link is visible before choosing.
- The report is part of the SoC regression results.

### 3. Lossless links (`lossless: true`)

A link marked `lossless: true` must be exact:

- **Static check** (generator): the producing block's `M_*` format must be at least the
  block's lossless format in both integer and fractional bits; otherwise the generator
  stops with an error that names the link and the format it would need.
- **Run-time check** (simulation and, optionally, hardware): `claude_fx_conv` has an
  `inexact_o` output (1 when the dropped fractional bits were not all zero) next to
  `sat_o`. On a lossless link, a monitor asserts that the producing block never reports
  `inexact` or `SAT`; this catches a declared `coef_bound` that software violates. The
  Python `convert_ex()` returns the same `inexact` flag.

---

## `convert`: the one quantization operation

`convert(q, src = (W1, F1, S1), dst = (W2, F2, S2), ROUND, SAT) → (q2, sat_flag)`

Steps, in this order:

1. **Align**: `k = F1 - F2`. If `k ≤ 0`, shift left by `-k` (exact, no rounding). If `k > 0`,
   drop `k` fractional bits with the **rounding mode** (step 2).
2. **Round** (exact integer definitions, *v* = the source integer, `D = 2^k`, `H = 2^(k-1)`,
   `floor` = toward minus infinity, i.e. arithmetic shift right):

   | `ROUND` | Code | Name | Definition | Use |
   |---|---|---|---|---|
   | `FX_TRUNC` | 0 | truncate (floor) | `floor(v / D)` | cheapest; biased by −½ LSB |
   | `FX_ZERO` | 1 | toward zero | `v ≥ 0 ? floor(v / D) : -floor(-v / D)` | C integer division, sign-magnitude |
   | `FX_HALF_UP` | 2 | round half up | `floor((v + H) / D)` | common DSP rounding |
   | `FX_HALF_AWAY` | 3 | round half away from zero | `v ≥ 0 ? floor((v + H) / D) : floor((v + H - 1) / D)` | **TFLite** requantization, C `round()` |
   | `FX_CONVERGENT` | 4 | round half to even | `floor((v + H - 1 + bit_k(v)) / D)`, `bit_k(v)` = bit *k* of *v* (the result's LSB before rounding) | **default**; unbiased; **PyTorch**, NumPy `rint` |

3. **Saturate** the rounded value to the destination range (rounding can carry out, for
   example Q1.15 `0x7FFF` + ½ LSB, so saturation is always **after** rounding):

   | `SAT` | Code | Name | Out-of-range result |
   |---|---|---|---|
   | `FX_WRAP` | 0 | wrap | keep the low `W2` bits (modular); `sat_flag` = 1 if the value changed |
   | `FX_SAT` | 1 | saturate (**default**) | clamp to the destination min / max |
   | `FX_SAT_SYM` | 2 | symmetric saturate | clamp to ±max (signed min becomes `-max`, so negation never overflows) |

   Unsigned destination: negative values clamp to 0 (`FX_SAT`, `FX_SAT_SYM`) or wrap.
4. **`sat_flag`** = 1 when step 3 changed the value. It drives `tuser[SAT]` on streams
   (`IP_SPEC_stream.md`) and the blocks' saturation counters.

Signed ↔ unsigned and widening / narrowing are all the same `convert`; there is no other
conversion operation.

### Other primitive operations

| Operation | Definition |
|---|---|
| `mul(a, fa, b, fb)` | exact product, format `(Wa + Wb, Fa + Fb, Sa \| Sb)`; no rounding, no doubling. Q1.15 × Q1.15 = Q2.30, and −1 × −1 = +1 fits; it only saturates if a later `convert` narrows it |
| `add` / `sub` | exact, result one bit wider, operands first aligned to the larger `F` (left shift, exact) |
| `neg` / `abs` | exact, one bit wider (so `abs(min)` is representable) |
| `lzc` / `lsc` | leading-zero / leading-sign count, for normalization (mag_log, block floating point in the FFT) |
| `srdhm(a, b)` | **TFLite** `SaturatingRoundingDoublingHighMul` on int32: `(a·b + nudge) >> 31` with `nudge = a·b ≥ 0 ? 2^30 : 1 - 2^30`, and `a = b = -2^31` → `2^31 - 1`. Defined here so the NPU's `REQUANT_MODE = TFLITE` matches TFLite exactly (plan §8.1) |
| `rdbpot(x, e)` | **TFLite** `RoundingDivideByPOT`: `convert` with `FX_HALF_AWAY` by `e` bits, no saturation |

The PyTorch path (`REQUANT_MODE = TORCH`) uses plain `mul` + `convert(FX_CONVERGENT,
FX_SAT)` with the float-derived multiplier, as `torch.ao` quantized kernels do; the NPU spec
lists the exact per-layer recipe for both frameworks.

---

## RTL primitives (`IP/common/design/rtl/{verilog,vhdl}/`)

All combinational, with an optional output register (`PIPE` = 0 / 1), integer parameters
(so SV and VHDL instances map one to one in mixed-language builds), and **bit-identical SV
and VHDL**.

| Module | Parameters | Ports |
|---|---|---|
| `claude_fx_pkg` (SV package + VHDL package) | — | the `FX_*` constants above, width helper functions |
| `claude_fx_round` | `IN_W`, `SHIFT` (= k), `SIGNED`, `ROUND` | `d_i` → `q_o` (`IN_W - SHIFT + 1` bits) |
| `claude_fx_sat` | `IN_W`, `OUT_W`, `IN_SIGNED`, `OUT_SIGNED`, `SAT` | `d_i` → `q_o`, `sat_o` |
| **`claude_fx_conv`** | `IN_W`, `IN_F`, `IN_SIGNED`, `OUT_W`, `OUT_F`, `OUT_SIGNED`, `ROUND`, `SAT`, `PIPE` | `d_i` → `q_o`, `sat_o`, `inexact_o` (round + saturate: the workhorse) |
| `claude_fx_mul` | `A_W`, `B_W`, `A_SIGNED`, `B_SIGNED`, `PIPE` (0–3, for DSP48 / DSP block inference) | `a_i`, `b_i` → `p_o` (exact) |
| `claude_fx_lzc` | `W`, `MODE` (zeros / sign) | `d_i` → `cnt_o`, `all_o` |
| `claude_fx_srdhm` | — (int32) | `a_i`, `b_i` → `q_o` (TFLite) |

Rules: no `real` types or division operators in synthesizable code; rounding is the add-
then-shift form of the table (one adder + a shift); DFT rules apply (no special handling).

## Python package (`IP/common/verification/tools/claude_fx.py`)

- `Fmt(w, frac, signed)`, with `Fmt.parse("Q1.15")` / `"UQ0.8"` / `"int16"` and `str()`.
- `quantize(x_float, fmt, round=CONVERGENT, sat=SAT)` → ints (float to fixed, for test
  inputs and coefficients; uses exact rational arithmetic on the float's value, so it is
  itself exact), `to_float(q, fmt)`.
- `convert(q, src, dst, round, sat)` → `(q, sat_flag)`, `convert_ex(...)` → `(q, sat_flag, inexact)`, `mul`, `add`, `sub`, `neg`, `abs`,
  `lzc`, `srdhm`, `rdbpot`, all scalar and NumPy-vectorized.
- Integer semantics: Python `int` (unbounded) for scalars; NumPy `int64` arrays when every
  intermediate fits in 63 bits, NumPy `object` arrays otherwise. The choice is automatic
  and never changes a result.
- Constants and mode codes equal the RTL codes (`FX_CONVERGENT = 4`, ...), so vectors and
  logs show the same numbers.
- Helpers for golden models: `sqnr_db(q, fmt, ref_float)`, `max_err_lsb(...)`, `headroom_bits(...)`.
- Chain support: every math model provides `out_fmt(in_fmt, params)`; `claude_fx.chain` propagates
  `fmt: auto`, applies `max_w` caps, and produces the per-link precision report and sweeps.

## C helpers (`IP/common/firmware/include/claude_fx.h`)

For firmware that prepares coefficients or checks results on target. Pure C99, header-only,
`W` ≤ 32 (64-bit intermediates).

```c
/** @file claude_fx.h  @brief Fixed-point convert / round / saturate (pure C99, header-only). */
#ifndef CLAUDE_FX_H
#define CLAUDE_FX_H

#include <stdint.h>

typedef enum { FX_TRUNC = 0, FX_ZERO = 1, FX_HALF_UP = 2, FX_HALF_AWAY = 3, FX_CONVERGENT = 4 } fx_round_t;
typedef enum { FX_WRAP = 0, FX_SAT = 1, FX_SAT_SYM = 2 } fx_sat_t;

/** Format: width (2..32), fractional bits, signed (1) or unsigned (0). */
typedef struct { uint8_t w; int8_t frac; uint8_t is_signed; } fx_fmt_t;

/* Named formats (IP_SPEC_fx.md), as initializers for declarations:
 *     static const fx_fmt_t q15 = FX_FMT_Q1_15;
 * In expressions (function arguments), use fx_fmt(w, frac, is_signed). */
#define FX_FMT_UINT4   {  4u,  0, 0u }
#define FX_FMT_SINT4   {  4u,  0, 1u }
#define FX_FMT_UINT8   {  8u,  0, 0u }
#define FX_FMT_SINT8   {  8u,  0, 1u }
#define FX_FMT_UINT16  { 16u,  0, 0u }
#define FX_FMT_SINT16  { 16u,  0, 1u }
#define FX_FMT_UINT32  { 32u,  0, 0u }
#define FX_FMT_SINT32  { 32u,  0, 1u }
#define FX_FMT_Q1_15   { 16u, 15, 1u }
#define FX_FMT_Q1_31   { 32u, 31, 1u }
#define FX_FMT_Q16_16  { 32u, 16, 1u }
/** Any format (named or custom) as a value, for use in expressions. */
static inline fx_fmt_t fx_fmt(unsigned w, int frac, unsigned is_signed)
{
    fx_fmt_t f;
    f.w = (uint8_t)w;
    f.frac = (int8_t)frac;
    f.is_signed = (uint8_t)(is_signed != 0u);
    return f;
}

/** Exact product of two values of up to 32 bits, except uint32 x uint32 (use fx_mul_u64).
 *  Result format: w = wa + wb, frac = fa + fb, signed if either operand is signed. */
static inline int64_t fx_mul(int64_t a, int64_t b) { return a * b; }

/** Exact unsigned product, for uint32 x uint32 (up to 64 bits). */
static inline uint64_t fx_mul_u64(uint64_t a, uint64_t b) { return a * b; }

/** Floor division by 2^k for k >= 0, defined for negative v (no implementation-defined >>). */
static inline int64_t fx_floor_shr(int64_t v, unsigned k)
{
    int64_t d = (int64_t)1 << k;
    int64_t q = v / d;                    /* C99: truncates toward zero */
    return (v % d < 0) ? q - 1 : q;
}

/** Round v by dropping k >= 0 fractional bits, as defined in IP_SPEC_fx.md. */
static inline int64_t fx_round(int64_t v, unsigned k, fx_round_t mode)
{
    int64_t h;
    if (k == 0u) { return v; }
    h = (int64_t)1 << (k - 1u);
    switch (mode) {
    case FX_TRUNC:      return fx_floor_shr(v, k);
    case FX_ZERO:       return (v >= 0) ? fx_floor_shr(v, k) : -fx_floor_shr(-v, k);
    case FX_HALF_UP:    return fx_floor_shr(v + h, k);
    case FX_HALF_AWAY:  return (v >= 0) ? fx_floor_shr(v + h, k) : fx_floor_shr(v + h - 1, k);
    case FX_CONVERGENT: return fx_floor_shr(v + h - 1 + (fx_floor_shr(v, k) & 1), k);
    default:            return fx_floor_shr(v, k);
    }
}

/** Saturate or wrap v into fmt; sets *sat to 1 if the value changed (sat may be NULL). */
static inline int64_t fx_saturate(int64_t v, fx_fmt_t fmt, fx_sat_t mode, int *sat)
{
    int64_t max = fmt.is_signed ? (((int64_t)1 << (fmt.w - 1u)) - 1) : (((int64_t)1 << fmt.w) - 1);
    int64_t min = fmt.is_signed ? -((int64_t)1 << (fmt.w - 1u)) : 0;
    int64_t r = v;
    if (mode == FX_SAT_SYM && fmt.is_signed) { min = -max; }
    if (mode == FX_WRAP) {
        uint64_t m = (((uint64_t)1) << fmt.w) - 1u;
        uint64_t u = (uint64_t)v & m;
        r = (fmt.is_signed && (u >> (fmt.w - 1u))) ? (int64_t)(u | ~m) : (int64_t)u;
    } else if (v > max) {
        r = max;
    } else if (v < min) {
        r = min;
    }
    if (sat != 0) { *sat = (r != v); }
    return r;
}

/** convert(): align, round, saturate (IP_SPEC_fx.md). Source value must fit in 62 bits after alignment. */
static inline int64_t fx_convert(int64_t v, fx_fmt_t src, fx_fmt_t dst,
                                 fx_round_t rnd, fx_sat_t sat_mode, int *sat)
{
    int k = (int)src.frac - (int)dst.frac;
    int64_t a = (k <= 0) ? v * ((int64_t)1 << (unsigned)(-k)) : fx_round(v, (unsigned)k, rnd);
    return fx_saturate(a, dst, sat_mode, sat);
}

/** convert() for an unsigned 64-bit source (the uint32 x uint32 path). src.frac - dst.frac
 *  must be >= 0; the destination may be signed or unsigned, up to 32 bits. FX_ZERO equals
 *  FX_TRUNC and FX_HALF_AWAY equals FX_HALF_UP for a non-negative value. */
static inline int64_t fx_convert_u64(uint64_t v, fx_fmt_t src, fx_fmt_t dst,
                                     fx_round_t rnd, fx_sat_t sat_mode, int *sat)
{
    unsigned k = (unsigned)((int)src.frac - (int)dst.frac);
    uint64_t r = v;
    if (k > 0u && k < 64u) {
        uint64_t h = (uint64_t)1 << (k - 1u);
        uint64_t q = v >> k;
        uint64_t rem = v & ((((uint64_t)1) << k) - 1u);
        switch (rnd) {
        case FX_HALF_UP:
        case FX_HALF_AWAY:  r = q + (rem >= h ? 1u : 0u); break;
        case FX_CONVERGENT: r = q + ((rem > h || (rem == h && (q & 1u))) ? 1u : 0u); break;
        default:            r = q; break;
        }
    } else if (k >= 64u) {
        r = 0u;
    }
    if (r > (uint64_t)INT64_MAX) {   /* only possible with k == 0 and a huge value */
        if (sat != 0) { *sat = 1; }
        return fx_saturate(INT64_MAX, dst, (sat_mode == FX_WRAP) ? FX_SAT : sat_mode, 0);
    }
    return fx_saturate((int64_t)r, dst, sat_mode, sat);
}

#endif /* CLAUDE_FX_H */
```

---

## Numerical robustness, definitions, compatibility and tooling (user 2026-11-27)

### R1. Feedback loops saturate, never wrap

A wrapped overflow inside a feedback loop (IIR state, PID integrator, AGC gain, any
accumulator whose output is fed back) turns +full scale into −full scale and can make the
block oscillate at full scale. **Every quantization point inside a feedback loop uses
`FX_SAT` or `FX_SAT_SYM`.**

- Each block's Python model lists its quantization points with a `recursive` flag; the chain
  generator rejects `FX_WRAP` on a recursive point.
- The RTL checks it at elaboration (`$error` in SV, `assert ... severity failure` in VHDL)
  when a recursive point's `SAT` parameter is `FX_WRAP`.
- `FX_WRAP` stays legal at non-recursive points (for example an NCO phase accumulator, which
  is meant to wrap and is documented as not recursive in this sense).

### R2. Limit cycles in recursive filters

Rounding in a feedback path can leave an IIR "humming" at a few LSB forever after its input
stops (zero-input limit cycles), or stuck at a non-zero output (dead band).

- `iir_biquad` (and any recursive block) gets two parameters:
  - `STATE_ROUND`: the rounding mode of the state quantization (default `FX_CONVERGENT`;
    `FX_ZERO`, magnitude truncation, suppresses most zero-input limit cycles at the cost of
    a small bias);
  - `ERR_FB`: 0 = none (default), 1 = first-order **error feedback** (the quantization error
    of the state is fed back into the next sample, about one adder and one register per
    section), which removes most limit cycles and lowers the noise floor near DC.
- **Required test** for every recursive block: full-scale stimulus, then zero input; the
  output must reach exactly 0 within the documented number of samples, or the block's spec
  states the maximum limit-cycle amplitude (in LSB) and the regression checks it.

### R3. Coefficient design and quantization tool (`claude_fx.coef`)

Quantizing coefficients moves poles and zeros; a narrow-band IIR can become unstable.

- `quantize_fir(h, fmt, method)` and `quantize_sos(sos, fmt, method)` (`method`: round, or an
  optimized search that minimizes the response error), with these checks and outputs:
  - **stability**: the largest quantized pole radius, an error if `≥ 1 − margin` (default
    margin 2^−10);
  - **response error**: maximum passband / stopband deviation in dB against the float design,
    and a plot file;
  - **cascade ordering and scaling** (biquads): section order (poles nearest the unit circle
    last), and L∞ / L2 / L1 scaling between sections (chosen by option) so no section
    overflows;
  - **asymmetry check** (R5): an error when a coefficient needs `+1.0` (or the format's
    `+max + 1 LSB`) in a format that cannot hold it, with the suggested format.
- **One coefficient file format**, read by RTL (`$readmemh` in SV, a shared `textio` reader
  in VHDL), C (the tool also writes a `.h` array) and Python:

```
// claude coef v1
// fmt q2.30
// count 15
// sections 3            (biquads only: b0 b1 b2 a1 a2 per section, a0 = 1 implied)
3FFF_FFFF
...
```

  Values are two's complement hex at the format's width, one per line, `_` allowed.

### R4. Dither and noise shaping at the final narrowing (optional)

Rounding a wide audio chain down to 16 bits adds distortion correlated with the signal.
`claude_stream_fmt` gets optional:

- `DITHER`: 0 = none (default), 1 = RPDF, 2 = **TPDF** (±1 LSB of the output, the audio
  standard), added before rounding, from `claude_lfsr` with a seed register;
- `NOISE_SHAPE`: 0 = none (default), 1 = first-order, 2 = second-order error-feedback noise
  shaping (fixed coefficients from the block's spec), with per-channel state for `tid`
  streams (`N_CH` parameter).

The Python model uses the same LFSR, seed and order, so dithered output is still bit-exact.

### R5. Two's-complement asymmetry

`q1.15` holds −1.0 but not +1.0 (max is `1 − 2^−15`); negating the minimum overflows.

- A gain or coefficient of exactly 1.0 needs a format with two integer bits (`q2.14`,
  `q2.30`), or the documented approximation `1 − 2^−F`. Block specs say which, and the
  coefficient tool and register helpers (R12) refuse a value that does not fit instead of
  silently clamping it (`clip=True` to allow clamping explicitly).
- `FX_SAT_SYM` is the mode to use where a value will later be negated.

### R6. Division and square root

Defined exactly, as `convert` of the exact mathematical result:

- **Quotient** `a / b` (any formats): the exact rational quotient, rounded to the output
  format with `ROUND` and saturated with `SAT`. With `FX_ZERO` and integer formats this is
  C / RISC-V integer division.
- **Remainder** (integer formats): `r = a − q·b` for the `q` above; with `FX_ZERO` it has the
  sign of the dividend (C, RISC-V).
- **Divide by zero**, parameter `DZ_MODE`:
  - `SAT` (default): quotient = destination max if `a ≥ 0`, min if `a < 0`; remainder = `a`;
    sticky `DZ` flag;
  - `RISCV`: quotient = all ones (−1 signed, max unsigned), remainder = `a`, as the RISC-V M
    extension; used when the divider backs CPU instructions.
- **Overflow** (`min / −1` for signed): `SAT` gives max with the `SAT` flag; `RISCV` gives `min`
  and remainder 0.
- **Square root** of a non-negative value: the exact square root rounded with `ROUND`
  (decided exactly by comparing squares, never by floating point); a negative input gives 0
  and a sticky `NEG` flag.

### R7. Transcendental and approximated functions

CORDIC, log2 / dB, sin / cos tables, NCO, reciprocal, activation LUTs cannot be bit-exact to a
math library. Rule:

1. The golden model is **bit-exact to the algorithm**: same iteration count, same table
   contents (generated by one Python script that also writes the RTL table file), same
   rounding at every step.
2. The model is **separately bounded** against the exact function (Python `mpmath` /
   NumPy float64): maximum error in LSB (or ULP) over the full input range, checked
   exhaustively for inputs up to 16 bits and by dense sampling above. The block spec states
   the bound; the regression enforces it.
3. Spectral blocks (NCO / DDS) also state their SFDR and phase-noise figures (R14 metrics).

### R8. Offset binary and sign-magnitude codes

Many ADCs and DACs use **offset binary** (two's complement with the MSB inverted), some use
sign-magnitude. `claude_stream_fmt` gets `IN_CODE` / `OUT_CODE`: `TWOS` (default), `OFFSET`,
`SIGNMAG` (negative zero reads as 0), so conversion happens once at the chain edge. Python
and C have the same helpers (`from_offset`, `to_signmag`, ...).

### R9. Block floating point on a stream (optional)

A block-floating-point frame is a set of mantissas in a fixed-point format plus **one shared
exponent** `e` per frame: value = mantissa × 2^e. Used by the FFT (output scaling) and
available to any block.

- Stream format flag `BFP` = 1 with exponent width `BFP_EW` (default 8, signed).
- The exponent travels in **`tuser[2 +: BFP_EW]`**, above the SOF / SAT bits, and is
  **constant for every beat of the frame** (so a consumer may read it on any beat, and the
  `tlast` / SOF framing defines the frame).
- The generator checks `BFP` / `BFP_EW` on both ends of a link; `claude_stream_fmt` can apply
  the exponent (convert BFP to a plain fixed-point format with `ROUND` / `SAT`).

### R10. CMSIS-DSP compatibility (Cortex-M33 firmware)

Firmware on the ARM target will often use CMSIS-DSP's `q15` / `q31` functions, whose
rounding is not uniform. For each math block whose operation has a CMSIS-DSP counterpart, the
block spec gives a **CMSIS-compatible parameter set** and states what it matches, for
example:

| CMSIS-DSP function | Behavior to match | `claude_fx` setting |
|---|---|---|
| `arm_mult_q15` / `arm_mult_q31` | product shifted down, truncated, saturated | `FX_TRUNC`, `FX_SAT` |
| `arm_fir_q15` | wide accumulator, final shift truncated, saturated | `FX_TRUNC`, `FX_SAT` at the output |
| `arm_biquad_cascade_df1_q15` / `_q31` | `postShift`, truncation of the state | `STATE_ROUND = FX_TRUNC`, the matching coefficient format |
| `*_fast_*` variants | drop LSBs in 32-bit intermediates | **not matched** (documented) |

- The exact behavior of each function is taken from the CMSIS-DSP sources, not assumed:
  `claude_fx.cmsis` reimplements the used functions, and is checked against CMSIS-DSP built
  for the host (and on the Cortex-M33 target) on the same vectors.
- The firmware examples then show the hardware block and the CMSIS-DSP call giving identical
  results.

### R11. ETSI / ITU basic operations (deferred)

Speech codecs (G.729, AMR) are specified with the ETSI / ITU-T basic operators (saturating
16- / 32-bit `add`, `L_mult` with doubling, `L_mac`, `round`, `norm_s`, `shr_r`, ...).
A `claude_fx.etsi` module, bit-exact with the ITU-T Software Tool Library (G.191 `basicop`),
is **reserved and deferred** until a speech codec is on the roadmap. Nothing else depends on
it.

### R12. Fixed-point register fields

A register field that holds a number carries its format in SystemRDL, with a user-defined
property shared by all IP (in `claude_std_regs.rdl`):

```systemrdl
property fx_fmt  { type = string; component = field; };   // e.g. "q16.16", "uint8"
property flt_fmt { type = string; component = field; };   // e.g. "fp16" (IP_SPEC_float_formats.md)
```

The rdl step then generates, per such field:

- C: `<IP>_<REG>_<FIELD>_FROM_DOUBLE(x)` / `_TO_DOUBLE(v)` macros or inline functions built on
  `claude_fx.h` (`FX_CONVERGENT`, saturating; refuses out-of-range values when `clip` is not
  allowed, R5), plus the format's range as constants;
- Python: the same conversions in the generated register model;
- documentation: the format and the real-value range in the register table.

Drivers never scale values by hand.

### R13. RTL coding rules for math IP (for the rtl / lint agents)

1. **All narrowing goes through `claude_fx_conv`** (or `_round` / `_sat`); no implicit
   truncation by assignment, no hand-written rounding.
2. **Width warnings are errors in math IP:** Verilator `WIDTHTRUNC`, `WIDTHEXPAND`,
   `WIDTHCONCAT` and the corresponding SpyGlass width rules are errors (not warnings) for
   `IP/DSP/**` and any IP using `claude_fx_*`, waivable only with a reason.
3. **Verilog signedness:** one unsigned operand makes the whole expression unsigned, so
   signed data paths declare every operand `signed` and cast with `$signed()` explicitly;
   `>>>` only on signed values; sized constants (`16'sd5`), never bare integers, in
   arithmetic.
4. **VHDL:** `resize` on `signed` drops MSBs **without saturating**, so it is used only for
   widening; narrowing goes through `claude_fx_conv`. No `integer` in data paths wider than
   31 bits.
5. Reviews check these rules; lint enforces 2.

### R14. Standard metric definitions (`claude_fx.metrics`)

Every report uses these, implemented once:

| Metric | Definition |
|---|---|
| **SQNR** (dB) | `10·log10(Σ ref² / Σ (y − ref)²)`, `ref` = the float model's output time-aligned with `y` (the quantized output as real values), over a window that starts after the block's documented settling time |
| **SINAD** (dB) | sine input at a coherent frequency (integer number of cycles in the window; otherwise a 4-term Blackman-Harris window): signal power (the signal bin and its leakage bins) over the power of everything else except DC |
| **ENOB** (bits) | `(SINAD − 1.76) / 6.02` |
| **THD+N** (dB) | noise + distortion power over signal power (= −SINAD) |
| **THD** (dB) | power of harmonics 2–10 over signal power |
| **SFDR** (dBc) | signal power over the largest spur |
| **Max error** | `max |y − ref|` in LSB of the output format |

The window length, input level and frequency are reported with every figure.

---

## Every math IP documents

1. Its format parameters and supported ranges (input, output, coefficients, accumulator).
2. **Every quantization point**: where, source and destination formats, `ROUND`, `SAT`.
3. Its internal growth (guard bits) and the input range for which it cannot overflow.
4. Its golden model (`verification/model/<ip>_model.py`, built on `claude_fx.py`) and the
   accuracy target against the float reference (SQNR or max error in LSB).
5. Its lossless output format (the `out_fmt` formula, for fixed and for reloadable
   coefficients) and which internal points always quantize (recursive state).
6. Its recursive quantization points (R1), limit-cycle behavior (R2), division / square-root
   behavior if any (R6), error bounds for approximated functions (R7), and its
   CMSIS-compatible parameter set if one exists (R10).

---

## Verification

- **Robustness and tooling** (R1–R14): elaboration error for `FX_WRAP` on a recursive point;
  zero-input limit-cycle test on every recursive block, with `STATE_ROUND` / `ERR_FB`
  variants; `claude_fx.coef` on reference designs (an unstable quantized IIR is rejected,
  file round trip RTL / C / Python); TPDF dither and noise shaping bit-exact with the model and
  measured (THD+N improvement); division and sqrt exhaustive at small widths for every
  `ROUND` and `DZ_MODE`, including divide by zero and `min / −1`; transcendental error bounds;
  offset-binary / sign-magnitude round trips; BFP exponent carried and applied;
  `claude_fx.cmsis` against host and target CMSIS-DSP; generated register-field helpers
  against `claude_fx.py`; `claude_fx.metrics` against textbook cases (ideal N-bit quantizer
  SQNR ≈ 6.02·N + 1.76 dB).
- **Chain features**: `out_fmt` of every block checked against exhaustive / worst-case
  simulation of its model (the lossless format is never exceeded and is the narrowest
  that holds the worst case); `fmt: auto` propagation and `max_w` caps on example chains;
  the generator rejects a `lossless: true` link that is too narrow; the run-time monitor
  fires on an injected `coef_bound` violation; the precision report matches hand-computed
  SQNR on a single-block chain.
- **Named-format matrix**: `convert` between every pair of the eleven named formats (121
  pairs) × every `ROUND` × `SAT`, and `mul` / `add` for every pair, on edge-case and random
  values, RTL vs. Python vs. C, plus `sint4` / `uint4` packing and unpacking, the TFLite
  16x8 mode against the TFLite reference kernels, and `claude_g711` against the G.711 tables. Plus a set of custom formats in the regression (`q1.23`,
  `q2.30`, `sint18`, `sint25`, `uq0.8`, `q8.24`, one negative-`F` format, one 64-bit).
- **Exhaustive** RTL vs. `claude_fx.py` for `claude_fx_conv`, `_round`, `_sat` at small
  widths (every input for `IN_W` ≤ 12, every `ROUND` × `SAT` × signedness × shift from −4 to
  +8), SV and VHDL, VCS and Xcelium; **random** for wide widths (up to 64) and for
  `claude_fx_mul` / `_lzc`.
- **Formal**: `claude_fx_conv` equals a behavioral reference (wide-integer SV written
  directly from the definitions table) for all inputs, for a set of parameter points;
  SV ≡ VHDL by the same proof.
- **TFLite / PyTorch agreement**: `srdhm` / `rdbpot` against TFLite's reference kernels and
  `FX_CONVERGENT` / `quantize` against `torch.quantize_per_tensor` and `numpy.rint` on random
  and edge-case vectors (ties, min / max, −2^31 × −2^31).
- **C ↔ Python**: host build of `claude_fx.h` against `claude_fx.py` on the same vectors;
  cross-compile checks (Cortex-M33, RISC-V, `-std=c99`).
- Edge cases always included: exact ties (±½ LSB, ±1½ LSB), signed min, rounding carry into
  saturation, `k` = 0, `k` < 0, `F` = 0 (integer), `F` > `W`, unsigned destination of a
  negative value.

---

## Change log

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-11-27 | approved |
