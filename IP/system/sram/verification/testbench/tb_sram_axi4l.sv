// tb_sram_axi4l.sv — AXI4-Lite system testbench for the sram IP (Step 4).
//
// The SRAMs are reached through bus_matrix_axi4l (IP/interface/bus_matrix),
// one matrix per data width, the way a system would connect them:
//
//   Matrix  Clock  Masters        Slaves (64 KB window each: S0 0x0, S1 0x1_0000, S2 0x2_0000)
//   X32     clk_a  u_m0 + u_m1    s32  32x1024            s32e 32x512 ECC BIST BANK_PG x2 RL2
//                                 dp0.A 32-bit ECC (8-bit codewords), port B on its own clock
//   X8      clk_b  u_m2           s8   8x2048 RL2         dp0.B 8-bit
//   X16     clk_a  u_m3           s16  16x4096 BYTE_EN=0 (partial = error)
//                                 s16w 16x64 BYTE_EN=0 (partial = full write)
//                                 dp1.A 16-bit, BIST
//   X24     clk_a  u_m4           s24  24x256 ECC         s24b 24x128 BANK_PG x4
//   X64     clk_a  u_m5           s64  64x512 ECC RL2 BIST
//                                 dp1.B 64-bit, BYTE_EN=0, RL2, common clock
//   none    clk_a  u_m6 / u_m7    s32p 32x256 RL1 / s32q 32x256 RL2, attached directly
//                                 (the protocol's own back-to-back rate, no matrix)
//
// Each SRAM sees the low 16 address bits, so an address inside the 64 KB window but past
// the SRAM tests the SRAM's range error, and an unmapped address tests the
// matrix's decode error.
//
// Technology: +define+TECH=<sram_pkg::TECH_*> (default GENERIC) and, for
// GENERIC, +define+TECH_GENERIC (backdoor tests). On SKY130 port B of both
// dual ports is read-only (the bench expects bus errors on B writes). On
// SAED14 dp0 uses COMMON_CLK = 1 and clk_b is clk_a (SRAM2RW has one write
// and one read clock).
//
// Checking: every read is compared at the master with a byte-level shadow
// memory (sram_tb_helpers.sv), and a sram_model per SRAM independently checks
// every response on the memory bus inside the top-level. Tests are in
// verification/tests/.
//
// AXI4-Lite specifics: no size signal or bursts. The BFM turns a sub-word
// write into WSTRB and reads whole words; a "burst" is the same address
// sequence as back-to-back transactions. SLVERR is the error response.
//
// The body (instances, models, counters, test sequence) is shared by every
// protocol: sram_tb_body.svh, with this file's wiring macros.

`timescale 1ns / 1ps

`ifndef TECH
`define TECH 0
`endif

`define TB_NAME tb_sram_axi4l
`define TB_STR "tb_sram_axi4l"
`define TB_PROTO "axi4l"
`define SRAM_TOP sram_axi4l
`define SRAM_DP_TOP sram_axi4l_dp

`define XBAR_WIRES(X, NM, NS, DW) \
  wire [NM-1:0]      X``_M_AWVALID; wire [NM-1:0]      X``_M_AWREADY; \
  wire [NM*32-1:0]   X``_M_AWADDR;  wire [NM-1:0]      X``_M_WVALID; \
  wire [NM-1:0]      X``_M_WREADY;  wire [NM*DW-1:0]   X``_M_WDATA; \
  wire [NM*DW/8-1:0] X``_M_WSTRB;   wire [NM-1:0]      X``_M_BVALID; \
  wire [NM-1:0]      X``_M_BREADY;  wire [NM*2-1:0]    X``_M_BRESP; \
  wire [NM-1:0]      X``_M_ARVALID; wire [NM-1:0]      X``_M_ARREADY; \
  wire [NM*32-1:0]   X``_M_ARADDR;  wire [NM-1:0]      X``_M_RVALID; \
  wire [NM-1:0]      X``_M_RREADY;  wire [NM*DW-1:0]   X``_M_RDATA; \
  wire [NM*2-1:0]    X``_M_RRESP; \
  wire [NS-1:0]      X``_S_AWVALID; wire [NS-1:0]      X``_S_AWREADY; \
  wire [NS*32-1:0]   X``_S_AWADDR;  wire [NS-1:0]      X``_S_WVALID; \
  wire [NS-1:0]      X``_S_WREADY;  wire [NS*DW-1:0]   X``_S_WDATA; \
  wire [NS*DW/8-1:0] X``_S_WSTRB;   wire [NS-1:0]      X``_S_BVALID; \
  wire [NS-1:0]      X``_S_BREADY;  wire [NS*2-1:0]    X``_S_BRESP; \
  wire [NS-1:0]      X``_S_ARVALID; wire [NS-1:0]      X``_S_ARREADY; \
  wire [NS*32-1:0]   X``_S_ARADDR;  wire [NS-1:0]      X``_S_RVALID; \
  wire [NS-1:0]      X``_S_RREADY;  wire [NS*DW-1:0]   X``_S_RDATA; \
  wire [NS*2-1:0]    X``_S_RRESP;

