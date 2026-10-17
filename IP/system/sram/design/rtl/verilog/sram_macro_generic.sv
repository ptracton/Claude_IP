// sram_macro_generic.sv — Behavioral single-port RAM wrapper (TECH_GENERIC).
//
// Synchronous W x D single-port RAM with per-lane write enables and a
// one-cycle registered read, written so FPGA tools and Yosys infer block RAM.
// Nothing is tiled here: the tool builds any W x D from its block RAMs. Used
// for simulation and formal on any host, and as the portable FPGA fallback.
//
// Read data (rdata_o) is valid in the cycle after a read (cs_i & !we_i) and
// holds until the next read. A write does not change rdata_o.
//
// Power pins: ls_i / ds_i keep the contents (callers never access a sleeping
// memory). In simulation only, a rising sd_i (shutdown) turns every word into
// X, so software that relies on contents across shutdown fails visibly.

module sram_macro_generic #(
  parameter int unsigned W         = 32,   // word width
  parameter int unsigned D         = 1024, // words
  parameter int unsigned NLANES    = 4,    // write lanes of W / NLANES bits
  parameter string       INIT_FILE = ""    // optional $readmemh preload
) (
  input  logic                 clk,       // clock
  input  logic                 cs_i,      // chip select
  input  logic                 we_i,      // 1 = write, 0 = read
  input  logic [$clog2(D)-1:0] addr_i,    // word address
  input  logic [W-1:0]         wdata_i,   // write data
  input  logic [NLANES-1:0]    lane_we_i, // lanes to write
  // Sleep pins are retention-only here; shutdown is simulation-only.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                 ls_i,      // light sleep
  input  logic                 ds_i,      // deep sleep
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic                 sd_i,      // shutdown
  output logic [W-1:0]         rdata_o    // read data (cycle after a read)
);

  localparam int unsigned LaneW = W / NLANES;

  logic [W-1:0] mem [D];
  logic         sd_q;  // sd_i last cycle (edge detect, simulation only)

  initial begin : p_init
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end
  end

  // Synchronous write (per lane) and registered read.
  always_ff @(posedge clk) begin : p_ram
    if (cs_i) begin
      if (we_i) begin
        for (int unsigned l = 0; l < NLANES; l++) begin
          if (lane_we_i[l]) begin
            mem[addr_i][LaneW*l +: LaneW] <= wdata_i[LaneW*l +: LaneW];
          end
        end
      end else begin
        rdata_o <= mem[addr_i];
      end
    end
    sd_q <= sd_i;
    // synopsys translate_off
    // Deviation: X assignment, simulation only — models loss of contents
    // when the memory is shut down (power switched off).
    if (sd_i && !sd_q) begin
      for (int unsigned i = 0; i < D; i++) begin
        mem[i] <= 'x;
      end
    end
    // synopsys translate_on
  end

endmodule : sram_macro_generic
