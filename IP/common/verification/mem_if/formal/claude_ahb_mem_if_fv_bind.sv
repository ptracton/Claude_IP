// claude_ahb_mem_if_fv_bind.sv — Binds the formal harness into claude_ahb_mem_if.
//
// Bind-only module: VC Formal applies binds found inside a module to a VHDL
// top as well (-sva_bind_enable claude_ahb_mem_if_fv_bind), so one file
// serves both the SV module and the VHDL entity.

module claude_ahb_mem_if_fv_bind;

bind claude_ahb_mem_if claude_ahb_mem_if_fv u_fv (
  .HCLK        (HCLK),
  .HRESETn     (HRESETn),
  .HSEL        (HSEL),
  .HADDR       (HADDR),
  .HTRANS      (HTRANS),
  .HWRITE      (HWRITE),
  .HSIZE       (HSIZE),
  .HWDATA      (HWDATA),
  .HWSTRB      (HWSTRB),
  .HREADY      (HREADY),
  .HRDATA      (HRDATA),
  .HREADYOUT   (HREADYOUT),
  .HRESP       (HRESP),
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

endmodule : claude_ahb_mem_if_fv_bind
