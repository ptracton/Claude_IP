// sram_macro_dp_sky130.sv — SKY130 OpenRAM macro tile (TECH_SKY130, DUAL_PORT).
//
// The same 1rw1r macros as sram_macro_sky130 with both ports used:
//   port 0 = port A, read/write: clk0, csb0 = ~a_cs_i, web0 = ~a_we_i,
//            wmask0 = a_wbe_i, addr0, din0, dout0
//   port 1 = port B, READ ONLY:  clk1, csb1 = ~b_cs_i, addr1, dout1
// The core turns every port-B write into a bus error for this technology
// (sram_port READ_ONLY), so b_we_i / b_wdata_i / b_wbe_i are never needed.
// Read data is valid in the cycle after a read; simulation clock period
// must exceed ~8 ns. No sleep pins (UPF).

module sram_macro_dp_sky130 #(
  parameter int unsigned MAC_W = 32,  // macro word width
  parameter int unsigned MAC_D = 512  // macro words
) (
  input  logic                     clk,       // clock (both ports)
  input  logic                     a_cs_i,    // port A chip select
  input  logic                     a_we_i,    // port A 1 = write
  input  logic [$clog2(MAC_D)-1:0] a_addr_i,  // port A word address
  input  logic [MAC_W-1:0]         a_wdata_i, // port A write data
  input  logic [MAC_W/8-1:0]       a_wbe_i,   // port A byte write enables
  output logic [MAC_W-1:0]         a_rdata_o, // port A read data
  input  logic                     b_cs_i,    // port B chip select
  // Port B is read-only on this macro (see header).
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                     b_we_i,    // port B 1 = write (unused)
  input  logic [$clog2(MAC_D)-1:0] b_addr_i,  // port B word address
  input  logic [MAC_W-1:0]         b_wdata_i, // port B write data (unused)
  input  logic [MAC_W/8-1:0]       b_wbe_i,   // port B byte write enables (unused)
  /* verilator lint_on UNUSEDSIGNAL */
  output logic [MAC_W-1:0]         b_rdata_o, // port B read data
  // No sleep pins on this macro family: power is controlled through UPF.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                     ls_i,      // light sleep (unused)
  input  logic                     ds_i,      // deep sleep (unused)
  input  logic                     sd_i       // shutdown (unused)
  /* verilator lint_on UNUSEDSIGNAL */
);

  logic a_csb, b_csb;  // chip selects, active low
  logic a_web;         // port A write enable, active low

  assign a_csb = ~a_cs_i;
  assign b_csb = ~b_cs_i;
  assign a_web = ~a_we_i;

  // One branch per supported size (sram_pkg::macro_depth_dp only picks these).
  if (MAC_W == 32 && MAC_D == 256) begin : g_32x256
    sky130_sram_1kbyte_1rw1r_32x256_8 #(
      .VERBOSE(0)
    ) u_macro (
      .clk0  (clk),
      .csb0  (a_csb),
      .web0  (a_web),
      .wmask0(a_wbe_i),
      .addr0 (a_addr_i),
      .din0  (a_wdata_i),
      .dout0 (a_rdata_o),
      .clk1  (clk),
      .csb1  (b_csb),
      .addr1 (b_addr_i),
      .dout1 (b_rdata_o)
    );
  end else if (MAC_W == 32 && MAC_D == 512) begin : g_32x512
    sky130_sram_2kbyte_1rw1r_32x512_8 #(
      .VERBOSE(0)
    ) u_macro (
      .clk0  (clk),
      .csb0  (a_csb),
      .web0  (a_web),
      .wmask0(a_wbe_i),
      .addr0 (a_addr_i),
      .din0  (a_wdata_i),
      .dout0 (a_rdata_o),
      .clk1  (clk),
      .csb1  (b_csb),
      .addr1 (b_addr_i),
      .dout1 (b_rdata_o)
    );
  end else if (MAC_W == 8 && MAC_D == 1024) begin : g_8x1024
    sky130_sram_1kbyte_1rw1r_8x1024_8 #(
      .VERBOSE(0)
    ) u_macro (
      .clk0  (clk),
      .csb0  (a_csb),
      .web0  (a_web),
      .wmask0(a_wbe_i),
      .addr0 (a_addr_i),
      .din0  (a_wdata_i),
      .dout0 (a_rdata_o),
      .clk1  (clk),
      .csb1  (b_csb),
      .addr1 (b_addr_i),
      .dout1 (b_rdata_o)
    );
  end else begin : g_unsupported
    // Elaboration-time error: no macro of this size in the curated list.
    initial $fatal(1, "sram_macro_dp_sky130: no %0dx%0d macro", MAC_W, MAC_D);
    assign a_rdata_o = '0;
    assign b_rdata_o = '0;
  end

endmodule : sram_macro_dp_sky130
