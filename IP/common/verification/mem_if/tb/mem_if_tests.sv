// mem_if_tests.sv — Protocol-neutral directed tests for the claude_<proto>_mem_if adapters.
//
// `include inside a tb_claude_<proto>_mem_if module AFTER the protocol BFM
// (tasks_<proto>.sv) and ip_test_pkg.sv. Uses only what every BFM provides
// (write_reg, read_reg, bfm_err) plus the testbench's memory model instance
// u_mem (claude_mem_tb_target).
//
// Address map seen through the model: word storage aliases above the
// model's 1024 words; any address with bit 31 set is the error region.

// Deviation: tasks defined in a standalone file for `include inside TB modules.

int unsigned n_xfers = 0;  // bus transfers issued (must equal u_mem.n_req)

localparam logic [31:0] ERR_BASE = 32'h8000_0000;

// ---------------------------------------------------------------------------
// Counted single transfers
// ---------------------------------------------------------------------------
task automatic mw;
  input logic [31:0] addr;
  input logic [31:0] data;
  input logic [3:0]  strb;
  begin
    write_reg(addr, data, strb);
    n_xfers++;
  end
endtask

task automatic mr;
  input  logic [31:0] addr;
  output logic [31:0] data;
  begin
    read_reg(addr, data);
    n_xfers++;
  end
endtask

