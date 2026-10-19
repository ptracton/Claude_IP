// sram_tb_body.svh — Body of the sram system testbench, shared by every protocol.
//
// `include inside module tb_sram_<proto> after its wiring macros:
//   TB_NAME / TB_STR             module name (identifier / string)
//   SRAM_TOP / SRAM_DP_TOP       sram_<proto> / sram_<proto>_dp
//   XBAR_WIRES(X, NM, NS, DW)    wires X_M_* / X_S_* of a matrix (flat-packed)
//   XBAR(X, NM, NS, DW, CLK, RST, PRIO)  bus_matrix_<proto> instance u_X
//     (generic vectors sized with BM_PW / BM_SW below)
//   MST(U, X, I, DW, CLK)        master BFM U on master port I of X
//   SLV(P, X, J, DW)             bus pins (prefix P: none, A_ or B_) on slave port J of X
//   CLKRST(P, CLK, RSTN)         clock / reset pins (RSTN active low)
//   LINK(X)                      wire X's master port 0 straight to its slave port 0
// The system it builds is described in the header of tb_sram_<proto>.sv.

  import sram_tb_pkg::*;

  // +define+VHDL_DUT: the SRAM tops and the matrices are the VHDL twins
  // (mixed-language; the bench, BFMs and models stay SystemVerilog). The VHDL
  // matrix generics are full-width vectors (16 masters x 4 bits, 32 slaves x
  // 32 bits); the SV parameters are sized by the port counts.
