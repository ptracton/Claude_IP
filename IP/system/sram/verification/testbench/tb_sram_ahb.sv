// tb_sram_ahb.sv — AHB-Lite system testbench for the sram IP (Step 4).
//
// The SRAMs are reached through bus_matrix_ahb (IP/interface/bus_matrix),
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
// AHB specifics: HSIZE travels through the matrix (byte lanes of sub-word
// transfers); bursts (INCR/WRAP, BUSY) are pipelined beat by beat into the
// directly attached SRAMs, and become single transfers through the matrix.
//
// The body (instances, models, counters, test sequence) is shared by every
// protocol: sram_tb_body.svh, with this file's wiring macros.

`timescale 1ns / 1ps

`ifndef TECH
`define TECH 0
`endif

`define TB_NAME tb_sram_ahb
`define TB_STR "tb_sram_ahb"
`define TB_PROTO "ahb"
`define SRAM_TOP sram_ahb
`define SRAM_DP_TOP sram_ahb_dp

`define XBAR_WIRES(X, NM, NS, DW) \
  wire [NM-1:0]       X``_M_HSEL;   wire [NM*32-1:0]    X``_M_HADDR; \
  wire [NM*2-1:0]     X``_M_HTRANS; wire [NM-1:0]       X``_M_HWRITE; \
  wire [NM*3-1:0]     X``_M_HSIZE;  wire [NM*3-1:0]     X``_M_HBURST; \
  wire [NM*DW-1:0]    X``_M_HWDATA; wire [NM*DW/8-1:0]  X``_M_HWSTRB; \
  wire [NM-1:0]       X``_M_HREADY; wire [NM*DW-1:0]    X``_M_HRDATA; \
  wire [NM-1:0]       X``_M_HRESP; \
  wire [NS-1:0]       X``_S_HSEL;   wire [NS*32-1:0]    X``_S_HADDR; \
  wire [NS*2-1:0]     X``_S_HTRANS; wire [NS-1:0]       X``_S_HWRITE; \
  wire [NS*3-1:0]     X``_S_HSIZE; \
  wire [NS*DW-1:0]    X``_S_HWDATA; wire [NS*DW/8-1:0]  X``_S_HWSTRB; \
  wire [NS-1:0]       X``_S_HREADY; wire [NS*DW-1:0]    X``_S_HRDATA; \
  wire [NS-1:0]       X``_S_HRESP;

`define XBAR(X, NM, NS, DW, CLK, RST, PRIO) \
  bus_matrix_ahb #( \
    .NUM_MASTERS(NM), .NUM_SLAVES(NS), .DATA_W(DW), .ADDR_W(32), .ARB_MODE(1), \
    .M_PRIORITY(PRIO), .S_BASE(slave_bases(NS)), .S_MASK({NS{32'hFFFF_0000}}) \
  ) u_``X ( \
    .clk(CLK), .rst_n(RST), \
    .M_HSEL(X``_M_HSEL), .M_HADDR(X``_M_HADDR), .M_HTRANS(X``_M_HTRANS), \
    .M_HWRITE(X``_M_HWRITE), .M_HSIZE(X``_M_HSIZE), .M_HWDATA(X``_M_HWDATA), \
    .M_HWSTRB(X``_M_HWSTRB), .M_HREADY(X``_M_HREADY), .M_HRDATA(X``_M_HRDATA), \
    .M_HRESP(X``_M_HRESP), \
    .S_HSEL(X``_S_HSEL), .S_HADDR(X``_S_HADDR), .S_HTRANS(X``_S_HTRANS), \
    .S_HWRITE(X``_S_HWRITE), .S_HSIZE(X``_S_HSIZE), .S_HWDATA(X``_S_HWDATA), \
    .S_HWSTRB(X``_S_HWSTRB), .S_HREADY(X``_S_HREADY), .S_HRDATA(X``_S_HRDATA), \
    .S_HRESP(X``_S_HRESP));

`define MST(U, X, I, WD, CLK) \
  sram_tb_ahb_master #(.DW(WD)) U ( \
    .HCLK(CLK), .HSEL(X``_M_HSEL[I]), .HADDR(X``_M_HADDR[I*32+:32]), \
    .HTRANS(X``_M_HTRANS[I*2+:2]), .HWRITE(X``_M_HWRITE[I]), .HSIZE(X``_M_HSIZE[I*3+:3]), \
    .HBURST(X``_M_HBURST[I*3+:3]), .HWDATA(X``_M_HWDATA[I*WD+:WD]), \
    .HWSTRB(X``_M_HWSTRB[I*WD/8+:WD/8]), .HREADY(X``_M_HREADY[I]), \
    .HRDATA(X``_M_HRDATA[I*WD+:WD]), .HRESP(X``_M_HRESP[I]));

`define SLV(P, X, J, DW) \
  .P``HSEL(X``_S_HSEL[J]), .P``HADDR(X``_S_HADDR[J*32+:SAW]), .P``HTRANS(X``_S_HTRANS[J*2+:2]), \
  .P``HWRITE(X``_S_HWRITE[J]), .P``HSIZE(X``_S_HSIZE[J*3+:3]), \
  .P``HWDATA(X``_S_HWDATA[J*DW+:DW]), .P``HWSTRB(X``_S_HWSTRB[J*DW/8+:DW/8]), \
  .P``HREADY(X``_S_HREADY[J]), .P``HRDATA(X``_S_HRDATA[J*DW+:DW]), \
  .P``HREADYOUT(X``_S_HREADY[J]), .P``HRESP(X``_S_HRESP[J])

`define CLKRST(P, CLK, RSTN) .P``HCLK(CLK), .P``HRESETn(RSTN)

`define LINK(X) \
  assign X``_S_HSEL = X``_M_HSEL;     assign X``_S_HADDR = X``_M_HADDR; \
  assign X``_S_HTRANS = X``_M_HTRANS; assign X``_S_HWRITE = X``_M_HWRITE; \
  assign X``_S_HSIZE = X``_M_HSIZE;   assign X``_S_HWDATA = X``_M_HWDATA; \
  assign X``_S_HWSTRB = X``_M_HWSTRB; assign X``_M_HREADY = X``_S_HREADY; \
  assign X``_M_HRDATA = X``_S_HRDATA; assign X``_M_HRESP = X``_S_HRESP;

module tb_sram_ahb;

`include "sram_tb_body.svh"

endmodule : tb_sram_ahb
