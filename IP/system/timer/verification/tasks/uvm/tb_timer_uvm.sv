// tb_timer_uvm.sv — Top-level UVM testbench for Timer APB4 IP.
//
// Responsibilities:
//   1. Generate PCLK (10 ns period, 100 MHz) and synchronous PRESETn.
//   2. Instantiate the timer_apb_if SystemVerilog interface.
//   3. Instantiate the timer_apb DUT and connect the interface.
//   4. Register the virtual interface handle in the UVM config_db so that
//      the driver and monitor can retrieve it.
//   5. Call run_test() to hand control to the UVM phase engine.
//
// The test name is selected at elaboration time via the simulator
// +UVM_TESTNAME plusarg (defaults to "timer_base_test" if not supplied).
//
// Compile order (VCS example):
//   vcs -sverilog -ntb_opts uvm-1.2        \
//       +incdir+$UVM_HOME/src               \
//       $UVM_HOME/src/uvm_pkg.sv            \
//       timer_apb_if.sv                     \
//       timer_uvm_pkg.sv                    \
//       <rtl_files>                         \
//       tb_timer_uvm.sv                     \
//       -o simv
//   ./simv +UVM_TESTNAME=timer_base_test
//
// NOTE: Requires a UVM-capable simulator (VCS, Questasim, or Riviera-PRO).
//       Not compatible with Icarus Verilog or GHDL.

`timescale 1ns / 1ps

module tb_timer_uvm;

  import uvm_pkg::*;
  `include "uvm_macros.svh"
  import timer_uvm_pkg::*;

  // -------------------------------------------------------------------------
  // Clock and reset generation
  // -------------------------------------------------------------------------
  logic clk;
  logic rst_n;

  // 100 MHz clock (10 ns period)
  initial clk = 1'b0;
  always #5 clk = ~clk;

  // Synchronous active-low reset:
  //   Assert for 10 clock cycles, then de-assert
  initial begin
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    @(negedge clk);   // de-assert between clock edges
    rst_n = 1'b1;
  end

  // -------------------------------------------------------------------------
  // APB4 interface instance
  // -------------------------------------------------------------------------
  timer_apb_if u_apb_if (
    .PCLK    (clk),
    .PRESETn (rst_n)
  );

  // -------------------------------------------------------------------------
  // DUT — timer_apb
  // -------------------------------------------------------------------------
  timer_apb #(
    .DATA_W  (32),
    .ADDR_W  (4),
    .RST_POL (0)   // active-low reset
  ) u_dut (
    .PCLK        (clk),
    .PRESETn     (rst_n),
    .PSEL        (u_apb_if.PSEL),
    .PENABLE     (u_apb_if.PENABLE),
    .PADDR       (u_apb_if.PADDR),
    .PWRITE      (u_apb_if.PWRITE),
    .PWDATA      (u_apb_if.PWDATA),
    .PSTRB       (u_apb_if.PSTRB),
    .PRDATA      (u_apb_if.PRDATA),
    .PREADY      (u_apb_if.PREADY),
    .PSLVERR     (u_apb_if.PSLVERR),
    .irq         (u_apb_if.irq),
    .trigger_out (u_apb_if.trigger_out)
  );

  // -------------------------------------------------------------------------
  // UVM config_db: publish virtual interface to the testbench hierarchy
  // -------------------------------------------------------------------------
  initial begin
    uvm_config_db #(virtual timer_apb_if)::set(
      null,               // context: null = root
      "uvm_test_top.*",   // target: all components under test top
      "timer_apb_vif",    // key name (must match driver / monitor get() call)
      u_apb_if            // value: the interface instance
    );

    // Start the UVM phase engine.
    // Test name is taken from +UVM_TESTNAME plusarg; falls back to
    // "timer_base_test" if the plusarg is absent.
    run_test("timer_base_test");
  end

  // -------------------------------------------------------------------------
  // Simulation timeout guard
  // -------------------------------------------------------------------------
  initial begin
    #1_000_000;   // 1 ms — should be more than enough for directed tests
    `uvm_fatal("TIMEOUT", "Simulation exceeded 1 ms — possible hang")
  end

endmodule : tb_timer_uvm