`ifdef VHDL_DUT
`define BM_PW(NM) (16 * 4)
`define BM_SW(NS) (32 * 32)
`else
`define BM_PW(NM) (NM * 4)
`define BM_SW(NS) (NS * 32)
`endif

  // Port-B options of a dual port default to port A's. VCS-MX evaluates such
  // a dependent VHDL generic default (READ_LATENCY_B := READ_LATENCY, ...)
  // from the other generic's default, not from its actual, when SV
  // instantiates the VHDL top (pure VHDL and Xcelium are correct): on VCS the
  // bench passes them to the VHDL tops explicitly.
`ifdef VHDL_DUT
`ifdef VCS
`define DP_B(BE, PWE, RL) .BYTE_EN_B(BE), .PARTIAL_WR_ERR_B(PWE), .READ_LATENCY_B(RL),
`endif
`endif
`ifndef DP_B
`define DP_B(BE, PWE, RL)
`endif

  localparam int unsigned TECH   = `TECH;
  localparam bit          SKY130 = (TECH == TB_TECH_SKY130);
  localparam bit          SAED14 = (TECH == TB_TECH_SAED14);
  localparam bit          DP0_CC = SAED14;   // dp0 COMMON_CLK
  localparam int unsigned SAW    = 16;       // SRAM byte-address width

  // -------------------------------------------------------------------------
  // Clocks and resets. clk_b is unrelated to clk_a (13.7 ns vs 10 ns), except
  // on SAED14 where both toggle in the same process (one clock, no delta).
  // -------------------------------------------------------------------------
  logic clk_a = 1'b0;
  logic clk_b = 1'b0;
  logic rst_a_n;
  logic rst_b_n;

  if (DP0_CC) begin : g_one_clk
    always #5 begin
      clk_a = ~clk_a;
      clk_b = ~clk_b;
    end
  end else begin : g_two_clk
    always #5 clk_a = ~clk_a;
    always #6.85 clk_b = ~clk_b;
  end

  // -------------------------------------------------------------------------
  // Matrices and masters (wiring macros from tb_sram_<proto>.sv)
  // -------------------------------------------------------------------------
  function automatic logic [32*5-1:0] slave_bases(int unsigned ns);
    logic [32*5-1:0] b;
    for (int unsigned j = 0; j < 5; j++) b[j*32 +: 32] = 32'(j) << 16;
    return b;
  endfunction

  `XBAR_WIRES(x32, 2, 5, 32)
  `XBAR_WIRES(x8,  1, 4, 8)
  `XBAR_WIRES(x16, 1, 3, 16)
  `XBAR_WIRES(x24, 1, 2, 24)
  `XBAR_WIRES(x64, 1, 2, 64)

  `XBAR(x32, 2, 5, 32, clk_a, rst_a_n, 8'h10)
  `XBAR(x8,  1, 4, 8,  clk_b, rst_b_n, 4'h0)
  `XBAR(x16, 1, 3, 16, clk_a, rst_a_n, 4'h0)
  `XBAR(x24, 1, 2, 24, clk_a, rst_a_n, 4'h0)
  `XBAR(x64, 1, 2, 64, clk_a, rst_a_n, 4'h0)

  `MST(u_m0, x32, 0, 32, clk_a)
  `MST(u_m1, x32, 1, 32, clk_a)
  `MST(u_m2, x8,  0, 8,  clk_b)
  `MST(u_m3, x16, 0, 16, clk_a)
  `MST(u_m4, x24, 0, 24, clk_a)
  `MST(u_m5, x64, 0, 64, clk_a)

  // -------------------------------------------------------------------------
  // Side-band, one set per SRAM instance (index = SB_* in sram_tb_pkg)
  // -------------------------------------------------------------------------
  logic [7:0]  pwr_req    [NSB];
  logic [7:0]  pwr_ack    [NSB];
  logic        clr_req    [NSB];
  logic        clr_done   [NSB];
  logic        busy       [NSB];
  logic        err_irq    [NSB];
  logic [1:0]  ecc_inj    [NSB];
  logic        ecc_corr   [NSB];
  logic        ecc_uncorr [NSB];
  logic        bist_start [NSB];
  logic        bist_done  [NSB];
  logic        bist_fail  [NSB];
  logic [15:0] bist_fail_addr [NSB];

  initial begin
    for (int i = 0; i < NSB; i++) begin
      pwr_req[i]    = '0;
      clr_req[i]    = 1'b0;
      ecc_inj[i]    = 2'b00;
      bist_start[i] = 1'b0;
    end
  end

  // Side-band ports of one instance (N = SB index, NPD = power domains).
`define SB(N, NPD, AW) \
  .pwr_mode_req_i(pwr_req[N][2*NPD-1:0]), .pwr_mode_ack_o(pwr_ack[N][2*NPD-1:0]), \
  .clr_req_i(clr_req[N]), .clr_done_o(clr_done[N]), .busy_o(busy[N]), .err_irq_o(err_irq[N]), \
  .ecc_inj_i(ecc_inj[N]), .ecc_corr_o(ecc_corr[N]), .ecc_uncorr_o(ecc_uncorr[N]), \
  .bist_start_i(bist_start[N]), .bist_done_o(bist_done[N]), .bist_fail_o(bist_fail[N]), \
  .bist_fail_addr_o(bist_fail_addr[N][AW-1:0])

  // -------------------------------------------------------------------------
  // SRAM instances
  // -------------------------------------------------------------------------
  `SRAM_TOP #(.TECH(TECH), .ADDR_W(SAW), .WIDTH(32), .DEPTH(1024)) u_s32 (
    `CLKRST(, clk_a, rst_a_n), `SLV(, x32, 0, 32), `SB(SB_S32, 1, 10));

  `SRAM_TOP #(.TECH(TECH), .ADDR_W(SAW), .WIDTH(32), .DEPTH(512), .ECC_EN(1), .BIST_EN(1),
             .BANK_PG(1), .NUM_BANKS(2), .READ_LATENCY(2)) u_s32e (
    `CLKRST(, clk_a, rst_a_n), `SLV(, x32, 1, 32), `SB(SB_S32E, 2, 9));

  `SRAM_DP_TOP #(.TECH(TECH), .ADDR_W(SAW), .WIDTH(32), .DEPTH(256), .ECC_EN(1), .WIDTH_B(8),
                `DP_B(1, 1, 1) .BIST_EN(1), .COMMON_CLK(DP0_CC)) u_dp0 (
    `CLKRST(A_, clk_a, rst_a_n), `CLKRST(B_, clk_b, rst_b_n),
    `SLV(A_, x32, 2, 32), `SLV(B_, x8, 1, 8), `SB(SB_DP0, 1, 8));

  `SRAM_TOP #(.TECH(TECH), .ADDR_W(SAW), .WIDTH(8), .DEPTH(2048), .READ_LATENCY(2)) u_s8 (
    `CLKRST(, clk_b, rst_b_n), `SLV(, x8, 0, 8), `SB(SB_S8, 1, 11));

  `SRAM_TOP #(.TECH(TECH), .ADDR_W(SAW), .WIDTH(16), .DEPTH(4096), .BYTE_EN(0),
             .PARTIAL_WR_ERR(1)) u_s16 (
    `CLKRST(, clk_a, rst_a_n), `SLV(, x16, 0, 16), `SB(SB_S16, 1, 12));

  `SRAM_TOP #(.TECH(TECH), .ADDR_W(SAW), .WIDTH(16), .DEPTH(64), .BYTE_EN(0),
             .PARTIAL_WR_ERR(0), .PWR_GATE(0)) u_s16w (
    `CLKRST(, clk_a, rst_a_n), `SLV(, x16, 1, 16), `SB(SB_S16W, 1, 6));

  `SRAM_DP_TOP #(.TECH(TECH), .ADDR_W(SAW), .WIDTH(16), .DEPTH(1024), .BIST_EN(1), .WIDTH_B(64),
                .BYTE_EN_B(0), .PARTIAL_WR_ERR_B(1), .READ_LATENCY_B(2), .COMMON_CLK(1)) u_dp1 (
    `CLKRST(A_, clk_a, rst_a_n), `CLKRST(B_, clk_a, rst_a_n),
    `SLV(A_, x16, 2, 16), `SLV(B_, x64, 1, 64), `SB(SB_DP1, 1, 10));

  `SRAM_DP_TOP #(.TECH(TECH), .ADDR_W(SAW), .WIDTH(32), .DEPTH(256), .ECC_EN(1), .WIDTH_B(32),
                .BANK_PG(1), .NUM_BANKS(2), .READ_LATENCY(2), `DP_B(1, 1, 2) .COMMON_CLK(1)) u_dp2 (
    `CLKRST(A_, clk_a, rst_a_n), `CLKRST(B_, clk_a, rst_a_n),
    `SLV(A_, x32, 3, 32), `SLV(B_, x32, 4, 32), `SB(SB_DP2, 2, 8));

  // Deep 8-bit dual port, both ports on clk_b: several primitive rows in every
  // technology's two-port leaf.
  `SRAM_DP_TOP #(.TECH(TECH), .ADDR_W(SAW), .WIDTH(8), .DEPTH(4096), .WIDTH_B(8),
                `DP_B(1, 1, 1) .COMMON_CLK(1)) u_dp3 (
    `CLKRST(A_, clk_b, rst_b_n), `CLKRST(B_, clk_b, rst_b_n),
    `SLV(A_, x8, 2, 8), `SLV(B_, x8, 3, 8), `SB(SB_DP3, 1, 12));

  `SRAM_TOP #(.TECH(TECH), .ADDR_W(SAW), .WIDTH(24), .DEPTH(256), .ECC_EN(1)) u_s24 (
    `CLKRST(, clk_a, rst_a_n), `SLV(, x24, 0, 24), `SB(SB_S24, 1, 8));

  `SRAM_TOP #(.TECH(TECH), .ADDR_W(SAW), .WIDTH(24), .DEPTH(128), .BANK_PG(1),
             .NUM_BANKS(4)) u_s24b (
    `CLKRST(, clk_a, rst_a_n), `SLV(, x24, 1, 24), `SB(SB_S24B, 4, 7));

  `SRAM_TOP #(.TECH(TECH), .ADDR_W(SAW), .WIDTH(64), .DEPTH(512), .ECC_EN(1), .READ_LATENCY(2),
             .BIST_EN(1)) u_s64 (
    `CLKRST(, clk_a, rst_a_n), `SLV(, x64, 0, 64), `SB(SB_S64, 1, 9));

  // Directly attached SRAMs: master port wired straight to the slave pins.
  for (genvar gp = 0; gp < 2; gp++) begin : g_direct
    `XBAR_WIRES(d, 1, 1, 32)
    `LINK(d)
    `MST(u_m, d, 0, 32, clk_a)
    `SRAM_TOP #(.TECH(TECH), .ADDR_W(SAW), .WIDTH(32), .DEPTH(256), .READ_LATENCY(gp + 1)) u_s (
      `CLKRST(, clk_a, rst_a_n), `SLV(, d, 0, 32), `SB(SB_S32P + gp, 1, 8));
  end

  // -------------------------------------------------------------------------
  // Reference models (one per SRAM, on the memory bus inside the top-level)
  // -------------------------------------------------------------------------
`define MODEL_A(U, I) \
  .mem_req(U.mem_req), .mem_gnt(U.mem_gnt), .mem_we(U.mem_we), .mem_addr(U.mem_addr), \
  .mem_be(U.mem_be), .mem_wdata(U.mem_wdata), .mem_rvalid(U.mem_rvalid), \
  .mem_rdata(U.mem_rdata), .mem_err(U.mem_err), \
  .pwr_mode_req(U.pwr_mode_req_i), .pwr_mode_ack(U.pwr_mode_ack_o), .clr_req(U.clr_req_i), \
  .clr_done(U.clr_done_o), .bist_done(U.bist_done_o), .ecc_inj(U.ecc_inj_i), \
  .mismatch_o(), .mismatch_b_o(), .n_checked(n_chk[I]), .n_mismatch(n_mis[I])

