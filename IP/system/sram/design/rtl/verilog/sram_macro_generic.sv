// sram_macro_generic.sv — Behavioral single-port RAM tile (TECH_GENERIC).
//
// Synchronous single-port RAM with per-byte write enables and a one-cycle
// registered read, written so FPGA tools and Yosys infer block RAM. Used for
// simulation and formal on any host, and as the portable FPGA fallback.
//
// Read data (rdata_o) is valid in the cycle after a read (cs_i & !we_i) and
// holds until the next read. A write does not change rdata_o.
//
// Power pins: ls_i / ds_i keep the contents (callers never access a sleeping
// tile). In simulation only, a rising sd_i (shutdown) turns every word into
// X, so software that relies on contents across shutdown fails visibly.

module sram_macro_generic #(
  parameter int unsigned MAC_W     = 32,   // word width (multiple of 8)
  parameter int unsigned MAC_D     = 1024, // words
  parameter string       INIT_FILE = ""    // optional $readmemh preload
) (
  input  logic                       clk,       // clock
  input  logic                       cs_i,      // chip select
  input  logic                       we_i,      // 1 = write, 0 = read
  input  logic [$clog2(MAC_D)-1:0]   addr_i,    // word address
  input  logic [MAC_W-1:0]           wdata_i,   // write data
  input  logic [MAC_W/8-1:0]         wbe_i,     // byte write enables
  // Sleep pins are retention-only for this tile; shutdown is simulation-only.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                       ls_i,      // light sleep
  input  logic                       ds_i,      // deep sleep
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic                       sd_i,      // shutdown
  output logic [MAC_W-1:0]           rdata_o    // read data
);

  logic [MAC_W-1:0] mem [MAC_D];
  logic             sd_q;  // sd_i last cycle (edge detect, simulation only)

  initial begin : p_init
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end
  end

  // Synchronous write (per byte) and registered read.
  always_ff @(posedge clk) begin : p_ram
    if (cs_i) begin
      if (we_i) begin
        for (int unsigned b = 0; b < MAC_W / 8; b++) begin
          if (wbe_i[b]) begin
            mem[addr_i][8*b +: 8] <= wdata_i[8*b +: 8];
          end
        end
      end else begin
        rdata_o <= mem[addr_i];
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

endmodule : sram_macro_generic
