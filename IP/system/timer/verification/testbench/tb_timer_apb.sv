// tb_timer_apb.sv — APB4 testbench for timer IP.
//
// Instantiates timer_apb and drives the APB4 bus to run all directed tests.
// No compile-time defines are used to select the DUT — this file always
// instantiates timer_apb explicitly.
//
// Test sequence:
//   1. apply_reset   — deassert reset, verify clean state
//   2. test_reset    — verify register reset values
//   3. test_rw       — write-then-read-back RW registers
//   4. test_back2back — back-to-back transactions
//   5. test_strobe   — byte-enable combinations
//   6. test_timer_ops — timer functional tests
//
// On success prints "PASS" and calls $finish.
// On any assertion failure calls $finish(1).

`timescale 1ns / 1ps

module tb_timer_apb;

  // -------------------------------------------------------------------------
  // Clock and reset
  // -------------------------------------------------------------------------
  logic clk;   // 10 ns period (100 MHz)
  logic rst_n; // synchronous active-low reset

  // Clock generator: 10 ns period
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // -------------------------------------------------------------------------
  // APB4 bus signals — driven by BFM tasks
  // -------------------------------------------------------------------------
  logic        PSEL;
  logic        PENABLE;
  logic [11:0] PADDR;
  logic        PWRITE;
  logic [31:0] PWDATA;
  logic [3:0]  PSTRB;
  logic [31:0] PRDATA;
  logic        PREADY;
  logic        PSLVERR;

  // -------------------------------------------------------------------------
  // IP outputs — observable for timer_ops tests
  // -------------------------------------------------------------------------
  logic irq;
  logic trigger_out;

  // -------------------------------------------------------------------------
  // DUT instantiation — timer_apb (explicit, no defines)
  // -------------------------------------------------------------------------
  timer_apb #(
    .DATA_W  (32),
    .ADDR_W  (4),
    .RST_POL (0)
  ) u_dut (
    .PCLK       (clk),
    .PRESETn    (rst_n),
    .PSEL       (PSEL),
    .PENABLE    (PENABLE),
    .PADDR      (PADDR),
    .PWRITE     (PWRITE),
    .PWDATA     (PWDATA),
    .PSTRB      (PSTRB),
    .PRDATA     (PRDATA),
    .PREADY     (PREADY),
    .PSLVERR    (PSLVERR),
    .irq        (irq),
    .trigger_out(trigger_out)
  );

  // -------------------------------------------------------------------------
  // BFM task library and directed test tasks
  // -------------------------------------------------------------------------
  `include "tasks_apb.sv"
  `include "ip_test_pkg.sv"
  `include "test_reset.sv"
  `include "test_rw.sv"
  `include "test_back2back.sv"
  `include "test_strobe.sv"
  `include "test_timer_ops.sv"

  // -------------------------------------------------------------------------
  // Simulation timeout watchdog (fail-safe)
  // -------------------------------------------------------------------------
  initial begin
    #1000000; // 1 ms @ 1 ns resolution
    $display("FAIL tb_timer_apb: simulation timeout");
    $finish(1);
  end

  // -------------------------------------------------------------------------
  // Test stimulus
  // -------------------------------------------------------------------------
  initial begin
    // Initialise all bus signals to idle state before reset
    PSEL    = 1'b0;
    PENABLE = 1'b0;
    PADDR   = 12'h000;
    PWRITE  = 1'b0;
    PWDATA  = 32'h0;
    PSTRB   = 4'hF;

    // Apply reset for 8 cycles
    apply_reset(8);

    // Run directed tests
    test_reset;
    test_rw;
    test_back2back;
    test_strobe;
    test_timer_ops;

    // All tests passed
    $display("PASS tb_timer_apb: all tests passed");
    $finish;
  end

endmodule : tb_timer_apb
