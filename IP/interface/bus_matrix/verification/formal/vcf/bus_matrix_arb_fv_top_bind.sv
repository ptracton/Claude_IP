// bus_matrix_arb_fv_top_bind.sv — binds bus_matrix_arb_fv to both arbiters of
// bus_matrix_arb_fv_top (SV or VHDL), through the harness's own ports.
// The configurations are literals that must match the two instances in
// bus_matrix_arb_fv_top.sv / .vhd: VHDL generics are not visible to an SV bind.

module bus_matrix_arb_fv_top_bind;

  bind bus_matrix_arb_fv_top bus_matrix_arb_fv #(
    .NUM_MASTERS (4),
    .ARB_MODE    (0),
    .M_PRIORITY  ({4'h1, 4'h0, 4'h1, 4'h2})
  ) u_fp_fv (
    .clk(clk), .rst_n(rst_n), .req(fp_req), .done(fp_done), .gnt(fp_gnt)
  );

  bind bus_matrix_arb_fv_top bus_matrix_arb_fv #(
    .NUM_MASTERS (4),
    .ARB_MODE    (1),
    .M_PRIORITY  (16'h0000)
  ) u_rr_fv (
    .clk(clk), .rst_n(rst_n), .req(rr_req), .done(rr_done), .gnt(rr_gnt)
  );

endmodule : bus_matrix_arb_fv_top_bind
