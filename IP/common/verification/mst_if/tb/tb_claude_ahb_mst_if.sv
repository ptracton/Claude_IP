// tb_claude_ahb_mst_if.sv — Loopback testbench for claude_ahb_mst_if.
//
//   initiator BFM ─ mem_* ─► claude_ahb_mst_if (DUT) ─ AHB-Lite ─► claude_ahb_mem_if
//                                                    ─ mem_* ─► claude_mem_model
//
// The DUT is checked on both sides: its mem_* target behaviour (mst_if_tests.sv)
// and its AHB-Lite master behaviour (monitor below: single NONSEQ transfers only,
// HBURST SINGLE, HMASTLOCK 0, legal HSIZE / alignment, data phase held through wait
// states, bus idle in reset), plus an end-to-end check that each request appears once
// on the bus with the expected HADDR, HSIZE, HWRITE, HPROT, HNONSEC, HWSTRB and data.
// The slave adapter is the signed-off claude_ahb_mem_if (HSEL tied high, HREADY =
// HREADYOUT, throttled as below), which adds one wait state per beat: the loopback latency is therefore
// 4 cycles and the period 5 (one more than the spec table, which assumes a zero-wait
// AHB slave).
//
// An HREADY throttle holds the bus-wide HREADY low at random outside this master's own
// data phase (as another slave stretching its data phase would in a real system), so the
// rule "the address phase is held until HREADY" is exercised.
//
// Parameters: DATA_W (8, 16 or 32), ADDR_W (32), HAS_HWSTRB, HAS_HNONSEC (0 / 1).
// With HAS_HWSTRB = 0 the sparse write patterns must come back as mem_err without a
// bus access (rule 8), which the shared tests expect through SPARSE_WR_OK.

