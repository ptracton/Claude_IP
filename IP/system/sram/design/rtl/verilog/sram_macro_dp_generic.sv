// sram_macro_dp_generic.sv — Behavioral two-port RAM wrapper (TECH_GENERIC, DUAL_PORT).
//
// Synchronous W x D true dual-port RAM, each port on its own clock: per-lane
// writes and a one-cycle registered read on each port (read data valid in
// the cycle after a read, held until that port's next read). Written in the
// FPGA tools' true dual-port (dual-clock) block-RAM template; nothing is
// tiled here. With COMMON_CLK the core never lets both ports touch the same
// word in one cycle when either writes; with separate clocks such a
// collision is undefined (in simulation the later clock edge wins).
// Power pins as in sram_macro_generic: retention only; a rising sd_i
// (sampled on a_clk) turns every word into X in simulation.

module sram_macro_dp_generic #(
  parameter int unsigned W         = 32,   // word width
  parameter int unsigned D         = 1024, // words
  parameter int unsigned NLANES    = 4,    // write lanes of W / NLANES bits
  parameter string       INIT_FILE = ""    // optional $readmemh preload
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
  // Retention-only here; shutdown is simulation-only.
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic                 ls_i,        // light sleep (unused)
  input  logic                 ds_i,        // deep sleep (unused)
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic                 sd_i         // shutdown (simulation only)
);

  localparam int unsigned LaneW = W / NLANES;

  logic [W-1:0] mem [D];
  logic         sd_q;  // sd_i last a_clk cycle (edge detect, simulation only)

  initial begin : p_init
    if (INIT_FILE != "") begin
      $readmemh(INIT_FILE, mem);
    end
  end

  // Deviation: plain always blocks, not always_ff. Both ports write the one
  // array from their own clocks (the dual-clock true dual-port RAM
  // template); always_ff forbids a variable written by two processes.

  // Port A: lane writes and registered read.
  always @(posedge a_clk) begin : p_port_a
    if (a_cs_i) begin
      if (a_we_i) begin
        for (int unsigned l = 0; l < NLANES; l++) begin
          if (a_lane_we_i[l]) begin
            mem[a_addr_i][LaneW*l +: LaneW] <= a_wdata_i[LaneW*l +: LaneW];
          end
        end
      end else begin
        a_rdata_o <= mem[a_addr_i];
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

  // Port B: lane writes and registered read.
  always @(posedge b_clk) begin : p_port_b
    if (b_cs_i) begin
      if (b_we_i) begin
        for (int unsigned l = 0; l < NLANES; l++) begin
          if (b_lane_we_i[l]) begin
            mem[b_addr_i][LaneW*l +: LaneW] <= b_wdata_i[LaneW*l +: LaneW];
          end
        end
      end else begin
        b_rdata_o <= mem[b_addr_i];
      end
    end
  end

endmodule : sram_macro_dp_generic
