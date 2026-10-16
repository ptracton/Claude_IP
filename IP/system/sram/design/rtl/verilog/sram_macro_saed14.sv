// sram_macro_saed14.sv — SAED14 SRAM macro tile (TECH_SAED14).
//
// One SAED14 (SAED14nm_EDK_SRAM) single-port macro of MAC_W x MAC_D, chosen by
// sram_pkg::macro_width/macro_depth (sizes listed in the generate below).
//
// Pin mapping:
//   CE = clk, CSB = cs_i (ACTIVE HIGH: SAED14nm Memories databook,
//   "CSB — Primary Chip Select, Active High"), WEB = ~write (active low),
//   OEB = 0. The macro drives O to 0 after any cycle that is not a read.
//   Quirk: SRAM1RW32x8 has a 32-bit I bus (model and liberty); its data is
//   zero-extended.
//   Read data is registered on CE: valid in the cycle after a read. The macro
//   has no byte mask, so the array only builds columns that lie inside one
//   write lane; wbe_i is therefore all-equal and wbe_i[0] gates the write.

module sram_macro_saed14 #(
  parameter int unsigned MAC_W = 8,   // macro word width
  parameter int unsigned MAC_D = 64   // macro words
) (
  input  logic                     clk,       // clock (macro CE)
  input  logic                     cs_i,      // chip select
  input  logic                     we_i,      // 1 = write, 0 = read
  input  logic [$clog2(MAC_D)-1:0] addr_i,    // word address
  input  logic [MAC_W-1:0]         wdata_i,   // write data
  // Uniform across the column (see header); only bit 0 is used.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [MAC_W/8-1:0]       wbe_i,     // byte write enables
  // No sleep pins on this macro family: power is controlled through UPF.
  input  logic                     ls_i,      // light sleep (unused)
  input  logic                     ds_i,      // deep sleep (unused)
  input  logic                     sd_i,      // shutdown (unused)
  /* verilator lint_on UNUSEDSIGNAL */
  output logic [MAC_W-1:0]         rdata_o    // read data
);

  logic csb;  // chip select, macro polarity
  logic web;  // write enable, active low

  assign csb = cs_i;
  assign web = ~(we_i & wbe_i[0]);

  // One branch per supported size (sram_pkg::macro_depth only picks these).
  if (MAC_W == 8 && MAC_D == 16) begin : g_8x16
    SRAM1RW16x8 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 8 && MAC_D == 32) begin : g_8x32
    SRAM1RW32x8 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      // SRAM1RW32x8 has a 32-bit I bus (liberty too); only 8 bits are used.
      .I  (32'(wdata_i)),
      .O  (rdata_o)
    );
  end else if (MAC_W == 8 && MAC_D == 64) begin : g_8x64
    SRAM1RW64x8 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 8 && MAC_D == 128) begin : g_8x128
    SRAM1RW128x8 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 8 && MAC_D == 256) begin : g_8x256
    SRAM1RW256x8 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 8 && MAC_D == 512) begin : g_8x512
    SRAM1RW512x8 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 32 && MAC_D == 16) begin : g_32x16
    SRAM1RW16x32 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 32 && MAC_D == 32) begin : g_32x32
    SRAM1RW32x32 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 32 && MAC_D == 64) begin : g_32x64
    SRAM1RW64x32 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 32 && MAC_D == 128) begin : g_32x128
    SRAM1RW128x32 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 32 && MAC_D == 256) begin : g_32x256
    SRAM1RW256x32 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 32 && MAC_D == 512) begin : g_32x512
    SRAM1RW512x32 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else begin : g_unsupported
    // Elaboration-time error: no macro of this size in the curated list.
    initial $fatal(1, "sram_macro_saed14: no %0dx%0d macro", MAC_W, MAC_D);
    assign rdata_o = '0;
  end

endmodule : sram_macro_saed14
