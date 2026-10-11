// bus_matrix_apb_fv_bind.sv — binds the VC Formal checkers into bus_matrix_apb.
//
// A bind-only module (never instantiated) so the same file serves both the
// SV and the VHDL top-level: VC Formal applies it with
// "elaborate ... -sva_bind_enable bus_matrix_apb_fv_bind".
// The checkers are configured from bus_matrix_fv_cfg.svh, which
// formal_bus_matrix.py generates from bus_matrix_pkg.sv before every run:
// VHDL generics are not visible to an SV bind, so the default (synthesized)
// configuration is passed as literals.

`include "bus_matrix_fv_cfg.svh"

module bus_matrix_apb_fv_bind;

  bind bus_matrix_apb bus_matrix_apb_fv #(
    .NUM_MASTERS (`BM_FV_NUM_MASTERS),
    .NUM_SLAVES  (`BM_FV_NUM_SLAVES),
    .S_BASE      (`BM_FV_S_BASE),
    .S_MASK      (`BM_FV_S_MASK)
  ) u_fv (
    .clk       (clk),
    .rst_n     (rst_n),
    .M_PSEL    (M_PSEL),
    .M_PENABLE (M_PENABLE),
    .M_PADDR   (M_PADDR),
    .M_PWRITE  (M_PWRITE),
    .M_PWDATA  (M_PWDATA),
    .M_PSTRB   (M_PSTRB),
    .M_PRDATA  (M_PRDATA),
    .M_PREADY  (M_PREADY),
    .M_PSLVERR (M_PSLVERR),
    .S_PSEL    (S_PSEL),
    .S_PENABLE (S_PENABLE),
    .S_PADDR   (S_PADDR),
    .S_PWRITE  (S_PWRITE),
    .S_PWDATA  (S_PWDATA),
    .S_PSTRB   (S_PSTRB),
    .S_PRDATA  (S_PRDATA),
    .S_PREADY  (S_PREADY),
    .S_PSLVERR (S_PSLVERR)
  );

`include "bus_matrix_block_binds.svh"

endmodule : bus_matrix_apb_fv_bind
