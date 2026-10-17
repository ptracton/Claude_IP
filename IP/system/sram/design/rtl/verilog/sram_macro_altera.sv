// sram_macro_altera.sv — Intel/Altera altsyncram single-port RAM wrapper (TECH_ALTERA).
//
// Wraps one altsyncram (altera_mf library) of W x D in SINGLE_PORT mode,
// targeting M10K blocks on Cyclone V; Quartus cascades the blocks itself, so
// the wrapper is not tiled. Lane enables (byte_size = W / NLANES) and an
// unregistered output (one cycle of read latency from the input registers).
//   clock0 = clk, clocken0 = cs_i (the block is clock-gated when not
//   selected, which is also its only low-power mode), wren_a = we_i,
//   byteena_a = lane_we_i, address_a, data_a, q_a.
// M10K has no sleep pins: ls_i/ds_i/sd_i are not needed (the core never
// selects a sleeping memory, so clocken0 is already low).
// Only elaborated on a host with Quartus/ModelSim (altera_mf); elsewhere
// TECH GENERIC infers the same behaviour.

module sram_macro_altera #(
  parameter int unsigned W         = 32,   // word width
  parameter int unsigned D         = 1024, // words
  parameter int unsigned NLANES    = 4,    // write lanes of W / NLANES bits
  parameter string       INIT_FILE = ""    // optional preload (.mif / .hex)
) (
  input  logic                 clk,       // clock
  input  logic                 cs_i,      // chip select
  input  logic                 we_i,      // 1 = write, 0 = read
  input  logic [$clog2(D)-1:0] addr_i,    // word address
  input  logic [W-1:0]         wdata_i,   // write data
  input  logic [NLANES-1:0]    lane_we_i, // lanes to write
  // M10K blocks have no sleep pins (see header).
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                 ls_i,      // light sleep (unused)
  input  logic                 ds_i,      // deep sleep (unused)
  input  logic                 sd_i,      // shutdown (unused)
  /* verilator lint_on UNUSEDSIGNAL */
  output logic [W-1:0]         rdata_o    // read data (cycle after a read)
);

  localparam string       InitFile = (INIT_FILE == "") ? "UNUSED" : INIT_FILE;
  // Byte size of the enables (unused with one lane, but must be legal).
  localparam int unsigned ByteSize = (NLANES > 1) ? W / NLANES : 8;

  altsyncram #(
    .operation_mode               ("SINGLE_PORT"),
    .intended_device_family       ("Cyclone V"),
    .ram_block_type               ("M10K"),
    .lpm_type                     ("altsyncram"),
    .width_a                      (W),
    .widthad_a                    ($clog2(D)),
    .numwords_a                   (D),
    .width_byteena_a              (NLANES),
    .byte_size                    (ByteSize),
    .outdata_reg_a                ("UNREGISTERED"),
    .outdata_aclr_a               ("NONE"),
    .clock_enable_input_a         ("NORMAL"),
    .clock_enable_output_a        ("BYPASS"),
    .read_during_write_mode_port_a("NEW_DATA_NO_NBE_READ"),
    .power_up_uninitialized       ("FALSE"),
    .init_file                    (InitFile)
  // Deviation: only the ports this mode uses are connected. altsyncram has
  // about 40 optional ports (port B, ECC, clears) with defaults in altera_mf.
  ) u_altsyncram (
    .clock0   (clk),
    .clocken0 (cs_i),
    .address_a(addr_i),
    .data_a   (wdata_i),
    .wren_a   (we_i),
    .byteena_a(lane_we_i),
    .q_a      (rdata_o)
  );

endmodule : sram_macro_altera