`define MODEL_DP(U, I, CLKB, RSTB) \
  .mem_req(U.a_mem_req), .mem_gnt(U.a_mem_gnt), .mem_we(U.a_mem_we), .mem_addr(U.a_mem_addr), \
  .mem_be(U.a_mem_be), .mem_wdata(U.a_mem_wdata), .mem_rvalid(U.a_mem_rvalid), \
  .mem_rdata(U.a_mem_rdata), .mem_err(U.a_mem_err), \
  .clk_b(CLKB), .rst_b_n(RSTB), \
  .mem_b_req(U.b_mem_req), .mem_b_gnt(U.b_mem_gnt), .mem_b_we(U.b_mem_we), \
  .mem_b_addr(U.b_mem_addr), .mem_b_be(U.b_mem_be), .mem_b_wdata(U.b_mem_wdata), \
  .mem_b_rvalid(U.b_mem_rvalid), .mem_b_rdata(U.b_mem_rdata), .mem_b_err(U.b_mem_err), \
  .pwr_mode_req(U.pwr_mode_req_i), .pwr_mode_ack(U.pwr_mode_ack_o), .clr_req(U.clr_req_i), \
  .clr_done(U.clr_done_o), .bist_done(U.bist_done_o), .ecc_inj(U.ecc_inj_i), \
  .mismatch_o(), .mismatch_b_o(), .n_checked(n_chk[I]), .n_mismatch(n_mis[I])

  int unsigned n_chk [NSB];
  int unsigned n_mis [NSB];

  sram_model #(.ADDR_W(SAW), .WIDTH(32), .DEPTH(1024)) u_mdl_s32 (
    .clk(clk_a), .rst_n(rst_a_n), `MODEL_A(u_s32, SB_S32));
  sram_model #(.ADDR_W(SAW), .WIDTH(32), .DEPTH(512), .ECC_EN(1), .BANK_PG(1),
               .NUM_BANKS(2), .READ_LATENCY(2)) u_mdl_s32e (
    .clk(clk_a), .rst_n(rst_a_n), `MODEL_A(u_s32e, SB_S32E));
  sram_model #(.ADDR_W(SAW), .WIDTH(32), .DEPTH(256), .ECC_EN(1), .DUAL_PORT(1), .WIDTH_B(8),
               .READ_ONLY_B(SKY130)) u_mdl_dp0 (
    .clk(clk_a), .rst_n(rst_a_n), `MODEL_DP(u_dp0, SB_DP0, clk_b, rst_b_n));
  sram_model #(.ADDR_W(SAW), .WIDTH(8), .DEPTH(2048), .READ_LATENCY(2)) u_mdl_s8 (
    .clk(clk_b), .rst_n(rst_b_n), `MODEL_A(u_s8, SB_S8));
  sram_model #(.ADDR_W(SAW), .WIDTH(16), .DEPTH(4096), .BYTE_EN(0),
               .PARTIAL_WR_ERR(1)) u_mdl_s16 (
    .clk(clk_a), .rst_n(rst_a_n), `MODEL_A(u_s16, SB_S16));
  sram_model #(.ADDR_W(SAW), .WIDTH(16), .DEPTH(64), .BYTE_EN(0),
               .PARTIAL_WR_ERR(0), .PWR_GATE(0)) u_mdl_s16w (
    .clk(clk_a), .rst_n(rst_a_n), `MODEL_A(u_s16w, SB_S16W));
  sram_model #(.ADDR_W(SAW), .WIDTH(16), .DEPTH(1024), .DUAL_PORT(1), .WIDTH_B(64),
               .BYTE_EN_B(0), .PARTIAL_WR_ERR_B(1), .READ_LATENCY_B(2),
               .READ_ONLY_B(SKY130)) u_mdl_dp1 (
    .clk(clk_a), .rst_n(rst_a_n), `MODEL_DP(u_dp1, SB_DP1, clk_a, rst_a_n));
  sram_model #(.ADDR_W(SAW), .WIDTH(32), .DEPTH(256), .ECC_EN(1), .BANK_PG(1), .NUM_BANKS(2),
               .READ_LATENCY(2), .DUAL_PORT(1), .WIDTH_B(32), .READ_ONLY_B(SKY130)) u_mdl_dp2 (
    .clk(clk_a), .rst_n(rst_a_n), `MODEL_DP(u_dp2, SB_DP2, clk_a, rst_a_n));
  sram_model #(.ADDR_W(SAW), .WIDTH(8), .DEPTH(4096), .DUAL_PORT(1), .WIDTH_B(8),
               .READ_ONLY_B(SKY130)) u_mdl_dp3 (
    .clk(clk_b), .rst_n(rst_b_n), `MODEL_DP(u_dp3, SB_DP3, clk_b, rst_b_n));
  sram_model #(.ADDR_W(SAW), .WIDTH(24), .DEPTH(256), .ECC_EN(1)) u_mdl_s24 (
    .clk(clk_a), .rst_n(rst_a_n), `MODEL_A(u_s24, SB_S24));
  sram_model #(.ADDR_W(SAW), .WIDTH(24), .DEPTH(128), .BANK_PG(1), .NUM_BANKS(4)) u_mdl_s24b (
    .clk(clk_a), .rst_n(rst_a_n), `MODEL_A(u_s24b, SB_S24B));
  sram_model #(.ADDR_W(SAW), .WIDTH(64), .DEPTH(512), .ECC_EN(1), .READ_LATENCY(2)) u_mdl_s64 (
    .clk(clk_a), .rst_n(rst_a_n), `MODEL_A(u_s64, SB_S64));
  sram_model #(.ADDR_W(SAW), .WIDTH(32), .DEPTH(256)) u_mdl_s32p (
    .clk(clk_a), .rst_n(rst_a_n), `MODEL_A(g_direct[0].u_s, SB_S32P));
  sram_model #(.ADDR_W(SAW), .WIDTH(32), .DEPTH(256), .READ_LATENCY(2)) u_mdl_s32q (
    .clk(clk_a), .rst_n(rst_a_n), `MODEL_A(g_direct[1].u_s, SB_S32Q));

  // -------------------------------------------------------------------------
  // Side-band event counters (each in its instance's clock domain)
  // -------------------------------------------------------------------------
  int unsigned n_corr [NSB];
  int unsigned n_uncorr [NSB];
  int unsigned n_irq [NSB];
  int unsigned n_clr_done [NSB];
  int unsigned n_bist_done [NSB];
  int unsigned n_busy [NSB];     // cycles with busy_o high

  for (genvar gi = 0; gi < NSB; gi++) begin : g_cnt
    if (gi == SB_S8 || gi == SB_DP3) begin : g_b
      always @(posedge clk_b) count(gi);
    end else begin : g_a
      always @(posedge clk_a) count(gi);
    end
  end

  task automatic count(input int i);
    if (ecc_corr[i] === 1'b1)   n_corr[i]++;
    if (ecc_uncorr[i] === 1'b1) n_uncorr[i]++;
    if (err_irq[i] === 1'b1)    n_irq[i]++;
    if (clr_done[i] === 1'b1)   n_clr_done[i]++;
    if (bist_done[i] === 1'b1)  n_bist_done[i]++;
    if (busy[i] === 1'b1)       n_busy[i]++;
  endtask

  // Same-word holds on dp1 / dp2 (common clock): a port waits for the other
  // (dp2 also for a read-modify-write of the other port, either way).
  int unsigned n_dp1_hold;
  int unsigned n_dp2_hold;
  always @(posedge clk_a) begin
    if (u_dp1.u_core.mem_b_req_i && u_dp1.u_core.b_stall &&
        !u_dp1.u_core.clr_pending && !u_dp1.u_core.bist_pending) n_dp1_hold++;
    if (((u_dp2.u_core.mem_b_req_i && u_dp2.u_core.b_stall) ||
         (u_dp2.u_core.mem_req_i && u_dp2.u_core.a_stall)) &&
        !u_dp2.u_core.clr_pending && !u_dp2.u_core.bist_pending) n_dp2_hold++;
  end

  // -------------------------------------------------------------------------
  // BIST fault injection (test_bist): stuck-at-0 on stored bit 3 of word
  // bf_addr[I] while bf_on[I]. A read of that word is seen at the clock edge
  // that issues it; the array output is forced from the following falling
  // edge for one cycle, so the compare at the next rising edge sees it.
  // VHDL DUT on VCS: a native SV force cannot write a bit of a VHDL signal
  // (nor a VHDL signal that the bench also reads), so $hdl_xmr_force does.
  // -------------------------------------------------------------------------
  int unsigned bf_addr [NSB];
  bit          bf_on   [NSB];

`ifdef VHDL_DUT
`ifdef VCS
`define BF_FORCE(U) $hdl_xmr_force({`TB_STR, ".", `"U`", ".u_core.arr_rdata[3]"}, "0", "0 ns", \
                                   "freeze", "", 0)
