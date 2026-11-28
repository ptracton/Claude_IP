# Floating-point and block-scaled formats — v1.1 approved 2026-11-27

Spec version: **1.1** (see "Change log" at the end).

Location: `.agents/IP_SPEC_float_formats.md` (all interface specs live in `.agents/`; the RTL
headers of components built from it point here).

Status: specification only, Phase 0.1 of `.agents/IP_PLAN.md` (§3.10, §8.1 NPU, §8.2 FPU,
D13). Nothing here is implemented yet.

Fixed-point and integer formats are in `IP_SPEC_fx.md`. This spec defines every
**floating-point** format the library uses, the **block-scaled** formats built on them, and
the rounding, overflow and special-value rules, **once**, for the FPU (`fpu_core`,
`fpu_stream`, `fpu_reg`), the NPU, the stream's `FMT = FLOAT`, the Python models and the C
helpers. Requirement (user 2026-11-27): support BF16, the 8-bit and 4-bit float formats in
use for ML, and the other formats worth having.

Names: `bfloat8` and `bfloat4` are not standard names. The standard 8-bit floats are the two
**OCP FP8** formats (E4M3, E5M2; AMD calls E5M2 "bf8"), and the 4-bit float is **FP4 E2M1**,
used with a shared block scale (MXFP4, NVFP4). This spec uses the standard names.

---

## Element formats

`E` = exponent bits, `M` = mantissa (fraction) bits, bias = `2^(E-1) - 1` unless noted.
All formats have a sign bit.

| Name | Bits | E | M | Bias | Inf | NaN | Subnormals | Max finite | Standard / users |
|---|---|---|---|---|---|---|---|---|---|
| `fp64` | 64 | 11 | 52 | 1023 | yes | yes | yes | ≈ 1.8 × 10^308 | IEEE 754 binary64; RISC-V D |
| `fp32` | 32 | 8 | 23 | 127 | yes | yes | yes | ≈ 3.4 × 10^38 | IEEE 754 binary32; RISC-V F |
| `fp16` | 16 | 5 | 10 | 15 | yes | yes | yes | 65 504 | IEEE 754 binary16; RISC-V `Zfh` / `Zfhmin` |
| `bf16` | 16 | 8 | 7 | 127 | yes | yes | yes | ≈ 3.39 × 10^38 | bfloat16 (top half of fp32); RISC-V `Zfbfmin` |
| `fp8_e4m3` | 8 | 4 | 3 | 7 | **no** | one pattern per sign (`S.1111.111`) | yes | **448** | OCP FP8 (E4M3FN in PyTorch / ml_dtypes) |
| `fp8_e5m2` | 8 | 5 | 2 | 15 | yes | yes | yes | 57 344 | OCP FP8 (IEEE-like) |
| `fp6_e2m3` | 6 | 2 | 3 | 1 | **no** | **no** | yes | 7.5 | OCP MX |
| `fp6_e3m2` | 6 | 3 | 2 | 3 | **no** | **no** | yes | 28 | OCP MX |
| `fp4_e2m1` | 4 | 2 | 1 | 1 | **no** | **no** | yes | 6 | OCP MX, NVFP4 element |
| `e8m0` | 8 | 8 | 0 | 127 | no | `0xFF` | no | 2^127 | OCP MX **scale only**: unsigned power of two, value `2^(e − 127)`, no sign, no zero |

Not supported (documented decisions): **TF32** (an internal multiplier width at most, never
a storage format); the **FNUZ** FP8 variants (AMD / Graphcore `e4m3fnuz`, `e5m2fnuz`: bias +1,
no negative zero), which can be added later as parameters of the same converter; **posits**
and **logarithmic** number systems (no framework support).

Value of a finite element (bit fields `s`, `e`, `m`): normal (`e ≠ 0`)
`(−1)^s × 2^(e − bias) × (1 + m / 2^M)`; subnormal (`e = 0`) `(−1)^s × 2^(1 − bias) × (m / 2^M)`.
For `fp8_e4m3`, `e = 15` is a normal exponent except for `m = 7` (NaN), which is why its
maximum is 448 and not 240.

## Block-scaled formats (OCP Microscaling MX v1.0, and NVFP4)

A **block** is `K` elements sharing one scale. The value of element *i* is
`scale × element_i`.

| Name | Element | K | Scale | Use |
|---|---|---|---|---|
| `mxfp8_e4m3` | `fp8_e4m3` | 32 | `e8m0` | inference weights / activations |
| `mxfp8_e5m2` | `fp8_e5m2` | 32 | `e8m0` | gradients, wide range |
| `mxfp6_e2m3` / `mxfp6_e3m2` | `fp6_*` | 32 | `e8m0` | compact weights |
| `mxfp4` | `fp4_e2m1` | 32 | `e8m0` | LLM weights |
| `mxint8` | `sint8` as a fixed-point value with 6 fractional bits (`q2.6`, OCP definition) | 32 | `e8m0` | integer alternative to MXFP8 |
| `nvfp4` | `fp4_e2m1` | 16 | `fp8_e4m3` per block + one `fp32` per tensor | NVIDIA Blackwell-style FP4 |

