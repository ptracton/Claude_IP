// tb_timer_ahb.sv — AHB-Lite testbench for timer IP.
//
// Instantiates timer_ahb and drives the AHB-Lite bus to run all directed tests.
// No compile-time defines are used to select the DUT — this file always
// instantiates timer_ahb explicitly.

`timescale 1ns / 1ps

module tb_timer_ahb;

  // -------------------------------------------------------------------------
  // Clock and reset
  // -------------------------------------------------------------------------
  logic clk;   // 10 ns period
  logic rst_n; // synchronous active-low reset

  initial clk = 1'b0;
  always #5 clk = ~clk;

  // -------------------------------------------------------------------------
  // AHB-Lite bus signals
  // -------------------------------------------------------------------------
  logic        HSEL;
  logic [11:0] HADDR;
  logic [1:0]  HTRANS;
  logic        HWRITE;
  logic [31:0] HWDATA;
  logic [3:0]  HWSTRB;
  logic [31:0] HRDATA;
  logic        HREADY;
  logic        HRESP;

  // -------------------------------------------------------------------------
  // IP outputs
  // -------------------------------------------------------------------------
  logic irq;
  logic trigger_out;

  // -------------------------------------------------------------------------
  // DUT instantiation — timer_ahb (explicit)
  // -------------------------------------------------------------------------
  timer_ahb #(
    .DATA_W  (32),
    .ADDR_W  (4),
    .RST_POL (0)
  ) u_dut (
    .HCLK       (clk),
    .HRESETn    (rst_n),
    .HSEL       (HSEL),
    .HADDR      (HADDR),
    .HTRANS     (HTRANS),
    .HWRITE     (HWRITE),
    .HWDATA     (HWDATA),
    .HWSTRB     (HWSTRB),
    .HRDATA     (HRDATA),
    .HREADY     (HREADY),
    .HRESP      (HRESP),
    .irq        (irq),
    .trigger_out(trigger_out)
  );

  // -------------------------------------------------------------------------
  // BFM task library and directed test tasks
  // -------------------------------------------------------------------------
  `include "tasks_ahb.sv"
  `include "ip_test_pkg.sv"
  `include "test_reset.sv"
  `include "test_rw.sv"
  `include "test_back2back.sv"
  `include "test_strobe.sv"
  `include "test_timer_ops.sv"

  // -------------------------------------------------------------------------
  // Simulation timeout watchdog
  // -------------------------------------------------------------------------
  initial begin
    #1000000;
    $display("FAIL tb_timer_ahb: simulation timeout");
    $finish(1);
  end

  // -------------------------------------------------------------------------
  // Test stimulus
  // -------------------------------------------------------------------------
  initial begin
    HSEL   = 1'b0;
    HADDR  = 12'h000;
    HTRANS = 2'b00; // IDLE
    HWRITE = 1'b0;
    HWDATA = 32'h0;
    HWSTRB = 4'hF;

    apply_reset(8);

    test_reset;
    test_rw;
    test_back2back;
    test_strobe;
    test_timer_ops;

    $display("PASS tb_timer_ahb: all tests passed");
    $finish;
  end

endmodule : tb_timer_ahb
