// sram_tb_drv.svh — Drive skew for the bench's procedural drivers.
//
// `TB_DRV goes between the last sample taken at a clock edge and the first
// signal driven after it (BFMs and the side-band pulses in the tests).
//
// With --timing, Verilator 5.x makes a nonblocking assignment issued by a
// suspended process (an initial block or task resumed by @(posedge clk))
// visible to the flops clocked by that same edge, so a DUT input driven
// "<= at the edge" is taken one cycle early. On Verilator the bench therefore
// drives 1 ns after the edge, which every clock period here (>= 10 ns)
// leaves room for; the DUT sees the same value at the same edge as with an
// IEEE-ordered nonblocking assignment. Other simulators keep the
// nonblocking assignments at the edge (the macro is empty).

`ifndef SRAM_TB_DRV_SVH
`define SRAM_TB_DRV_SVH
`ifdef VERILATOR
`define TB_DRV #1
`else
`define TB_DRV
`endif
`endif
