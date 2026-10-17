// sram_cdc.sv — Clock-domain crossing between the sram core (clk_a) and a
// bus port B on its own clock (clk_b), for DUAL_PORT with COMMON_CLK = 0.
//
// The power FSMs, clear engine, BIST and status run on clk_a (port A's
// clock). Port B may only access a power domain while it holds that
// domain's permission, a four-phase handshake per domain:
//
//   A -> B  allow[d]  request: B may start accesses to domain d
//   B -> A  hold[d]   acknowledge: B holds the permission or still has an
//                     access to d in flight (registered on clk_b:
//                     allow seen | access busy)
//
// The core asks for the permission to be given while want[d] is high (the
// domain is in RUN, will stay there, and no engine wants the array).
// allow[d] only changes when it equals hold[d], i.e. after B has
// acknowledged the previous change, so a short want pulse can never leave
// a grant that A has not seen. quiet[d] = !allow[d] && !hold[d]: B has
// seen the permission withdrawn and its last access has completed; only
// then may the core put the domain to sleep or start an engine.
//
// Other crossings:
//   A -> B  err[d]    domain d requested into deep sleep / shutdown (B answers
//                     its requests to d with a bus error)
//   B -> A  wake[d]   a B request waits for domain d (light-sleep auto wake);
//                     the core ignores it for domains that may not wake
//   B -> A  busy      B read-modify-write in progress (status only)
//   B -> A  ECC corrected / uncorrectable and error-IRQ pulses
// Every signal is registered in its source domain before the synchronizer
// (claude_sync / claude_pulse_sync, IP/common), so no combinational logic
// feeds a crossing.

module sram_cdc #(
  parameter int unsigned NPD = 1   // power domains
) (
  input  logic           clk_a,         // core clock (port A)
  input  logic           rst_a_n,       // clk_a synchronous active-low reset
  input  logic           clk_b,         // port B clock
  input  logic           rst_b_n,       // clk_b synchronous active-low reset

  // clk_a side
  input  logic [NPD-1:0] a_want_i,      // B should be allowed into the domain
  input  logic [NPD-1:0] a_err_i,       // domain access is a bus error
  output logic [NPD-1:0] a_quiet_o,     // B is out of the domain (handshake idle)
  output logic [NPD-1:0] a_wake_o,      // a B request waits for the domain
  output logic           a_busy_o,      // B read-modify-write in progress
  output logic           a_corr_o,      // B corrected an ECC error (pulse)
  output logic           a_uncorr_o,    // B read an uncorrectable word (pulse)
  output logic           a_irq_o,       // B bus error or ECC event (pulse)

  // clk_b side
  output logic [NPD-1:0] b_allow_o,     // synchronized allow
  output logic [NPD-1:0] b_err_o,       // synchronized err
  input  logic [NPD-1:0] b_dom_busy_i,  // B access to the domain in flight
  input  logic [NPD-1:0] b_wake_i,      // B request waits for the domain
  input  logic           b_busy_i,      // B read-modify-write in progress
  input  logic           b_corr_i,      // ECC corrected (registered pulse)
  input  logic           b_uncorr_i,    // ECC uncorrectable (registered pulse)
  input  logic           b_irq_i        // error IRQ (registered pulse)
);

  // -------------------------------------------------------------------------
  // clk_a -> clk_b
  // -------------------------------------------------------------------------
  logic [NPD-1:0] a_allow_q, a_err_q;  // registered at the source
  logic [NPD-1:0] a_hold;              // synchronized acknowledge

  // allow follows want only when the handshake is settled (allow == hold).
  always_ff @(posedge clk_a) begin : p_a_src
    if (!rst_a_n) begin
      a_allow_q <= '0;
      a_err_q   <= '0;
    end else begin
      for (int unsigned d = 0; d < NPD; d++) begin
        if (a_allow_q[d] == a_hold[d]) begin
          a_allow_q[d] <= a_want_i[d];
        end
      end
      a_err_q <= a_err_i;
    end
  end

  assign a_quiet_o = ~a_allow_q & ~a_hold;

  claude_sync #(
    .WIDTH(2 * NPD)
  ) u_sync_to_b (
    .clk  (clk_b),
    .rst_n(rst_b_n),
    .d_i  ({a_err_q, a_allow_q}),
    .q_o  ({b_err_o, b_allow_o})
  );

  // -------------------------------------------------------------------------
  // clk_b -> clk_a
  // -------------------------------------------------------------------------
  logic [NPD-1:0] b_hold_q, b_wake_q;  // registered at the source
  logic           b_busy_q;

  // hold: B saw the permission, or an access it started is still in flight.
  always_ff @(posedge clk_b) begin : p_b_src
    if (!rst_b_n) begin
      b_hold_q <= '0;
      b_wake_q <= '0;
      b_busy_q <= 1'b0;
    end else begin
      b_hold_q <= b_allow_o | b_dom_busy_i;
      b_wake_q <= b_wake_i;
      b_busy_q <= b_busy_i;
    end
  end

  claude_sync #(
    .WIDTH(2 * NPD + 1)
  ) u_sync_to_a (
    .clk  (clk_a),
    .rst_n(rst_a_n),
    .d_i  ({b_busy_q, b_wake_q, b_hold_q}),
    .q_o  ({a_busy_o, a_wake_o, a_hold})
  );

  claude_pulse_sync u_corr (
    .src_clk    (clk_b),
    .src_rst_n  (rst_b_n),
    .src_pulse_i(b_corr_i),
    .dst_clk    (clk_a),
    .dst_rst_n  (rst_a_n),
    .dst_pulse_o(a_corr_o)
  );

  claude_pulse_sync u_uncorr (
    .src_clk    (clk_b),
    .src_rst_n  (rst_b_n),
    .src_pulse_i(b_uncorr_i),
    .dst_clk    (clk_a),
    .dst_rst_n  (rst_a_n),
    .dst_pulse_o(a_uncorr_o)
  );

  claude_pulse_sync u_irq (
    .src_clk    (clk_b),
    .src_rst_n  (rst_b_n),
    .src_pulse_i(b_irq_i),
    .dst_clk    (clk_a),
    .dst_rst_n  (rst_a_n),
    .dst_pulse_o(a_irq_o)
  );

endmodule : sram_cdc
