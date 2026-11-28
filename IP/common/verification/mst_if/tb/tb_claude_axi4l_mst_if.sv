// tb_claude_axi4l_mst_if.sv — Loopback testbench for claude_axi4l_mst_if.
//
//   initiator BFM ─ mem_* ─► claude_axi4l_mst_if (DUT) ─ AXI4-Lite ─► claude_axi4l_mem_if
//                                                      ─ mem_* ─► claude_mem_model
//
// The DUT is checked on both sides: its mem_* target behaviour (mst_if_tests.sv) and
// its AXI4-Lite master behaviour (monitor below: VALID and payload held until READY on
// AW / W / AR, AWVALID and WVALID raised together, one transaction outstanding, no read
// and write at once, every VALID / READY low in reset), plus an end-to-end check that
// each request appears once on the bus with the same AWADDR / ARADDR, AxPROT, WDATA
// and WSTRB. The slave adapter is the signed-off claude_axi4l_mem_if (it has no AxPROT
// ports; AxPROT is checked on the bus). The slave adapter registers its slots, raises
// its memory request the cycle after capturing AW + W (or AR) and drives BVALID / RVALID
// the cycle after the memory response, so the loopback latency is 5 cycles and the
// period 6 (the spec table's 3 and 4 assume a zero-wait AXI4-Lite slave).
//
// A channel throttle between the DUT and the slave adapter adds random back-pressure on
// AW, W and AR (the slave adapter alone is always ready, because only one transaction
// is outstanding), so the "hold VALID and payload until READY" rules are exercised. It
// is legal on both sides: once it passes a VALID to the slave, it keeps passing it until
// the handshake.
//
// Parameters: DATA_W (32 or 64), ADDR_W (32).

