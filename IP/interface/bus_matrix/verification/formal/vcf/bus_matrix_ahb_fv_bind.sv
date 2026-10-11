// bus_matrix_ahb_fv_bind.sv — binds the VC Formal checkers into bus_matrix_ahb.
//
// A bind-only module (never instantiated) so the same file serves both the
// SV and the VHDL top-level: VC Formal applies it with
// "elaborate ... -sva_bind_enable bus_matrix_ahb_fv_bind".
// The checkers are configured from bus_matrix_fv_cfg.svh, which
// formal_bus_matrix.py generates from bus_matrix_pkg.sv before every run:
// VHDL generics are not visible to an SV bind, so the default (synthesized)
// configuration is passed as literals.

`include "bus_matrix_fv_cfg.svh"

module bus_matrix_ahb_fv_bind;

  bind bus_matrix_ahb bus_matrix_ahb_fv #(
    .NUM_MASTERS (`BM_FV_NUM_MASTERS),
    .NUM_SLAVES  (`BM_FV_NUM_SLAVES),
    .S_BASE      (`BM_FV_S_BASE),
    .S_MASK      (`BM_FV_S_MASK)
  ) u_fv (
    .clk      (clk),
    .rst_n    (rst_n),
    .M_HSEL   (M_HSEL),
    .M_HADDR  (M_HADDR),
    .M_HTRANS (M_HTRANS),
    .M_HWRITE (M_HWRITE),
    .M_HWDATA (M_HWDATA),
    .M_HWSTRB (M_HWSTRB),
    .M_HRDATA (M_HRDATA),
    .M_HREADY (M_HREADY),
    .M_HRESP  (M_HRESP),
    .S_HSEL   (S_HSEL),
    .S_HADDR  (S_HADDR),
    .S_HTRANS (S_HTRANS),
    .S_HWRITE (S_HWRITE),
    .S_HWDATA (S_HWDATA),
    .S_HWSTRB (S_HWSTRB),
    .S_HRDATA (S_HRDATA),
    .S_HREADY (S_HREADY),
    .S_HRESP  (S_HRESP)
  );

`include "bus_matrix_block_binds.svh"

endmodule : bus_matrix_ahb_fv_bind
