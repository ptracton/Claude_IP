// sram_macro_xilinx.sv — Xilinx XPM single-port RAM tile (TECH_XILINX).
//
// Wraps xpm_memory_spram (Vivado XPM library): block RAM / UltraRAM chosen by
// Vivado (MEMORY_PRIMITIVE = "auto"), one-cycle read latency, byte writes.
//   ena  = cs_i, wea = we_i ? wbe_i : 0, addra, dina, douta.
//   sleep = ls_i | ds_i | sd_i with WAKEUP_TIME = "use_sleep_pin": the
//   dynamic power-down of the block RAM. The core never accesses a sleeping
//   tile, which XPM requires.
// Only elaborated on a host with Vivado (the XPM library); elsewhere TECH
// GENERIC infers the same behaviour.

module sram_macro_xilinx #(
  parameter int unsigned MAC_W     = 32,   // word width (multiple of 8)
  parameter int unsigned MAC_D     = 1024, // words
  parameter string       INIT_FILE = ""    // optional preload (.mem, hex)
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
  output logic [MAC_W-1:0]         rdata_o    // read data
);

  localparam string InitFile = (INIT_FILE == "") ? "none" : INIT_FILE;

  logic [MAC_W/8-1:0] wea;
  logic               sleep;

  assign wea   = we_i ? wbe_i : '0;
  assign sleep = ls_i | ds_i | sd_i;

  xpm_memory_spram #(
    .ADDR_WIDTH_A       ($clog2(MAC_D)),
    .AUTO_SLEEP_TIME    (0),
    .BYTE_WRITE_WIDTH_A (8),
    .ECC_MODE           ("no_ecc"),
    .MEMORY_INIT_FILE   (InitFile),
    .MEMORY_INIT_PARAM  ("0"),
    .MEMORY_OPTIMIZATION("true"),
    .MEMORY_PRIMITIVE   ("auto"),
    .MEMORY_SIZE        (MAC_W * MAC_D),
    .MESSAGE_CONTROL    (0),
    .READ_DATA_WIDTH_A  (MAC_W),
    .READ_LATENCY_A     (1),
    .READ_RESET_VALUE_A ("0"),
    .RST_MODE_A         ("SYNC"),
    .USE_MEM_INIT       (1),
    .WAKEUP_TIME        ("use_sleep_pin"),
    .WRITE_DATA_WIDTH_A (MAC_W),
    .WRITE_MODE_A       ("read_first")
  ) u_xpm (
    .clka          (clk),
    .rsta          (1'b0),
    .ena           (cs_i),
    .regcea        (1'b1),
    .wea           (wea),
    .addra         (addr_i),
    .dina          (wdata_i),
    .douta         (rdata_o),
    .sleep         (sleep),
    .injectsbiterra(1'b0),
    .injectdbiterra(1'b0),
    .sbiterra      (),
    .dbiterra      ()
  );

endmodule : sram_macro_xilinx
