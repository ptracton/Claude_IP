// tb_sram_apb.sv — APB4 system testbench for the sram IP (Step 4).
//
// The SRAMs are reached through bus_matrix_apb (IP/interface/bus_matrix),
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
// APB specifics: no size signal or bursts. The BFM turns a sub-word
// transfer into PSTRB (writes) and reads whole words; a "burst" is the same
// address sequence as back-to-back APB transfers.
//
// The body (instances, models, counters, test sequence) is shared by every
// protocol: sram_tb_body.svh, with this file's wiring macros.

`timescale 1ns / 1ps

`ifndef TECH
`define TECH 0
`endif

`define TB_NAME tb_sram_apb
`define TB_STR "tb_sram_apb"
`define TB_PROTO "apb"
`define SRAM_TOP sram_apb
`define SRAM_DP_TOP sram_apb_dp

`define XBAR_WIRES(X, NM, NS, DW) \
  wire [NM-1:0]      X``_M_PSEL;    wire [NM-1:0]      X``_M_PENABLE; \
  wire [NM*32-1:0]   X``_M_PADDR;   wire [NM-1:0]      X``_M_PWRITE; \
  wire [NM*DW-1:0]   X``_M_PWDATA;  wire [NM*DW/8-1:0] X``_M_PSTRB; \
  wire [NM*DW-1:0]   X``_M_PRDATA;  wire [NM-1:0]      X``_M_PREADY; \
  wire [NM-1:0]      X``_M_PSLVERR; \
  wire [NS-1:0]      X``_S_PSEL;    wire [NS-1:0]      X``_S_PENABLE; \
  wire [NS*32-1:0]   X``_S_PADDR;   wire [NS-1:0]      X``_S_PWRITE; \
  wire [NS*DW-1:0]   X``_S_PWDATA;  wire [NS*DW/8-1:0] X``_S_PSTRB; \
  wire [NS*DW-1:0]   X``_S_PRDATA;  wire [NS-1:0]      X``_S_PREADY; \
  wire [NS-1:0]      X``_S_PSLVERR;

`define XBAR(X, NM, NS, DW, CLK, RST, PRIO) \
  bus_matrix_apb #( \
    .NUM_MASTERS(NM), .NUM_SLAVES(NS), .DATA_W(DW), .ADDR_W(32), .ARB_MODE(1), \
    .M_PRIORITY(PRIO), .S_BASE(slave_bases(NS)), .S_MASK({NS{32'hFFFF_0000}}) \
  ) u_``X ( \
    .clk(CLK), .rst_n(RST), \
    .M_PSEL(X``_M_PSEL), .M_PENABLE(X``_M_PENABLE), .M_PADDR(X``_M_PADDR), \
    .M_PWRITE(X``_M_PWRITE), .M_PWDATA(X``_M_PWDATA), .M_PSTRB(X``_M_PSTRB), \
    .M_PRDATA(X``_M_PRDATA), .M_PREADY(X``_M_PREADY), .M_PSLVERR(X``_M_PSLVERR), \
    .S_PSEL(X``_S_PSEL), .S_PENABLE(X``_S_PENABLE), .S_PADDR(X``_S_PADDR), \
    .S_PWRITE(X``_S_PWRITE), .S_PWDATA(X``_S_PWDATA), .S_PSTRB(X``_S_PSTRB), \
    .S_PRDATA(X``_S_PRDATA), .S_PREADY(X``_S_PREADY), .S_PSLVERR(X``_S_PSLVERR));

`define MST(U, X, I, WD, CLK) \
  sram_tb_apb_master #(.DW(WD)) U ( \
    .PCLK(CLK), .PSEL(X``_M_PSEL[I]), .PENABLE(X``_M_PENABLE[I]), \
    .PADDR(X``_M_PADDR[I*32+:32]), .PWRITE(X``_M_PWRITE[I]), \
    .PWDATA(X``_M_PWDATA[I*WD+:WD]), .PSTRB(X``_M_PSTRB[I*WD/8+:WD/8]), \
    .PREADY(X``_M_PREADY[I]), .PRDATA(X``_M_PRDATA[I*WD+:WD]), .PSLVERR(X``_M_PSLVERR[I]));

`define SLV(P, X, J, DW) \
  .P``PSEL(X``_S_PSEL[J]), .P``PENABLE(X``_S_PENABLE[J]), .P``PADDR(X``_S_PADDR[J*32+:SAW]), \
  .P``PWRITE(X``_S_PWRITE[J]), .P``PWDATA(X``_S_PWDATA[J*DW+:DW]), \
  .P``PSTRB(X``_S_PSTRB[J*DW/8+:DW/8]), .P``PRDATA(X``_S_PRDATA[J*DW+:DW]), \
  .P``PREADY(X``_S_PREADY[J]), .P``PSLVERR(X``_S_PSLVERR[J])

`define CLKRST(P, CLK, RSTN) .P``PCLK(CLK), .P``PRESETn(RSTN)

`define LINK(X) \
  assign X``_S_PSEL = X``_M_PSEL;     assign X``_S_PENABLE = X``_M_PENABLE; \
  assign X``_S_PADDR = X``_M_PADDR;   assign X``_S_PWRITE = X``_M_PWRITE; \
  assign X``_S_PWDATA = X``_M_PWDATA; assign X``_S_PSTRB = X``_M_PSTRB; \
  assign X``_M_PRDATA = X``_S_PRDATA; assign X``_M_PREADY = X``_S_PREADY; \
  assign X``_M_PSLVERR = X``_S_PSLVERR;

module tb_sram_apb;

`include "sram_tb_body.svh"

endmodule : tb_sram_apb
