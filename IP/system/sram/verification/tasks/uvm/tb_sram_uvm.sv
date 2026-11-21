// tb_sram_uvm.sv — Top-level of the sram UVM bench (Step 6).
//
// One DUT, chosen at compile time (uvm_sram.py sets the defines):
//   protocol  SRAM_PROTO_APB | SRAM_PROTO_AHB | SRAM_PROTO_AXI4L | SRAM_PROTO_WB
//   config    SRAM_CFG_BASE  32 x 1024, defaults (single port)
//             SRAM_CFG_FULL  32 x 1024, ECC + BANK_PG (2 banks) + BIST, READ_LATENCY 2
//             SRAM_CFG_DP    dual port, A 32 x 1024 / B 8 x 4096; port B on its own
//                            clock (13.7 ns vs 10 ns), except SAED14 (COMMON_CLK = 1,
//                            one clock); SKY130 port B is read-only
//   TECH=<sram_pkg::TECH_*>, VHDL_DUT (the VHDL top, mixed language), VCS
//
// The DUT pins go through local wires to the UVM interfaces (sram_bus_if per
// port, sram_sb_if for the side band), which keeps the VHDL-top port maps
// plain signals. sram_model watches the memory bus inside the top as a second,
// independent checker; the scoreboard reads its counters at the end. The
// read-path fault knob (full config) makes one stored data bit of one word read
// stuck at 0 or 1 (BIST fault, ECC single errors at every data position).

`timescale 1ns / 1ps

`include "uvm_macros.svh"

`ifndef TECH
`define TECH 0
`endif

// ---- protocol wiring --------------------------------------------------------------
`ifdef SRAM_PROTO_AHB
`define PROTO_STR "ahb"
`define SRAM_SP sram_ahb
`define SRAM_DP sram_ahb_dp
`define BUS_WIRES(X, W) \
  logic X``_HSEL, X``_HWRITE, X``_HREADY, X``_HRESP; logic [1:0] X``_HTRANS; \
  logic [2:0] X``_HSIZE; logic [AW-1:0] X``_HADDR; logic [W-1:0] X``_HWDATA, X``_HRDATA; \
  logic [W/8-1:0] X``_HWSTRB;
`define BUS_LINK(X, IF) \
  assign X``_HSEL = IF.HSEL;     assign X``_HADDR = IF.HADDR[AW-1:0]; \
  assign X``_HTRANS = IF.HTRANS; assign X``_HWRITE = IF.HWRITE; assign X``_HSIZE = IF.HSIZE; \
  assign X``_HWDATA = IF.HWDATA[$bits(X``_HWDATA)-1:0]; \
  assign X``_HWSTRB = IF.HWSTRB[$bits(X``_HWSTRB)-1:0]; \
  assign IF.HRDATA = 64'(X``_HRDATA); assign IF.HREADY = X``_HREADY; assign IF.HRESP = X``_HRESP;
`define BUS_PINS(P, X) \
  .P``HSEL(X``_HSEL), .P``HADDR(X``_HADDR), .P``HTRANS(X``_HTRANS), .P``HWRITE(X``_HWRITE), \
  .P``HSIZE(X``_HSIZE), .P``HWDATA(X``_HWDATA), .P``HWSTRB(X``_HWSTRB), \
  .P``HREADY(X``_HREADY), .P``HRDATA(X``_HRDATA), .P``HREADYOUT(X``_HREADY), \
  .P``HRESP(X``_HRESP)
`define CLKRST(P, CLK, RSTN) .P``HCLK(CLK), .P``HRESETn(RSTN)
`elsif SRAM_PROTO_AXI4L
`define PROTO_STR "axi4l"
`define SRAM_SP sram_axi4l
`define SRAM_DP sram_axi4l_dp
`define BUS_WIRES(X, W) \
  logic X``_AWVALID, X``_AWREADY, X``_WVALID, X``_WREADY, X``_BVALID, X``_BREADY; \
  logic X``_ARVALID, X``_ARREADY, X``_RVALID, X``_RREADY; logic [1:0] X``_BRESP, X``_RRESP; \
  logic [AW-1:0] X``_AWADDR, X``_ARADDR; logic [W-1:0] X``_WDATA, X``_RDATA; \
  logic [W/8-1:0] X``_WSTRB;
