// claude_apb_mem_if_fv_bind.sv — Binds the formal harness into claude_apb_mem_if.
//
// Bind-only module: VC Formal applies binds found inside a module to a VHDL
// top as well (-sva_bind_enable claude_apb_mem_if_fv_bind), so one file
// serves both the SV module and the VHDL entity.

module claude_apb_mem_if_fv_bind;

bind claude_apb_mem_if claude_apb_mem_if_fv u_fv (
  .PCLK        (PCLK),
  .PRESETn     (PRESETn),
  .PSEL        (PSEL),
  .PENABLE     (PENABLE),
  .PADDR       (PADDR),
  .PWRITE      (PWRITE),
  .PWDATA      (PWDATA),
  .PSTRB       (PSTRB),
  .PRDATA      (PRDATA),
  .PREADY      (PREADY),
  .PSLVERR     (PSLVERR),
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

endmodule : claude_apb_mem_if_fv_bind
