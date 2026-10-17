// sram_macro_dp.sv — Technology dispatcher for one two-port sram bank (DUAL_PORT).
//
// Two-port counterpart of sram_macro: instantiates sram_macro_dp_<tech>.
// Each port has its own clock (a_clk / b_clk; one clock when COMMON_CLK,
// which only the FPGA primitives need to know), select, write enable,
// address, data and write lanes, with read data valid in the cycle after a
// read. Only the selected branch is elaborated.

module sram_macro_dp #(
  parameter int unsigned TECH       = sram_pkg::TECH_GENERIC, // technology
  parameter int unsigned W          = 32,                     // word width
  parameter int unsigned D          = 1024,                   // words (power of two)
  parameter int unsigned NLANES     = 4,                      // write lanes of W / NLANES bits
  parameter bit          COMMON_CLK = 1,                      // 1: a_clk and b_clk are one clock
  parameter string       INIT_FILE  = ""                      // preload (GENERIC/FPGA)
) (
  input  logic                 a_clk,       // port A clock
  input  logic                 a_cs_i,      // port A chip select
  input  logic                 a_we_i,      // port A 1 = write
  input  logic [$clog2(D)-1:0] a_addr_i,    // port A word address
  input  logic [W-1:0]         a_wdata_i,   // port A write data
  input  logic [NLANES-1:0]    a_lane_we_i, // port A lanes to write
  output logic [W-1:0]         a_rdata_o,   // port A read data
  input  logic                 b_clk,       // port B clock
  input  logic                 b_cs_i,      // port B chip select
  input  logic                 b_we_i,      // port B 1 = write
  input  logic [$clog2(D)-1:0] b_addr_i,    // port B word address
  input  logic [W-1:0]         b_wdata_i,   // port B write data
  input  logic [NLANES-1:0]    b_lane_we_i, // port B lanes to write
  output logic [W-1:0]         b_rdata_o,   // port B read data
  input  logic                 ls_i,        // light sleep
  input  logic                 ds_i,        // deep sleep
  input  logic                 sd_i         // shutdown
);

  if (TECH == sram_pkg::TECH_SAED90) begin : g_saed90
    sram_macro_dp_saed90 #(
      .W     (W),
      .D     (D),
      .NLANES(NLANES)
    ) u_leaf (
      .a_clk      (a_clk),
      .a_cs_i     (a_cs_i),
      .a_we_i     (a_we_i),
      .a_addr_i   (a_addr_i),
      .a_wdata_i  (a_wdata_i),
      .a_lane_we_i(a_lane_we_i),
      .a_rdata_o  (a_rdata_o),
      .b_clk      (b_clk),
      .b_cs_i     (b_cs_i),
      .b_we_i     (b_we_i),
      .b_addr_i   (b_addr_i),
      .b_wdata_i  (b_wdata_i),
      .b_lane_we_i(b_lane_we_i),
      .b_rdata_o  (b_rdata_o),
      .ls_i       (ls_i),
      .ds_i       (ds_i),
      .sd_i       (sd_i)
    );
  end else if (TECH == sram_pkg::TECH_SAED32) begin : g_saed32
    sram_macro_dp_saed32 #(
      .W     (W),
      .D     (D),
      .NLANES(NLANES)
    ) u_leaf (
      .a_clk      (a_clk),
      .a_cs_i     (a_cs_i),
      .a_we_i     (a_we_i),
      .a_addr_i   (a_addr_i),
      .a_wdata_i  (a_wdata_i),
      .a_lane_we_i(a_lane_we_i),
      .a_rdata_o  (a_rdata_o),
      .b_clk      (b_clk),
      .b_cs_i     (b_cs_i),
      .b_we_i     (b_we_i),
      .b_addr_i   (b_addr_i),
      .b_wdata_i  (b_wdata_i),
      .b_lane_we_i(b_lane_we_i),
      .b_rdata_o  (b_rdata_o),
      .ls_i       (ls_i),
      .ds_i       (ds_i),
      .sd_i       (sd_i)
    );
  end else if (TECH == sram_pkg::TECH_SAED14) begin : g_saed14
    sram_macro_dp_saed14 #(
      .W     (W),
      .D     (D),
      .NLANES(NLANES)
    ) u_leaf (
      .a_clk      (a_clk),
      .a_cs_i     (a_cs_i),
      .a_we_i     (a_we_i),
      .a_addr_i   (a_addr_i),
      .a_wdata_i  (a_wdata_i),
      .a_lane_we_i(a_lane_we_i),
      .a_rdata_o  (a_rdata_o),
      .b_clk      (b_clk),
      .b_cs_i     (b_cs_i),
      .b_we_i     (b_we_i),
      .b_addr_i   (b_addr_i),
      .b_wdata_i  (b_wdata_i),
      .b_lane_we_i(b_lane_we_i),
      .b_rdata_o  (b_rdata_o),
      .ls_i       (ls_i),
      .ds_i       (ds_i),
      .sd_i       (sd_i)
    );
  end else if (TECH == sram_pkg::TECH_SKY130) begin : g_sky130
    sram_macro_dp_sky130 #(
      .W     (W),
      .D     (D),
      .NLANES(NLANES)
    ) u_leaf (
      .a_clk      (a_clk),
      .a_cs_i     (a_cs_i),
      .a_we_i     (a_we_i),
      .a_addr_i   (a_addr_i),
      .a_wdata_i  (a_wdata_i),
      .a_lane_we_i(a_lane_we_i),
      .a_rdata_o  (a_rdata_o),
      .b_clk      (b_clk),
      .b_cs_i     (b_cs_i),
      .b_we_i     (b_we_i),
      .b_addr_i   (b_addr_i),
      .b_wdata_i  (b_wdata_i),
      .b_lane_we_i(b_lane_we_i),
      .b_rdata_o  (b_rdata_o),
      .ls_i       (ls_i),
      .ds_i       (ds_i),
      .sd_i       (sd_i)
    );
  end else if (TECH == sram_pkg::TECH_XILINX) begin : g_xilinx
    sram_macro_dp_xilinx #(
      .W         (W),
      .D         (D),
      .NLANES    (NLANES),
      .COMMON_CLK(COMMON_CLK),
      .INIT_FILE (INIT_FILE)
    ) u_leaf (
      .a_clk      (a_clk),
      .a_cs_i     (a_cs_i),
      .a_we_i     (a_we_i),
      .a_addr_i   (a_addr_i),
      .a_wdata_i  (a_wdata_i),
      .a_lane_we_i(a_lane_we_i),
      .a_rdata_o  (a_rdata_o),
      .b_clk      (b_clk),
      .b_cs_i     (b_cs_i),
      .b_we_i     (b_we_i),
      .b_addr_i   (b_addr_i),
      .b_wdata_i  (b_wdata_i),
      .b_lane_we_i(b_lane_we_i),
      .b_rdata_o  (b_rdata_o),
      .ls_i       (ls_i),
      .ds_i       (ds_i),
      .sd_i       (sd_i)
    );
  end else if (TECH == sram_pkg::TECH_ALTERA) begin : g_altera
    sram_macro_dp_altera #(
      .W         (W),
      .D         (D),
      .NLANES    (NLANES),
      .COMMON_CLK(COMMON_CLK),
      .INIT_FILE (INIT_FILE)
    ) u_leaf (
      .a_clk      (a_clk),
      .a_cs_i     (a_cs_i),
      .a_we_i     (a_we_i),
      .a_addr_i   (a_addr_i),
      .a_wdata_i  (a_wdata_i),
      .a_lane_we_i(a_lane_we_i),
      .a_rdata_o  (a_rdata_o),
      .b_clk      (b_clk),
      .b_cs_i     (b_cs_i),
      .b_we_i     (b_we_i),
      .b_addr_i   (b_addr_i),
      .b_wdata_i  (b_wdata_i),
      .b_lane_we_i(b_lane_we_i),
      .b_rdata_o  (b_rdata_o),
      .ls_i       (ls_i),
      .ds_i       (ds_i),
      .sd_i       (sd_i)
    );
  end else begin : g_generic
    sram_macro_dp_generic #(
      .W        (W),
      .D        (D),
      .NLANES   (NLANES),
      .INIT_FILE(INIT_FILE)
    ) u_leaf (
      .a_clk      (a_clk),
      .a_cs_i     (a_cs_i),
      .a_we_i     (a_we_i),
      .a_addr_i   (a_addr_i),
      .a_wdata_i  (a_wdata_i),
      .a_lane_we_i(a_lane_we_i),
      .a_rdata_o  (a_rdata_o),
      .b_clk      (b_clk),
      .b_cs_i     (b_cs_i),
      .b_we_i     (b_we_i),
      .b_addr_i   (b_addr_i),
      .b_wdata_i  (b_wdata_i),
      .b_lane_we_i(b_lane_we_i),
      .b_rdata_o  (b_rdata_o),
      .ls_i       (ls_i),
      .ds_i       (ds_i),
      .sd_i       (sd_i)
    );
  end

endmodule : sram_macro_dp