`define BUS_LINK(X, IF) \
  assign X``_AWVALID = IF.AWVALID; assign X``_AWADDR = IF.AWADDR[AW-1:0]; \
  assign X``_WVALID = IF.WVALID;   assign X``_WDATA = IF.WDATA[$bits(X``_WDATA)-1:0]; \
  assign X``_WSTRB = IF.WSTRB[$bits(X``_WSTRB)-1:0]; assign X``_BREADY = IF.BREADY; \
  assign X``_ARVALID = IF.ARVALID; assign X``_ARADDR = IF.ARADDR[AW-1:0]; \
  assign X``_RREADY = IF.RREADY; \
  assign IF.AWREADY = X``_AWREADY; assign IF.WREADY = X``_WREADY; assign IF.BVALID = X``_BVALID; \
  assign IF.BRESP = X``_BRESP; assign IF.ARREADY = X``_ARREADY; assign IF.RVALID = X``_RVALID; \
  assign IF.RDATA = 64'(X``_RDATA); assign IF.RRESP = X``_RRESP;
`define BUS_PINS(P, X) \
  .P``AWVALID(X``_AWVALID), .P``AWREADY(X``_AWREADY), .P``AWADDR(X``_AWADDR), \
  .P``WVALID(X``_WVALID), .P``WREADY(X``_WREADY), .P``WDATA(X``_WDATA), .P``WSTRB(X``_WSTRB), \
  .P``BVALID(X``_BVALID), .P``BREADY(X``_BREADY), .P``BRESP(X``_BRESP), \
  .P``ARVALID(X``_ARVALID), .P``ARREADY(X``_ARREADY), .P``ARADDR(X``_ARADDR), \
  .P``RVALID(X``_RVALID), .P``RREADY(X``_RREADY), .P``RDATA(X``_RDATA), .P``RRESP(X``_RRESP)
`define CLKRST(P, CLK, RSTN) .P``ACLK(CLK), .P``ARESETn(RSTN)
`elsif SRAM_PROTO_WB
`define PROTO_STR "wb"
`define SRAM_SP sram_wb
`define SRAM_DP sram_wb_dp
`define BUS_WIRES(X, W) \
  logic X``_CYC, X``_STB, X``_WE, X``_ACK, X``_ERR; logic [AW-1:0] X``_ADR; \
  logic [W-1:0] X``_DAT_W, X``_DAT_R; logic [W/8-1:0] X``_SEL;
`define BUS_LINK(X, IF) \
  assign X``_CYC = IF.CYC; assign X``_STB = IF.STB; assign X``_WE = IF.WE; \
  assign X``_ADR = IF.ADR[AW-1:0]; assign X``_DAT_W = IF.DAT_W[$bits(X``_DAT_W)-1:0]; \
  assign X``_SEL = IF.SEL[$bits(X``_SEL)-1:0]; \
  assign IF.DAT_R = 64'(X``_DAT_R); assign IF.ACK = X``_ACK; assign IF.ERR = X``_ERR;
`define BUS_PINS(P, X) \
  .P``CYC_I(X``_CYC), .P``STB_I(X``_STB), .P``WE_I(X``_WE), .P``ADR_I(X``_ADR), \
  .P``DAT_I(X``_DAT_W), .P``SEL_I(X``_SEL), .P``DAT_O(X``_DAT_R), .P``ACK_O(X``_ACK), \
  .P``ERR_O(X``_ERR)
