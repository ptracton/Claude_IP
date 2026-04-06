// test_bus_matrix_ops.sv — Bus matrix functional tests.
//
// Tests routed through the matrix fabric via the master/slave BFMs.
// Uses tasks that operate on the testbench-level BFM control signals:
//   m0_req, m0_req_addr, m0_req_write, m0_req_wdata, m0_req_strb, m0_done, m0_rdata
//   m1_req, m1_req_addr, m1_req_write, m1_req_wdata, m1_req_strb, m1_done, m1_rdata
//
// Address map is baked into DUT parameters — no runtime configuration needed.

// ---------------------------------------------------------------------------
// Helper: drive master 0 transaction and wait for done
// ---------------------------------------------------------------------------
task automatic m0_trans;
  input  logic [31:0] addr;
  input  logic        is_write;
  input  logic [31:0] wdata;
  input  logic [3:0]  strb;
  output logic [31:0] rdata_out;
  integer timeout_cnt;
  begin
    m0_req       = 1'b1;
    m0_req_addr  = addr;
    m0_req_write = is_write;
    m0_req_wdata = wdata;
    m0_req_strb  = strb;
    @(posedge clk);
    m0_req = 1'b0;
    timeout_cnt = 0;
    while (!m0_done) begin
      @(posedge clk);
      timeout_cnt = timeout_cnt + 1;
      if (timeout_cnt > 100) begin
        $display("FAIL [m0_trans] timeout waiting for m0_done, addr=0x%08h", addr);
        $finish(1);
      end
    end
    rdata_out = m0_rdata;
  end
endtask

// ---------------------------------------------------------------------------
// Helper: drive master 1 transaction and wait for done
// ---------------------------------------------------------------------------
task automatic m1_trans;
  input  logic [31:0] addr;
  input  logic        is_write;
  input  logic [31:0] wdata;
  input  logic [3:0]  strb;
  output logic [31:0] rdata_out;
  integer timeout_cnt;
  begin
    m1_req       = 1'b1;
    m1_req_addr  = addr;
    m1_req_write = is_write;
    m1_req_wdata = wdata;
    m1_req_strb  = strb;
    @(posedge clk);
    m1_req = 1'b0;
    timeout_cnt = 0;
    while (!m1_done) begin
      @(posedge clk);
      timeout_cnt = timeout_cnt + 1;
      if (timeout_cnt > 100) begin
        $display("FAIL [m1_trans] timeout waiting for m1_done, addr=0x%08h", addr);
        $finish(1);
      end
    end
    rdata_out = m1_rdata;
  end
endtask

// ---------------------------------------------------------------------------
// Main test task
// ---------------------------------------------------------------------------
task automatic test_bus_matrix_ops;
  logic [31:0] rd0;
  logic [31:0] rd1;
  begin
    test_start("test_bus_matrix_ops");

    // -----------------------------------------------------------------------
    // Test 1: Basic routing — master 0 writes to slave 0 address space,
    //          master 1 writes to slave 1 address space (parallel intent
    //          tested sequentially here for simplicity)
    // -----------------------------------------------------------------------

    // Master 0 writes 0xA5A5_A5A5 to slave 0 at 0x1000_0100
    m0_trans(32'h1000_0100, 1'b1, 32'hA5A5_A5A5, 4'hF, rd0);
    // Master 0 reads back from slave 0
    m0_trans(32'h1000_0100, 1'b0, 32'h0, 4'hF, rd0);
    check_eq(rd0, 32'hA5A5_A5A5, "basic route: M0->S0 write then read");

    // Master 1 writes 0x5A5A_5A5A to slave 1 at 0x2000_0200
    m1_trans(32'h2000_0200, 1'b1, 32'h5A5A_5A5A, 4'hF, rd1);
    // Master 1 reads back from slave 1
    m1_trans(32'h2000_0200, 1'b0, 32'h0, 4'hF, rd1);
    check_eq(rd1, 32'h5A5A_5A5A, "basic route: M1->S1 write then read");

    // -----------------------------------------------------------------------
    // Test 2: Cross routing — master 0 to slave 1, master 1 to slave 0
    // -----------------------------------------------------------------------
    m0_trans(32'h2000_0300, 1'b1, 32'hDEAD_CAFE, 4'hF, rd0);
    m0_trans(32'h2000_0300, 1'b0, 32'h0,          4'hF, rd0);
    check_eq(rd0, 32'hDEAD_CAFE, "cross route: M0->S1 write then read");

    m1_trans(32'h1000_0400, 1'b1, 32'hBEEF_F00D, 4'hF, rd1);
    m1_trans(32'h1000_0400, 1'b0, 32'h0,          4'hF, rd1);
    check_eq(rd1, 32'hBEEF_F00D, "cross route: M1->S0 write then read");

    // -----------------------------------------------------------------------
    // Test 3: Verify addresses in slave 0 space did not alias to slave 1
    // -----------------------------------------------------------------------
    // We wrote 0xA5A5_A5A5 to slave 0 offset 0x100, and 0xBEEF_F00D to slave 0 offset 0x400
    // Read slave 0 at a different offset to verify no corruption
    m0_trans(32'h1000_0004, 1'b0, 32'h0, 4'hF, rd0);
    check_eq(rd0, 32'h0000_0000, "no alias: slave 0 offset 4 still 0");

    // -----------------------------------------------------------------------
    // Test 4: Sequential transactions through same slave
    // -----------------------------------------------------------------------
    m0_trans(32'h1000_0010, 1'b1, 32'h0000_0001, 4'hF, rd0);
    m0_trans(32'h1000_0014, 1'b1, 32'h0000_0002, 4'hF, rd0);
    m0_trans(32'h1000_0018, 1'b1, 32'h0000_0003, 4'hF, rd0);

    m0_trans(32'h1000_0010, 1'b0, 32'h0, 4'hF, rd0);
    check_eq(rd0, 32'h0000_0001, "seq trans: S0 offset 0x10");
    m0_trans(32'h1000_0014, 1'b0, 32'h0, 4'hF, rd0);
    check_eq(rd0, 32'h0000_0002, "seq trans: S0 offset 0x14");
    m0_trans(32'h1000_0018, 1'b0, 32'h0, 4'hF, rd0);
    check_eq(rd0, 32'h0000_0003, "seq trans: S0 offset 0x18");

    test_done("test_bus_matrix_ops");
  end
endtask
