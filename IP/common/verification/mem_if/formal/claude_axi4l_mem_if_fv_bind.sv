// claude_axi4l_mem_if_fv_bind.sv — Binds the formal harness into claude_axi4l_mem_if.
//
// Bind-only module: VC Formal applies binds found inside a module to a VHDL
// top as well (-sva_bind_enable claude_axi4l_mem_if_fv_bind), so one file
// serves both the SV module and the VHDL entity.

module claude_axi4l_mem_if_fv_bind;

bind claude_axi4l_mem_if claude_axi4l_mem_if_fv u_fv (
  .ACLK        (ACLK),
  .ARESETn     (ARESETn),
  .AWVALID     (AWVALID),
  .AWREADY     (AWREADY),
  .AWADDR      (AWADDR),
  .WVALID      (WVALID),
  .WREADY      (WREADY),
  .WDATA       (WDATA),
  .WSTRB       (WSTRB),
  .BVALID      (BVALID),
  .BREADY      (BREADY),
  .BRESP       (BRESP),
  .ARVALID     (ARVALID),
  .ARREADY     (ARREADY),
  .ARADDR      (ARADDR),
  .RVALID      (RVALID),
  .RREADY      (RREADY),
  .RDATA       (RDATA),
  .RRESP       (RRESP),
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

endmodule : claude_axi4l_mem_if_fv_bind
