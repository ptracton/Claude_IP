// mst_if_tests.sv — Protocol-neutral tests for the claude_<proto>_mst_if master adapters.
//
// `include'd inside each tb_claude_<proto>_mst_if module. The including module
// provides:
//   parameters DATA_W, ADDR_W; localparams StrbW, OffW
//   signals    clk, rst_n (DUT reset), mem_req, mem_gnt, mem_we, mem_addr,
//              mem_be, mem_wdata, mem_prot, mem_rvalid, mem_rdata, mem_err
//   instance   u_tgt (claude_mem_model: max_gnt_delay, max_rsp_delay, 1024 words
//              from address 0, error range = address bit ADDR_W-1 set)
//   tasks      bus_check_report() — prints and returns the bus-side error count
//   variables  bus_xfers (completed bus transfers), bus_errors
//   localparam SPARSE_WR_OK — 1 if the adapter issues every write-strobe pattern;
//              0 if it answers non-aligned write patterns with mem_err and no bus
//              access (AHB-Lite with HAS_HWSTRB = 0, initiator rule 8)
//
// Provides: an initiator BFM on mem_* (initiator rules 1, 2, 6-9 of
// .agents/IP_SPEC_mem_bus_initiator.md), checks of the adapter's target rules
// (3-5), an expected-transfer queue for end-to-end checks on the bus side, a
// reference memory, and the tests.
//
// Simulation only. Written for Icarus 12, xsim, VCS and Xcelium (no classes,
// no queues).

  // ---------------------------------------------------------------------------
  // Reference memory (same indexing as u_tgt: 1024 words, wrapping)
  // ---------------------------------------------------------------------------
  localparam int unsigned RefWords = 1024;
  localparam int unsigned IdxW     = $clog2(RefWords);
  logic [DATA_W-1:0] ref_mem [RefWords];

  function automatic int unsigned ref_index(logic [ADDR_W-1:0] a);
    return int'(a[OffW +: IdxW]);
  endfunction

  // ---------------------------------------------------------------------------
  // Expected-transfer queue: every accepted request must appear once on the
  // bus with the same attributes (checked by the protocol-specific monitor).
  // ---------------------------------------------------------------------------
  localparam int unsigned ExpDepth = 16;
  logic              exp_we    [ExpDepth];
  logic [ADDR_W-1:0] exp_addr  [ExpDepth];
  logic [StrbW-1:0]  exp_be    [ExpDepth];
  logic [DATA_W-1:0] exp_wdata [ExpDepth];
  logic [2:0]        exp_prot  [ExpDepth];
  int unsigned       exp_wr_ptr = 0;
  int unsigned       exp_rd_ptr = 0;

  // ---------------------------------------------------------------------------
  // Counters and checks on the adapter's mem_* target behaviour
  // ---------------------------------------------------------------------------
  int unsigned n_fail      = 0;   // test failures (data, latency, ...)
  int unsigned n_mem_viol  = 0;   // target-rule violations by the adapter
  int unsigned n_accepted  = 0;   // requests accepted (req & gnt)
  int unsigned n_responses = 0;   // mem_rvalid pulses
  int unsigned n_err_seen  = 0;   // responses with mem_err
  int unsigned n_aborted   = 0;   // accepted requests cut off by a reset
  int unsigned n_nobus     = 0;   // accepted requests answered without a bus access (rule 8)
  realtime     last_hs_t   = 0;   // time of the latest handshake
  realtime     prev_hs_t   = 0;   // time of the handshake before it

  // A byte-enable pattern that is a naturally aligned power-of-two block (rule 7).
  function automatic logic is_aligned(logic [StrbW-1:0] be);
    int unsigned lo, n;
    logic        gap, ok;
    lo = StrbW; n = 0; gap = 1'b0; ok = 1'b1;
    for (int b = 0; b < StrbW; b++) begin
      if (be[b]) begin
        if (lo == StrbW) lo = b;
        if (gap) ok = 1'b0;
        n++;
      end else if (lo != StrbW) begin
        gap = 1'b1;
      end
    end
    if (n == 0 || (n & (n - 1)) != 0 || (lo % n) != 0) ok = 1'b0;
    return ok;
  endfunction

  // Does this request reach the bus? (rule 8: illegal write patterns do not)
  function automatic logic bus_legal(logic we, logic [StrbW-1:0] be);
    return SPARSE_WR_OK || !we || is_aligned(be);
  endfunction

  logic hs_q;          // last cycle was a handshake
  logic pending;       // accepted, response not yet seen

  always @(posedge clk) begin : p_mem_rules
    if (!rst_n) begin
      if (pending) n_aborted++;
      hs_q    <= 1'b0;
      pending <= 1'b0;
      if (mem_gnt) begin
        $display("ERROR [mst_if] mem_gnt high during reset (%0t)", $time);
        n_mem_viol++;
      end
    end else begin
      if (mem_rvalid) begin
        n_responses++;
        if (!pending) begin
          $display("ERROR [mst_if] mem_rvalid without an outstanding request (%0t)", $time);
          n_mem_viol++;
        end
      end
      if (mem_req && mem_gnt) begin
        n_accepted++;
        prev_hs_t = last_hs_t;
        last_hs_t = $realtime;
        if (pending && !mem_rvalid) begin
          $display("ERROR [mst_if] request accepted while one is outstanding (%0t)", $time);
          n_mem_viol++;
        end
        if (bus_legal(mem_we, mem_be)) begin
          exp_we   [exp_wr_ptr % ExpDepth] <= mem_we;
          exp_addr [exp_wr_ptr % ExpDepth] <= mem_addr;
          exp_be   [exp_wr_ptr % ExpDepth] <= mem_be;
          exp_wdata[exp_wr_ptr % ExpDepth] <= mem_wdata;
          exp_prot [exp_wr_ptr % ExpDepth] <= mem_prot;
          exp_wr_ptr <= exp_wr_ptr + 1;
        end else begin
          n_nobus++;
        end
      end
      // rvalid is never in the handshake cycle itself (rule 3): the response
      // to a request accepted in cycle N appears in cycle N+1 at the earliest.
      if (mem_rvalid && hs_q && !pending) begin
        $display("ERROR [mst_if] mem_rvalid in the handshake cycle (%0t)", $time);
        n_mem_viol++;
      end
      hs_q <= mem_req & mem_gnt;
      if (mem_req && mem_gnt)  pending <= 1'b1;
      else if (mem_rvalid)     pending <= 1'b0;
    end
  end

  // ---------------------------------------------------------------------------
  // Initiator BFM. Drives on the falling edge, samples on the rising edge.
  // ---------------------------------------------------------------------------
  int unsigned max_idle = 0;   // random idle cycles before each request: 0..max_idle

  task automatic bfm_idle();
    mem_req   = 1'b0;
    mem_we    = 1'b0;
    mem_addr  = '0;
    mem_be    = '0;
    mem_wdata = '0;
    mem_prot  = 3'b000;
  endtask

  // One transfer. Returns the response; lat = rising edges from the handshake
  // edge to the edge that samples mem_rvalid.
  task automatic bfm_xfer(input logic we, input logic [ADDR_W-1:0] addr,
                          input logic [StrbW-1:0] be, input logic [DATA_W-1:0] wdata,
                          input logic [2:0] prot,
                          output logic [DATA_W-1:0] rdata, output logic err,
                          output int unsigned lat);
    int unsigned idle;
    int unsigned guard;
    idle = (max_idle == 0) ? 0 : $urandom_range(max_idle, 0);
    repeat (idle) @(negedge clk);
    @(negedge clk);
    mem_req   = 1'b1;
    mem_we    = we;
    mem_addr  = addr;
    mem_be    = be;
    mem_wdata = we ? wdata : {DATA_W{1'bx}};   // don't care on reads
    mem_prot  = prot;
    // Hold the request until the rising edge that sees mem_gnt (rule 1).
    guard = 0;
    do begin
      @(posedge clk);
      guard++;
    end while (!mem_gnt && guard < 1000);
    if (!mem_gnt) begin
      $display("FAIL [mst_if] no grant within 1000 cycles");
      n_fail++;
    end
    @(negedge clk);
    bfm_idle();
    // Wait for the response.
    lat = 0;
    do begin
      @(posedge clk);
      lat++;
    end while (!mem_rvalid && lat < 1000);
    if (!mem_rvalid) begin
      $display("FAIL [mst_if] no response within 1000 cycles");
      n_fail++;
    end
    rdata = mem_rdata;
    err   = mem_err;
    if (err) n_err_seen++;
  endtask

  // Write with the reference memory updated.
  task automatic do_write(input logic [ADDR_W-1:0] addr, input logic [StrbW-1:0] be,
                          input logic [DATA_W-1:0] data, input logic [2:0] prot,
                          input logic expect_err);
    logic [DATA_W-1:0] rd;
    logic              err;
    int unsigned       lat;
    expect_err = expect_err | ~bus_legal(1'b1, be);   // rule 8
    bfm_xfer(1'b1, addr, be, data, prot, rd, err, lat);
    if (err !== expect_err) begin
      $display("FAIL [mst_if] write 0x%0h be %b: err = %b, expected %b", addr, be, err, expect_err);
      n_fail++;
    end
    if (!expect_err) begin
      for (int b = 0; b < StrbW; b++)
        if (be[b]) ref_mem[ref_index(addr)][8*b +: 8] = data[8*b +: 8];
    end
  endtask

  // Read, checking the enabled lanes against the reference memory.
  task automatic do_read(input logic [ADDR_W-1:0] addr, input logic [StrbW-1:0] be,
                         input logic [2:0] prot, input logic expect_err);
    logic [DATA_W-1:0] rd;
    logic              err;
    int unsigned       lat;
    bfm_xfer(1'b0, addr, be, '0, prot, rd, err, lat);
    if (err !== expect_err) begin
      $display("FAIL [mst_if] read 0x%0h be %b: err = %b, expected %b", addr, be, err, expect_err);
      n_fail++;
    end
    if (!expect_err) begin
      for (int b = 0; b < StrbW; b++) begin
        if (be[b] && rd[8*b +: 8] !== ref_mem[ref_index(addr)][8*b +: 8]) begin
          $display("FAIL [mst_if] read 0x%0h lane %0d: 0x%0h, expected 0x%0h", addr, b,
                   rd[8*b +: 8], ref_mem[ref_index(addr)][8*b +: 8]);
          n_fail++;
        end
      end
    end
  endtask

  // Byte enables of a naturally aligned access of 2**size bytes at lane offset.
  function automatic logic [StrbW-1:0] lanes(int unsigned size, int unsigned off);
    logic [StrbW-1:0] be;
    be = '0;
    for (int b = 0; b < (1 << size); b++) be[off + b] = 1'b1;
    return be;
  endfunction

  function automatic logic [ADDR_W-1:0] word_addr(int unsigned idx);
    logic [ADDR_W-1:0] a;
    a = '0;
    a[OffW +: IdxW] = idx[IdxW-1:0];
    return a;
  endfunction

  function automatic logic [DATA_W-1:0] rand_data();
    logic [DATA_W-1:0] d;
    for (int b = 0; b < StrbW; b++) d[8*b +: 8] = $urandom_range(255, 0);
    return d;
  endfunction

  localparam int unsigned MaxSize = $clog2(StrbW);   // largest access: 2**MaxSize bytes
  localparam logic [ADDR_W-1:0] ErrBit = {1'b1, {(ADDR_W-1){1'b0}}};

  // ---------------------------------------------------------------------------
  // Tests
  // ---------------------------------------------------------------------------

  // Full words at both ends and in the middle of the storage, back to back.
  task automatic test_basic_rw();
    int unsigned idx [3];
    idx[0] = 0; idx[1] = RefWords / 2; idx[2] = RefWords - 1;
    for (int i = 0; i < 3; i++) do_write(word_addr(idx[i]), '1, rand_data(), 3'b000, 1'b0);
    for (int i = 0; i < 3; i++) do_read(word_addr(idx[i]), '1, 3'b000, 1'b0);
  endtask

  // Every naturally aligned size on every lane: write, then read back exactly
  // those lanes (rules 6 and 7).
  task automatic test_sizes_lanes();
    logic [ADDR_W-1:0] a;
    for (int unsigned size = 0; size <= MaxSize; size++) begin
      for (int unsigned off = 0; off < StrbW; off += (1 << size)) begin
        a = word_addr(16 + size) | ADDR_W'(off);
        do_write(a, lanes(size, off), rand_data(), 3'b000, 1'b0);
        do_read(a, lanes(size, off), 3'b000, 1'b0);
      end
      // Whole word read after the per-lane writes.
      do_read(word_addr(16 + size), '1, 3'b000, 1'b0);
    end
  endtask

  // Sparse write strobes (rule 8: APB4 / AXI4-Lite / Wishbone take any pattern).
  task automatic test_sparse_strobes();
    logic [StrbW-1:0] be;
    logic [ADDR_W-1:0] a;
    if (StrbW >= 2) begin
      do_write(word_addr(40), '1, '0, 3'b000, 1'b0);
      for (int p = 1; p < (1 << StrbW); p++) begin
        be = p[StrbW-1:0];
        a  = word_addr(40);
        for (int b = StrbW - 1; b >= 0; b--) if (be[b]) a = word_addr(40) + ADDR_W'(b);  // lowest lane
        do_write(a, be, rand_data(), 3'b000, 1'b0);
        do_read(word_addr(40), '1, 3'b000, 1'b0);
      end
    end
  endtask

  // mem_prot reaches the bus unchanged (checked by the bus monitor through the
  // expected-transfer queue) for every value.
  task automatic test_prot();
    for (int p = 0; p < 8; p++) begin
      do_write(word_addr(60), '1, rand_data(), p[2:0], 1'b0);
      do_read(word_addr(60), '1, p[2:0], 1'b0);
    end
  endtask

  // Errors reach the initiator; the write is dropped; the next transfer is OKAY.
  task automatic test_error();
    do_write(word_addr(70), '1, rand_data(), 3'b000, 1'b0);
    do_write(ErrBit | word_addr(70), '1, rand_data(), 3'b000, 1'b1);
    do_read(ErrBit | word_addr(70), '1, 3'b000, 1'b1);
    do_read(word_addr(70), '1, 3'b000, 1'b0);
  endtask

  // Latency and throughput with a zero-wait target and no idle cycles
  // (the table in the initiator spec).
  task automatic test_latency(input int unsigned exp_lat, input int unsigned exp_period);
    logic [DATA_W-1:0] rd, wd;
    logic              err;
    int unsigned       lat;
    int unsigned       saved_idle;
    saved_idle = max_idle;
    max_idle   = 0;
    wd = rand_data();
    bfm_xfer(1'b1, word_addr(80), '1, wd, 3'b000, rd, err, lat);
    ref_mem[ref_index(word_addr(80))] = wd;
    if (lat != exp_lat) begin
      $display("FAIL [mst_if] write latency %0d cycles, expected %0d", lat, exp_lat);
      n_fail++;
    end
    bfm_xfer(1'b0, word_addr(80), '1, '0, 3'b000, rd, err, lat);
    if (lat != exp_lat) begin
      $display("FAIL [mst_if] read latency %0d cycles, expected %0d", lat, exp_lat);
      n_fail++;
    end
    // Throughput: time between the handshakes of two back-to-back transfers.
    bfm_xfer(1'b0, word_addr(80), '1, '0, 3'b000, rd, err, lat);
    bfm_xfer(1'b0, word_addr(80), '1, '0, 3'b000, rd, err, lat);
    if ((last_hs_t - prev_hs_t) != exp_period * CLK_PERIOD) begin
      $display("FAIL [mst_if] back-to-back handshakes %0t apart, expected %0d cycles",
               last_hs_t - prev_hs_t, exp_period);
      n_fail++;
    end
    // Read back the word written above.
    do_read(word_addr(80), '1, 3'b000, 1'b0);
    max_idle = saved_idle;
  endtask

  // Constrained-random traffic against the reference memory.
  task automatic test_random(input int unsigned n);
    logic [ADDR_W-1:0] a;
    logic [StrbW-1:0]  be;
    int unsigned       size, off, idx;
    logic              is_err, we;
    for (int unsigned i = 0; i < n; i++) begin
      idx    = $urandom_range(RefWords - 1, 0);
      is_err = ($urandom_range(19, 0) == 0);           // 5 % error region
      we     = $urandom_range(1, 0);
      if (we && StrbW > 1 && $urandom_range(3, 0) == 0) begin
        be = $urandom_range((1 << StrbW) - 1, 1);       // sparse write pattern
        off = 0;
        for (int b = StrbW - 1; b >= 0; b--) if (be[b]) off = b;
      end else begin
        size = $urandom_range(MaxSize, 0);
        off  = $urandom_range(StrbW / (1 << size) - 1, 0) * (1 << size);
        be   = lanes(size, off);
      end
      a = word_addr(idx) | ADDR_W'(off);
      if (is_err) a = a | ErrBit;
      if (we) do_write(a, be, rand_data(), 3'($urandom_range(7, 0)), is_err);
      else    do_read(a, be, 3'($urandom_range(7, 0)), is_err);
    end
  endtask

  // Reset while a transfer is in flight: the bus goes idle and mem_gnt drops
  // during reset (checked by the monitors), and traffic works afterwards.
  task automatic test_reset_mid_transfer();
    @(negedge clk);
    mem_req   = 1'b1;
    mem_we    = 1'b1;
    mem_addr  = word_addr(90);
    mem_be    = '1;
    mem_wdata = rand_data();
    mem_prot  = 3'b000;
    do @(posedge clk); while (!mem_gnt);
    @(negedge clk);
    bfm_idle();
    @(negedge clk);          // SETUP / address phase on the bus now
    rst_n = 1'b0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    // The interrupted write may or may not have reached the memory: rewrite
    // the word, and restart the expected-transfer queue.
    exp_rd_ptr = exp_wr_ptr;
    repeat (2) @(negedge clk);
    do_write(word_addr(90), '1, rand_data(), 3'b000, 1'b0);
    do_read(word_addr(90), '1, 3'b000, 1'b0);
  endtask

  // Run every test with a given target speed and initiator idle setting.
  task automatic run_all(input string label);
    $display("[mst_if] --- %s: max_gnt_delay %0d, max_rsp_delay %0d, max_idle %0d ---",
             label, u_tgt.max_gnt_delay, u_tgt.max_rsp_delay, max_idle);
    test_basic_rw();
    test_sizes_lanes();
    test_sparse_strobes();
    test_prot();
    test_error();
    test_random(500);
  endtask

  // Final accounting and the PASS / FAIL line.
  task automatic finish_tests(input string top);
    int unsigned bus_err_count;
    repeat (5) @(negedge clk);
    bus_err_count = bus_check_report();
    if (n_accepted != n_responses + n_aborted) begin
      $display("FAIL [mst_if] %0d requests accepted, %0d responses, %0d aborted by reset",
               n_accepted, n_responses, n_aborted);
      n_fail++;
    end
    if (u_tgt.proto_errors != 0) begin
      $display("FAIL [mst_if] %0d memory-bus violations seen by the target model",
               u_tgt.proto_errors);
      n_fail++;
    end
    $display("[mst_if] requests %0d, responses %0d, errors %0d, bus transfers %0d, answered without bus access %0d",
             n_accepted, n_responses, n_err_seen, bus_xfers, n_nobus);
    if (n_fail == 0 && n_mem_viol == 0 && bus_err_count == 0) begin
      $display("PASS %s", top);
    end else begin
      $display("FAIL %s: %0d test failures, %0d mem_* violations, %0d bus violations",
               top, n_fail, n_mem_viol, bus_err_count);
    end
    $finish;
  endtask
