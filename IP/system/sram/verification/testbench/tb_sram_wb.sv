// tb_sram_wb.sv — Wishbone B4 classic system testbench for the sram IP (Step 4).
//
// The SRAMs are reached through bus_matrix_wb (IP/interface/bus_matrix),
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
// Wishbone specifics: no size signal or bursts. SEL carries the byte lanes
// of every transfer (reads too); a "burst" is the same address sequence as
// back-to-back classic cycles inside one CYC. ERR is the error response.
//
// The body (instances, models, counters, test sequence) is shared by every
// protocol: sram_tb_body.svh, with this file's wiring macros.

`timescale 1ns / 1ps

`ifndef TECH
`define TECH 0
`endif

`define TB_NAME tb_sram_wb
`define TB_STR "tb_sram_wb"
`define TB_PROTO "wb"
`define SRAM_TOP sram_wb
`define SRAM_DP_TOP sram_wb_dp

`define XBAR_WIRES(X, NM, NS, DW) \
  wire [NM-1:0]      X``_M_CYC;    wire [NM-1:0]      X``_M_STB; \
  wire [NM-1:0]      X``_M_WE;     wire [NM*32-1:0]   X``_M_ADR; \
  wire [NM*DW-1:0]   X``_M_DAT_I;  wire [NM*DW/8-1:0] X``_M_SEL; \
  wire [NM*DW-1:0]   X``_M_DAT_O;  wire [NM-1:0]      X``_M_ACK; \
  wire [NM-1:0]      X``_M_ERR; \
  wire [NS-1:0]      X``_S_CYC;    wire [NS-1:0]      X``_S_STB; \
  wire [NS-1:0]      X``_S_WE;     wire [NS*32-1:0]   X``_S_ADR; \
  wire [NS*DW-1:0]   X``_S_DAT_O;  wire [NS*DW/8-1:0] X``_S_SEL; \
  wire [NS*DW-1:0]   X``_S_DAT_I;  wire [NS-1:0]      X``_S_ACK; \
  wire [NS-1:0]      X``_S_ERR;

`define XBAR(X, NM, NS, DW, CLK, RST, PRIO) \
  bus_matrix_wb #( \
    .NUM_MASTERS(NM), .NUM_SLAVES(NS), .DATA_W(DW), .ADDR_W(32), .ARB_MODE(1), \
    .M_PRIORITY(PRIO), .S_BASE(slave_bases(NS)), .S_MASK({NS{32'hFFFF_0000}}) \
  ) u_``X ( \
    .clk(CLK), .rst_n(RST), \
    .M_CYC(X``_M_CYC), .M_STB(X``_M_STB), .M_WE(X``_M_WE), .M_ADR(X``_M_ADR), \
    .M_DAT_I(X``_M_DAT_I), .M_SEL(X``_M_SEL), .M_DAT_O(X``_M_DAT_O), .M_ACK(X``_M_ACK), \
    .M_ERR(X``_M_ERR), \
    .S_CYC(X``_S_CYC), .S_STB(X``_S_STB), .S_WE(X``_S_WE), .S_ADR(X``_S_ADR), \
    .S_DAT_O(X``_S_DAT_O), .S_SEL(X``_S_SEL), .S_DAT_I(X``_S_DAT_I), .S_ACK(X``_S_ACK), \
    .S_ERR(X``_S_ERR));

`define MST(U, X, I, WD, CLK) \
  sram_tb_wb_master #(.DW(WD)) U ( \
    .CLK_I(CLK), .CYC_O(X``_M_CYC[I]), .STB_O(X``_M_STB[I]), .WE_O(X``_M_WE[I]), \
    .ADR_O(X``_M_ADR[I*32+:32]), .DAT_O(X``_M_DAT_I[I*WD+:WD]), \
    .SEL_O(X``_M_SEL[I*WD/8+:WD/8]), .DAT_I(X``_M_DAT_O[I*WD+:WD]), \
    .ACK_I(X``_M_ACK[I]), .ERR_I(X``_M_ERR[I]));

`define SLV(P, X, J, DW) \
  .P``CYC_I(X``_S_CYC[J]), .P``STB_I(X``_S_STB[J]), .P``WE_I(X``_S_WE[J]), \
  .P``ADR_I(X``_S_ADR[J*32+:SAW]), .P``DAT_I(X``_S_DAT_O[J*DW+:DW]), \
  .P``SEL_I(X``_S_SEL[J*DW/8+:DW/8]), .P``DAT_O(X``_S_DAT_I[J*DW+:DW]), \
  .P``ACK_O(X``_S_ACK[J]), .P``ERR_O(X``_S_ERR[J])

// Wishbone reset is active high.
`define CLKRST(P, CLK, RSTN) .P``CLK_I(CLK), .P``RST_I(!(RSTN))

`define LINK(X) \
  assign X``_S_CYC = X``_M_CYC;       assign X``_S_STB = X``_M_STB; \
  assign X``_S_WE = X``_M_WE;         assign X``_S_ADR = X``_M_ADR; \
  assign X``_S_DAT_O = X``_M_DAT_I;   assign X``_S_SEL = X``_M_SEL; \
  assign X``_M_DAT_O = X``_S_DAT_I;   assign X``_M_ACK = X``_S_ACK; \
  assign X``_M_ERR = X``_S_ERR;

module tb_sram_wb;

`include "sram_tb_body.svh"

endmodule : tb_sram_wb
