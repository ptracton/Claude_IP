# bus_matrix — Lint Waivers

## RTL Waivers (design/rtl/)

| File | Line | Tool / Code | Justification |
|------|------|-------------|----------------|
| `design/rtl/verilog/bus_matrix_ahb_tgt.sv` | 28–30 | Verilator `UNUSEDSIGNAL` | `HTRANS[0]` is unused: an address phase is `HSEL & HTRANS[1]`, and NONSEQ and SEQ are handled the same. |
| `design/rtl/verilog/bus_matrix_axi4l_ini.sv` | 40–42 | Verilator `UNUSEDSIGNAL` | `BRESP[0]` is unused: bit 1 alone separates errors (SLVERR, DECERR) from OKAY / EXOKAY. |
| `design/rtl/verilog/bus_matrix_axi4l_ini.sv` | 50–52 | Verilator `UNUSEDSIGNAL` | `RRESP[0]` is unused, for the same reason as `BRESP[0]`. |

SpyGlass (csun.edu) and GHDL: no waivers.

## Testbench Waivers (verification/)

None at this time.