// Wishbone reset is active high.
`define CLKRST(P, CLK, RSTN) .P``CLK_I(CLK), .P``RST_I(!(RSTN))
`else
`define PROTO_STR "apb"
`define SRAM_SP sram_apb
`define SRAM_DP sram_apb_dp
`define BUS_WIRES(X, W) \
  logic X``_PSEL, X``_PENABLE, X``_PWRITE, X``_PREADY, X``_PSLVERR; logic [AW-1:0] X``_PADDR; \
  logic [W-1:0] X``_PWDATA, X``_PRDATA; logic [W/8-1:0] X``_PSTRB;
`define BUS_LINK(X, IF) \
  assign X``_PSEL = IF.PSEL; assign X``_PENABLE = IF.PENABLE; \
  assign X``_PADDR = IF.PADDR[AW-1:0]; assign X``_PWRITE = IF.PWRITE; \
  assign X``_PWDATA = IF.PWDATA[$bits(X``_PWDATA)-1:0]; \
  assign X``_PSTRB = IF.PSTRB[$bits(X``_PSTRB)-1:0]; \
  assign IF.PRDATA = 64'(X``_PRDATA); assign IF.PREADY = X``_PREADY; \
  assign IF.PSLVERR = X``_PSLVERR;
`define BUS_PINS(P, X) \
  .P``PSEL(X``_PSEL), .P``PENABLE(X``_PENABLE), .P``PADDR(X``_PADDR), \
  .P``PWRITE(X``_PWRITE), .P``PWDATA(X``_PWDATA), .P``PSTRB(X``_PSTRB), \
  .P``PRDATA(X``_PRDATA), .P``PREADY(X``_PREADY), .P``PSLVERR(X``_PSLVERR)
`define CLKRST(P, CLK, RSTN) .P``PCLK(CLK), .P``PRESETn(RSTN)
`endif

module tb_sram_uvm;

  import uvm_pkg::*;
  import sram_uvm_pkg::*;

  // ---- configuration --------------------------------------------------------------
  localparam int unsigned TECH   = `TECH;
  localparam bit          SKY130 = (TECH == 6);
  localparam bit          SAED14 = (TECH == 5);
  localparam int unsigned AW     = 16;          // bus byte-address width
  localparam int unsigned W      = 32;
  localparam int unsigned D      = 1024;
`ifdef SRAM_CFG_FULL
  localparam string       CFG    = "full";
  localparam bit          ECC    = 1'b1;
  localparam bit          BPG    = 1'b1;
  localparam int unsigned NB     = 2;
  localparam bit          BIST   = 1'b1;
  localparam int unsigned RL     = 2;
  localparam bit          DUAL   = 1'b0;
`elsif SRAM_CFG_DP
  localparam string       CFG    = "dp";
  localparam bit          ECC    = 1'b0;
  localparam bit          BPG    = 1'b0;
  localparam int unsigned NB     = 1;
  localparam bit          BIST   = 1'b0;
  localparam int unsigned RL     = 1;
  localparam bit          DUAL   = 1'b1;
`else
  localparam string       CFG    = "base";
  localparam bit          ECC    = 1'b0;
  localparam bit          BPG    = 1'b0;
  localparam int unsigned NB     = 1;
  localparam bit          BIST   = 1'b0;
  localparam int unsigned RL     = 1;
  localparam bit          DUAL   = 1'b0;
