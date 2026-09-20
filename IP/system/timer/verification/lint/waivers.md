# Lint Waivers — timer IP

## RTL Waivers (design/rtl/)

| File | Line | Tool / Code | Justification |
|------|------|-------------|----------------|
| `design/rtl/verilog/timer_core.sv` | 96–121 | SpyGlass `STARC05-2.11.3.1` | `p_prescaler`'s next-value logic is computed inline via `if/else` inside the `always_ff` block rather than in a separate `always_comb` block, deviating from the two-process pattern in `VerilogCodingStyle.md`. It's a plain synchronous counter (`always_ff`-only, no blocking assignments) — not a functional issue. Accepted as a style deviation for now; `p_counter` below it has the same pattern and would need the same treatment if a future SpyGlass rule flags it too. |

Verilator and GHDL: zero warnings accepted — no waivers on standard hosts.

## Common-component RTL Waivers (`${IP_COMMON_PATH}/design/rtl/`)

Timer's SpyGlass lint (csun.edu only) reads shared bus-interface RTL from
`IP/common/`. A waiver there affects every IP that uses that component, not
just timer, so it's recorded here for visibility but lives in the shared file.

| File | Line | Tool / Code | Justification |
|------|------|-------------|----------------|
| `${IP_COMMON_PATH}/design/rtl/verilog/claude_apb_if.sv` | 40–41 | SpyGlass `W240` | `PCLK`/`PRESETn` are APB4-required ports on this purely-combinational bridge; it has no registered state and routes both signals through to the regfile above, which is where they're actually consumed. Same rationale as the existing `verilator lint_off UNUSEDSIGNAL` waiver immediately around it. |

## Testbench Waivers (verification/)

None at this time.

---

*Any future waiver must include:*
- File path (relative to `${CLAUDE_TIMER_PATH}`, or `${IP_COMMON_PATH}` for shared components)
- Line number
- Warning code (Verilator, SpyGlass) or error message (GHDL)
- One-line justification
- Corresponding suppression pragma at that exact line in the source file
