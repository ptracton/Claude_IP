// sram_wb_fv_bind.sv — bind-only module of the sram_wb top-level formal job.
//
// Binds the bus-port checker (sram_bus_fv.sv) into sram_wb, plus the core,
// array and power checkers shared by every job (sram_fv_block_binds.svh).
// The configuration comes from the generated sram_fv_cfg.svh.

`include "sram_fv_cfg.svh"

module sram_wb_fv_bind;

bind sram_wb sram_wb_bus_fv #(
  .ADDR_W  (`SRAM_FV_ADDR_W),
  .WIDTH   (`SRAM_FV_WIDTH),
  .MAX_WAIT(`SRAM_FV_BUS_WAIT)
) u_bus_fv (
  .CLK_I     (CLK_I),
  .RST_I     (RST_I),
  .CYC_I     (CYC_I),
  .STB_I     (STB_I),
  .WE_I      (WE_I),
  .ADR_I     (ADR_I),
  .DAT_I     (DAT_I),
  .SEL_I     (SEL_I),
  .DAT_O     (DAT_O),
  .ACK_O     (ACK_O),
  .ERR_O     (ERR_O)
);

`include "sram_fv_block_binds.svh"

endmodule : sram_wb_fv_bind