`endif
  localparam int unsigned WB     = DUAL ? 8 : W;          // port B width
  localparam int unsigned DB     = W * D / WB;            // port B words
  localparam bit          CC     = !DUAL || SAED14;       // one clock
  localparam int unsigned NPD    = BPG ? NB : 1;
  localparam int unsigned IW     = $clog2(D);
  localparam realtime     TA     = 10.0;
  localparam realtime     TB     = CC ? TA : 13.7;

  // ---- clocks and resets ------------------------------------------------------------
  logic clk_a = 1'b0;
  logic clk_b = 1'b0;
  logic rst_a_n;
  logic rst_b_n;

  if (CC) begin : g_one_clk
    always #(TA / 2) begin
      clk_a = ~clk_a;
      clk_b = ~clk_b;
    end
  end else begin : g_two_clk
    always #(TA / 2) clk_a = ~clk_a;
    always #(TB / 2) clk_b = ~clk_b;
  end

  initial begin
    rst_a_n = 1'b0;
    rst_b_n = 1'b0;
    repeat (10) @(posedge clk_a);
    rst_a_n <= 1'b1;
  end
  initial begin
    repeat (10) @(posedge clk_b);
    wait (rst_a_n === 1'b1);                    // port B leaves reset after port A
    @(posedge clk_b);
    rst_b_n <= 1'b1;
  end

  // ---- interfaces -------------------------------------------------------------------
  sram_bus_if bus_a (.clk(clk_a), .rst_n(rst_a_n));
  sram_bus_if bus_b (.clk(clk_b), .rst_n(rst_b_n));
  sram_sb_if  sbi   (.clk(clk_a), .rst_n(rst_a_n));

  `BUS_WIRES(pa, W)
  `BUS_WIRES(pb, WB)
  `BUS_LINK(pa, bus_a)

  logic [2*NPD-1:0] pwr_req, pwr_ack;
  logic             clr_req, clr_done, busy, err_irq, ecc_corr, ecc_uncorr;
  logic [1:0]       ecc_inj;
  logic             bist_start, bist_done, bist_fail;
  logic [IW-1:0]    bist_fail_addr;
  int unsigned      n_chk, n_mis;

  assign pwr_req            = sbi.pwr_mode_req[2*NPD-1:0];
  assign clr_req            = sbi.clr_req;
  assign ecc_inj            = sbi.ecc_inj;
  assign bist_start         = sbi.bist_start;
  assign sbi.pwr_mode_ack   = 8'(pwr_ack);
  assign sbi.clr_done       = clr_done;
  assign sbi.busy           = busy;
  assign sbi.err_irq        = err_irq;
  assign sbi.ecc_corr       = ecc_corr;
  assign sbi.ecc_uncorr     = ecc_uncorr;
  assign sbi.bist_done      = bist_done;
  assign sbi.bist_fail      = bist_fail;
  assign sbi.bist_fail_addr = 16'(bist_fail_addr);
  assign sbi.n_checked      = n_chk;
  assign sbi.n_mismatch     = n_mis;

