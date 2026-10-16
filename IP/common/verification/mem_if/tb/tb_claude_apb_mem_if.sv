// tb_claude_apb_mem_if.sv — Directed testbench for claude_apb_mem_if (APB4).
//
// The DUT is whichever claude_apb_mem_if was compiled: the SV module or the
// VHDL-2008 entity (mixed-language VCS / Xcelium). The APB4 master is the
// shared BFM (IP/common/verification/tasks/tasks_apb.sv); the memory is
// claude_mem_tb_target. Tests: mem_if_tests.sv.
//
// Prints "PASS tb_claude_apb_mem_if" on success; any failed check ends the
// simulation with $finish(1).

`define CLAUDE_BFM_ADDR_W 32

`timescale 1ns / 1ps

module tb_claude_apb_mem_if;

  localparam int unsigned DataW = 32;
  localparam int unsigned AddrW = 32;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic             rst_n;
  logic             PSEL;
  logic             PENABLE;
  logic [AddrW-1:0] PADDR;
  logic             PWRITE;
  logic [DataW-1:0] PWDATA;
  logic [3:0]       PSTRB;
  logic [DataW-1:0] PRDATA;
  logic             PREADY;
  logic             PSLVERR;

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

  claude_apb_mem_if #(
    .DATA_W(DataW),
    .ADDR_W(AddrW)
  ) u_dut (
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

  `include "tasks_apb.sv"
  `include "ip_test_pkg.sv"
  `include "mem_if_tests.sv"

  initial begin : p_timeout
    #5ms;
    $display("FAIL tb_claude_apb_mem_if: simulation timeout");
    $finish(1);
  end

`ifdef CLAUDE_DUMP_VCD
  initial begin
    $dumpfile("tb_claude_apb_mem_if.vcd");
    $dumpvars(0, tb_claude_apb_mem_if);
  end
`endif

  initial begin : p_main
    apply_reset(4);
    run_common_tests();
    check_accounting();
    $display("PASS tb_claude_apb_mem_if: all tests passed");
    $finish;
  end

endmodule : tb_claude_apb_mem_if
