// sram_macro_saed90.sv — SAED90 SRAM macro tile (TECH_SAED90).
//
// One SAED90 (SAED_EDK90nm Memories) single-port macro of MAC_W x MAC_D, chosen by
// sram_pkg::macro_width/macro_depth (sizes listed in the generate below).
//
// Pin mapping:
//   CE = clk, CSB = ~cs_i (active low), WEB = ~write (active low), OEB = 0.
//   Read data is registered on CE: valid in the cycle after a read. The macro
//   has no byte mask, so the array only builds columns that lie inside one
//   write lane; wbe_i is therefore all-equal and wbe_i[0] gates the write.

module sram_macro_saed90 #(
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

  assign csb = ~cs_i;
  assign web = ~(we_i & wbe_i[0]);

  // One branch per supported size (sram_pkg::macro_depth only picks these).
  if (MAC_W == 8 && MAC_D == 64) begin : g_8x64
    SRAM8x64_1rw u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 8 && MAC_D == 128) begin : g_8x128
    SRAM8x128_1rw u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 8 && MAC_D == 256) begin : g_8x256
    SRAM8x256_1rw u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 8 && MAC_D == 512) begin : g_8x512
    SRAM8x512_1rw u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 8 && MAC_D == 1024) begin : g_8x1024
    SRAM8x1024_1rw u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 32 && MAC_D == 64) begin : g_32x64
    SRAM32x64_1rw u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 32 && MAC_D == 256) begin : g_32x256
    SRAM32x256_1rw u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o)
    );
  end else if (MAC_W == 32 && MAC_D == 512) begin : g_32x512
    SRAM32x512_1rw u_macro (
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
    initial $fatal(1, "sram_macro_saed90: no %0dx%0d macro", MAC_W, MAC_D);
    assign rdata_o = '0;
  end

endmodule : sram_macro_saed90
