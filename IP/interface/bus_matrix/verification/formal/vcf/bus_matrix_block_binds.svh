// bus_matrix_block_binds.svh — bind statements shared by every bus_matrix top-level.
//
// Included inside each bus_matrix_<proto>_fv_bind module. bus_matrix_core and
// bus_matrix_arb are identical in all four top-levels (and have the same port
// names in SV and VHDL), so their checkers are bound the same way. The
// configuration comes from bus_matrix_fv_cfg.svh (included by the bind module).

bind bus_matrix_core bus_matrix_core_fv #(
  .NUM_MASTERS (`BM_FV_NUM_MASTERS),
  .NUM_SLAVES  (`BM_FV_NUM_SLAVES),
  .DATA_W      (32),
  .ADDR_W      (32),
  .S_BASE      (`BM_FV_S_BASE),
  .S_MASK      (`BM_FV_S_MASK)
) u_core_fv (
  .clk(clk), .rst_n(rst_n),
  .mst_req(mst_req), .mst_addr(mst_addr), .mst_wdata(mst_wdata), .mst_we(mst_we),
  .mst_be(mst_be), .mst_done(mst_done), .mst_rdata(mst_rdata), .mst_err(mst_err),
  .slv_req(slv_req), .slv_addr(slv_addr), .slv_wdata(slv_wdata), .slv_we(slv_we),
  .slv_be(slv_be), .slv_done(slv_done), .slv_rdata(slv_rdata), .slv_err(slv_err)
);

bind bus_matrix_arb bus_matrix_arb_fv #(
  .NUM_MASTERS (`BM_FV_NUM_MASTERS),
  .ARB_MODE    (`BM_FV_ARB_MODE),
  .M_PRIORITY  (`BM_FV_M_PRIORITY)
) u_arb_fv (
  .clk(clk), .rst_n(rst_n), .req(req), .done(done), .gnt(gnt)
);