`define BF_RELEASE(U) $hdl_xmr_release({`TB_STR, ".", `"U`", ".u_core.arr_rdata[3]"}, 0)
`endif
`endif
`ifndef BF_FORCE
`define BF_FORCE(U) force U.u_core.arr_rdata[3] = 1'b0
`define BF_RELEASE(U) release U.u_core.arr_rdata[3]
`endif

`define BIST_FAULT(U, I) \
  if (1) begin : g_bf_``U \
    logic hit_q; \
    logic forced; \
    initial forced = 1'b0; \
    always @(posedge clk_a) hit_q <= bf_on[I] && U.u_core.arr_cs && !U.u_core.arr_we && \
                                     (int'(U.u_core.arr_idx) == int'(bf_addr[I])); \
    always @(negedge clk_a) begin \
      if (hit_q) begin \
        `BF_FORCE(U); \
        forced = 1'b1; \
      end else if (forced) begin \
        `BF_RELEASE(U); \
        forced = 1'b0; \
      end \
    end \
  end

  `BIST_FAULT(u_s32e, SB_S32E)
  `BIST_FAULT(u_s64, SB_S64)
  `BIST_FAULT(u_dp1, SB_DP1)
  `BIST_FAULT(u_dp0, SB_DP0)

  // -------------------------------------------------------------------------
  // Tests
  // -------------------------------------------------------------------------
  `include "sram_tb_helpers.sv"
  `include "test_reset.sv"
  `include "test_params.sv"
  `include "test_access.sv"
  `include "test_burst.sv"
  `include "test_pipeline.sv"
  `include "test_contention.sv"
  `include "test_ecc.sv"
  `include "test_power.sv"
  `include "test_clear.sv"
  `include "test_bist.sv"
  `include "test_dp.sv"
  `include "test_reset_busy.sv"

`ifdef VCS
  initial if ($test$plusargs("waves")) $vcdpluson(0, `TB_NAME);
`endif

  string only;

  initial begin
    if (!$value$plusargs("test=%s", only)) only = "all";
    tb_init();
    reset_all();
    if (only == "all" || only == "reset")      test_reset();
    if (only == "all" || only == "params")     test_params();
    if (only == "all" || only == "access")     test_access();
    if (only == "all" || only == "burst")      test_burst();
    if (only == "all" || only == "pipeline")   test_pipeline();
    if (only == "all" || only == "contention") test_contention();
    if (only == "all" || only == "ecc")        test_ecc();
    if (only == "all" || only == "power")      test_power();
    if (only == "all" || only == "clear")      test_clear();
    if (only == "all" || only == "bist")       test_bist();
    if (only == "all" || only == "dp")         test_dp();
    if (only == "all" || only == "resetbusy")  test_reset_busy();
    finish_all();
  end

  initial begin
    #500ms;
    $display("FAIL %s: global timeout", `TB_STR);
    $finish(1);
  end

