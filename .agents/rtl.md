# Step 3 — `rtl` Sub-Agent

## Trigger

Step 2 complete (`design/rtl/verilog/IP_NAME_regfile.sv` and
`design/rtl/vhdl/IP_NAME_regfile.vhd` exist and are parse-clean).

## Prerequisites

- `design/rtl/verilog/IP_NAME_regfile.sv` and `design/rtl/vhdl/IP_NAME_regfile.vhd` exist.
- `design/rtl/verilog/` and `design/rtl/vhdl/` directories exist.
- `design/behavioral/` directory exists.
- `IP_COMMON_PATH` is set (sourced from `setup.sh`).

## Common Components

**Check `${IP_COMMON_PATH}/rtl/` before writing any new RTL component.**

- CDC synchronizers, reset synchronizers, and other low-level primitives are in
  `${IP_COMMON_PATH}/rtl/verilog/` and `${IP_COMMON_PATH}/rtl/vhdl/`. Instantiate them
  directly rather than re-implementing them.
- If a new primitive would be reusable across other IPs, write it in
  `${IP_COMMON_PATH}/rtl/` (both verilog/ and vhdl/) rather than inside this IP's `design/rtl/`.
- Instantiation paths must use `IP_COMMON_PATH`, never a hardcoded path.

## Coding Standards

**RULE — Read both style guides in full before writing a single line of RTL.**

- `.agents/VerilogCodingStyle.md` — lowRISC Comportable style for SystemVerilog
- `.agents/VHDL2008CodingStyle.md` — IEEE 1076-2008 VHDL style

**RULE — These documents are immutable. Do not edit, summarize, or override them.**
Every rule in these guides applies to every `.sv` and `.vhd` file produced by this step.
If a style-guide rule and any other instruction conflict, the style guide wins for all
matters of code formatting and structure.

**RULE — No silent deviations.** If a synthesis constraint or language limitation makes
strict compliance impossible at a specific line, add an inline comment at that exact line
explaining why. Deviations without a comment are a quality-gate failure.

## Responsibilities

1. Implement the core IP logic:
   - `design/rtl/verilog/IP_NAME.sv` — SystemVerilog implementation.
   - `design/rtl/vhdl/IP_NAME.vhd` — VHDL-2008 implementation.
2. Implement one bus-interface adapter per requested protocol in both languages.
   File naming convention: `IP_NAME_<proto>.[sv|vhd]` in the respective RTL directory.
   Supported protocols: AHB-Lite, APB4, AXI4-Lite, Wishbone B4.
3. Each bus adapter is a thin wrapper only: protocol state machine → register-file interface.
   No functional logic lives in the adapter files.
4. Write a behavioral reference model in `design/behavioral/IP_NAME_model.sv` for use
   by the scoreboard in Step 5.
5. Every port is documented inline. Every `always_ff`/`process` block has a one-line comment
   describing its purpose.
6. Parameterize data width, address width, and number of registers via SV `parameter` /
   VHDL `generic`. No hardcoded widths anywhere.
7. Reset is synchronous active-low. Reset polarity is a top-level parameter.
8. Run parse checks before marking complete:
   - `iverilog -tnull` on every `.sv` file in `design/rtl/verilog/`.
   - `ghdl -s` on every `.vhd` file in `design/rtl/vhdl/`.

## Outputs

| Artifact | Description |
|----------|-------------|
| `design/rtl/verilog/IP_NAME.sv` | Core IP logic — SystemVerilog |
| `design/rtl/vhdl/IP_NAME.vhd` | Core IP logic — VHDL-2008 |
| `design/rtl/verilog/IP_NAME_<proto>.sv` | Bus adapter(s) — SystemVerilog |
| `design/rtl/vhdl/IP_NAME_<proto>.vhd` | Bus adapter(s) — VHDL-2008 |
| `design/behavioral/IP_NAME_model.sv` | Behavioral reference model |

## Quality Gate

- `iverilog -tnull` passes on all SV files.
- `ghdl -s` passes on all VHDL files.
- SV and VHDL twins are port-for-port identical.
- No functional logic present in bus adapter files.
- All style-guide rules followed (no tabs, correct naming, explicit widths, etc.).
