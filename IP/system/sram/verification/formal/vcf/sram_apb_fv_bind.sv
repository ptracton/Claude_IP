// sram_apb_fv_bind.sv — bind-only module of the sram_apb top-level formal job.
//
// Binds the bus-port checker (sram_bus_fv.sv) into sram_apb, plus the core,
// array and power checkers shared by every job (sram_fv_block_binds.svh).
// The configuration comes from the generated sram_fv_cfg.svh.

`include "sram_fv_cfg.svh"

module sram_apb_fv_bind;

bind sram_apb sram_apb_bus_fv #(
  .ADDR_W  (`SRAM_FV_ADDR_W),
  .WIDTH   (`SRAM_FV_WIDTH),
  .MAX_WAIT(`SRAM_FV_BUS_WAIT)
) u_bus_fv (
  .PCLK      (PCLK),
  .PRESETn   (PRESETn),
  .PSEL      (PSEL),
  .PENABLE   (PENABLE),
  .PADDR     (PADDR),
  .PWRITE    (PWRITE),
  .PWDATA    (PWDATA),
  .PSTRB     (PSTRB),
  .PRDATA    (PRDATA),
  .PREADY    (PREADY),
  .PSLVERR   (PSLVERR)
);

`include "sram_fv_block_binds.svh"

endmodule : sram_apb_fv_bind
