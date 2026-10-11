// bus_matrix_arb_fv.sv — VC Formal properties for bus_matrix_arb.
//
// Bound to every bus_matrix_arb instance (SV module or VHDL entity) by the
// bus_matrix_<proto>_fv_bind modules. Uses only the arbiter's ports, so it is
// language-neutral.
//
//   a_onehot           at most one master is granted
//   a_new_gnt_req      a new grant goes to a master that was requesting
//   a_fp_winner        fixed priority: a new grant goes to the best requester
//                      (lowest M_PRIORITY value, then lowest index)
//   a_rr_fair          round robin: a requesting master waits for at most
//                      NUM_MASTERS-1 grants to other masters
//   a_lock             the grant is held while the owner requests and the
//                      transaction has not completed
//   a_release          the grant is dropped after done (or when the owner
//                      stops requesting)
//   a_grant_when_free  a free slave with a pending request grants next cycle
//   a_idle             no request, no grant

module bus_matrix_arb_fv #(
  parameter int unsigned NUM_MASTERS = 2,
  parameter int unsigned ARB_MODE    = 0,
  parameter logic [NUM_MASTERS*4-1:0] M_PRIORITY = '0
) (
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic [NUM_MASTERS-1:0] req,
  input  logic                   done,
  input  logic [NUM_MASTERS-1:0] gnt
);

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  logic busy, owner_req, new_gnt;
  assign busy      = |gnt;
  assign owner_req = |(gnt & req);

  // Previous-cycle values (reset to the arbiter's reset state).
  logic [NUM_MASTERS-1:0] gnt_q, req_q;
  always_ff @(posedge clk) begin
    if (!rst_n) begin
      gnt_q <= '0;
      req_q <= '0;
    end else begin
      gnt_q <= gnt;
      req_q <= req;
    end
  end
  assign new_gnt = busy && (gnt_q == '0);

  // Reference fixed-priority winner of a request vector.
  function automatic logic [NUM_MASTERS-1:0] fp_winner(input logic [NUM_MASTERS-1:0] r);
    logic [NUM_MASTERS-1:0] w;
    int best;
    w = '0;
    best = -1;
    for (int i = 0; i < NUM_MASTERS; i++) begin
      if (r[i] && (best < 0 || M_PRIORITY[i*4+:4] < M_PRIORITY[best*4+:4])) begin
        best = i;
      end
    end
    if (best >= 0) begin
      w[best] = 1'b1;
    end
    return w;
  endfunction

  a_onehot:          assert property ($onehot0(gnt));
  a_new_gnt_req:     assert property (new_gnt |-> ((gnt & req_q) == gnt));
  a_lock:            assert property ((busy && !done && owner_req) |=> (gnt == gnt_q));
  a_release:         assert property ((busy && (done || !owner_req)) |=> (gnt == '0));
  a_grant_when_free: assert property ((!busy && (|req)) |=> busy);
  a_idle:            assert property ((!busy && (req == '0)) |=> !busy);

  if (ARB_MODE == 0) begin : g_fp
    a_fp_winner: assert property (new_gnt |-> (gnt == fp_winner(req_q)));
  end else begin : g_rr
    // Grants given to other masters while master i keeps requesting.
    for (genvar gi = 0; gi < NUM_MASTERS; gi++) begin : g_m
      int unsigned skipped_q;
      always_ff @(posedge clk) begin
        if (!rst_n || !req[gi] || gnt[gi]) begin
          skipped_q <= 0;
        end else if (new_gnt && !gnt[gi] && req_q[gi]) begin
          skipped_q <= skipped_q + 1;
        end
      end
      a_rr_fair: assert property (skipped_q < NUM_MASTERS);
    end
  end

  // Coverage
  for (genvar gi = 0; gi < NUM_MASTERS; gi++) begin : g_cov
    c_gnt: cover property (new_gnt && gnt[gi]);
  end
  c_contention: cover property (new_gnt && !$onehot(req_q));
  c_wait:       cover property (busy && !done ##1 busy && done);
  c_back2back:  cover property (busy && done ##2 busy);

endmodule : bus_matrix_arb_fv
