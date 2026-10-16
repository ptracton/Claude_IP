// sram_macro_altera.sv — Intel/Altera altsyncram single-port RAM tile (TECH_ALTERA).
//
// Wraps altsyncram (altera_mf library) in SINGLE_PORT mode, targeting M10K
// blocks on Cyclone V, with byte enables and an unregistered output (one
// cycle of read latency from the input registers).
//   clock0 = clk, clocken0 = cs_i (the block is clock-gated when not
//   selected, which is also its only low-power mode), wren_a = we_i,
//   byteena_a = wbe_i, address_a, data_a, q_a.
// M10K has no sleep pins: ls_i/ds_i/sd_i are not needed (the core never
// selects a sleeping tile, so clocken0 is already low).
// Only elaborated on a host with Quartus/ModelSim (altera_mf); elsewhere
// TECH GENERIC infers the same behaviour.

module sram_macro_altera #(
  parameter int unsigned MAC_W     = 32,   // word width (multiple of 8)
  parameter int unsigned MAC_D     = 1024, // words
  parameter string       INIT_FILE = ""    // optional preload (.mif / .hex)
) (
  input  logic                     clk,       // clock
  input  logic                     cs_i,      // chip select
  input  logic                     we_i,      // 1 = write, 0 = read
  input  logic [$clog2(MAC_D)-1:0] addr_i,    // word address
  input  logic [MAC_W-1:0]         wdata_i,   // write data
  input  logic [MAC_W/8-1:0]       wbe_i,     // byte write enables
  // M10K blocks have no sleep pins (see header).
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                     ls_i,      // light sleep (unused)
  input  logic                     ds_i,      // deep sleep (unused)
  input  logic                     sd_i,      // shutdown (unused)
  /* verilator lint_on UNUSEDSIGNAL */
  output logic [MAC_W-1:0]         rdata_o    // read data
);

  localparam string InitFile = (INIT_FILE == "") ? "UNUSED" : INIT_FILE;

  altsyncram #(
    .operation_mode               ("SINGLE_PORT"),
    .intended_device_family       ("Cyclone V"),
    .ram_block_type               ("M10K"),
    .lpm_type                     ("altsyncram"),
    .width_a                      (MAC_W),
    .widthad_a                    ($clog2(MAC_D)),
    .numwords_a                   (MAC_D),
    .width_byteena_a              (MAC_W / 8),
    .byte_size                    (8),
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
    .byteena_a(wbe_i),
    .q_a      (rdata_o)
  );

endmodule : sram_macro_altera
