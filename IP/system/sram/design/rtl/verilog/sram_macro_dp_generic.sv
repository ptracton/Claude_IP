// sram_macro_dp_generic.sv — Behavioral two-port RAM tile (TECH_GENERIC, DUAL_PORT).
//
// Synchronous true dual-port RAM on one clock: per-byte writes and a
// one-cycle registered read on each port (read data valid in the cycle after
// a read, held until that port's next read). Written so FPGA tools infer a
// true dual-port block RAM. The core never lets both ports touch the same
// word in one cycle when either writes; if it happened, port B's write would
// win in simulation.
// Power pins as in sram_macro_generic: retention only; a rising sd_i turns
// every word into X in simulation.

module sram_macro_dp_generic #(
  parameter int unsigned MAC_W     = 32,   // word width (multiple of 8)
  parameter int unsigned MAC_D     = 1024, // words
  parameter string       INIT_FILE = ""    // optional $readmemh preload
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
  // Retention-only for this tile; shutdown is simulation-only.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                     ls_i,      // light sleep (unused)
  input  logic                     ds_i,      // deep sleep (unused)
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic                     sd_i       // shutdown (simulation only)
);

  logic [MAC_W-1:0] mem [MAC_D];
  logic             sd_q;  // sd_i last cycle (edge detect, simulation only)

  initial begin : p_init
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end
  end

  // Both ports' writes and registered reads (one process: one array driver).
  always_ff @(posedge clk) begin : p_ram
    if (a_cs_i) begin
      if (a_we_i) begin
        for (int unsigned b = 0; b < MAC_W / 8; b++) begin
          if (a_wbe_i[b]) begin
            mem[a_addr_i][8*b +: 8] <= a_wdata_i[8*b +: 8];
          end
        end
      end else begin
        a_rdata_o <= mem[a_addr_i];
      end
    end
    if (b_cs_i) begin
      if (b_we_i) begin
        for (int unsigned b = 0; b < MAC_W / 8; b++) begin
          if (b_wbe_i[b]) begin
            mem[b_addr_i][8*b +: 8] <= b_wdata_i[8*b +: 8];
          end
        end
      end else begin
        b_rdata_o <= mem[b_addr_i];
      end
    end
    sd_q <= sd_i;
    // synopsys translate_off
    // Deviation: X assignment, simulation only — models loss of contents
    // when the tile is shut down (power switched off).
    if (sd_i && !sd_q) begin
      for (int unsigned w = 0; w < MAC_D; w++) begin
        mem[w] <= 'x;
      end
    end
    // synopsys translate_on
  end

endmodule : sram_macro_dp_generic
