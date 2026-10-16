// sram_macro_dp_saed14.sv — SAED14 two-port SRAM macro tile (DUAL_PORT).
//
// One SAED14 (SAED14nm_EDK_SRAM, SRAM2RW) macro of MAC_W x MAC_D, chosen by
// sram_pkg::macro_width_dp / macro_depth_dp. Two independent read/write
// ports on one clock.
//
// Pin mapping:
//   CE1 = CE2 = clk; CSB1/CSB2 = ~cs (ACTIVE LOW for the two-port macros —
//   databook: "Chip Select signal is low for read/write" — unlike the
//   single-port SRAM1RW macros); WEB1/WEB2 = ~write; OEB1 = OEB2 = 0.
//   Read data is registered on the clock: valid in the cycle after a read.
//   No byte mask: columns lie inside one write lane, so *_wbe_i is all-equal
//   and bit 0 gates the write. The core never lets both ports access the
//   same word in one cycle when either writes.

module sram_macro_dp_saed14 #(
  parameter int unsigned MAC_W = 8,   // macro word width
  parameter int unsigned MAC_D = 64   // macro words
) (
  input  logic                     clk,       // clock (both ports)
  input  logic                     a_cs_i,    // port A chip select
  input  logic                     a_we_i,    // port A 1 = write
  input  logic [$clog2(MAC_D)-1:0] a_addr_i,  // port A word address
  input  logic [MAC_W-1:0]         a_wdata_i, // port A write data
  // Uniform across the column (see header); only bit 0 is used.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [MAC_W/8-1:0]       a_wbe_i,   // port A byte write enables
  /* verilator lint_on UNUSEDSIGNAL */
  output logic [MAC_W-1:0]         a_rdata_o, // port A read data
  input  logic                     b_cs_i,    // port B chip select
  input  logic                     b_we_i,    // port B 1 = write
  input  logic [$clog2(MAC_D)-1:0] b_addr_i,  // port B word address
  input  logic [MAC_W-1:0]         b_wdata_i, // port B write data
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [MAC_W/8-1:0]       b_wbe_i,   // port B byte write enables
  /* verilator lint_on UNUSEDSIGNAL */
  output logic [MAC_W-1:0]         b_rdata_o, // port B read data
  // No sleep pins on this macro family: power is controlled through UPF.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                     ls_i,      // light sleep (unused)
  input  logic                     ds_i,      // deep sleep (unused)
  input  logic                     sd_i       // shutdown (unused)
  /* verilator lint_on UNUSEDSIGNAL */
);

  logic a_csb, b_csb;  // chip selects, active low
  logic a_web, b_web;  // write enables, active low

  assign a_csb    = ~a_cs_i;
  assign b_csb    = ~b_cs_i;
  assign a_web    = ~(a_we_i & a_wbe_i[0]);
  assign b_web    = ~(b_we_i & b_wbe_i[0]);

  // One branch per supported size (sram_pkg::macro_depth_dp only picks these).
  if (MAC_W == 8 && MAC_D == 16) begin : g_8x16
    SRAM2RW16x8 u_macro (
      .A1  (a_addr_i),
      .A2  (b_addr_i),
      .CE1 (clk),
      .CE2 (clk),
      .WEB1(a_web),
      .WEB2(b_web),
      .OEB1(1'b0),
      .OEB2(1'b0),
      .CSB1(a_csb),
      .CSB2(b_csb),
      .I1  (a_wdata_i),
      .I2  (b_wdata_i),
      .O1  (a_rdata_o),
      .O2  (b_rdata_o)
    );
  end else if (MAC_W == 8 && MAC_D == 32) begin : g_8x32
    SRAM2RW32x8 u_macro (
      .A1  (a_addr_i),
      .A2  (b_addr_i),
      .CE1 (clk),
      .CE2 (clk),
      .WEB1(a_web),
      .WEB2(b_web),
      .OEB1(1'b0),
      .OEB2(1'b0),
      .CSB1(a_csb),
      .CSB2(b_csb),
      .I1  (a_wdata_i),
      .I2  (b_wdata_i),
      .O1  (a_rdata_o),
      .O2  (b_rdata_o)
    );
  end else if (MAC_W == 8 && MAC_D == 64) begin : g_8x64
    SRAM2RW64x8 u_macro (
      .A1  (a_addr_i),
      .A2  (b_addr_i),
      .CE1 (clk),
      .CE2 (clk),
      .WEB1(a_web),
      .WEB2(b_web),
      .OEB1(1'b0),
      .OEB2(1'b0),
      .CSB1(a_csb),
      .CSB2(b_csb),
      .I1  (a_wdata_i),
      .I2  (b_wdata_i),
      .O1  (a_rdata_o),
      .O2  (b_rdata_o)
    );
  end else if (MAC_W == 8 && MAC_D == 128) begin : g_8x128
    SRAM2RW128x8 u_macro (
      .A1  (a_addr_i),
      .A2  (b_addr_i),
      .CE1 (clk),
      .CE2 (clk),
      .WEB1(a_web),
      .WEB2(b_web),
      .OEB1(1'b0),
      .OEB2(1'b0),
      .CSB1(a_csb),
      .CSB2(b_csb),
      .I1  (a_wdata_i),
      .I2  (b_wdata_i),
      .O1  (a_rdata_o),
      .O2  (b_rdata_o)
    );
  end else if (MAC_W == 8 && MAC_D == 256) begin : g_8x256
    SRAM2RW256x8 u_macro (
      .A1  (a_addr_i),
      .A2  (b_addr_i),
      .CE1 (clk),
      .CE2 (clk),
      .WEB1(a_web),
      .WEB2(b_web),
      .OEB1(1'b0),
      .OEB2(1'b0),
      .CSB1(a_csb),
      .CSB2(b_csb),
      .I1  (a_wdata_i),
      .I2  (b_wdata_i),
      .O1  (a_rdata_o),
      .O2  (b_rdata_o)
    );
  end else if (MAC_W == 8 && MAC_D == 512) begin : g_8x512
    SRAM2RW512x8 u_macro (
      .A1  (a_addr_i),
      .A2  (b_addr_i),
      .CE1 (clk),
      .CE2 (clk),
      .WEB1(a_web),
      .WEB2(b_web),
      .OEB1(1'b0),
      .OEB2(1'b0),
      .CSB1(a_csb),
      .CSB2(b_csb),
      .I1  (a_wdata_i),
      .I2  (b_wdata_i),
      .O1  (a_rdata_o),
      .O2  (b_rdata_o)
    );
  end else if (MAC_W == 32 && MAC_D == 16) begin : g_32x16
    SRAM2RW16x32 u_macro (
      .A1  (a_addr_i),
      .A2  (b_addr_i),
      .CE1 (clk),
      .CE2 (clk),
      .WEB1(a_web),
      .WEB2(b_web),
      .OEB1(1'b0),
      .OEB2(1'b0),
      .CSB1(a_csb),
      .CSB2(b_csb),
      .I1  (a_wdata_i),
      .I2  (b_wdata_i),
      .O1  (a_rdata_o),
      .O2  (b_rdata_o)
    );
  end else if (MAC_W == 32 && MAC_D == 32) begin : g_32x32
    SRAM2RW32x32 u_macro (
      .A1  (a_addr_i),
      .A2  (b_addr_i),
      .CE1 (clk),
      .CE2 (clk),
      .WEB1(a_web),
      .WEB2(b_web),
      .OEB1(1'b0),
      .OEB2(1'b0),
      .CSB1(a_csb),
      .CSB2(b_csb),
      .I1  (a_wdata_i),
      .I2  (b_wdata_i),
      .O1  (a_rdata_o),
      .O2  (b_rdata_o)
    );
  end else if (MAC_W == 32 && MAC_D == 64) begin : g_32x64
    SRAM2RW64x32 u_macro (
      .A1  (a_addr_i),
      .A2  (b_addr_i),
      .CE1 (clk),
      .CE2 (clk),
      .WEB1(a_web),
      .WEB2(b_web),
      .OEB1(1'b0),
      .OEB2(1'b0),
      .CSB1(a_csb),
      .CSB2(b_csb),
      .I1  (a_wdata_i),
      .I2  (b_wdata_i),
      .O1  (a_rdata_o),
      .O2  (b_rdata_o)
    );
  end else if (MAC_W == 32 && MAC_D == 128) begin : g_32x128
    SRAM2RW128x32 u_macro (
      .A1  (a_addr_i),
      .A2  (b_addr_i),
      .CE1 (clk),
      .CE2 (clk),
      .WEB1(a_web),
      .WEB2(b_web),
      .OEB1(1'b0),
      .OEB2(1'b0),
      .CSB1(a_csb),
      .CSB2(b_csb),
      .I1  (a_wdata_i),
      .I2  (b_wdata_i),
      .O1  (a_rdata_o),
      .O2  (b_rdata_o)
    );
  end else if (MAC_W == 32 && MAC_D == 256) begin : g_32x256
    SRAM2RW256x32 u_macro (
      .A1  (a_addr_i),
      .A2  (b_addr_i),
      .CE1 (clk),
      .CE2 (clk),
      .WEB1(a_web),
      .WEB2(b_web),
      .OEB1(1'b0),
      .OEB2(1'b0),
      .CSB1(a_csb),
      .CSB2(b_csb),
      .I1  (a_wdata_i),
      .I2  (b_wdata_i),
      .O1  (a_rdata_o),
      .O2  (b_rdata_o)
    );
  end else if (MAC_W == 32 && MAC_D == 512) begin : g_32x512
    SRAM2RW512x32 u_macro (
      .A1  (a_addr_i),
      .A2  (b_addr_i),
      .CE1 (clk),
      .CE2 (clk),
      .WEB1(a_web),
      .WEB2(b_web),
      .OEB1(1'b0),
      .OEB2(1'b0),
      .CSB1(a_csb),
      .CSB2(b_csb),
      .I1  (a_wdata_i),
      .I2  (b_wdata_i),
      .O1  (a_rdata_o),
      .O2  (b_rdata_o)
    );
  end else begin : g_unsupported
    // Elaboration-time error: no macro of this size in the curated list.
    initial $fatal(1, "sram_macro_dp_saed14: no %0dx%0d macro", MAC_W, MAC_D);
    assign a_rdata_o = '0;
    assign b_rdata_o = '0;
  end

endmodule : sram_macro_dp_saed14