`timescale 1ns / 1ps

module tb_claude_ahb_mst_if #(
  parameter int unsigned DATA_W      = 32,
  parameter int unsigned ADDR_W      = 32,
  parameter int unsigned HAS_HWSTRB  = 1,
  parameter int unsigned HAS_HNONSEC = 1
);

  localparam int unsigned StrbW        = DATA_W / 8;
  localparam int unsigned OffW         = (StrbW > 1) ? $clog2(StrbW) : 0;
  localparam int unsigned CLK_PERIOD   = 10;
  localparam bit          SPARSE_WR_OK = (HAS_HWSTRB != 0);

  logic clk = 1'b0;
  logic rst_n;
  always #(CLK_PERIOD / 2) clk = ~clk;

  // mem_* between the BFM and the DUT
  logic                mem_req, mem_gnt, mem_we, mem_rvalid, mem_err;
  logic [ADDR_W-1:0]   mem_addr;
  logic [StrbW-1:0]    mem_be;
  logic [DATA_W-1:0]   mem_wdata, mem_rdata;
  logic [2:0]          mem_prot;

  // AHB-Lite between the DUT and the slave adapter
  logic [ADDR_W-1:0]   HADDR;
  logic [1:0]          HTRANS;
  logic                HWRITE, HMASTLOCK, HNONSEC, HREADYOUT, HRESP;
  logic                HREADY;          // bus-wide ready: HREADYOUT, throttled outside the data phase
  logic [2:0]          HSIZE, HBURST;
  logic [3:0]          HPROT;
  logic [DATA_W-1:0]   HWDATA, HRDATA;
  logic [StrbW-1:0]    HWSTRB;

  // mem_* between the slave adapter and the memory model
  logic                t_req, t_gnt, t_we, t_rvalid, t_err;
  logic [ADDR_W-1:0]   t_addr;
  logic [StrbW-1:0]    t_be;
  logic [DATA_W-1:0]   t_wdata, t_rdata;

  claude_ahb_mst_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W),
                      .HAS_HWSTRB(HAS_HWSTRB), .HAS_HNONSEC(HAS_HNONSEC)) u_dut (
    .HCLK        (clk),
    .HRESETn     (rst_n),
    .HADDR       (HADDR),
    .HTRANS      (HTRANS),
    .HWRITE      (HWRITE),
    .HSIZE       (HSIZE),
    .HBURST      (HBURST),
    .HPROT       (HPROT),
    .HMASTLOCK   (HMASTLOCK),
    .HNONSEC     (HNONSEC),
    .HWDATA      (HWDATA),
    .HWSTRB      (HWSTRB),
    .HRDATA      (HRDATA),
    .HREADY      (HREADY),
    .HRESP       (HRESP),
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

  claude_ahb_mem_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_slv (
    .HCLK        (clk),
    .HRESETn     (rst_n),
    .HSEL        (1'b1),
    .HADDR       (HADDR),
    .HTRANS      (HTRANS),
    .HWRITE      (HWRITE),
    .HSIZE       (HSIZE),
    .HWDATA      (HWDATA),
    .HWSTRB      (HWSTRB),
    .HREADY      (HREADY),
    .HRDATA      (HRDATA),
    .HREADYOUT   (HREADYOUT),
    .HRESP       (HRESP),
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
                     .OOR_ERR(1'b0), .SEED(11)) u_tgt (
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

  int unsigned bus_xfers  = 0;   // completed AHB data phases
  int unsigned throttle   = 0;   // 0: off; N: HREADY high with probability 1/(N+1) outside the data phase
  logic        hr_allow;
  logic        dp_active;        // a data phase is in progress (set by the monitor)

  always @(posedge clk) hr_allow <= (throttle == 0) || ($urandom_range(throttle, 0) == 0);
  assign HREADY = HREADYOUT & (dp_active | hr_allow);
  int unsigned bus_errors = 0;   // AHB rule or end-to-end violations

  // ---------------------------------------------------------------------------
  // Protocol-neutral BFM, reference memory and tests
  // ---------------------------------------------------------------------------
`include "mst_if_tests.sv"

  // ---------------------------------------------------------------------------
  // AHB-Lite master-rule monitor and end-to-end check
  // ---------------------------------------------------------------------------
  localparam logic [1:0] TrIdle = 2'b00;
  localparam logic [1:0] TrNseq = 2'b10;

  logic              rst_seen_q;    // rst_n was high at the previous edge
  logic              p_nseq, p_hready, p_hwrite;
  logic [ADDR_W-1:0] p_haddr;
  logic [2:0]        p_hsize;
  logic [3:0]        p_hprot;
  logic              dp_first;      // first cycle of that data phase
  logic              dp_write;
  logic [StrbW-1:0]  dp_be;         // expected byte enables of the data phase
  logic [DATA_W-1:0] dp_wdata;      // expected write data
  logic [DATA_W-1:0] dp_hwdata;     // HWDATA seen in the first data-phase cycle
  logic [StrbW-1:0]  dp_hwstrb;     // HWSTRB seen in the first data-phase cycle

  task automatic bus_fail(input string msg);
    $display("ERROR [ahb mon] %s (%0t)", msg, $time);
    bus_errors++;
  endtask

  function automatic int unsigned popcount(logic [StrbW-1:0] be);
    int unsigned n;
    n = 0;
    for (int b = 0; b < StrbW; b++) if (be[b]) n++;
    return n;
  endfunction

  always @(posedge clk) begin : p_ahb_mon
    int unsigned       k;
    logic [ADDR_W-1:0] e_addr;
    logic [2:0]        e_size;
    logic [3:0]        e_prot;
    logic [StrbW-1:0]  e_strb;
    if (!rst_n) begin
      if (rst_seen_q && HTRANS != TrIdle) bus_fail("HTRANS not IDLE in reset");
      if (!rst_seen_q && HTRANS != TrIdle && $time > 3 * CLK_PERIOD) bus_fail("HTRANS not IDLE in reset");
      rst_seen_q <= 1'b0;
      dp_active  <= 1'b0;
    end else begin
      if (HTRANS != TrIdle && HTRANS != TrNseq) bus_fail($sformatf("HTRANS = %b (only IDLE / NONSEQ)", HTRANS));
      if (HBURST != 3'b000) bus_fail("HBURST not SINGLE");
      if (HMASTLOCK)        bus_fail("HMASTLOCK high");

      // ---- data phase -----------------------------------------------------------
      if (dp_active) begin
        if (HTRANS == TrNseq) bus_fail("new transfer during a data phase (one outstanding only)");
        if (dp_first) begin
          dp_hwdata <= HWDATA;
          dp_hwstrb <= HWSTRB;
        end else if (HWDATA !== dp_hwdata || HWSTRB !== dp_hwstrb) begin
          bus_fail("HWDATA / HWSTRB changed during a data-phase wait state");
        end
        dp_first <= 1'b0;
        if (HREADY) begin
          bus_xfers++;
          dp_active <= 1'b0;
          if (dp_write) begin
            e_strb = (HAS_HWSTRB != 0) ? dp_be : {StrbW{1'b1}};
            if (HWSTRB !== e_strb) bus_fail($sformatf("HWSTRB %b, expected %b", HWSTRB, e_strb));
            for (int b = 0; b < StrbW; b++)
              if (dp_be[b] && HWDATA[8*b +: 8] !== dp_wdata[8*b +: 8])
                bus_fail($sformatf("HWDATA lane %0d differs from mem_wdata", b));
          end else if (HAS_HWSTRB != 0 && HWSTRB !== '0) begin
            bus_fail("HWSTRB not zero on a read");
          end
        end
      end

      // ---- address phase --------------------------------------------------------
      // A NONSEQ address phase not accepted (HREADY low) is held unchanged.
      if (rst_seen_q && p_nseq && !p_hready && !(HTRANS == TrNseq && HADDR == p_haddr &&
          HWRITE == p_hwrite && HSIZE == p_hsize && HPROT == p_hprot))
        bus_fail("address phase dropped or changed while HREADY was low");
      if (HTRANS == TrNseq) begin
        if ((1 << HSIZE) > StrbW) bus_fail($sformatf("HSIZE %0d wider than the bus", HSIZE));
        if ((HADDR % (1 << HSIZE)) != 0) bus_fail($sformatf("HADDR 0x%0h not aligned to HSIZE %0d", HADDR, HSIZE));
        if (HREADY && !dp_active) begin
          // accepted: compare with the next expected request
          if (exp_rd_ptr == exp_wr_ptr) begin
            bus_fail("bus transfer without an accepted request");
          end else begin
            k = exp_rd_ptr % ExpDepth;
            if (is_aligned(exp_be[k])) begin
              e_addr = exp_addr[k];
              e_size = 3'($clog2(popcount(exp_be[k])));
            end else begin
              e_addr = exp_addr[k] & ~ADDR_W'(StrbW - 1);
              e_size = 3'($clog2(StrbW));
            end
            e_prot = {2'b00, exp_prot[k][0], ~exp_prot[k][2]};
            if (HWRITE !== exp_we[k] || HADDR !== e_addr || HSIZE !== e_size)
              bus_fail($sformatf("address phase %s 0x%0h size %0d, expected %s 0x%0h size %0d",
                                 HWRITE ? "WR" : "RD", HADDR, HSIZE,
                                 exp_we[k] ? "WR" : "RD", e_addr, e_size));
            if (HPROT !== e_prot) bus_fail($sformatf("HPROT %b, expected %b", HPROT, e_prot));
            if (HNONSEC !== ((HAS_HNONSEC != 0) ? exp_prot[k][1] : 1'b0)) bus_fail("HNONSEC wrong");
            dp_active <= 1'b1;
            dp_first  <= 1'b1;
            dp_write  <= exp_we[k];
            dp_be     <= exp_be[k];
            dp_wdata  <= exp_wdata[k];
            exp_rd_ptr = exp_rd_ptr + 1;
          end
        end
      end
      rst_seen_q <= 1'b1;
    end
    p_nseq   <= (HTRANS == TrNseq) && !dp_active;
    p_hready <= HREADY;
    p_haddr  <= HADDR;
    p_hwrite <= HWRITE;
    p_hsize  <= HSIZE;
    p_hprot  <= HPROT;
  end

  function automatic int unsigned bus_check_report();
    if (bus_xfers + n_aborted + n_nobus != n_accepted) begin
      $display("ERROR [ahb mon] %0d bus transfers for %0d accepted requests (%0d aborted, %0d no bus)",
               bus_xfers, n_accepted, n_aborted, n_nobus);
      bus_errors++;
    end
    if (exp_rd_ptr != exp_wr_ptr) begin
      $display("ERROR [ahb mon] %0d accepted requests never appeared on the bus",
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

    // Zero-wait memory, no idle cycles. The slave adapter adds one wait state.
    u_tgt.max_gnt_delay = 0;
    u_tgt.max_rsp_delay = 0;
    max_idle            = 0;
    test_latency(4, 5);
    run_all("zero wait");
    test_reset_mid_transfer();

    // Random grant / response delays (AHB wait states) and random idle cycles.
    u_tgt.max_gnt_delay = 3;
    u_tgt.max_rsp_delay = 4;
    max_idle            = 3;
    throttle            = 3;
    run_all("random delays and HREADY stalls");

    finish_tests("tb_claude_ahb_mst_if");
  end

  initial begin : p_timeout
    #(5_000_000);
    $display("FAIL tb_claude_ahb_mst_if: timeout");
    $finish;
  end

endmodule : tb_claude_ahb_mst_if
