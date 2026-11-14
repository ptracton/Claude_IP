// sram_axi4l_fv_bind.sv — bind-only module of the sram_axi4l top-level formal job.
//
// Binds the bus-port checker (sram_bus_fv.sv) into sram_axi4l, plus the core,
// array and power checkers shared by every job (sram_fv_block_binds.svh).
// The configuration comes from the generated sram_fv_cfg.svh.

`include "sram_fv_cfg.svh"

module sram_axi4l_fv_bind;

bind sram_axi4l sram_axi4l_bus_fv #(
  .ADDR_W  (`SRAM_FV_ADDR_W),
  .WIDTH   (`SRAM_FV_WIDTH),
  .MAX_WAIT(`SRAM_FV_BUS_WAIT)
) u_bus_fv (
  .ACLK      (ACLK),
  .ARESETn   (ARESETn),
  .AWVALID   (AWVALID),
  .AWREADY   (AWREADY),
  .AWADDR    (AWADDR),
  .WVALID    (WVALID),
  .WREADY    (WREADY),
  .WDATA     (WDATA),
  .WSTRB     (WSTRB),
  .BVALID    (BVALID),
  .BREADY    (BREADY),
  .BRESP     (BRESP),
  .ARVALID   (ARVALID),
  .ARREADY   (ARREADY),
  .ARADDR    (ARADDR),
  .RVALID    (RVALID),
  .RREADY    (RREADY),
  .RDATA     (RDATA),
  .RRESP     (RRESP)
);

`include "sram_fv_block_binds.svh"

endmodule : sram_axi4l_fv_bind