Rules:

1. **Scale choice** (quantizing a block of real values `v`): the OCP rule,
   `scale_exp = floor(log2(max |v|)) − emax_elem` (clamped to the `e8m0` range), where
   `emax_elem` is the element format's largest normal exponent; then each element is
   converted with **RNE** and **saturation** to the element's max finite value. An all-zero
   block gets the smallest scale. A NaN in the block makes the scale NaN (`0xFF`) for MX.
2. **Memory layout** (NPU and DMA): the scales of a tensor are stored as a separate array
   (one byte per block, `e8m0`), elements packed little-endian, low element in the low bits:
   two `fp4` per byte, four `fp6` per three bytes, one `fp8` per byte. Block *b* covers
   elements `b·K … b·K + K − 1` along the tensor's innermost (reduction) dimension. The NPU
   compiler may tile differently, and documents its layout.
3. **On a claude stream**, block-scaled data is not a stream format in this version: MX /
   NVFP4 tensors live in memory and are read by the NPU through `mem_*`. Element formats up
   to 16 bits (`fp16`, `bf16`, `fp8_*`) can be stream formats (below).

---

## Rounding

| Mode | Code | Meaning | Where |
|---|---|---|---|
| `RNE` | 0 | round to nearest, ties to even (**default**) | everywhere |
| `RTZ` | 1 | toward zero | FPU (IEEE) |
| `RDN` | 2 | toward −∞ | FPU (IEEE) |
| `RUP` | 3 | toward +∞ | FPU (IEEE) |
| `RMM` | 4 | to nearest, ties away from zero | FPU (IEEE, RISC-V) |
| `SR` | 8 | **stochastic rounding**: round up with probability equal to the discarded fraction, using `claude_lfsr` (`SR_BITS` random bits, default 8, seed register) | optional for the low-precision conversions (`fp8_*`, `fp6_*`, `fp4`, `bf16`) |

Codes 0–4 equal the RISC-V `frm` encoding. They are a **separate code space** from the
fixed-point `FX_*` rounding codes of `IP_SPEC_fx.md` (which also use 0–4): constants are
always named `FLT_RM_*` vs. `FX_*`, and a converter between the two (`claude_flt_fx_cvt`)
takes one parameter of each kind. `SR` is deterministic for a given seed, so the
Python model reproduces it bit for bit (same LFSR, same seed, same order).

## Overflow, NaN and subnormal rules

| Situation | IEEE formats (`fp64`, `fp32`, `fp16`, `bf16`, `fp8_e5m2`) | `fp8_e4m3` | `fp6_*`, `fp4_e2m1` |
|---|---|---|---|
| Result too large | ±∞ (or max finite in RTZ / RDN / RUP as IEEE says); OF + NX flags | **saturate** to ±448 (`SAT_MODE = SATFINITE`, default) or NaN (`SAT_MODE = NONSAT`) | **saturate** to the max finite (there is no other choice) |
| Input ∞ | ∞ (fp8_e5m2: ∞) | NaN, or ±448 with `SATFINITE` | ± max finite |
| Input NaN | **canonical quiet NaN** (RISC-V: sign 0, MSB of mantissa 1, rest 0); NV for signalling | the NaN pattern | no NaN encoding exists (OCP leaves it implementation-defined): maps to **+0** and raises NV. Inside an MX block, the block's scale becomes NaN (`0xFF`) instead |
| Subnormal results | **kept** (D13: full subnormals by default; `FTZ` parameter flushes) | kept | kept |
| Tininess | detected **after rounding** (RISC-V) | — | — |

`fp32 → bf16` is "keep the top 16 bits, rounded": RNE on the low 16 bits, with the IEEE rules
above (so it is exact for NaN, ∞ and zero, and never wraps).

---

## Where each format is used (plan staging)

| Unit | Formats | Stage |
|---|---|---|
| `fpu_core` / `fpu_rv` | `fp32` (default, D13), `fp64`; **`fp16`** (`Zfh`: full arithmetic, or `Zfhmin`: load / store / convert only) and **`bf16`** (`Zfbfmin`: conversions) by parameter (`HAS_FP16`, `HAS_BF16`) | FPU SP → DP → FP16 / BF16 |
| `fpu_stream` | stream `FMT = FLOAT` with `FLT` = `fp32`, `fp64`, `fp16`, `bf16`, `fp8_e4m3`, `fp8_e5m2`; converters to / from every `IP_SPEC_fx.md` named format | with the FPU |
| NPU | int8 and TFLite **16x8** first (`IP_SPEC_fx.md`), then **int4** weights, then **`bf16`**, then **`fp8_*` and the MX formats** (`mxfp8`, `mxfp6`, `mxfp4`, `mxint8`), then `nvfp4` | NPU-1 … NPU-4 (plan §8.1) |

