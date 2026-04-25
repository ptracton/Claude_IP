// tb_timer_wb.sv — Wishbone B4 testbench for timer IP.
//
// Instantiates timer_wb and drives the Wishbone B4 bus to run all directed tests.
// No compile-time defines are used to select the DUT — this file always
// instantiates timer_wb explicitly.
//
// Note: Wishbone uses a synchronous active-high RST_I.  The BFM tasks in
// tasks_wb.sv drive RST_I rather than the active-low rst_n used by APB/AHB/AXI.

`timescale 1ns / 1ps

module tb_timer_wb;

  // -------------------------------------------------------------------------
  // Clock
  // -------------------------------------------------------------------------
  logic clk;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  // -------------------------------------------------------------------------
  // Wishbone bus signals
  // -------------------------------------------------------------------------
  logic        RST_I; // active-high synchronous reset
  logic        CYC_I;
  logic        STB_I;
  logic        WE_I;
  logic [11:0] ADR_I;
  logic [31:0] DAT_I;
  logic [3:0]  SEL_I;
  logic [31:0] DAT_O;
  logic        ACK_O;
  logic        ERR_O;

  // -------------------------------------------------------------------------
  // IP outputs
  // -------------------------------------------------------------------------
  logic irq;
  logic trigger_out;

  // -------------------------------------------------------------------------
  // DUT instantiation — timer_wb (explicit)
  // -------------------------------------------------------------------------
  timer_wb #(
    .DATA_W  (32),
    .ADDR_W  (4),
    .RST_POL (0)
  ) u_dut (
    .CLK_I      (clk),
    .RST_I      (RST_I),
    .CYC_I      (CYC_I),
    .STB_I      (STB_I),
    .WE_I       (WE_I),
    .ADR_I      (ADR_I),
    .DAT_I      (DAT_I),
    .SEL_I      (SEL_I),
    .DAT_O      (DAT_O),
    .ACK_O      (ACK_O),
    .ERR_O      (ERR_O),
    .irq        (irq),
    .trigger_out(trigger_out)
  );

  // -------------------------------------------------------------------------
  // BFM task library and directed test tasks
  // -------------------------------------------------------------------------
  `include "tasks_wb.sv"
  `include "ip_test_pkg.sv"
  `include "test_reset.sv"
  `include "test_rw.sv"
  `include "test_back2back.sv"
  `include "test_strobe.sv"
  `include "test_timer_ops.sv"

  // -------------------------------------------------------------------------
  // Waveform dump
  // -------------------------------------------------------------------------
  initial $vcdpluson(0, tb_timer_wb);

  // -------------------------------------------------------------------------
  // Simulation timeout watchdog
  // -------------------------------------------------------------------------
  initial begin
    #1000000;
    $display("FAIL tb_timer_wb: simulation timeout");
    $finish(1);
  end

  // -------------------------------------------------------------------------
  // Test stimulus
  // -------------------------------------------------------------------------
  initial begin
    CYC_I = 1'b0;
    STB_I = 1'b0;
    WE_I  = 1'b0;
    ADR_I = 12'h000;
    DAT_I = 32'h0;
    SEL_I = 4'hF;

    apply_reset(8);

    test_reset;
    test_rw;
    test_back2back;
    test_strobe;
    test_timer_ops;

    $display("PASS tb_timer_wb: all tests passed");
    $finish;
  end

endmodule : tb_timer_wb
