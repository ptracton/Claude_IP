// sram_macro_sky130.sv — SkyWater SKY130 OpenRAM macro tile (TECH_SKY130).
//
// One OpenRAM 1rw1r macro of MAC_W x MAC_D from libs.ref/sky130_sram_macros,
// chosen by sram_pkg::macro_width/macro_depth:
//   32 x 256   sky130_sram_1kbyte_1rw1r_32x256_8   (wmask0[3:0], one per byte)
//   32 x 512   sky130_sram_2kbyte_1rw1r_32x512_8   (wmask0[3:0])
//    8 x 1024  sky130_sram_1kbyte_1rw1r_8x1024_8   (wmask0[0])
//
// Pin mapping (port 0 = read/write; port 1 = read-only, unused here):
//   clk0 = clk, csb0 = ~cs_i, web0 = ~we_i (both active low),
//   wmask0 = wbe_i (native byte mask), addr0, din0, dout0.
//   clk1 = clk, csb1 = 1 (deselected), addr1 = 0; dout1 left open.
//   vccd1/vssd1 exist only with USE_POWER_PINS (not used in RTL).
// The model latches inputs on the rising edge and drives dout0 a few ns
// after the falling edge; it goes X shortly after the next rising edge, so
// read data is valid exactly in the cycle after the read. The clock period
// must exceed ~8 ns in simulation (model DELAY = 3 ns after the falling edge).
// VERBOSE = 0 silences the model's per-access messages.
//
// No sleep pins: power is controlled through UPF.

module sram_macro_sky130 #(
  parameter int unsigned MAC_W = 32,  // macro word width
  parameter int unsigned MAC_D = 512  // macro words
) (
  input  logic                     clk,       // clock
  input  logic                     cs_i,      // chip select
  input  logic                     we_i,      // 1 = write, 0 = read
  input  logic [$clog2(MAC_D)-1:0] addr_i,    // word address
  input  logic [MAC_W-1:0]         wdata_i,   // write data
  input  logic [MAC_W/8-1:0]       wbe_i,     // byte write enables (native mask)
  // No sleep pins on this macro family: power is controlled through UPF.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                     ls_i,      // light sleep (unused)
  input  logic                     ds_i,      // deep sleep (unused)
  input  logic                     sd_i,      // shutdown (unused)
  /* verilator lint_on UNUSEDSIGNAL */
  output logic [MAC_W-1:0]         rdata_o    // read data
);

  logic csb;  // chip select, active low
  logic web;  // write enable, active low

  assign csb = ~cs_i;
  assign web = ~we_i;

  // One branch per supported size (sram_pkg::macro_depth only picks these).
  if (MAC_W == 32 && MAC_D == 256) begin : g_32x256
    sky130_sram_1kbyte_1rw1r_32x256_8 #(
      .VERBOSE(0)
    ) u_macro (
      .clk0  (clk),
      .csb0  (csb),
      .web0  (web),
      .wmask0(wbe_i),
      .addr0 (addr_i),
      .din0  (wdata_i),
      .dout0 (rdata_o),
      .clk1  (clk),
      .csb1  (1'b1),
      .addr1 ('0),
      .dout1 ()
    );
  end else if (MAC_W == 32 && MAC_D == 512) begin : g_32x512
    sky130_sram_2kbyte_1rw1r_32x512_8 #(
      .VERBOSE(0)
    ) u_macro (
      .clk0  (clk),
      .csb0  (csb),
      .web0  (web),
      .wmask0(wbe_i),
      .addr0 (addr_i),
      .din0  (wdata_i),
      .dout0 (rdata_o),
      .clk1  (clk),
      .csb1  (1'b1),
      .addr1 ('0),
      .dout1 ()
    );
  end else if (MAC_W == 8 && MAC_D == 1024) begin : g_8x1024
    sky130_sram_1kbyte_1rw1r_8x1024_8 #(
      .VERBOSE(0)
    ) u_macro (
      .clk0  (clk),
      .csb0  (csb),
      .web0  (web),
      .wmask0(wbe_i),
      .addr0 (addr_i),
      .din0  (wdata_i),
      .dout0 (rdata_o),
      .clk1  (clk),
      .csb1  (1'b1),
      .addr1 ('0),
      .dout1 ()
    );
  end else begin : g_unsupported
    // Elaboration-time error: no macro of this size in the curated list.
    initial $fatal(1, "sram_macro_sky130: no %0dx%0d macro", MAC_W, MAC_D);
    assign rdata_o = '0;
  end

endmodule : sram_macro_sky130
