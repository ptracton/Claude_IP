// claude_sync.sv — Multi-flop synchronizer for level signals.
//
// Each bit of d_i (from another clock domain) passes through STAGES flops
// on clk. Bits are synchronized independently, so a multi-bit d_i must be
// a set of unrelated levels (or change one bit at a time, e.g. Gray code).
// The source must hold each level for longer than STAGES + 1 destination
// cycles to be seen. Synchronous active-low reset to RST_VAL.
//
// CDC: the first flop (stage_q[0]) is the metastability stage; waive the
// crossing onto it in CDC lint.

module claude_sync #(
  parameter int unsigned WIDTH   = 1,   // independent bits
  parameter int unsigned STAGES  = 2,   // flops per bit (>= 2)
  parameter logic        RST_VAL = 1'b0 // reset value of every bit
) (
  input  logic             clk,    // destination clock
  input  logic             rst_n,  // destination synchronous active-low reset
  input  logic [WIDTH-1:0] d_i,    // asynchronous levels
  output logic [WIDTH-1:0] q_o     // synchronized levels
);

  logic [WIDTH-1:0] stage_q [STAGES];

  // synopsys translate_off
  initial begin : p_param_check
    if (STAGES < 2) $fatal(1, "claude_sync: STAGES must be >= 2");
  end
  // synopsys translate_on

  // Synchronizer chain.
  always_ff @(posedge clk) begin : p_sync
    if (!rst_n) begin
      for (int unsigned i = 0; i < STAGES; i++) begin
        stage_q[i] <= {WIDTH{RST_VAL}};
      end
    end else begin
      stage_q[0] <= d_i;
      for (int unsigned i = 1; i < STAGES; i++) begin
        stage_q[i] <= stage_q[i-1];
      end
    end
  end

  assign q_o = stage_q[STAGES-1];

endmodule : claude_sync
