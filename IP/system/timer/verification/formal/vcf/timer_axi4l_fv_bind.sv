// timer_axi4l_fv_bind.sv — binds the VC Formal checkers into timer_axi4l.
//
// A bind-only module (never instantiated) so the same file serves both the
// SV and the VHDL top-level: VC Formal applies it with
// "elaborate ... -sva_bind_enable timer_axi4l_fv_bind".

module timer_axi4l_fv_bind;

  bind timer_axi4l timer_axi4l_fv #(.DATA_W(32), .ADDR_W(4)) u_fv (
    .ACLK(ACLK), .ARESETn(ARESETn), .AWVALID(AWVALID), .AWREADY(AWREADY),
    .AWADDR(AWADDR), .WVALID(WVALID), .WREADY(WREADY), .WDATA(WDATA),
    .WSTRB(WSTRB), .BVALID(BVALID), .BREADY(BREADY), .BRESP(BRESP),
    .ARVALID(ARVALID), .ARREADY(ARREADY), .ARADDR(ARADDR), .RVALID(RVALID),
    .RREADY(RREADY), .RDATA(RDATA), .RRESP(RRESP), .irq(irq),
    .trigger_out(trigger_out)
  );

`include "timer_block_binds.svh"

endmodule : timer_axi4l_fv_bind
