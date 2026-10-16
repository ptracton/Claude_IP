// sram_macro.sv — Technology dispatcher for one sram array tile.
//
// Instantiates the leaf for TECH (sram_pkg::TECH_*). All leaves share this
// port list: a synchronous single-port RAM of MAC_W x MAC_D with per-byte
// write enables, read data valid in the cycle after a read, and the three
// sleep pins (used only by technologies that have them).
// Only the selected branch is elaborated, so a host only needs the macro
// library (or XPM / altera_mf) of the technology it builds.

module sram_macro #(
  parameter int unsigned TECH      = sram_pkg::TECH_GENERIC, // technology
  parameter int unsigned MAC_W     = 32,                     // tile word width
  parameter int unsigned MAC_D     = 1024,                   // tile words
  parameter string       INIT_FILE = ""                      // preload (GENERIC/FPGA)
) (
  input  logic                     clk,       // clock
  input  logic                     cs_i,      // chip select
  input  logic                     we_i,      // 1 = write, 0 = read
  input  logic [$clog2(MAC_D)-1:0] addr_i,    // word address
  input  logic [MAC_W-1:0]         wdata_i,   // write data
  input  logic [MAC_W/8-1:0]       wbe_i,     // byte write enables
  input  logic                     ls_i,      // light sleep
  input  logic                     ds_i,      // deep sleep
  input  logic                     sd_i,      // shutdown
  output logic [MAC_W-1:0]         rdata_o    // read data (cycle after a read)
);

  if (TECH == sram_pkg::TECH_SAED90) begin : g_saed90
    sram_macro_saed90 #(
      .MAC_W(MAC_W),
      .MAC_D(MAC_D)
    ) u_leaf (
      .clk    (clk),
      .cs_i   (cs_i),
      .we_i   (we_i),
      .addr_i (addr_i),
      .wdata_i(wdata_i),
      .wbe_i  (wbe_i),
      .ls_i   (ls_i),
      .ds_i   (ds_i),
      .sd_i   (sd_i),
      .rdata_o(rdata_o)
    );
  end else if (TECH == sram_pkg::TECH_SAED32) begin : g_saed32
    sram_macro_saed32 #(
      .MAC_W(MAC_W),
      .MAC_D(MAC_D)
    ) u_leaf (
      .clk    (clk),
      .cs_i   (cs_i),
      .we_i   (we_i),
      .addr_i (addr_i),
      .wdata_i(wdata_i),
      .wbe_i  (wbe_i),
      .ls_i   (ls_i),
      .ds_i   (ds_i),
      .sd_i   (sd_i),
      .rdata_o(rdata_o)
    );
  end else if (TECH == sram_pkg::TECH_SAED14) begin : g_saed14
    sram_macro_saed14 #(
      .MAC_W(MAC_W),
      .MAC_D(MAC_D)
    ) u_leaf (
      .clk    (clk),
      .cs_i   (cs_i),
      .we_i   (we_i),
      .addr_i (addr_i),
      .wdata_i(wdata_i),
      .wbe_i  (wbe_i),
      .ls_i   (ls_i),
      .ds_i   (ds_i),
      .sd_i   (sd_i),
      .rdata_o(rdata_o)
    );
  end else if (TECH == sram_pkg::TECH_SKY130) begin : g_sky130
    sram_macro_sky130 #(
      .MAC_W(MAC_W),
      .MAC_D(MAC_D)
    ) u_leaf (
      .clk    (clk),
      .cs_i   (cs_i),
      .we_i   (we_i),
      .addr_i (addr_i),
      .wdata_i(wdata_i),
      .wbe_i  (wbe_i),
      .ls_i   (ls_i),
      .ds_i   (ds_i),
      .sd_i   (sd_i),
      .rdata_o(rdata_o)
    );
  end else if (TECH == sram_pkg::TECH_XILINX) begin : g_xilinx
    sram_macro_xilinx #(
      .MAC_W    (MAC_W),
      .MAC_D    (MAC_D),
      .INIT_FILE(INIT_FILE)
    ) u_leaf (
      .clk    (clk),
      .cs_i   (cs_i),
      .we_i   (we_i),
      .addr_i (addr_i),
      .wdata_i(wdata_i),
      .wbe_i  (wbe_i),
      .ls_i   (ls_i),
      .ds_i   (ds_i),
      .sd_i   (sd_i),
      .rdata_o(rdata_o)
    );
  end else if (TECH == sram_pkg::TECH_ALTERA) begin : g_altera
    sram_macro_altera #(
      .MAC_W    (MAC_W),
      .MAC_D    (MAC_D),
      .INIT_FILE(INIT_FILE)
    ) u_leaf (
      .clk    (clk),
      .cs_i   (cs_i),
      .we_i   (we_i),
      .addr_i (addr_i),
      .wdata_i(wdata_i),
      .wbe_i  (wbe_i),
      .ls_i   (ls_i),
      .ds_i   (ds_i),
      .sd_i   (sd_i),
      .rdata_o(rdata_o)
    );
  end else begin : g_generic
    sram_macro_generic #(
      .MAC_W    (MAC_W),
      .MAC_D    (MAC_D),
      .INIT_FILE(INIT_FILE)
    ) u_leaf (
      .clk    (clk),
      .cs_i   (cs_i),
      .we_i   (we_i),
      .addr_i (addr_i),
      .wdata_i(wdata_i),
      .wbe_i  (wbe_i),
      .ls_i   (ls_i),
      .ds_i   (ds_i),
      .sd_i   (sd_i),
      .rdata_o(rdata_o)
    );
  end

endmodule : sram_macro
