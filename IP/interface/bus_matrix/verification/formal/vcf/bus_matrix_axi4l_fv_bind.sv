// bus_matrix_axi4l_fv_bind.sv — binds the VC Formal checkers into bus_matrix_axi4l.
//
// A bind-only module (never instantiated) so the same file serves both the
// SV and the VHDL top-level: VC Formal applies it with
// "elaborate ... -sva_bind_enable bus_matrix_axi4l_fv_bind".
// The checkers are configured from bus_matrix_fv_cfg.svh, which
// formal_bus_matrix.py generates from bus_matrix_pkg.sv before every run:
// VHDL generics are not visible to an SV bind, so the default (synthesized)
// configuration is passed as literals.

`include "bus_matrix_fv_cfg.svh"

module bus_matrix_axi4l_fv_bind;

  bind bus_matrix_axi4l bus_matrix_axi4l_fv #(
    .NUM_MASTERS (`BM_FV_NUM_MASTERS),
    .NUM_SLAVES  (`BM_FV_NUM_SLAVES),
    .S_BASE      (`BM_FV_S_BASE),
    .S_MASK      (`BM_FV_S_MASK)
  ) u_fv (
    .clk       (clk),
    .rst_n     (rst_n),
    .M_AWVALID (M_AWVALID),
    .M_AWREADY (M_AWREADY),
    .M_AWADDR  (M_AWADDR),
    .M_WVALID  (M_WVALID),
    .M_WREADY  (M_WREADY),
    .M_WDATA   (M_WDATA),
    .M_WSTRB   (M_WSTRB),
    .M_BVALID  (M_BVALID),
    .M_BREADY  (M_BREADY),
    .M_BRESP   (M_BRESP),
    .M_ARVALID (M_ARVALID),
    .M_ARREADY (M_ARREADY),
    .M_ARADDR  (M_ARADDR),
    .M_RVALID  (M_RVALID),
    .M_RREADY  (M_RREADY),
    .M_RDATA   (M_RDATA),
    .M_RRESP   (M_RRESP),
    .S_AWVALID (S_AWVALID),
    .S_AWREADY (S_AWREADY),
    .S_AWADDR  (S_AWADDR),
    .S_WVALID  (S_WVALID),
    .S_WREADY  (S_WREADY),
    .S_WDATA   (S_WDATA),
    .S_WSTRB   (S_WSTRB),
    .S_BVALID  (S_BVALID),
    .S_BREADY  (S_BREADY),
    .S_BRESP   (S_BRESP),
    .S_ARVALID (S_ARVALID),
    .S_ARREADY (S_ARREADY),
    .S_ARADDR  (S_ARADDR),
    .S_RVALID  (S_RVALID),
    .S_RREADY  (S_RREADY),
    .S_RDATA   (S_RDATA),
    .S_RRESP   (S_RRESP)
  );

`include "bus_matrix_block_binds.svh"

endmodule : bus_matrix_axi4l_fv_bind
