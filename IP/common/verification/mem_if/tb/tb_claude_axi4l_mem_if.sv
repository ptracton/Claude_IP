// tb_claude_axi4l_mem_if.sv — Directed testbench for claude_axi4l_mem_if (AXI4-Lite).
//
// The DUT is whichever claude_axi4l_mem_if was compiled: the SV module or the
// VHDL-2008 entity (mixed-language VCS / Xcelium). The AXI4-Lite master is the
// shared BFM (IP/common/verification/tasks/tasks_axi4l.sv); the memory is
// claude_mem_tb_target. Tests: mem_if_tests.sv, plus concurrent read/write tests below.
//
// Prints "PASS tb_claude_axi4l_mem_if" on success; any failed check ends the
// simulation with $finish(1).

`define CLAUDE_BFM_ADDR_W 32

`timescale 1ns / 1ps

module tb_claude_axi4l_mem_if;

  localparam int unsigned DataW = 32;
  localparam int unsigned AddrW = 32;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic             rst_n;
  logic             AWVALID;
  logic             AWREADY;
  logic [AddrW-1:0] AWADDR;
  logic             WVALID;
  logic             WREADY;
  logic [DataW-1:0] WDATA;
  logic [3:0]       WSTRB;
  logic             BVALID;
  logic             BREADY;
  logic [1:0]       BRESP;
  logic             ARVALID;
  logic             ARREADY;
  logic [AddrW-1:0] ARADDR;
  logic             RVALID;
  logic             RREADY;
  logic [DataW-1:0] RDATA;
  logic [1:0]       RRESP;

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

  claude_axi4l_mem_if #(
    .DATA_W(DataW),
    .ADDR_W(AddrW)
  ) u_dut (
    .ACLK        (clk),
    .ARESETn     (rst_n),
    .AWVALID     (AWVALID),
    .AWREADY     (AWREADY),
    .AWADDR      (AWADDR),
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
    .RVALID      (RVALID),
    .RREADY      (RREADY),
    .RDATA       (RDATA),
    .RRESP       (RRESP),
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

  `include "tasks_axi4l.sv"
  `include "ip_test_pkg.sv"
  `include "mem_if_tests.sv"

  // -------------------------------------------------------------------------
  // test_axi_concurrent — a write and a read issued in the same cycle both
  // complete with the right data (the adapter serializes them).
  // -------------------------------------------------------------------------
  task automatic test_axi_concurrent;
    input string tag;
    logic [31:0] rd;
    int i;
    begin
      test_start({"test_axi_concurrent ", tag});
      for (i = 0; i < 8; i++) begin
        mw(32'h0000_0600 + 8 * i, 32'h6000_0000 + i, 4'hF);
        fork
          write_reg(32'h0000_0604 + 8 * i, 32'h6100_0000 + i, 4'hF);
          read_reg(32'h0000_0600 + 8 * i, rd);
        join
        n_xfers += 2;
        check_eq(rd, 32'h6000_0000 + i, $sformatf("concurrent read %0d", i));
        mr(32'h0000_0604 + 8 * i, rd);
        check_eq(rd, 32'h6100_0000 + i, $sformatf("concurrent write %0d landed", i));
      end
      test_done({"test_axi_concurrent ", tag});
    end
  endtask

  initial begin : p_timeout
    #5ms;
    $display("FAIL tb_claude_axi4l_mem_if: simulation timeout");
    $finish(1);
  end

`ifdef CLAUDE_DUMP_VCD
  initial begin
    $dumpfile("tb_claude_axi4l_mem_if.vcd");
    $dumpvars(0, tb_claude_axi4l_mem_if);
  end
`endif

  initial begin : p_main
    apply_reset(4);
    run_common_tests();
    u_mem.max_gnt_delay = 0;
    u_mem.max_rsp_delay = 0;
    test_axi_concurrent("(fast memory)");
    u_mem.max_gnt_delay = 3;
    u_mem.max_rsp_delay = 4;
    test_axi_concurrent("(slow memory)");
    check_accounting();
    $display("PASS tb_claude_axi4l_mem_if: all tests passed");
    $finish;
  end

endmodule : tb_claude_axi4l_mem_if
