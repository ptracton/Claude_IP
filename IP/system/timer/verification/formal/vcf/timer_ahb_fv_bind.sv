// timer_ahb_fv_bind.sv — binds the VC Formal checkers into timer_ahb.
//
// A bind-only module (never instantiated) so the same file serves both the
// SV and the VHDL top-level: VC Formal applies it with
// "elaborate ... -sva_bind_enable timer_ahb_fv_bind".

module timer_ahb_fv_bind;

  bind timer_ahb timer_ahb_fv #(.DATA_W(32), .ADDR_W(4)) u_fv (
    .HCLK(HCLK), .HRESETn(HRESETn), .HSEL(HSEL), .HADDR(HADDR),
    .HTRANS(HTRANS), .HWRITE(HWRITE), .HWDATA(HWDATA), .HWSTRB(HWSTRB),
    .HRDATA(HRDATA), .HREADY(HREADY), .HRESP(HRESP), .irq(irq),
    .trigger_out(trigger_out)
  );

`include "timer_block_binds.svh"

endmodule : timer_ahb_fv_bind
