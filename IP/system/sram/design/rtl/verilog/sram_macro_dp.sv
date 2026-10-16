// sram_macro_dp.sv — Technology dispatcher for one two-port sram array tile (DUAL_PORT).
//
// Two-port counterpart of sram_macro: instantiates sram_macro_dp_<tech>.
// Both ports share the clock; each has its own select, write enable,
// address, data and byte enables, with read data valid in the cycle after a
// read. Only the selected branch is elaborated.

module sram_macro_dp #(
  parameter int unsigned TECH      = sram_pkg::TECH_GENERIC, // technology
  parameter int unsigned MAC_W     = 32,                     // tile word width
  parameter int unsigned MAC_D     = 1024,                   // tile words
  parameter string       INIT_FILE = ""                      // preload (GENERIC/FPGA)
) (
  input  logic                     clk,       // clock (both ports)
  input  logic                     a_cs_i,    // port A chip select
  input  logic                     a_we_i,    // port A 1 = write
  input  logic [$clog2(MAC_D)-1:0] a_addr_i,  // port A word address
  input  logic [MAC_W-1:0]         a_wdata_i, // port A write data
  input  logic [MAC_W/8-1:0]       a_wbe_i,   // port A byte write enables
  output logic [MAC_W-1:0]         a_rdata_o, // port A read data
  input  logic                     b_cs_i,    // port B chip select
  input  logic                     b_we_i,    // port B 1 = write
  input  logic [$clog2(MAC_D)-1:0] b_addr_i,  // port B word address
  input  logic [MAC_W-1:0]         b_wdata_i, // port B write data
  input  logic [MAC_W/8-1:0]       b_wbe_i,   // port B byte write enables
  output logic [MAC_W-1:0]         b_rdata_o, // port B read data
  input  logic                     ls_i,      // light sleep
  input  logic                     ds_i,      // deep sleep
  input  logic                     sd_i       // shutdown
);

  if (TECH == sram_pkg::TECH_SAED90) begin : g_saed90
    sram_macro_dp_saed90 #(
      .MAC_W(MAC_W),
      .MAC_D(MAC_D)
    ) u_leaf (
      .clk      (clk),
      .a_cs_i   (a_cs_i),
      .a_we_i   (a_we_i),
      .a_addr_i (a_addr_i),
      .a_wdata_i(a_wdata_i),
      .a_wbe_i  (a_wbe_i),
      .a_rdata_o(a_rdata_o),
      .b_cs_i   (b_cs_i),
      .b_we_i   (b_we_i),
      .b_addr_i (b_addr_i),
      .b_wdata_i(b_wdata_i),
      .b_wbe_i  (b_wbe_i),
      .b_rdata_o(b_rdata_o),
      .ls_i     (ls_i),
      .ds_i     (ds_i),
      .sd_i     (sd_i)
    );
  end else if (TECH == sram_pkg::TECH_SAED32) begin : g_saed32
    sram_macro_dp_saed32 #(
      .MAC_W(MAC_W),
      .MAC_D(MAC_D)
    ) u_leaf (
      .clk      (clk),
      .a_cs_i   (a_cs_i),
      .a_we_i   (a_we_i),
      .a_addr_i (a_addr_i),
      .a_wdata_i(a_wdata_i),
      .a_wbe_i  (a_wbe_i),
      .a_rdata_o(a_rdata_o),
      .b_cs_i   (b_cs_i),
      .b_we_i   (b_we_i),
      .b_addr_i (b_addr_i),
      .b_wdata_i(b_wdata_i),
      .b_wbe_i  (b_wbe_i),
      .b_rdata_o(b_rdata_o),
      .ls_i     (ls_i),
      .ds_i     (ds_i),
      .sd_i     (sd_i)
    );
  end else if (TECH == sram_pkg::TECH_SAED14) begin : g_saed14
    sram_macro_dp_saed14 #(
      .MAC_W(MAC_W),
      .MAC_D(MAC_D)
    ) u_leaf (
      .clk      (clk),
      .a_cs_i   (a_cs_i),
      .a_we_i   (a_we_i),
      .a_addr_i (a_addr_i),
      .a_wdata_i(a_wdata_i),
      .a_wbe_i  (a_wbe_i),
      .a_rdata_o(a_rdata_o),
      .b_cs_i   (b_cs_i),
      .b_we_i   (b_we_i),
      .b_addr_i (b_addr_i),
      .b_wdata_i(b_wdata_i),
      .b_wbe_i  (b_wbe_i),
      .b_rdata_o(b_rdata_o),
      .ls_i     (ls_i),
      .ds_i     (ds_i),
      .sd_i     (sd_i)
    );
  end else if (TECH == sram_pkg::TECH_SKY130) begin : g_sky130
    sram_macro_dp_sky130 #(
      .MAC_W(MAC_W),
      .MAC_D(MAC_D)
    ) u_leaf (
      .clk      (clk),
      .a_cs_i   (a_cs_i),
      .a_we_i   (a_we_i),
      .a_addr_i (a_addr_i),
      .a_wdata_i(a_wdata_i),
      .a_wbe_i  (a_wbe_i),
      .a_rdata_o(a_rdata_o),
      .b_cs_i   (b_cs_i),
      .b_we_i   (b_we_i),
      .b_addr_i (b_addr_i),
      .b_wdata_i(b_wdata_i),
      .b_wbe_i  (b_wbe_i),
      .b_rdata_o(b_rdata_o),
      .ls_i     (ls_i),
      .ds_i     (ds_i),
      .sd_i     (sd_i)
    );
  end else if (TECH == sram_pkg::TECH_XILINX) begin : g_xilinx
    sram_macro_dp_xilinx #(
      .MAC_W    (MAC_W),
      .MAC_D    (MAC_D),
      .INIT_FILE(INIT_FILE)
    ) u_leaf (
      .clk      (clk),
      .a_cs_i   (a_cs_i),
      .a_we_i   (a_we_i),
      .a_addr_i (a_addr_i),
      .a_wdata_i(a_wdata_i),
      .a_wbe_i  (a_wbe_i),
      .a_rdata_o(a_rdata_o),
      .b_cs_i   (b_cs_i),
      .b_we_i   (b_we_i),
      .b_addr_i (b_addr_i),
      .b_wdata_i(b_wdata_i),
      .b_wbe_i  (b_wbe_i),
      .b_rdata_o(b_rdata_o),
      .ls_i     (ls_i),
      .ds_i     (ds_i),
      .sd_i     (sd_i)
    );
  end else if (TECH == sram_pkg::TECH_ALTERA) begin : g_altera
    sram_macro_dp_altera #(
      .MAC_W    (MAC_W),
      .MAC_D    (MAC_D),
      .INIT_FILE(INIT_FILE)
    ) u_leaf (
      .clk      (clk),
      .a_cs_i   (a_cs_i),
      .a_we_i   (a_we_i),
      .a_addr_i (a_addr_i),
      .a_wdata_i(a_wdata_i),
      .a_wbe_i  (a_wbe_i),
      .a_rdata_o(a_rdata_o),
      .b_cs_i   (b_cs_i),
      .b_we_i   (b_we_i),
      .b_addr_i (b_addr_i),
      .b_wdata_i(b_wdata_i),
      .b_wbe_i  (b_wbe_i),
      .b_rdata_o(b_rdata_o),
      .ls_i     (ls_i),
      .ds_i     (ds_i),
      .sd_i     (sd_i)
    );
  end else begin : g_generic
    sram_macro_dp_generic #(
      .MAC_W    (MAC_W),
      .MAC_D    (MAC_D),
      .INIT_FILE(INIT_FILE)
    ) u_leaf (
      .clk      (clk),
      .a_cs_i   (a_cs_i),
      .a_we_i   (a_we_i),
      .a_addr_i (a_addr_i),
      .a_wdata_i(a_wdata_i),
      .a_wbe_i  (a_wbe_i),
      .a_rdata_o(a_rdata_o),
      .b_cs_i   (b_cs_i),
      .b_we_i   (b_we_i),
      .b_addr_i (b_addr_i),
      .b_wdata_i(b_wdata_i),
      .b_wbe_i  (b_wbe_i),
      .b_rdata_o(b_rdata_o),
      .ls_i     (ls_i),
      .ds_i     (ds_i),
      .sd_i     (sd_i)
    );
  end

endmodule : sram_macro_dp
