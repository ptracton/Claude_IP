// tb_claude_ahb_mem_if.sv — Directed testbench for claude_ahb_mem_if (AHB-Lite).
//
// The DUT is whichever claude_ahb_mem_if was compiled: the SV module or the
// VHDL-2008 entity (mixed-language VCS / Xcelium). The AHB-Lite master is the
// shared BFM (IP/common/verification/tasks/tasks_ahb.sv); the memory is
// claude_mem_tb_target. Tests: mem_if_tests.sv, plus sized-transfer and burst tests below.
//
// Prints "PASS tb_claude_ahb_mem_if" on success; any failed check ends the
// simulation with $finish(1).

`define CLAUDE_BFM_ADDR_W 32
`define CLAUDE_BFM_AHB_HSIZE
`timescale 1ns / 1ps

module tb_claude_ahb_mem_if;

  localparam int unsigned DataW = 32;
  localparam int unsigned AddrW = 32;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic             rst_n;
  logic             HSEL;
  logic [AddrW-1:0] HADDR;
  logic [1:0]       HTRANS;
  logic             HWRITE;
  logic [2:0]       HSIZE;
  logic [DataW-1:0] HWDATA;
  logic [3:0]       HWSTRB;
  logic             HREADY;     // bus ready = this (only) slave's HREADYOUT
  logic [DataW-1:0] HRDATA;
  logic             HREADYOUT;
  logic             HRESP;

  assign HREADY = HREADYOUT;

  // Memory bus
  logic             mem_req;
  logic             mem_gnt;
  logic             mem_we;
  logic [AddrW-1:0] mem_addr;
  logic [3:0]       mem_be;
  logic [DataW-1:0] mem_wdata;
  logic             mem_rvalid;
  logic [DataW-1:0] mem_rdata;
  logic             mem_err;

  claude_ahb_mem_if #(
    .DATA_W(DataW),
    .ADDR_W(AddrW)
  ) u_dut (
    .HCLK        (clk),
    .HRESETn     (rst_n),
    .HSEL        (HSEL),
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
    .mem_req_o   (mem_req),
    .mem_gnt_i   (mem_gnt),
    .mem_we_o    (mem_we),
    .mem_addr_o  (mem_addr),
    .mem_be_o    (mem_be),
    .mem_wdata_o (mem_wdata),
    .mem_rvalid_i(mem_rvalid),
    .mem_rdata_i (mem_rdata),
    .mem_err_i   (mem_err)
  );

  claude_mem_tb_target #(
    .DATA_W(DataW),
    .ADDR_W(AddrW)
  ) u_mem (
    .clk       (clk),
    .rst       (~rst_n),
    .mem_req   (mem_req),
    .mem_gnt   (mem_gnt),
    .mem_we    (mem_we),
    .mem_addr  (mem_addr),
    .mem_be    (mem_be),
    .mem_wdata (mem_wdata),
    .mem_rvalid(mem_rvalid),
    .mem_rdata (mem_rdata),
    .mem_err   (mem_err)
  );

  `include "tasks_ahb.sv"
  `include "ip_test_pkg.sv"
  `include "mem_if_tests.sv"

  // -------------------------------------------------------------------------
  // test_ahb_sized — byte and halfword transfers: byte enables follow
  // HSIZE/HADDR (ANDed with HWSTRB on writes).
  // -------------------------------------------------------------------------
  task automatic test_ahb_sized;
    input string tag;
    logic [31:0] rd;
    begin
      test_start({"test_ahb_sized ", tag});
      mw(32'h0000_0300, 32'h0000_0000, 4'hF);
      write_sized(32'h0000_0300, 32'h0000_00AA, 3'd0, 4'hF); n_xfers++;
      check_eq({28'd0, u_mem.last_be}, 32'h1, "byte 0 lanes");
      write_sized(32'h0000_0301, 32'h0000_BB00, 3'd0, 4'hF); n_xfers++;
      check_eq({28'd0, u_mem.last_be}, 32'h2, "byte 1 lanes");
      write_sized(32'h0000_0302, 32'h00CC_0000, 3'd0, 4'hF); n_xfers++;
      check_eq({28'd0, u_mem.last_be}, 32'h4, "byte 2 lanes");
      write_sized(32'h0000_0303, 32'hDD00_0000, 3'd0, 4'hF); n_xfers++;
      check_eq({28'd0, u_mem.last_be}, 32'h8, "byte 3 lanes");
      mr(32'h0000_0300, rd); check_eq(rd, 32'hDDCC_BBAA, "four byte writes");
      write_sized(32'h0000_0302, 32'h1234_0000, 3'd1, 4'hF); n_xfers++;
      check_eq({28'd0, u_mem.last_be}, 32'hC, "upper halfword lanes");
      mr(32'h0000_0300, rd); check_eq(rd, 32'h1234_BBAA, "halfword write");
      write_sized(32'h0000_0302, 32'h5678_0000, 3'd1, 4'b0100); n_xfers++;
      check_eq({28'd0, u_mem.last_be}, 32'h4, "halfword AND HWSTRB");
      mr(32'h0000_0300, rd); check_eq(rd, 32'h1278_BBAA, "halfword with HWSTRB 0100");
      read_sized(32'h0000_0301, 3'd0, rd); n_xfers++;
      check_eq({28'd0, u_mem.last_be}, 32'h2, "byte read lanes");
      check_eq(rd, 32'h1278_BBAA, "byte read returns the word");
      read_sized(32'h0000_0300, 3'd1, rd); n_xfers++;
      check_eq({28'd0, u_mem.last_be}, 32'h3, "halfword read lanes");
      test_done({"test_ahb_sized ", tag});
    end
  endtask

  // -------------------------------------------------------------------------
  // test_ahb_burst — pipelined INCR4 bursts (SEQ beats), with and without a
  // BUSY cycle, and a burst into the error region.
  // -------------------------------------------------------------------------
  task automatic test_ahb_burst;
    input string tag;
    logic [31:0] r0, r1, r2, r3, rd;
    begin
      test_start({"test_ahb_burst ", tag});
      burst_incr4_write(32'h0000_0500, 32'hB000_0000, 32'hB000_0001, 32'hB000_0002,
                        32'hB000_0003, 1'b0);
      n_xfers += 4;
      check_eq({31'd0, bfm_err}, 32'd0, "burst write OKAY");
      burst_incr4_read(32'h0000_0500, 1'b0, r0, r1, r2, r3);
      n_xfers += 4;
      check_eq(r0, 32'hB000_0000, "burst read beat 0");
      check_eq(r1, 32'hB000_0001, "burst read beat 1");
      check_eq(r2, 32'hB000_0002, "burst read beat 2");
      check_eq(r3, 32'hB000_0003, "burst read beat 3");
      burst_incr4_write(32'h0000_0510, 32'hC000_0000, 32'hC000_0001, 32'hC000_0002,
                        32'hC000_0003, 1'b1);
      n_xfers += 4;
      burst_incr4_read(32'h0000_0510, 1'b1, r0, r1, r2, r3);
      n_xfers += 4;
      check_eq(r0, 32'hC000_0000, "BUSY burst beat 0");
      check_eq(r1, 32'hC000_0001, "BUSY burst beat 1");
      check_eq(r2, 32'hC000_0002, "BUSY burst beat 2");
      check_eq(r3, 32'hC000_0003, "BUSY burst beat 3");
      mr(32'h0000_0504, rd); check_eq(rd, 32'hB000_0001, "single read inside burst area");
      burst_incr4_write(ERR_BASE | 32'h0000_0520, 32'h1, 32'h2, 32'h3, 32'h4, 1'b0);
      n_xfers += 4;
      check_eq({31'd0, bfm_err}, 32'd1, "burst into error region -> error");
      burst_incr4_read(ERR_BASE | 32'h0000_0520, 1'b1, r0, r1, r2, r3);
      n_xfers += 4;
      check_eq({31'd0, bfm_err}, 32'd1, "burst read of error region -> error");
      mr(32'h0000_0500, rd);
      check_eq({31'd0, bfm_err}, 32'd0, "OKAY after error burst");
      check_eq(rd, 32'hB000_0000, "data intact after error burst");
      test_done({"test_ahb_burst ", tag});
    end
  endtask

  initial begin : p_timeout
    #5ms;
    $display("FAIL tb_claude_ahb_mem_if: simulation timeout");
    $finish(1);
  end

`ifdef CLAUDE_DUMP_VCD
  initial begin
    $dumpfile("tb_claude_ahb_mem_if.vcd");
    $dumpvars(0, tb_claude_ahb_mem_if);
  end
`endif

  initial begin : p_main
    apply_reset(4);
    run_common_tests();
    u_mem.max_gnt_delay = 0;
    u_mem.max_rsp_delay = 0;
    test_ahb_sized("(fast memory)");
    test_ahb_burst("(fast memory)");
    u_mem.max_gnt_delay = 3;
    u_mem.max_rsp_delay = 4;
    test_ahb_sized("(slow memory)");
    test_ahb_burst("(slow memory)");
    check_accounting();
    $display("PASS tb_claude_ahb_mem_if: all tests passed");
    $finish;
  end

endmodule : tb_claude_ahb_mem_if