### Stream format parameters (`FMT = FLOAT`)

The stream spec's `FMT = FLOAT` gains one parameter, **`FLT`** (one of the element names
above, default `fp32`); `W` follows from it (`fp8_*` = 8, `fp16` / `bf16` = 16, `fp32` = 32,
`fp64` = 64). `CPLX` and `LANES` work as for fixed point. The generator checks `FLT` on both
ends of every link, like the fixed-point format.

---

## Implementation

### RTL (one parameterized converter, shared)

| Module | Parameters | Purpose |
|---|---|---|
| `claude_flt_pkg` (SV + VHDL) | — | format constants `FLT_<NAME>_E`, `_M`, `_BIAS`, `_SPECIALS` (IEEE / FN / NONE), rounding codes |
| `claude_flt_cvt` | `IN_E`, `IN_M`, `IN_SPECIALS`, `OUT_E`, `OUT_M`, `OUT_SPECIALS`, `SAT_MODE`, `FTZ`, `HAS_SR`, `PIPE` | any float ↔ any float, with flags (NV, OF, UF, NX) |
| `claude_flt_fx_cvt` | float format + an `IP_SPEC_fx.md` format | float ↔ fixed / integer, `fx` saturation on the integer side |
| `claude_mx_quant` / `claude_mx_dequant` | element format, `K` | block scale computation (rule 1) and scaling, for the NPU and DMA |

The FPU's arithmetic is `fpu_core`; the converters above are what it, `fpu_stream` and the
NPU share.

### Python (`IP/common/verification/tools/claude_flt.py`)

- `FltFmt.parse("bf16")`, ..., and the block formats `MxFmt.parse("mxfp4")`.
- `quantize(x, fmt, rnd="RNE", sat="SATFINITE", seed=None)`, `to_float(bits, fmt)`,
  `convert(bits, src, dst, ...)` → `(bits, flags)`, `mx_quantize(block, mxfmt)` →
  `(scale, elements)`, `mx_dequantize(...)`.
- Exact by construction: values are handled as Python `Fraction`s, so every rounding mode
  (including `SR` with the shared LFSR) is exact; NumPy-vectorized for speed.
- **Cross-checked** against: Berkeley **SoftFloat** (`fp16`, `fp32`, `fp64`, all rounding modes
  and flags), Google **`ml_dtypes`** (`bf16`, `fp8_e4m3fn`, `fp8_e5m2`, `fp6_*`, `fp4_e2m1fn`,
  `e8m0`, RNE casts), **PyTorch** dtypes (`bfloat16`, `float8_e4m3fn`, `float8_e5m2`,
  `float4_e2m1fn_x2`), and the **OCP MX reference library** (`microxcaling`) for block
  scaling.

### C (`IP/common/firmware/include/claude_flt.h`, pure C99)

For firmware that prepares weights or converts samples on target: conversion functions
between `float` / `double` and `fp16`, `bf16`, `fp8_e4m3`, `fp8_e5m2`, `fp4_e2m1` (RNE, with
the saturation rules above), packing helpers for `fp4` / `fp6`, and an MX block quantizer.
Pure C99 (no `_Float16`), bit-manipulation only, so it builds for Cortex-M33 and RISC-V
without an FPU.

---

## What every unit using these formats documents

1. Which formats and rounding modes it supports, and its `SAT_MODE` / `FTZ` settings.
2. For accumulation (NPU, FPU dot products): the accumulator format (for example `fp32`
   accumulation of `bf16` or `fp8` products) and when it rounds.
3. For MX / NVFP4: block size, scale layout in memory, and the reduction dimension.

---

## Verification

- **Exhaustive** for every format up to 16 bits: all 65 536 `fp16` and `bf16` inputs, all 256
  `fp8_*`, all 64 / 16 `fp6` / `fp4` values, converted to every other format, every rounding
  mode, `SATFINITE` and `NONSAT`: RTL vs. `claude_flt.py` vs. the external references above.
- `fp32` / `fp64` sources: TestFloat-style vectors (random, plus every exponent boundary,
  ties, ±0, ±∞, NaN payloads, the largest values that round to max finite and the smallest
  that overflow).
- `SR`: RTL and Python agree bit for bit for the same seed; statistical test that the mean
  rounding error is unbiased.
- MX / NVFP4: block quantize / dequantize vs. the OCP reference library on random tensors,
  all-zero blocks, blocks with NaN / ∞, and blocks whose maximum lies on a power of two.
- C: host build vs. `claude_flt.py` on the exhaustive sets; cross-compile checks.
- NPU / FPU: as in plan §8.1 / §8.2, with these converters inside.

---

## Change log

| Version | Date | Change |
|---|---|---|
| 1.0 | 2026-11-27 | approved |
| 1.1 | 2026-11-27 | FLT_RM_* vs FX_* code spaces stated |
