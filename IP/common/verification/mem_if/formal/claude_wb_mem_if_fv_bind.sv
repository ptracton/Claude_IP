// claude_wb_mem_if_fv_bind.sv — Binds the formal harness into claude_wb_mem_if.
//
// Bind-only module: VC Formal applies binds found inside a module to a VHDL
// top as well (-sva_bind_enable claude_wb_mem_if_fv_bind), so one file
// serves both the SV module and the VHDL entity.

module claude_wb_mem_if_fv_bind;

bind claude_wb_mem_if claude_wb_mem_if_fv u_fv (
  .CLK_I       (CLK_I),
  .RST_I       (RST_I),
  .CYC_I       (CYC_I),
  .STB_I       (STB_I),
  .WE_I        (WE_I),
  .ADR_I       (ADR_I),
  .DAT_I       (DAT_I),
  .SEL_I       (SEL_I),
  .DAT_O       (DAT_O),
  .ACK_O       (ACK_O),
  .ERR_O       (ERR_O),
  .mem_req_o   (mem_req_o),
  .mem_gnt_i   (mem_gnt_i),
  .mem_we_o    (mem_we_o),
  .mem_addr_o  (mem_addr_o),
  .mem_be_o    (mem_be_o),
  .mem_wdata_o (mem_wdata_o),
  .mem_rvalid_i(mem_rvalid_i),
  .mem_rdata_i (mem_rdata_i),
  .mem_err_i   (mem_err_i)
);

endmodule : claude_wb_mem_if_fv_bind
