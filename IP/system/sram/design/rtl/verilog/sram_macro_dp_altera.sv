// sram_macro_dp_altera.sv — Intel/Altera altsyncram true dual-port wrapper
// (TECH_ALTERA, DUAL_PORT).
//
// One altsyncram of W x D in BIDIR_DUAL_PORT mode (M10K, Cyclone V): one
// clock (clock0) with COMMON_CLK, else clock0 = a_clk and clock1 = b_clk.
// Quartus cascades the blocks itself, so the wrapper is not tiled.
// Lane enables (byte_size = W / NLANES) on both ports, unregistered outputs
// (one cycle of read latency).
// Clock enables: clocken0 = a_cs_i | b_cs_i with COMMON_CLK, else a_cs_i /
// b_cs_i on clocken0 / clocken1. No sleep pins on M10K. Only elaborated on a
// host with Quartus/ModelSim (altera_mf).

module sram_macro_dp_altera #(
  parameter int unsigned W          = 32,   // word width
  parameter int unsigned D          = 1024, // words
  parameter int unsigned NLANES     = 4,    // write lanes of W / NLANES bits
  parameter bit          COMMON_CLK = 1,    // 1: a_clk and b_clk are the same clock
  parameter string       INIT_FILE  = ""    // optional preload (.mif / .hex)
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
  // M10K blocks have no sleep pins (see header).
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                 ls_i,        // light sleep (unused)
  input  logic                 ds_i,        // deep sleep (unused)
  input  logic                 sd_i         // shutdown (unused)
  /* verilator lint_on UNUSEDSIGNAL */
);

  localparam string       InitFile = (INIT_FILE == "") ? "UNUSED" : INIT_FILE;
  // Byte size of the enables (unused with one lane, but must be legal).
  localparam int unsigned ByteSize = (NLANES > 1) ? W / NLANES : 8;
  // Port B registers: clock0 with a common clock, else clock1.
  localparam string       ClkB     = COMMON_CLK ? "CLOCK0" : "CLOCK1";

  altsyncram #(
    .operation_mode                    ("BIDIR_DUAL_PORT"),
    .intended_device_family            ("Cyclone V"),
    .ram_block_type                    ("M10K"),
    .lpm_type                          ("altsyncram"),
    .width_a                           (W),
    .width_b                           (W),
    .widthad_a                         ($clog2(D)),
    .widthad_b                         ($clog2(D)),
    .numwords_a                        (D),
    .numwords_b                        (D),
    .width_byteena_a                   (NLANES),
    .width_byteena_b                   (NLANES),
    .byte_size                         (ByteSize),
    .address_reg_b                     (ClkB),
    .indata_reg_b                      (ClkB),
    .wrcontrol_wraddress_reg_b         (ClkB),
    .byteena_reg_b                     (ClkB),
    .outdata_reg_a                     ("UNREGISTERED"),
    .outdata_reg_b                     ("UNREGISTERED"),
    .outdata_aclr_a                    ("NONE"),
    .outdata_aclr_b                    ("NONE"),
    .clock_enable_input_a              ("NORMAL"),
    .clock_enable_input_b              ("NORMAL"),
    .clock_enable_output_a             ("BYPASS"),
    .clock_enable_output_b             ("BYPASS"),
    .read_during_write_mode_mixed_ports("OLD_DATA"),
    .read_during_write_mode_port_a     ("NEW_DATA_NO_NBE_READ"),
    .read_during_write_mode_port_b     ("NEW_DATA_NO_NBE_READ"),
    .power_up_uninitialized            ("FALSE"),
    .init_file                         (InitFile)
  // Deviation: only the ports this mode uses are connected. altsyncram has
  // about 40 optional ports (ECC, clears, second clock) with defaults.
  ) u_altsyncram (
    .clock0   (a_clk),
    .clocken0 (COMMON_CLK ? (a_cs_i | b_cs_i) : a_cs_i),
    .clock1   (b_clk),
    .clocken1 (COMMON_CLK ? 1'b1 : b_cs_i),
    .address_a(a_addr_i),
    .data_a   (a_wdata_i),
    .wren_a   (a_we_i),
    .byteena_a(a_lane_we_i),
    .q_a      (a_rdata_o),
    .address_b(b_addr_i),
    .data_b   (b_wdata_i),
    .wren_b   (b_we_i),
    .byteena_b(b_lane_we_i),
    .q_b      (b_rdata_o)
  );

endmodule : sram_macro_dp_altera
