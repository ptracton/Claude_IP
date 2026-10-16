// sram_macro_saed32.sv — SAED32 low-power SRAM macro tile (TECH_SAED32).
//
// One SAED32 low-power (lib/sram_lp) single-port macro of MAC_W x MAC_D, chosen by
// sram_pkg::macro_width/macro_depth (sizes listed in the generate below).
//
// Pin mapping:
//   CE = clk, CSB = ~cs_i (active low), WEB = ~write (active low), OEB = 0.
//   LS / DS / SD = ls_i / ds_i / sd_i (light sleep, deep sleep, shutdown).
//   The macro only honours LS/DS/SD while deselected (CSB high); the core
//   never selects a sleeping bank. VDD/VDDL/VSS are power pins (UPF/PG),
//   left unconnected in RTL.
//   Read data is registered on CE: valid in the cycle after a read. The macro
//   has no byte mask, so the array only builds columns that lie inside one
//   write lane; wbe_i is therefore all-equal and wbe_i[0] gates the write.

module sram_macro_saed32 #(
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
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic                     ls_i,      // light sleep
  input  logic                     ds_i,      // deep sleep
  input  logic                     sd_i,      // shutdown
  output logic [MAC_W-1:0]         rdata_o    // read data
);

  logic csb;  // chip select, macro polarity
  logic web;  // write enable, active low

  assign csb = ~cs_i;
  assign web = ~(we_i & wbe_i[0]);

  // One branch per supported size (sram_pkg::macro_depth only picks these).
  if (MAC_W == 8 && MAC_D == 64) begin : g_8x64
    SRAMLP1RW64x8 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o),
      .SD (sd_i),
      .LS (ls_i),
      .DS (ds_i)
    );
  end else if (MAC_W == 8 && MAC_D == 128) begin : g_8x128
    SRAMLP1RW128x8 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o),
      .SD (sd_i),
      .LS (ls_i),
      .DS (ds_i)
    );
  end else if (MAC_W == 8 && MAC_D == 256) begin : g_8x256
    SRAMLP1RW256x8 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o),
      .SD (sd_i),
      .LS (ls_i),
      .DS (ds_i)
    );
  end else if (MAC_W == 8 && MAC_D == 512) begin : g_8x512
    SRAMLP1RW512x8 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o),
      .SD (sd_i),
      .LS (ls_i),
      .DS (ds_i)
    );
  end else if (MAC_W == 8 && MAC_D == 1024) begin : g_8x1024
    SRAMLP1RW1024x8 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o),
      .SD (sd_i),
      .LS (ls_i),
      .DS (ds_i)
    );
  end else if (MAC_W == 32 && MAC_D == 64) begin : g_32x64
    SRAMLP1RW64x32 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o),
      .SD (sd_i),
      .LS (ls_i),
      .DS (ds_i)
    );
  end else if (MAC_W == 32 && MAC_D == 256) begin : g_32x256
    SRAMLP1RW256x32 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o),
      .SD (sd_i),
      .LS (ls_i),
      .DS (ds_i)
    );
  end else if (MAC_W == 32 && MAC_D == 512) begin : g_32x512
    SRAMLP1RW512x32 u_macro (
      .A  (addr_i),
      .CE (clk),
      .WEB(web),
      .OEB(1'b0),
      .CSB(csb),
      .I  (wdata_i),
      .O  (rdata_o),
      .SD (sd_i),
      .LS (ls_i),
      .DS (ds_i)
    );
  end else begin : g_unsupported
    // Elaboration-time error: no macro of this size in the curated list.
    initial $fatal(1, "sram_macro_saed32: no %0dx%0d macro", MAC_W, MAC_D);
    assign rdata_o = '0;
  end

endmodule : sram_macro_saed32
