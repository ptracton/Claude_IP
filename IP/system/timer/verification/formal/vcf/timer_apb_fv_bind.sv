// timer_apb_fv_bind.sv — binds the VC Formal checkers into timer_apb.
//
// A bind-only module (never instantiated) so the same file serves both the
// SV and the VHDL top-level: VC Formal applies it with
// "elaborate ... -sva_bind_enable timer_apb_fv_bind".

module timer_apb_fv_bind;

  bind timer_apb timer_apb_fv #(.DATA_W(32), .ADDR_W(4)) u_fv (
    .PCLK(PCLK), .PRESETn(PRESETn), .PSEL(PSEL), .PENABLE(PENABLE),
    .PADDR(PADDR), .PWRITE(PWRITE), .PWDATA(PWDATA), .PSTRB(PSTRB),
    .PRDATA(PRDATA), .PREADY(PREADY), .PSLVERR(PSLVERR),
    .irq(irq), .trigger_out(trigger_out)
  );

`include "timer_block_binds.svh"

endmodule : timer_apb_fv_bind
