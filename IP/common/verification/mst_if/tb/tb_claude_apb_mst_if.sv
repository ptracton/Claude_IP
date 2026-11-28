// tb_claude_apb_mst_if.sv — Loopback testbench for claude_apb_mst_if.
//
//   initiator BFM ─ mem_* ─► claude_apb_mst_if (DUT) ─ APB4 ─► claude_apb_mem_if
//                                                     ─ mem_* ─► claude_mem_model
//
// The DUT is checked on both sides: its mem_* target behaviour (mst_if_tests.sv)
// and its APB4 master behaviour (monitor below: every APB4 master rule, plus an
// end-to-end check that each accepted request appears once on the bus with the
// same address, direction, strobes, data and PPROT). The slave adapter and the
// memory are the signed-off claude_apb_mem_if and claude_mem_model
// (IP/common/verification/models/).
//
// Languages: the DUT and the slave adapter may each be the SV or the VHDL
// version (chosen by the file list of the runner, verify_mst_if.py); the
// testbench names them explicitly and has no DUT-selection defines.
//
// Parameters: DATA_W (8, 16 or 32), ADDR_W (32).

`timescale 1ns / 1ps

module tb_claude_apb_mst_if #(
  parameter int unsigned DATA_W = 32,
  parameter int unsigned ADDR_W = 32
);

  localparam int unsigned StrbW      = DATA_W / 8;
  localparam int unsigned OffW       = (StrbW > 1) ? $clog2(StrbW) : 0;
  localparam int unsigned CLK_PERIOD = 10;
  localparam bit          SPARSE_WR_OK = 1'b1;   // APB4 PSTRB takes any pattern

  logic clk = 1'b0;
  logic rst_n;
  always #(CLK_PERIOD / 2) clk = ~clk;

  // mem_* between the BFM and the DUT
  logic                mem_req, mem_gnt, mem_we, mem_rvalid, mem_err;
  logic [ADDR_W-1:0]   mem_addr;
  logic [StrbW-1:0]    mem_be;
  logic [DATA_W-1:0]   mem_wdata, mem_rdata;
  logic [2:0]          mem_prot;

  // APB4 between the DUT and the slave adapter
  logic                PSEL, PENABLE, PWRITE, PREADY, PSLVERR;
  logic [ADDR_W-1:0]   PADDR;
  logic [DATA_W-1:0]   PWDATA, PRDATA;
  logic [StrbW-1:0]    PSTRB;
  logic [2:0]          PPROT;

  // mem_* between the slave adapter and the memory model
  logic                t_req, t_gnt, t_we, t_rvalid, t_err;
  logic [ADDR_W-1:0]   t_addr;
  logic [StrbW-1:0]    t_be;
  logic [DATA_W-1:0]   t_wdata, t_rdata;

  claude_apb_mst_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_dut (
    .PCLK        (clk),
    .PRESETn     (rst_n),
    .PSEL        (PSEL),
    .PENABLE     (PENABLE),
    .PADDR       (PADDR),
    .PWRITE      (PWRITE),
    .PWDATA      (PWDATA),
    .PSTRB       (PSTRB),
    .PPROT       (PPROT),
    .PRDATA      (PRDATA),
    .PREADY      (PREADY),
    .PSLVERR     (PSLVERR),
    .mem_req_i   (mem_req),
    .mem_gnt_o   (mem_gnt),
    .mem_we_i    (mem_we),
    .mem_addr_i  (mem_addr),
    .mem_be_i    (mem_be),
    .mem_wdata_i (mem_wdata),
    .mem_prot_i  (mem_prot),
    .mem_rvalid_o(mem_rvalid),
    .mem_rdata_o (mem_rdata),
    .mem_err_o   (mem_err)
  );

  claude_apb_mem_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_slv (
    .PCLK        (clk),
    .PRESETn     (rst_n),
    .PSEL        (PSEL),
    .PENABLE     (PENABLE),
    .PADDR       (PADDR),
    .PWRITE      (PWRITE),
    .PWDATA      (PWDATA),
    .PSTRB       (PSTRB),
    .PRDATA      (PRDATA),
    .PREADY      (PREADY),
    .PSLVERR     (PSLVERR),
    .mem_req_o   (t_req),
    .mem_gnt_i   (t_gnt),
    .mem_we_o    (t_we),
    .mem_addr_o  (t_addr),
    .mem_be_o    (t_be),
    .mem_wdata_o (t_wdata),
    .mem_rvalid_i(t_rvalid),
    .mem_rdata_i (t_rdata),
    .mem_err_i   (t_err)
  );

  // 4 KiB from address 0, wrapping above; the top half of the address space is an
  // error region (set in p_main).
  claude_mem_model #(.DATA_W(DATA_W), .ADDR_W(ADDR_W), .BASE(64'h0), .SIZE(1024 * StrbW),
                     .OOR_ERR(1'b0), .SEED(7)) u_tgt (
    .clk       (clk),
    .rst_n     (rst_n),
    .mem_req   (t_req),
    .mem_gnt   (t_gnt),
    .mem_we    (t_we),
    .mem_addr  (t_addr),
    .mem_be    (t_be),
    .mem_wdata (t_wdata),
    .mem_rvalid(t_rvalid),
    .mem_rdata (t_rdata),
    .mem_err   (t_err)
  );

  int unsigned bus_xfers  = 0;   // completed APB transfers
  int unsigned bus_errors = 0;   // APB rule or end-to-end violations

  // ---------------------------------------------------------------------------
  // Protocol-neutral BFM, reference memory and tests
  // ---------------------------------------------------------------------------
`include "mst_if_tests.sv"

  // ---------------------------------------------------------------------------
  // APB4 master-rule monitor and end-to-end check
  // ---------------------------------------------------------------------------

  logic              rst_seen_q;   // rst_n was high at the previous edge
  logic              p_psel, p_penable, p_pwrite, p_pready;
  logic [ADDR_W-1:0] p_paddr;
  logic [DATA_W-1:0] p_pwdata;
  logic [StrbW-1:0]  p_pstrb;
  logic [2:0]        p_pprot;

  function automatic logic same_payload();
    return PADDR == p_paddr && PWRITE == p_pwrite && PSTRB == p_pstrb && PPROT == p_pprot
           && (!PWRITE || PWDATA == p_pwdata);
  endfunction

  task automatic bus_fail(input string msg);
    $display("ERROR [apb mon] %s (%0t)", msg, $time);
    bus_errors++;
  endtask

  always @(posedge clk) begin : p_apb_mon
    int unsigned k;
    if (!rst_n) begin
      if (!rst_seen_q && (PSEL || PENABLE)) bus_fail("PSEL / PENABLE high during reset");
      rst_seen_q <= 1'b0;
    end else begin
      if (PENABLE && !PSEL) bus_fail("PENABLE without PSEL");
      if (rst_seen_q) begin
        // SETUP is always followed by ACCESS with the same payload.
        if (p_psel && !p_penable) begin
          if (!(PSEL && PENABLE)) bus_fail("SETUP not followed by ACCESS");
          if (!same_payload())    bus_fail("payload changed from SETUP to ACCESS");
        end
        // A waiting ACCESS holds everything.
        if (p_psel && p_penable && !p_pready) begin
          if (!(PSEL && PENABLE)) bus_fail("ACCESS dropped before PREADY");
          if (!same_payload())    bus_fail("payload changed during a wait state");
        end
        // A completed ACCESS is followed by PENABLE low.
        if (p_psel && p_penable && p_pready && PENABLE) bus_fail("PENABLE high after a completed ACCESS");
        // ACCESS only after SETUP or a wait state.
        if (PSEL && PENABLE && !(p_psel && (!p_penable || !p_pready)))
          bus_fail("ACCESS without a preceding SETUP");
      end
      if (PSEL && !PENABLE && !PWRITE && PSTRB != '0) bus_fail("PSTRB not zero on a read");
      // End to end: the first SETUP cycle of a transfer matches the next expected request.
      if (PSEL && !PENABLE && !(rst_seen_q && p_psel && !p_penable)) begin
        if (exp_rd_ptr == exp_wr_ptr) begin
          bus_fail("bus transfer without an accepted request");
        end else begin
          k = exp_rd_ptr % ExpDepth;
          if (PWRITE !== exp_we[k] || PADDR !== exp_addr[k] || PPROT !== exp_prot[k])
            bus_fail($sformatf("SETUP %s 0x%0h prot %b, expected %s 0x%0h prot %b",
                               PWRITE ? "WR" : "RD", PADDR, PPROT,
                               exp_we[k] ? "WR" : "RD", exp_addr[k], exp_prot[k]));
          if (exp_we[k]) begin
            if (PSTRB !== exp_be[k]) bus_fail("PSTRB differs from mem_be");
            for (int b = 0; b < StrbW; b++)
              if (exp_be[k][b] && PWDATA[8*b +: 8] !== exp_wdata[k][8*b +: 8])
                bus_fail("PWDATA differs from mem_wdata");
          end
          exp_rd_ptr = exp_rd_ptr + 1;
        end
      end
      if (PSEL && PENABLE && PREADY) bus_xfers++;
      rst_seen_q <= 1'b1;
    end
    p_psel    <= PSEL;
    p_penable <= PENABLE;
    p_pwrite  <= PWRITE;
    p_pready  <= PREADY;
    p_paddr   <= PADDR;
    p_pwdata  <= PWDATA;
    p_pstrb   <= PSTRB;
    p_pprot   <= PPROT;
  end

  function automatic int unsigned bus_check_report();
    if (bus_xfers + n_aborted + n_nobus != n_accepted) begin
      $display("ERROR [apb mon] %0d bus transfers for %0d accepted requests (%0d aborted, %0d no bus)",
               bus_xfers, n_accepted, n_aborted, n_nobus);
      bus_errors++;
    end
    if (exp_rd_ptr != exp_wr_ptr) begin
      $display("ERROR [apb mon] %0d accepted requests never appeared on the bus",
               exp_wr_ptr - exp_rd_ptr);
      bus_errors++;
    end
    return bus_errors;
  endfunction

  initial begin : p_main
    for (int i = 0; i < RefWords; i++) ref_mem[i] = '0;
    bfm_idle();
    u_tgt.err_lo = {1'b1, {(ADDR_W-1){1'b0}}};
    u_tgt.err_hi = '1;
    rst_n = 1'b0;
    repeat (5) @(negedge clk);
    rst_n = 1'b1;
    repeat (2) @(negedge clk);

    // Zero-wait target, no idle cycles: latency and throughput of the spec table.
    u_tgt.max_gnt_delay = 0;
    u_tgt.max_rsp_delay = 0;
    max_idle            = 0;
    test_latency(3, 4);
    run_all("zero wait");
    test_reset_mid_transfer();

    // Random grant / response delays (APB wait states) and random idle cycles.
    u_tgt.max_gnt_delay = 3;
    u_tgt.max_rsp_delay = 4;
    max_idle            = 3;
    run_all("random delays");

    finish_tests("tb_claude_apb_mst_if");
  end

  initial begin : p_timeout
    #(5_000_000);
    $display("FAIL tb_claude_apb_mst_if: timeout");
    $finish;
  end

endmodule : tb_claude_apb_mst_if