// ---------------------------------------------------------------------------
// test_basic_rw — words at both ends of the storage and in the middle.
// ---------------------------------------------------------------------------
task automatic test_basic_rw;
  input string tag;
  logic [31:0] rd;
  begin
    test_start({"test_basic_rw ", tag});
    mw(32'h0000_0000, 32'hDEAD_BEEF, 4'hF);
    mw(32'h0000_0004, 32'h0123_4567, 4'hF);
    mw(32'h0000_0800, 32'hCAFE_F00D, 4'hF);
    mw(32'h0000_0FFC, 32'hA5A5_5A5A, 4'hF);
    mr(32'h0000_0000, rd); check_eq(rd, 32'hDEAD_BEEF, "word 0x000");
    check_eq({31'd0, bfm_err}, 32'd0, "no error on read 0x000");
    mr(32'h0000_0004, rd); check_eq(rd, 32'h0123_4567, "word 0x004");
    mr(32'h0000_0800, rd); check_eq(rd, 32'hCAFE_F00D, "word 0x800");
    mr(32'h0000_0FFC, rd); check_eq(rd, 32'hA5A5_5A5A, "word 0xFFC");
    test_done({"test_basic_rw ", tag});
  end
endtask

// ---------------------------------------------------------------------------
// test_strobe — partial writes merge into the stored word.
// ---------------------------------------------------------------------------
task automatic test_strobe;
  input string tag;
  logic [31:0] rd;
  begin
    test_start({"test_strobe ", tag});
    mw(32'h0000_0100, 32'h1122_3344, 4'hF);
    mw(32'h0000_0100, 32'hAAAA_AAAA, 4'b0001);
    mr(32'h0000_0100, rd); check_eq(rd, 32'h1122_33AA, "strb 0001");
    mw(32'h0000_0100, 32'hBBBB_BBBB, 4'b0100);
    mr(32'h0000_0100, rd); check_eq(rd, 32'h11BB_33AA, "strb 0100");
    mw(32'h0000_0100, 32'hCCDD_EEFF, 4'b1010);
    mr(32'h0000_0100, rd); check_eq(rd, 32'hCCBB_EEAA, "strb 1010");
    mw(32'h0000_0100, 32'h0000_0000, 4'b0000);
    mr(32'h0000_0100, rd); check_eq(rd, 32'hCCBB_EEAA, "strb 0000 writes nothing");
    test_done({"test_strobe ", tag});
  end
endtask

// ---------------------------------------------------------------------------
// test_sweep — 64 consecutive words, written then read back.
// ---------------------------------------------------------------------------
task automatic test_sweep;
  input string tag;
  input logic [31:0] seed;
  logic [31:0] rd;
  int i;
  begin
    test_start({"test_sweep ", tag});
    for (i = 0; i < 64; i++) mw(32'h0000_0200 + 4 * i, seed ^ (32'h0101_0101 * i), 4'hF);
    for (i = 0; i < 64; i++) begin
      mr(32'h0000_0200 + 4 * i, rd);
      check_eq(rd, seed ^ (32'h0101_0101 * i), $sformatf("sweep word %0d", i));
    end
    test_done({"test_sweep ", tag});
  end
endtask

// ---------------------------------------------------------------------------
// test_raw — read directly after a write to the same word.
// ---------------------------------------------------------------------------
task automatic test_raw;
  input string tag;
  logic [31:0] rd;
  int i;
  begin
    test_start({"test_raw ", tag});
    for (i = 0; i < 8; i++) begin
      mw(32'h0000_0400 + 4 * i, 32'h5000_0000 + i, 4'hF);
      mr(32'h0000_0400 + 4 * i, rd);
      check_eq(rd, 32'h5000_0000 + i, $sformatf("read after write %0d", i));
    end
    test_done({"test_raw ", tag});
  end
endtask

// ---------------------------------------------------------------------------
// test_error — the error region answers with the bus error response, drops
// writes, and the adapter recovers for the next transfer.
// ---------------------------------------------------------------------------
task automatic test_error;
  input string tag;
  logic [31:0] rd;
  begin
    test_start({"test_error ", tag});
    mw(32'h0000_0010, 32'h7777_7777, 4'hF);
    mw(ERR_BASE | 32'h10, 32'h9999_9999, 4'hF);
    check_eq({31'd0, bfm_err}, 32'd1, "write to error region -> error");
    mr(ERR_BASE | 32'h10, rd);
    check_eq({31'd0, bfm_err}, 32'd1, "read of error region -> error");
    mr(32'h0000_0010, rd);
    check_eq({31'd0, bfm_err}, 32'd0, "next read OKAY");
    check_eq(rd, 32'h7777_7777, "error write was dropped (alias)");
    mw(32'h0000_0010, 32'h8888_8888, 4'hF);
    check_eq({31'd0, bfm_err}, 32'd0, "next write OKAY");
    mr(32'h0000_0010, rd);
    check_eq(rd, 32'h8888_8888, "next write landed");
    test_done({"test_error ", tag});
  end
endtask

// ---------------------------------------------------------------------------
// run_common_tests — every test above, first against a memory that answers
// at full speed, then with random grant and response delays.
// ---------------------------------------------------------------------------
task automatic run_common_tests;
  begin
    u_mem.max_gnt_delay = 0;
    u_mem.max_rsp_delay = 0;
    test_basic_rw("(fast memory)");
    test_strobe("(fast memory)");
    test_sweep("(fast memory)", 32'h1357_9BDF);
    test_raw("(fast memory)");
    test_error("(fast memory)");

    u_mem.max_gnt_delay = 3;
    u_mem.max_rsp_delay = 4;
    test_basic_rw("(slow memory)");
    test_strobe("(slow memory)");
    test_sweep("(slow memory)", 32'h2468_ACE0);
    test_raw("(slow memory)");
    test_error("(slow memory)");
    u_mem.max_gnt_delay = 0;
    u_mem.max_rsp_delay = 0;
  end
endtask

// ---------------------------------------------------------------------------
// check_accounting — one memory request per bus transfer, no protocol errors.
// ---------------------------------------------------------------------------
task automatic check_accounting;
  begin
    test_start("check_accounting");
    check_eq(u_mem.n_req, n_xfers, "memory requests == bus transfers");
    check_eq(u_mem.proto_errors, 32'd0, "memory-bus protocol violations");
    // The slow-memory half of the run really stalled the adapter.
    check_eq(32'(u_mem.n_gnt_stall > 0), 32'd1, "grant stalls exercised");
    check_eq(32'(u_mem.n_rsp_stall > 0), 32'd1, "response stalls exercised");
    test_done("check_accounting");
  end
endtask
