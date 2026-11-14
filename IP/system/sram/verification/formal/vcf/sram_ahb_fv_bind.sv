// sram_ahb_fv_bind.sv — bind-only module of the sram_ahb top-level formal job.
//
// Binds the bus-port checker (sram_bus_fv.sv) into sram_ahb, plus the core,
// array and power checkers shared by every job (sram_fv_block_binds.svh).
// The configuration comes from the generated sram_fv_cfg.svh.

`include "sram_fv_cfg.svh"

module sram_ahb_fv_bind;

bind sram_ahb sram_ahb_bus_fv #(
  .ADDR_W  (`SRAM_FV_ADDR_W),
  .WIDTH   (`SRAM_FV_WIDTH),
  .MAX_WAIT(`SRAM_FV_BUS_WAIT)
) u_bus_fv (
  .HCLK      (HCLK),
  .HRESETn   (HRESETn),
  .HSEL      (HSEL),
  .HADDR     (HADDR),
  .HTRANS    (HTRANS),
  .HWRITE    (HWRITE),
  .HSIZE     (HSIZE),
  .HWDATA    (HWDATA),
  .HWSTRB    (HWSTRB),
  .HREADY    (HREADY),
  .HRDATA    (HRDATA),
  .HREADYOUT (HREADYOUT),
  .HRESP     (HRESP)
);

`include "sram_fv_block_binds.svh"

endmodule : sram_ahb_fv_bind