`define SB_PINS \
  .pwr_mode_req_i(pwr_req), .pwr_mode_ack_o(pwr_ack), .clr_req_i(clr_req), \
  .clr_done_o(clr_done), .busy_o(busy), .err_irq_o(err_irq), .ecc_inj_i(ecc_inj), \
  .ecc_corr_o(ecc_corr), .ecc_uncorr_o(ecc_uncorr), .bist_start_i(bist_start), \
  .bist_done_o(bist_done), .bist_fail_o(bist_fail), .bist_fail_addr_o(bist_fail_addr)

  // Port-B options are passed explicitly to a VHDL top on VCS (VCS-MX takes a
  // dependent generic default from the other generic's default; see Step 4).
`ifdef VHDL_DUT
`ifdef VCS
`define DP_B .BYTE_EN_B(1), .PARTIAL_WR_ERR_B(1), .READ_LATENCY_B(RL),
`endif
`endif
`ifndef DP_B
`define DP_B
`endif

  // ---- DUT and reference model ---------------------------------------------------------
  if (DUAL) begin : g_dp
    `BUS_LINK(pb, bus_b)
    `SRAM_DP #(
      .TECH(TECH), .ADDR_W(AW), .WIDTH(W), .DEPTH(D), .READ_LATENCY(RL), .WIDTH_B(WB),
      `DP_B .COMMON_CLK(CC)
    ) u_dut (
      `CLKRST(A_, clk_a, rst_a_n), `CLKRST(B_, clk_b, rst_b_n),
      `BUS_PINS(A_, pa), `BUS_PINS(B_, pb), `SB_PINS);

    sram_model #(
      .ADDR_W(AW), .WIDTH(W), .DEPTH(D), .READ_LATENCY(RL), .DUAL_PORT(1), .WIDTH_B(WB),
      .READ_ONLY_B(SKY130), .B_MODE_GUARD(CC ? 0 : 8)
    ) u_model (
      .clk(clk_a), .rst_n(rst_a_n),
      .mem_req(u_dut.a_mem_req), .mem_gnt(u_dut.a_mem_gnt), .mem_we(u_dut.a_mem_we),
      .mem_addr(u_dut.a_mem_addr), .mem_be(u_dut.a_mem_be), .mem_wdata(u_dut.a_mem_wdata),
      .mem_rvalid(u_dut.a_mem_rvalid), .mem_rdata(u_dut.a_mem_rdata),
      .mem_err(u_dut.a_mem_err),
      .clk_b(clk_b), .rst_b_n(rst_b_n),
      .mem_b_req(u_dut.b_mem_req), .mem_b_gnt(u_dut.b_mem_gnt), .mem_b_we(u_dut.b_mem_we),
      .mem_b_addr(u_dut.b_mem_addr), .mem_b_be(u_dut.b_mem_be),
      .mem_b_wdata(u_dut.b_mem_wdata), .mem_b_rvalid(u_dut.b_mem_rvalid),
      .mem_b_rdata(u_dut.b_mem_rdata), .mem_b_err(u_dut.b_mem_err),
      .pwr_mode_req(pwr_req), .pwr_mode_ack(pwr_ack), .clr_req(clr_req),
      .clr_done(clr_done), .bist_done(bist_done), .ecc_inj(ecc_inj),
      .mismatch_o(), .mismatch_b_o(), .n_checked(n_chk), .n_mismatch(n_mis));
  end else begin : g_sp
    `SRAM_SP #(
      .TECH(TECH), .ADDR_W(AW), .WIDTH(W), .DEPTH(D), .READ_LATENCY(RL), .ECC_EN(ECC),
      .BANK_PG(BPG), .NUM_BANKS(NB), .BIST_EN(BIST)
    ) u_dut (
      `CLKRST(, clk_a, rst_a_n), `BUS_PINS(, pa), `SB_PINS);

    sram_model #(
      .ADDR_W(AW), .WIDTH(W), .DEPTH(D), .READ_LATENCY(RL), .ECC_EN(ECC), .BANK_PG(BPG),
      .NUM_BANKS(NB)
    ) u_model (
      .clk(clk_a), .rst_n(rst_a_n),
      .mem_req(u_dut.mem_req), .mem_gnt(u_dut.mem_gnt), .mem_we(u_dut.mem_we),
      .mem_addr(u_dut.mem_addr), .mem_be(u_dut.mem_be), .mem_wdata(u_dut.mem_wdata),
      .mem_rvalid(u_dut.mem_rvalid), .mem_rdata(u_dut.mem_rdata), .mem_err(u_dut.mem_err),
      .clk_b(1'b0), .rst_b_n(1'b0),
      .mem_b_req(1'b0), .mem_b_gnt(1'b0), .mem_b_we(1'b0), .mem_b_addr('0), .mem_b_be('0),
      .mem_b_wdata('0), .mem_b_rvalid(1'b0), .mem_b_rdata('0), .mem_b_err(1'b0),
      .pwr_mode_req(pwr_req), .pwr_mode_ack(pwr_ack), .clr_req(clr_req),
      .clr_done(clr_done), .bist_done(bist_done), .ecc_inj(ecc_inj),
      .mismatch_o(), .mismatch_b_o(), .n_checked(n_chk), .n_mismatch(n_mis));

    // The model learns about the read-path fault knob (ECC: an extra error).
    if (ECC) begin : g_stuck
      always @(sbi.bf_on or sbi.bf_addr or sbi.bf_bit or sbi.bf_val) begin
        u_model.set_stuck(sbi.bf_on, sbi.bf_addr, sbi.bf_bit, sbi.bf_val);
      end
    end

    // Read-path fault knob (BIST and ECC tests): while bf_on, stored data bit
    // bf_bit of word bf_addr reads as bf_val. A read of that word is seen at the
    // edge that issues it; the array output is forced from the following falling
    // edge for one cycle (Step 4 scheme), so the decoder / BIST compare at the
    // next rising edge sees it. VHDL DUT on VCS: $hdl_xmr_force (no native force
    // of a VHDL bit-select); elsewhere one native force per data bit.
    if (BIST || ECC) begin : g_bf
      logic hit_q;
      always @(posedge clk_a) begin
        hit_q <= sbi.bf_on && u_dut.u_core.arr_cs && !u_dut.u_core.arr_we &&
                 (int'(u_dut.u_core.arr_idx) == int'(sbi.bf_addr));
      end
`ifdef VHDL_DUT
`ifdef VCS
`define BF_XMR
`endif
`endif
`ifdef BF_XMR
      bit    forced = 1'b0;
      string path;
      always @(negedge clk_a) begin
        if (hit_q) begin
          if (forced) $hdl_xmr_release(path, 0);
          path = $sformatf("tb_sram_uvm.g_sp.u_dut.u_core.arr_rdata[%0d]", sbi.bf_bit);
          // the force value must be a string literal ("Force value missing" otherwise)
          if (sbi.bf_val) $hdl_xmr_force(path, "1", "0 ns", "freeze", "", 0);
          else $hdl_xmr_force(path, "0", "0 ns", "freeze", "", 0);
          forced = 1'b1;
        end else if (forced) begin
          $hdl_xmr_release(path, 0);
          forced = 1'b0;
        end
      end
`else
      for (genvar gb = 0; gb < W; gb++) begin : g_bit
        bit forced = 1'b0;
        always @(negedge clk_a) begin
          if (hit_q && sbi.bf_bit == gb) begin
            // constant values: Xcelium forces a VHDL bit-select with a constant only
            if (sbi.bf_val) force u_dut.u_core.arr_rdata[gb] = 1'b1;
            else force u_dut.u_core.arr_rdata[gb] = 1'b0;
            forced = 1'b1;
          end else if (forced) begin
            release u_dut.u_core.arr_rdata[gb];
            forced = 1'b0;
          end
        end
      end
`endif
    end
  end

  // ---- UVM ------------------------------------------------------------------------------
  initial begin
    sram_uvm_cfg c;
    c              = new("cfg");
    c.proto        = `PROTO_STR;
    c.cfg_name     = CFG;
`ifdef VHDL_DUT
    c.vhdl         = 1'b1;
`endif
    c.tech         = TECH;
    c.dual_port    = DUAL;
    c.common_clk   = CC;
    c.width        = '{W, WB};
    c.depth        = '{D, DB};
    c.stride       = '{W / 8, WB / 8};
    c.rl           = '{RL, RL};
    c.byte_en      = '{1'b1, 1'b1};
    c.read_only    = '{1'b0, DUAL && SKY130};
    c.ecc          = ECC;
    c.bist         = BIST;
    c.pwr_gate     = 1'b1;
    c.npd          = NPD;
    c.total_bytes  = W * D / 8;
    c.clk_period   = '{TA, TB};
    uvm_config_db #(sram_uvm_cfg)::set(null, "*", "cfg", c);
    uvm_config_db #(virtual sram_bus_if)::set(null, "uvm_test_top.env.bus_a*", "vif", bus_a);
    uvm_config_db #(virtual sram_bus_if)::set(null, "uvm_test_top.env.bus_b*", "vif", bus_b);
    uvm_config_db #(virtual sram_sb_if)::set(null, "*", "sb_vif", sbi);
    run_test();
  end

`ifdef VCS
  initial if ($test$plusargs("waves")) $vcdpluson(0, tb_sram_uvm);
`endif

  initial begin
    #200ms;
    `uvm_fatal("TIMEOUT", "global timeout (hung transfer?)")
  end

endmodule : tb_sram_uvm
