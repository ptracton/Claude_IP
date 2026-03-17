# Step 2 — `rdl` Sub-Agent

## Trigger

Step 1 complete; user provides register specification (name, offset, fields, reset values,
access type).

## Prerequisites

- `IP_NAME/setup.sh` exists and sources without error.
- `IP_NAME/design/systemrdl/` and `IP_NAME/design/systemrdl/tools/` directories exist.
- `IP_NAME/design/rtl/verilog/` and `IP_NAME/design/rtl/vhdl/` directories exist.
- `IP_NAME/firmware/include/` directory exists.
- `generate_IP_NAME.py` skeleton exists from Step 1.

## Responsibilities

1. Write the authoritative `IP_NAME/design/systemrdl/IP_NAME.rdl` following the
   SystemRDL 2.0 specification. This file is the single source of truth for all registers.
2. Complete `design/systemrdl/tools/generate_IP_NAME.py` to invoke PeakRDL and produce:
   - `design/rtl/verilog/IP_NAME_reg_pkg.sv` — SV package: address offsets, field masks,
     reset values.
   - `design/rtl/verilog/IP_NAME_regfile.sv` — synthesizable SV register-file module.
   - `design/rtl/vhdl/IP_NAME_reg_pkg.vhd` — VHDL-2008 package equivalent.
   - `design/rtl/vhdl/IP_NAME_regfile.vhd` — synthesizable VHDL-2008 register-file entity.
   - `firmware/include/IP_NAME_regs.h` — C header with `#define` macros for every field.
   - `doc/IP_NAME_regs.html` — HTML register documentation.
3. The register-file module/entity exposes a simple, bus-agnostic interface:
   `(clk, rst_n, wr_en, wr_addr, wr_data, wr_strb, rd_en, rd_addr, rd_data)`.
   Bus adapters (Step 3) connect to this interface only.
4. Run `generate_IP_NAME.py` to produce all outputs, then verify syntax:
   - SV: `iverilog -tnull design/rtl/verilog/IP_NAME_regfile.sv`
   - VHDL: `ghdl -s design/rtl/vhdl/IP_NAME_regfile.vhd`
   - C header: `gcc -fsyntax-only firmware/include/IP_NAME_regs.h`

## Outputs

| Artifact | Description |
|----------|-------------|
| `design/systemrdl/IP_NAME.rdl` | SystemRDL 2.0 source — single source of truth |
| `design/systemrdl/tools/generate_IP_NAME.py` | Completed PeakRDL driver |
| `design/rtl/verilog/IP_NAME_reg_pkg.sv` | SV package: offsets, masks, reset values |
| `design/rtl/verilog/IP_NAME_regfile.sv` | Synthesizable SV register-file module |
| `design/rtl/vhdl/IP_NAME_reg_pkg.vhd` | VHDL-2008 package equivalent |
| `design/rtl/vhdl/IP_NAME_regfile.vhd` | Synthesizable VHDL-2008 register-file entity |
| `firmware/include/IP_NAME_regs.h` | C header with `#define` macros for every field |
| `doc/IP_NAME_regs.html` | HTML register documentation |

## Quality Gate

- `iverilog -tnull` passes on all generated SV files.
- `ghdl -s` passes on all generated VHDL files.
- `gcc -fsyntax-only` passes on the generated C header.
- SV and VHDL register-file interfaces are port-for-port equivalent.
- `generate_IP_NAME.py` is idempotent (running it twice produces identical output).
