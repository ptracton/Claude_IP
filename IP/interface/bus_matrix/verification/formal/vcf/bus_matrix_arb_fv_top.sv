// bus_matrix_arb_fv_top.sv — VC Formal harness for bus_matrix_arb on its own.
//
// The top-level jobs check the arbiter only in the default configuration
// (2 masters, round robin). This harness checks both arbitration modes with
// 4 masters and free-running inputs:
//   u_fp  fixed priority, M_PRIORITY = {M3:1, M2:0, M1:1, M0:2}
//         (M2 is best; M1 and M3 tie, so the lower index must win)
//   u_rr  round robin
// bus_matrix_arb_fv is bound to both instances by bus_matrix_arb_fv_top_bind.

module bus_matrix_arb_fv_top (
  input  logic       clk,
  input  logic       rst_n,
  input  logic [3:0] fp_req,
  input  logic       fp_done,
  output logic [3:0] fp_gnt,
  input  logic [3:0] rr_req,
  input  logic       rr_done,
  output logic [3:0] rr_gnt
);

  bus_matrix_arb #(
    .NUM_MASTERS (4),
    .ARB_MODE    (0),
    .M_PRIORITY  ({4'h1, 4'h0, 4'h1, 4'h2})
  ) u_fp (
    .clk   (clk),
    .rst_n (rst_n),
    .req   (fp_req),
    .done  (fp_done),
    .gnt   (fp_gnt)
  );

  bus_matrix_arb #(
    .NUM_MASTERS (4),
    .ARB_MODE    (1),
    .M_PRIORITY  (16'h0000)
  ) u_rr (
    .clk   (clk),
    .rst_n (rst_n),
    .req   (rr_req),
    .done  (rr_done),
    .gnt   (rr_gnt)
  );

endmodule : bus_matrix_arb_fv_top
