// sram_macro.sv — Technology dispatcher for one sram bank.
//
// Instantiates the wrapper for TECH (sram_pkg::TECH_*). All wrappers share
// this port list: a synchronous single-port RAM of any W x D (D a power of
// two) with NLANES write lanes, read data valid in the cycle after a read,
// and the three sleep pins (used only by technologies that have them).
// The ASIC wrappers tile their vendor primitives into rows and columns;
// GENERIC / XILINX / ALTERA infer one memory and leave tiling to the tool.
// Only the selected branch is elaborated, so a host only needs the macro
// library (or XPM / altera_mf) of the technology it builds.

module sram_macro #(
  parameter int unsigned TECH      = sram_pkg::TECH_GENERIC, // technology
  parameter int unsigned W         = 32,                     // word width
  parameter int unsigned D         = 1024,                   // words (power of two)
  parameter int unsigned NLANES    = 4,                      // write lanes of W / NLANES bits
  parameter string       INIT_FILE = ""                      // preload (GENERIC/FPGA)
) (
  input  logic                 clk,       // clock
  input  logic                 cs_i,      // chip select
  input  logic                 we_i,      // 1 = write, 0 = read
  input  logic [$clog2(D)-1:0] addr_i,    // word address
  input  logic [W-1:0]         wdata_i,   // write data
  input  logic [NLANES-1:0]    lane_we_i, // lanes to write
  input  logic                 ls_i,      // light sleep
  input  logic                 ds_i,      // deep sleep
  input  logic                 sd_i,      // shutdown
  output logic [W-1:0]         rdata_o    // read data (cycle after a read)
);

  if (TECH == sram_pkg::TECH_SAED90) begin : g_saed90
    sram_macro_saed90 #(
      .W     (W),
      .D     (D),
      .NLANES(NLANES)
    ) u_leaf (
      .clk      (clk),
      .cs_i     (cs_i),
      .we_i     (we_i),
      .addr_i   (addr_i),
      .wdata_i  (wdata_i),
      .lane_we_i(lane_we_i),
      .ls_i     (ls_i),
      .ds_i     (ds_i),
      .sd_i     (sd_i),
      .rdata_o  (rdata_o)
    );
  end else if (TECH == sram_pkg::TECH_SAED32) begin : g_saed32
    sram_macro_saed32 #(
      .W     (W),
      .D     (D),
      .NLANES(NLANES)
    ) u_leaf (
      .clk      (clk),
      .cs_i     (cs_i),
      .we_i     (we_i),
      .addr_i   (addr_i),
      .wdata_i  (wdata_i),
      .lane_we_i(lane_we_i),
      .ls_i     (ls_i),
      .ds_i     (ds_i),
      .sd_i     (sd_i),
      .rdata_o  (rdata_o)
    );
  end else if (TECH == sram_pkg::TECH_SAED14) begin : g_saed14
    sram_macro_saed14 #(
      .W     (W),
      .D     (D),
      .NLANES(NLANES)
    ) u_leaf (
      .clk      (clk),
      .cs_i     (cs_i),
      .we_i     (we_i),
      .addr_i   (addr_i),
      .wdata_i  (wdata_i),
      .lane_we_i(lane_we_i),
      .ls_i     (ls_i),
      .ds_i     (ds_i),
      .sd_i     (sd_i),
      .rdata_o  (rdata_o)
    );
  end else if (TECH == sram_pkg::TECH_SKY130) begin : g_sky130
    sram_macro_sky130 #(
      .W     (W),
      .D     (D),
      .NLANES(NLANES)
    ) u_leaf (
      .clk      (clk),
      .cs_i     (cs_i),
      .we_i     (we_i),
      .addr_i   (addr_i),
      .wdata_i  (wdata_i),
      .lane_we_i(lane_we_i),
      .ls_i     (ls_i),
      .ds_i     (ds_i),
      .sd_i     (sd_i),
      .rdata_o  (rdata_o)
    );
  end else if (TECH == sram_pkg::TECH_XILINX) begin : g_xilinx
    sram_macro_xilinx #(
      .W        (W),
      .D        (D),
      .NLANES   (NLANES),
      .INIT_FILE(INIT_FILE)
    ) u_leaf (
      .clk      (clk),
      .cs_i     (cs_i),
      .we_i     (we_i),
      .addr_i   (addr_i),
      .wdata_i  (wdata_i),
      .lane_we_i(lane_we_i),
      .ls_i     (ls_i),
      .ds_i     (ds_i),
      .sd_i     (sd_i),
      .rdata_o  (rdata_o)
    );
  end else if (TECH == sram_pkg::TECH_ALTERA) begin : g_altera
    sram_macro_altera #(
      .W        (W),
      .D        (D),
      .NLANES   (NLANES),
      .INIT_FILE(INIT_FILE)
    ) u_leaf (
      .clk      (clk),
      .cs_i     (cs_i),
      .we_i     (we_i),
      .addr_i   (addr_i),
      .wdata_i  (wdata_i),
      .lane_we_i(lane_we_i),
      .ls_i     (ls_i),
      .ds_i     (ds_i),
      .sd_i     (sd_i),
      .rdata_o  (rdata_o)
    );
  end else begin : g_generic
    sram_macro_generic #(
      .W        (W),
      .D        (D),
      .NLANES   (NLANES),
      .INIT_FILE(INIT_FILE)
    ) u_leaf (
      .clk      (clk),
      .cs_i     (cs_i),
      .we_i     (we_i),
      .addr_i   (addr_i),
      .wdata_i  (wdata_i),
      .lane_we_i(lane_we_i),
      .ls_i     (ls_i),
      .ds_i     (ds_i),
      .sd_i     (sd_i),
      .rdata_o  (rdata_o)
    );
  end

endmodule : sram_macro
