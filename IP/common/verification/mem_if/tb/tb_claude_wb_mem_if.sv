// tb_claude_wb_mem_if.sv — Directed testbench for claude_wb_mem_if (Wishbone B4).
//
// The DUT is whichever claude_wb_mem_if was compiled: the SV module or the
// VHDL-2008 entity (mixed-language VCS / Xcelium). The Wishbone B4 master is the
// shared BFM (IP/common/verification/tasks/tasks_wb.sv); the memory is
// claude_mem_tb_target. Tests: mem_if_tests.sv.
//
// Prints "PASS tb_claude_wb_mem_if" on success; any failed check ends the
// simulation with $finish(1).

`define CLAUDE_BFM_ADDR_W 32

`timescale 1ns / 1ps

module tb_claude_wb_mem_if;

  localparam int unsigned DataW = 32;
  localparam int unsigned AddrW = 32;

  logic clk = 1'b0;
  always #5 clk = ~clk;

  logic             RST_I;
  logic             CYC_I;
  logic             STB_I;
  logic             WE_I;
  logic [AddrW-1:0] ADR_I;
  logic [DataW-1:0] DAT_I;
  logic [3:0]       SEL_I;
  logic [DataW-1:0] DAT_O;
  logic             ACK_O;
  logic             ERR_O;

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

  claude_wb_mem_if #(
    .DATA_W(DataW),
    .ADDR_W(AddrW)
  ) u_dut (
    .CLK_I       (clk),
    .RST_I       (RST_I),
    .CYC_I       (CYC_I),
    .STB_I       (STB_I),
    .WE_I        (WE_I),
    .ADR_I       (ADR_I),
    .DAT_I       (DAT_I),
    .SEL_I       (SEL_I),
    .DAT_O       (DAT_O),
    .ACK_O       (ACK_O),
    .ERR_O       (ERR_O),
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
    .rst       (RST_I),
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

  `include "tasks_wb.sv"
  `include "ip_test_pkg.sv"
  `include "mem_if_tests.sv"

  initial begin : p_timeout
    #5ms;
    $display("FAIL tb_claude_wb_mem_if: simulation timeout");
    $finish(1);
  end

`ifdef CLAUDE_DUMP_VCD
  initial begin
    $dumpfile("tb_claude_wb_mem_if.vcd");
    $dumpvars(0, tb_claude_wb_mem_if);
  end
`endif

  initial begin : p_main
    apply_reset(4);
    run_common_tests();
    check_accounting();
    $display("PASS tb_claude_wb_mem_if: all tests passed");
    $finish;
  end

endmodule : tb_claude_wb_mem_if
