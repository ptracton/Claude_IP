// sram_macro_dp_xilinx.sv — Xilinx XPM true dual-port RAM wrapper (TECH_XILINX, DUAL_PORT).
//
// Wraps one xpm_memory_tdpram (Vivado XPM) of W x D, CLOCKING_MODE
// "common_clock" with COMMON_CLK, else "independent_clock" (a_clk / b_clk);
// Vivado cascades block RAMs itself, so the wrapper is not tiled. One-cycle
// read latency and lane writes (W / NLANES bits) on both ports; sleep = ls_i | ds_i | sd_i with
// WAKEUP_TIME = "use_sleep_pin". Only elaborated on a host with Vivado.

module sram_macro_dp_xilinx #(
  parameter int unsigned W          = 32,   // word width
  parameter int unsigned D          = 1024, // words
  parameter int unsigned NLANES     = 4,    // write lanes of W / NLANES bits
  parameter bit          COMMON_CLK = 1,    // 1: a_clk and b_clk are the same clock
  parameter string       INIT_FILE  = ""    // optional preload (.mem)
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

  localparam string InitFile = (INIT_FILE == "") ? "none" : INIT_FILE;

  logic [NLANES-1:0] wea, web;
  logic              sleep;

  assign wea   = a_we_i ? a_lane_we_i : '0;
  assign web   = b_we_i ? b_lane_we_i : '0;
  assign sleep = ls_i | ds_i | sd_i;

  xpm_memory_tdpram #(
    .ADDR_WIDTH_A       ($clog2(D)),
    .ADDR_WIDTH_B       ($clog2(D)),
    .AUTO_SLEEP_TIME    (0),
    .BYTE_WRITE_WIDTH_A (W / NLANES),
    .BYTE_WRITE_WIDTH_B (W / NLANES),
    .CLOCKING_MODE      (COMMON_CLK ? "common_clock" : "independent_clock"),
    .ECC_MODE           ("no_ecc"),
    .MEMORY_INIT_FILE   (InitFile),
    .MEMORY_INIT_PARAM  ("0"),
    .MEMORY_OPTIMIZATION("true"),
    .MEMORY_PRIMITIVE   ("auto"),
    .MEMORY_SIZE        (W * D),
    .MESSAGE_CONTROL    (0),
    .READ_DATA_WIDTH_A  (W),
    .READ_DATA_WIDTH_B  (W),
    .READ_LATENCY_A     (1),
    .READ_LATENCY_B     (1),
    .READ_RESET_VALUE_A ("0"),
    .READ_RESET_VALUE_B ("0"),
    .RST_MODE_A         ("SYNC"),
    .RST_MODE_B         ("SYNC"),
    .USE_MEM_INIT       (1),
    .WAKEUP_TIME        ("use_sleep_pin"),
    .WRITE_DATA_WIDTH_A (W),
    .WRITE_DATA_WIDTH_B (W),
    .WRITE_MODE_A       ("read_first"),
    .WRITE_MODE_B       ("read_first")
  ) u_xpm (
    .clka          (a_clk),
    .clkb          (b_clk),
    .rsta          (1'b0),
    .rstb          (1'b0),
    .ena           (a_cs_i),
    .enb           (b_cs_i),
    .regcea        (1'b1),
    .regceb        (1'b1),
    .wea           (wea),
    .web           (web),
    .addra         (a_addr_i),
    .addrb         (b_addr_i),
    .dina          (a_wdata_i),
    .dinb          (b_wdata_i),
    .douta         (a_rdata_o),
    .doutb         (b_rdata_o),
    .sleep         (sleep),
    .injectsbiterra(1'b0),
    .injectdbiterra(1'b0),
    .injectsbiterrb(1'b0),
    .injectdbiterrb(1'b0),
    .sbiterra      (),
    .dbiterra      (),
    .sbiterrb      (),
    .dbiterrb      ()
  );

endmodule : sram_macro_dp_xilinx
