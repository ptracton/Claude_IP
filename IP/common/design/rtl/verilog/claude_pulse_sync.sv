// claude_pulse_sync.sv — Single-cycle pulse crossing between clock domains.
//
// Each src_pulse_i (one src_clk cycle wide) flips a toggle flop in the
// source domain; the toggle is synchronized into dst_clk (claude_sync) and
// every change becomes a one-cycle dst_pulse_o. Pulses closer together
// than about three destination cycles plus one source cycle may merge, so
// use it for events, not counts that must be exact.
// Each domain has its own synchronous active-low reset; reset both
// together.

module claude_pulse_sync #(
  parameter int unsigned STAGES = 2   // synchronizer flops (>= 2)
) (
  input  logic src_clk,      // source clock
  input  logic src_rst_n,    // source synchronous active-low reset
  input  logic src_pulse_i,  // event (one src_clk cycle)
  input  logic dst_clk,      // destination clock
  input  logic dst_rst_n,    // destination synchronous active-low reset
  output logic dst_pulse_o   // event (one dst_clk cycle)
);

  logic src_tgl_q;  // flips on every source pulse
  logic dst_tgl;    // synchronized toggle
  logic dst_tgl_q;  // synchronized toggle, one cycle later

  // Source toggle.
  always_ff @(posedge src_clk) begin : p_src
    if (!src_rst_n) begin
      src_tgl_q <= 1'b0;
    end else if (src_pulse_i) begin
      src_tgl_q <= !src_tgl_q;
    end
  end

  claude_sync #(
    .WIDTH (1),
    .STAGES(STAGES)
  ) u_sync (
    .clk  (dst_clk),
    .rst_n(dst_rst_n),
    .d_i  (src_tgl_q),
    .q_o  (dst_tgl)
  );

  // Destination edge detect.
  always_ff @(posedge dst_clk) begin : p_dst
    if (!dst_rst_n) begin
      dst_tgl_q <= 1'b0;
    end else begin
      dst_tgl_q <= dst_tgl;
    end
  end

  assign dst_pulse_o = dst_tgl ^ dst_tgl_q;

endmodule : claude_pulse_sync
