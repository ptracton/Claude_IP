// sram_macro_dp_altera.sv — Intel/Altera altsyncram true dual-port tile (TECH_ALTERA, DUAL_PORT).
//
// altsyncram in BIDIR_DUAL_PORT mode (M10K, Cyclone V) on one clock, byte
// enables on both ports, unregistered outputs (one cycle of read latency).
// clocken0 = a_cs_i | b_cs_i. No sleep pins on M10K. Only elaborated on a
// host with Quartus/ModelSim (altera_mf).

module sram_macro_dp_altera #(
  parameter int unsigned MAC_W     = 32,   // word width (multiple of 8)
  parameter int unsigned MAC_D     = 1024, // words
  parameter string       INIT_FILE = ""    // optional preload (.mif / .hex)
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
  // M10K blocks have no sleep pins (see header).
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                     ls_i,      // light sleep (unused)
  input  logic                     ds_i,      // deep sleep (unused)
  input  logic                     sd_i       // shutdown (unused)
  /* verilator lint_on UNUSEDSIGNAL */
);

  localparam string InitFile = (INIT_FILE == "") ? "UNUSED" : INIT_FILE;

  altsyncram #(
    .operation_mode                    ("BIDIR_DUAL_PORT"),
    .intended_device_family            ("Cyclone V"),
    .ram_block_type                    ("M10K"),
    .lpm_type                          ("altsyncram"),
    .width_a                           (MAC_W),
    .width_b                           (MAC_W),
    .widthad_a                         ($clog2(MAC_D)),
    .widthad_b                         ($clog2(MAC_D)),
    .numwords_a                        (MAC_D),
    .numwords_b                        (MAC_D),
    .width_byteena_a                   (MAC_W / 8),
    .width_byteena_b                   (MAC_W / 8),
    .byte_size                         (8),
    .address_reg_b                     ("CLOCK0"),
    .indata_reg_b                      ("CLOCK0"),
    .wrcontrol_wraddress_reg_b         ("CLOCK0"),
    .byteena_reg_b                     ("CLOCK0"),
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
    .clock0   (clk),
    .clocken0 (a_cs_i | b_cs_i),
    .address_a(a_addr_i),
    .data_a   (a_wdata_i),
    .wren_a   (a_we_i),
    .byteena_a(a_wbe_i),
    .q_a      (a_rdata_o),
    .address_b(b_addr_i),
    .data_b   (b_wdata_i),
    .wren_b   (b_we_i),
    .byteena_b(b_wbe_i),
    .q_b      (b_rdata_o)
  );

endmodule : sram_macro_dp_altera
