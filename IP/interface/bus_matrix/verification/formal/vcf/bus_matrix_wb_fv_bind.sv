// bus_matrix_wb_fv_bind.sv — binds the VC Formal checkers into bus_matrix_wb.
//
// A bind-only module (never instantiated) so the same file serves both the
// SV and the VHDL top-level: VC Formal applies it with
// "elaborate ... -sva_bind_enable bus_matrix_wb_fv_bind".
// The checkers are configured from bus_matrix_fv_cfg.svh, which
// formal_bus_matrix.py generates from bus_matrix_pkg.sv before every run:
// VHDL generics are not visible to an SV bind, so the default (synthesized)
// configuration is passed as literals.

`include "bus_matrix_fv_cfg.svh"

module bus_matrix_wb_fv_bind;

  bind bus_matrix_wb bus_matrix_wb_fv #(
    .NUM_MASTERS (`BM_FV_NUM_MASTERS),
    .NUM_SLAVES  (`BM_FV_NUM_SLAVES),
    .S_BASE      (`BM_FV_S_BASE),
    .S_MASK      (`BM_FV_S_MASK)
  ) u_fv (
    .clk     (clk),
    .rst_n   (rst_n),
    .M_CYC   (M_CYC),
    .M_STB   (M_STB),
    .M_WE    (M_WE),
    .M_ADR   (M_ADR),
    .M_DAT_I (M_DAT_I),
    .M_SEL   (M_SEL),
    .M_DAT_O (M_DAT_O),
    .M_ACK   (M_ACK),
    .M_ERR   (M_ERR),
    .S_CYC   (S_CYC),
    .S_STB   (S_STB),
    .S_WE    (S_WE),
    .S_ADR   (S_ADR),
    .S_DAT_O (S_DAT_O),
    .S_SEL   (S_SEL),
    .S_DAT_I (S_DAT_I),
    .S_ACK   (S_ACK),
    .S_ERR   (S_ERR)
  );

`include "bus_matrix_block_binds.svh"

endmodule : bus_matrix_wb_fv_bind