`define XBAR(X, NM, NS, DW, CLK, RST, PRIO) \
  bus_matrix_axi4l #( \
    .NUM_MASTERS(NM), .NUM_SLAVES(NS), .DATA_W(DW), .ADDR_W(32), .ARB_MODE(1), \
    .M_PRIORITY(`BM_PW(NM)'(PRIO)), .S_BASE(`BM_SW(NS)'(slave_bases(NS))), \
    .S_MASK(`BM_SW(NS)'({NS{32'hFFFF_0000}})) \
  ) u_``X ( \
    .clk(CLK), .rst_n(RST), \
    .M_AWVALID(X``_M_AWVALID), .M_AWREADY(X``_M_AWREADY), .M_AWADDR(X``_M_AWADDR), \
    .M_WVALID(X``_M_WVALID), .M_WREADY(X``_M_WREADY), .M_WDATA(X``_M_WDATA), \
    .M_WSTRB(X``_M_WSTRB), .M_BVALID(X``_M_BVALID), .M_BREADY(X``_M_BREADY), \
    .M_BRESP(X``_M_BRESP), .M_ARVALID(X``_M_ARVALID), .M_ARREADY(X``_M_ARREADY), \
    .M_ARADDR(X``_M_ARADDR), .M_RVALID(X``_M_RVALID), .M_RREADY(X``_M_RREADY), \
    .M_RDATA(X``_M_RDATA), .M_RRESP(X``_M_RRESP), \
    .S_AWVALID(X``_S_AWVALID), .S_AWREADY(X``_S_AWREADY), .S_AWADDR(X``_S_AWADDR), \
    .S_WVALID(X``_S_WVALID), .S_WREADY(X``_S_WREADY), .S_WDATA(X``_S_WDATA), \
    .S_WSTRB(X``_S_WSTRB), .S_BVALID(X``_S_BVALID), .S_BREADY(X``_S_BREADY), \
    .S_BRESP(X``_S_BRESP), .S_ARVALID(X``_S_ARVALID), .S_ARREADY(X``_S_ARREADY), \
    .S_ARADDR(X``_S_ARADDR), .S_RVALID(X``_S_RVALID), .S_RREADY(X``_S_RREADY), \
    .S_RDATA(X``_S_RDATA), .S_RRESP(X``_S_RRESP));

`define MST(U, X, I, WD, CLK) \
  sram_tb_axi4l_master #(.DW(WD)) U ( \
    .ACLK(CLK), .AWVALID(X``_M_AWVALID[I]), .AWREADY(X``_M_AWREADY[I]), \
    .AWADDR(X``_M_AWADDR[I*32+:32]), .WVALID(X``_M_WVALID[I]), .WREADY(X``_M_WREADY[I]), \
    .WDATA(X``_M_WDATA[I*WD+:WD]), .WSTRB(X``_M_WSTRB[I*WD/8+:WD/8]), \
    .BVALID(X``_M_BVALID[I]), .BREADY(X``_M_BREADY[I]), .BRESP(X``_M_BRESP[I*2+:2]), \
    .ARVALID(X``_M_ARVALID[I]), .ARREADY(X``_M_ARREADY[I]), .ARADDR(X``_M_ARADDR[I*32+:32]), \
    .RVALID(X``_M_RVALID[I]), .RREADY(X``_M_RREADY[I]), .RDATA(X``_M_RDATA[I*WD+:WD]), \
    .RRESP(X``_M_RRESP[I*2+:2]));

`define SLV(P, X, J, DW) \
  .P``AWVALID(X``_S_AWVALID[J]), .P``AWREADY(X``_S_AWREADY[J]), \
  .P``AWADDR(X``_S_AWADDR[J*32+:SAW]), .P``WVALID(X``_S_WVALID[J]), \
  .P``WREADY(X``_S_WREADY[J]), .P``WDATA(X``_S_WDATA[J*DW+:DW]), \
  .P``WSTRB(X``_S_WSTRB[J*DW/8+:DW/8]), .P``BVALID(X``_S_BVALID[J]), \
  .P``BREADY(X``_S_BREADY[J]), .P``BRESP(X``_S_BRESP[J*2+:2]), \
  .P``ARVALID(X``_S_ARVALID[J]), .P``ARREADY(X``_S_ARREADY[J]), \
  .P``ARADDR(X``_S_ARADDR[J*32+:SAW]), .P``RVALID(X``_S_RVALID[J]), \
  .P``RREADY(X``_S_RREADY[J]), .P``RDATA(X``_S_RDATA[J*DW+:DW]), .P``RRESP(X``_S_RRESP[J*2+:2])

`define CLKRST(P, CLK, RSTN) .P``ACLK(CLK), .P``ARESETn(RSTN)

`define LINK(X) \
  assign X``_S_AWVALID = X``_M_AWVALID; assign X``_M_AWREADY = X``_S_AWREADY; \
  assign X``_S_AWADDR = X``_M_AWADDR;   assign X``_S_WVALID = X``_M_WVALID; \
  assign X``_M_WREADY = X``_S_WREADY;   assign X``_S_WDATA = X``_M_WDATA; \
  assign X``_S_WSTRB = X``_M_WSTRB;     assign X``_M_BVALID = X``_S_BVALID; \
  assign X``_S_BREADY = X``_M_BREADY;   assign X``_M_BRESP = X``_S_BRESP; \
  assign X``_S_ARVALID = X``_M_ARVALID; assign X``_M_ARREADY = X``_S_ARREADY; \
  assign X``_S_ARADDR = X``_M_ARADDR;   assign X``_M_RVALID = X``_S_RVALID; \
  assign X``_S_RREADY = X``_M_RREADY;   assign X``_M_RDATA = X``_S_RDATA; \
  assign X``_M_RRESP = X``_S_RRESP;

module tb_sram_axi4l;

`include "sram_tb_body.svh"

endmodule : tb_sram_axi4l