`timescale 1ns / 1ps

module tb_claude_axi4l_mst_if #(
  parameter int unsigned DATA_W = 32,
  parameter int unsigned ADDR_W = 32
);

  localparam int unsigned StrbW        = DATA_W / 8;
  localparam int unsigned OffW         = (StrbW > 1) ? $clog2(StrbW) : 0;
  localparam int unsigned CLK_PERIOD   = 10;
  localparam bit          SPARSE_WR_OK = 1'b1;   // WSTRB takes any pattern
  // Loopback latency with the zero-wait memory (rising edges from the mem_* handshake
  // to the edge that samples mem_rvalid), see the header.
  localparam int unsigned LAT_EXP      = 5;

  logic clk = 1'b0;
  logic rst_n;
  always #(CLK_PERIOD / 2) clk = ~clk;

  // mem_* between the BFM and the DUT
  logic                mem_req, mem_gnt, mem_we, mem_rvalid, mem_err;
  logic [ADDR_W-1:0]   mem_addr;
  logic [StrbW-1:0]    mem_be;
  logic [DATA_W-1:0]   mem_wdata, mem_rdata;
  logic [2:0]          mem_prot;

  // AXI4-Lite between the DUT and the slave adapter
  logic                AWVALID, AWREADY, WVALID, WREADY, BVALID, BREADY;
  logic                ARVALID, ARREADY, RVALID, RREADY;
  logic [ADDR_W-1:0]   AWADDR, ARADDR;
  logic [2:0]          AWPROT, ARPROT;
  logic [DATA_W-1:0]   WDATA, RDATA;
  logic [StrbW-1:0]    WSTRB;
  logic [1:0]          BRESP, RRESP;

  // AW / W / AR VALID / READY on the slave side of the throttle
  logic                s_awvalid, s_awready, s_wvalid, s_wready, s_arvalid, s_arready;

  // mem_* between the slave adapter and the memory model
  logic                t_req, t_gnt, t_we, t_rvalid, t_err;
  logic [ADDR_W-1:0]   t_addr;
  logic [StrbW-1:0]    t_be;
  logic [DATA_W-1:0]   t_wdata, t_rdata;

  claude_axi4l_mst_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_dut (
    .ACLK        (clk),
    .ARESETn     (rst_n),
    .AWVALID     (AWVALID),
    .AWREADY     (AWREADY),
    .AWADDR      (AWADDR),
    .AWPROT      (AWPROT),
    .WVALID      (WVALID),
    .WREADY      (WREADY),
    .WDATA       (WDATA),
    .WSTRB       (WSTRB),
    .BVALID      (BVALID),
    .BREADY      (BREADY),
    .BRESP       (BRESP),
    .ARVALID     (ARVALID),
    .ARREADY     (ARREADY),
    .ARADDR      (ARADDR),
    .ARPROT      (ARPROT),
    .RVALID      (RVALID),
    .RREADY      (RREADY),
    .RDATA       (RDATA),
    .RRESP       (RRESP),
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

  claude_axi4l_mem_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_slv (
    .ACLK        (clk),
    .ARESETn     (rst_n),
    .AWVALID     (s_awvalid),
    .AWREADY     (s_awready),
    .AWADDR      (AWADDR),
    .WVALID      (s_wvalid),
    .WREADY      (s_wready),
    .WDATA       (WDATA),
    .WSTRB       (WSTRB),
    .BVALID      (BVALID),
    .BREADY      (BREADY),
    .BRESP       (BRESP),
    .ARVALID     (s_arvalid),
    .ARREADY     (s_arready),
    .ARADDR      (ARADDR),
    .RVALID      (RVALID),
    .RREADY      (RREADY),
    .RDATA       (RDATA),
    .RRESP       (RRESP),
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

  claude_mem_model #(.DATA_W(DATA_W), .ADDR_W(ADDR_W), .BASE(64'h0), .SIZE(1024 * StrbW),
                     .OOR_ERR(1'b0), .SEED(13)) u_tgt (
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

  // ---------------------------------------------------------------------------
  // Channel throttle (AW, W, AR). go = pass this cycle; fwd_q keeps passing a VALID
  // that the slave has seen until its handshake.
  // ---------------------------------------------------------------------------
  int unsigned throttle = 0;          // 0: off; N: pass with probability 1/(N+1) per cycle
  logic        aw_fwd_q, w_fwd_q, ar_fwd_q;
  logic        aw_allow, w_allow, ar_allow;
  logic        aw_go, w_go, ar_go;

  always @(posedge clk) begin : p_throttle
    aw_allow <= (throttle == 0) || ($urandom_range(throttle, 0) == 0);
    w_allow  <= (throttle == 0) || ($urandom_range(throttle, 0) == 0);
    ar_allow <= (throttle == 0) || ($urandom_range(throttle, 0) == 0);
    if (!rst_n) begin
      aw_fwd_q <= 1'b0;
      w_fwd_q  <= 1'b0;
      ar_fwd_q <= 1'b0;
    end else begin
      aw_fwd_q <= s_awvalid & ~s_awready;
      w_fwd_q  <= s_wvalid  & ~s_wready;
      ar_fwd_q <= s_arvalid & ~s_arready;
    end
  end

  assign aw_go     = aw_fwd_q | aw_allow;
  assign w_go      = w_fwd_q  | w_allow;
  assign ar_go     = ar_fwd_q | ar_allow;
  assign s_awvalid = AWVALID & aw_go;
  assign s_wvalid  = WVALID  & w_go;
  assign s_arvalid = ARVALID & ar_go;
  assign AWREADY   = s_awready & aw_go;
  assign WREADY    = s_wready  & w_go;
  assign ARREADY   = s_arready & ar_go;

  int unsigned bus_xfers  = 0;   // completed B / R handshakes
  int unsigned bus_errors = 0;   // AXI rule or end-to-end violations

`include "mst_if_tests.sv"

  // ---------------------------------------------------------------------------
  // AXI4-Lite master-rule monitor and end-to-end check
  // ---------------------------------------------------------------------------
  logic              rst_seen_q;
  logic              p_awvalid, p_awready, p_wvalid, p_wready, p_arvalid, p_arready;
  logic [ADDR_W-1:0] p_awaddr, p_araddr;
  logic [2:0]        p_awprot, p_arprot;
  logic [DATA_W-1:0] p_wdata;
  logic [StrbW-1:0]  p_wstrb;
  logic              wr_out, rd_out;      // a write / read transaction is outstanding
  logic              w_pending;           // expected W data stored, W not seen yet
  logic [StrbW-1:0]  w_exp_be;
  logic [DATA_W-1:0] w_exp_data;

  task automatic bus_fail(input string msg);
    $display("ERROR [axi mon] %s (%0t)", msg, $time);
    bus_errors++;
  endtask

  always @(posedge clk) begin : p_axi_mon
    int unsigned k;
    if (!rst_n) begin
      if (rst_seen_q === 1'b0 && (AWVALID || WVALID || ARVALID || BREADY || RREADY) && $time > 3 * CLK_PERIOD)
        bus_fail("VALID / READY high in reset");
      rst_seen_q <= 1'b0;
      wr_out     <= 1'b0;
      rd_out     <= 1'b0;
      w_pending  <= 1'b0;
    end else begin
      if (rst_seen_q) begin
        // VALID and payload held until READY.
        if (p_awvalid && !p_awready && !(AWVALID && AWADDR == p_awaddr && AWPROT == p_awprot))
          bus_fail("AW dropped or changed before AWREADY");
        if (p_wvalid && !p_wready && !(WVALID && WDATA == p_wdata && WSTRB == p_wstrb))
          bus_fail("W dropped or changed before WREADY");
        if (p_arvalid && !p_arready && !(ARVALID && ARADDR == p_araddr && ARPROT == p_arprot))
          bus_fail("AR dropped or changed before ARREADY");
      end
      // New write: AWVALID and WVALID rise together; one transaction outstanding.
      if (AWVALID && !(p_awvalid && rst_seen_q)) begin
        if (!WVALID)          bus_fail("AWVALID raised without WVALID");
        if (wr_out || rd_out) bus_fail("write issued while a transaction is outstanding");
        if (exp_rd_ptr == exp_wr_ptr) begin
          bus_fail("bus write without an accepted request");
        end else begin
          k = exp_rd_ptr % ExpDepth;
          if (!exp_we[k] || AWADDR !== exp_addr[k] || AWPROT !== exp_prot[k])
            bus_fail($sformatf("AW 0x%0h prot %b, expected %s 0x%0h prot %b", AWADDR, AWPROT,
                               exp_we[k] ? "WR" : "RD", exp_addr[k], exp_prot[k]));
          w_exp_be   = exp_be[k];
          w_exp_data = exp_wdata[k];
          w_pending  = 1'b1;
          exp_rd_ptr = exp_rd_ptr + 1;
        end
        wr_out <= 1'b1;
      end else if (WVALID && !(p_wvalid && rst_seen_q) && !AWVALID && !w_pending) begin
        bus_fail("WVALID raised without AWVALID");
      end
      if (WVALID && w_pending) begin
        if (WSTRB !== w_exp_be) bus_fail($sformatf("WSTRB %b, expected %b", WSTRB, w_exp_be));
        for (int b = 0; b < StrbW; b++)
          if (w_exp_be[b] && WDATA[8*b +: 8] !== w_exp_data[8*b +: 8])
            bus_fail($sformatf("WDATA lane %0d differs from mem_wdata", b));
        w_pending = 1'b0;
      end
      // New read.
      if (ARVALID && !(p_arvalid && rst_seen_q)) begin
        if (wr_out || rd_out || AWVALID) bus_fail("read issued while a transaction is outstanding");
        if (exp_rd_ptr == exp_wr_ptr) begin
          bus_fail("bus read without an accepted request");
        end else begin
          k = exp_rd_ptr % ExpDepth;
          if (exp_we[k] || ARADDR !== exp_addr[k] || ARPROT !== exp_prot[k])
            bus_fail($sformatf("AR 0x%0h prot %b, expected %s 0x%0h prot %b", ARADDR, ARPROT,
                               exp_we[k] ? "WR" : "RD", exp_addr[k], exp_prot[k]));
          exp_rd_ptr = exp_rd_ptr + 1;
        end
        rd_out <= 1'b1;
      end
      // Responses.
      if (BVALID && BREADY) begin
        if (!wr_out && !AWVALID) bus_fail("B handshake without an outstanding write");
        bus_xfers++;
        wr_out <= 1'b0;
      end
      if (RVALID && RREADY) begin
        if (!rd_out && !ARVALID) bus_fail("R handshake without an outstanding read");
        bus_xfers++;
        rd_out <= 1'b0;
      end
      if ((BREADY && !(wr_out || AWVALID)) || (RREADY && !(rd_out || ARVALID)))
        bus_fail("BREADY / RREADY high with no response expected");
      rst_seen_q <= 1'b1;
    end
    p_awvalid <= AWVALID;  p_awready <= AWREADY;  p_awaddr <= AWADDR;  p_awprot <= AWPROT;
    p_wvalid  <= WVALID;   p_wready  <= WREADY;   p_wdata  <= WDATA;   p_wstrb  <= WSTRB;
    p_arvalid <= ARVALID;  p_arready <= ARREADY;  p_araddr <= ARADDR;  p_arprot <= ARPROT;
  end

  function automatic int unsigned bus_check_report();
    if (bus_xfers + n_aborted + n_nobus != n_accepted) begin
      $display("ERROR [axi mon] %0d bus transfers for %0d accepted requests (%0d aborted, %0d no bus)",
               bus_xfers, n_accepted, n_aborted, n_nobus);
      bus_errors++;
    end
    if (exp_rd_ptr != exp_wr_ptr) begin
      $display("ERROR [axi mon] %0d accepted requests never appeared on the bus",
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

    u_tgt.max_gnt_delay = 0;
    u_tgt.max_rsp_delay = 0;
    max_idle            = 0;
    test_latency(LAT_EXP, LAT_EXP + 1);
    run_all("zero wait");
    test_reset_mid_transfer();

    u_tgt.max_gnt_delay = 3;
    u_tgt.max_rsp_delay = 4;
    max_idle            = 3;
    throttle            = 3;
    run_all("random delays and channel back-pressure");

    finish_tests("tb_claude_axi4l_mst_if");
  end

  initial begin : p_timeout
    #(5_000_000);
    $display("FAIL tb_claude_axi4l_mst_if: timeout");
    $finish;
  end

endmodule : tb_claude_axi4l_mst_if
