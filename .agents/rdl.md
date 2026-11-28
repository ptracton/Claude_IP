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
   **New IP (user 2026-11-27):** the interface also has a **`rd_peek`** input: a read with
   `rd_peek` = 1 returns the value with no side effect (no FIFO pop, no read-to-clear). It is
   driven by the side-band debug freeze and by non-owner control-stream reads
   (`IP_SPEC_ctl_stream.md`). Signed-off IP keeps today's interface.
3a. **Standard blocks in every new IP's map** (`IP_SPEC_sideband.md`, `IP_SPEC_stream.md`):
   - include the shared **`claude_std_regs.rdl`** at **`0xFC0`** (`STD_ID`, `STD_VERSION`,
     `STD_PARAMS`, `STD_CTRL`, `IRQ_STATUS` / `IRQ_ENABLE` / `IRQ_SET` / `IRQ_OVF`, `EVT_EN`,
     `EVT_MISS`, `DMA_CTRL`, `DMA_STAT`, `OWNER`); registers the IP does not use read 0;
   - streaming IP also include **`claude_busmode.rdl`** at **`0xF80`** (`BUS_CTRL`,
     `BUS_STAT`, `DIN_CTL`, `DOUT_CTL`, `DOUT_THRESH`, `DIN[0..3]`, `DOUT[0..3]`);
   - the IP's own registers live in `0x000`–`0xF7F` (streaming IP) or `0x000`–`0xFBF` (others).
3b. **Number-valued fields** carry their format (`IP_SPEC_fx.md` R12) with the shared
   user-defined properties `fx_fmt` (for example `"q16.16"`, `"uint8"`) and `flt_fmt` (for
   example `"fp16"`). For each such field the generator also writes:
   - C: `IP_NAME_<REG>_<FIELD>_FROM_DOUBLE(x)` / `_TO_DOUBLE(v)` on `claude_fx.h` /
     `claude_flt.h` (convergent rounding, saturation; out-of-range values refused unless the
     field allows clipping), plus `_MIN` / `_MAX` constants;
   - Python: the same conversions in the generated register model;
   - HTML: the format and the real-value range in the field table.
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
- **New IP:** `claude_std_regs.rdl` is included at `0xFC0` (and `claude_busmode.rdl` at
  `0xF80` for streaming IP); no IP register overlaps them; the regfile has `rd_peek`, and a
  peek read of every register with a read side effect leaves its state unchanged.
- Every number-valued field has `fx_fmt` / `flt_fmt`, and its generated C and Python helpers
  round-trip against `claude_fx.py` / `claude_flt.py` on the field's min, max and a random set.
