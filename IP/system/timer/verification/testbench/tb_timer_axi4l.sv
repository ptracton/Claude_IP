// tb_timer_axi4l.sv — AXI4-Lite testbench for timer IP.
//
// Instantiates timer_axi4l and drives the AXI4-Lite bus to run all directed tests.
// No compile-time defines are used to select the DUT — this file always
// instantiates timer_axi4l explicitly.

`timescale 1ns / 1ps

module tb_timer_axi4l;

  // -------------------------------------------------------------------------
  // Clock and reset
  // -------------------------------------------------------------------------
  logic clk;
  logic rst_n;

  initial clk = 1'b0;
  always #5 clk = ~clk;

  // -------------------------------------------------------------------------
  // AXI4-Lite bus signals
  // -------------------------------------------------------------------------
  logic        AWVALID;
  logic        AWREADY;
  logic [11:0] AWADDR;

  logic        WVALID;
  logic        WREADY;
  logic [31:0] WDATA;
  logic [3:0]  WSTRB;

  logic        BVALID;
  logic        BREADY;
  logic [1:0]  BRESP;

  logic        ARVALID;
  logic        ARREADY;
  logic [11:0] ARADDR;

  logic        RVALID;
  logic        RREADY;
  logic [31:0] RDATA;
  logic [1:0]  RRESP;

  // -------------------------------------------------------------------------
  // IP outputs
  // -------------------------------------------------------------------------
  logic irq;
  logic trigger_out;

  // -------------------------------------------------------------------------
  // DUT instantiation — timer_axi4l (explicit)
  // -------------------------------------------------------------------------
  timer_axi4l #(
    .DATA_W  (32),
    .ADDR_W  (4),
    .RST_POL (0)
  ) u_dut (
    .ACLK       (clk),
    .ARESETn    (rst_n),
    .AWVALID    (AWVALID),
    .AWREADY    (AWREADY),
    .AWADDR     (AWADDR),
    .WVALID     (WVALID),
    .WREADY     (WREADY),
    .WDATA      (WDATA),
    .WSTRB      (WSTRB),
    .BVALID     (BVALID),
    .BREADY     (BREADY),
    .BRESP      (BRESP),
    .ARVALID    (ARVALID),
    .ARREADY    (ARREADY),
    .ARADDR     (ARADDR),
    .RVALID     (RVALID),
    .RREADY     (RREADY),
    .RDATA      (RDATA),
    .RRESP      (RRESP),
    .irq        (irq),
    .trigger_out(trigger_out)
  );

  // -------------------------------------------------------------------------
  // BFM task library and directed test tasks
  // -------------------------------------------------------------------------
  `include "tasks_axi4l.sv"
  `include "ip_test_pkg.sv"
  `include "test_reset.sv"
  `include "test_rw.sv"
  `include "test_back2back.sv"
  `include "test_strobe.sv"
  `include "test_timer_ops.sv"

  // -------------------------------------------------------------------------
  // Waveform dump
  // -------------------------------------------------------------------------
  initial $vcdpluson(0, tb_timer_axi4l);

  // -------------------------------------------------------------------------
  // Simulation timeout watchdog
  // -------------------------------------------------------------------------
  initial begin
    #1000000;
    $display("FAIL tb_timer_axi4l: simulation timeout");
    $finish(1);
  end

  // -------------------------------------------------------------------------
  // Test stimulus
  // -------------------------------------------------------------------------
  initial begin
    AWVALID = 1'b0;
    AWADDR  = 12'h000;
    WVALID  = 1'b0;
    WDATA   = 32'h0;
    WSTRB   = 4'hF;
    BREADY  = 1'b1;
    ARVALID = 1'b0;
    ARADDR  = 12'h000;
    RREADY  = 1'b1;

    apply_reset(8);

    test_reset;
    test_rw;
    test_back2back;
    test_strobe;
    test_timer_ops;

    $display("PASS tb_timer_axi4l: all tests passed");
    $finish;
  end

endmodule : tb_timer_axi4l
