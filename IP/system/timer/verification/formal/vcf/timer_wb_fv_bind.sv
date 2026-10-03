// timer_wb_fv_bind.sv — binds the VC Formal checkers into timer_wb.
//
// A bind-only module (never instantiated) so the same file serves both the
// SV and the VHDL top-level: VC Formal applies it with
// "elaborate ... -sva_bind_enable timer_wb_fv_bind".

module timer_wb_fv_bind;

  bind timer_wb timer_wb_fv #(.DATA_W(32), .ADDR_W(4)) u_fv (
    .CLK_I(CLK_I), .RST_I(RST_I), .CYC_I(CYC_I), .STB_I(STB_I), .WE_I(WE_I),
    .ADR_I(ADR_I), .DAT_I(DAT_I), .SEL_I(SEL_I), .DAT_O(DAT_O), .ACK_O(ACK_O),
    .ERR_O(ERR_O), .irq(irq), .trigger_out(trigger_out)
  );

`include "timer_block_binds.svh"

endmodule : timer_wb_fv_bind
