// tasks_apb.sv — APB4 Bus Functional Model task library.
//
// Provides common tasks for driving APB4 transactions in simulation.
// Intended for reuse across all IP blocks that include an APB4 interface.
//
// Usage: `include this file inside the testbench module that declares the
// matching APB4 signal variables listed in the port list below.
//
// Required signals in the including scope (all logic):
//   clk, rst_n       — clock and active-low reset
//   PSEL             — APB slave select
//   PENABLE          — APB enable
//   PADDR [11:0]     — APB byte address
//   PWRITE           — APB write enable
//   PWDATA [31:0]    — APB write data
//   PSTRB  [3:0]     — APB byte strobes
//   PRDATA [31:0]    — APB read data (from DUT)
//   PREADY           — APB ready (from DUT)
//   PSLVERR          — APB slave error (from DUT)
//
// Tasks provided:
//   apply_reset       — deassert/assert/deassert reset sequence
//   write_reg         — single 32-bit APB write
//   read_reg          — single 32-bit APB read, returns data in rdata output
//   assert_eq         — compare two 32-bit values, $finish(1) on mismatch
//   burst_write       — N consecutive APB writes without idle cycles
//   burst_read        — N consecutive APB reads without idle cycles

// Deviation: tasks are defined in a standalone file without a module wrapper
// so they can be `included inside a testbench module.  This avoids the
// SV interface/modport constructs prohibited by the project coding standard.

// ---------------------------------------------------------------------------
// apply_reset — assert synchronous active-low reset for N cycles
// ---------------------------------------------------------------------------
task automatic apply_reset;
  input integer n_cycles;
  integer idx_r;
  begin
    rst_n  <= 1'b0;
    PSEL   <= 1'b0;
    PENABLE<= 1'b0;
    PWRITE <= 1'b0;
    PADDR  <= 12'h000;
    PWDATA <= 32'h0000_0000;
    PSTRB  <= 4'hF;
    for (idx_r = 0; idx_r < n_cycles; idx_r = idx_r + 1) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);
  end
endtask

// ---------------------------------------------------------------------------
// write_reg — perform a single APB4 write transaction
// ---------------------------------------------------------------------------
task automatic write_reg;
  input  logic [11:0] addr;
  input  logic [31:0] data;
  input  logic [3:0]  strb;
  begin
    // SETUP phase (PSEL=1, PENABLE=0)
    @(posedge clk);
    PSEL   <= 1'b1;
    PENABLE<= 1'b0;
    PADDR  <= addr;
    PWRITE <= 1'b1;
    PWDATA <= data;
    PSTRB  <= strb;
    // ACCESS phase (PSEL=1, PENABLE=1): wr_en fires here
    @(posedge clk);
    PENABLE <= 1'b1;
    // Completion cycle
    @(posedge clk);
    // Deassert
    PSEL    <= 1'b0;
    PENABLE <= 1'b0;
    PWRITE  <= 1'b0;
  end
endtask

// ---------------------------------------------------------------------------
// read_reg — perform a single APB4 read transaction
// ---------------------------------------------------------------------------
task automatic read_reg;
  input  logic [11:0] addr;
  output logic [31:0] rdata;
  begin
    // SETUP phase: rd_en fires (PSEL & ~PENABLE & ~PWRITE in apb_if)
    @(posedge clk);
    PSEL    <= 1'b1;
    PENABLE <= 1'b0;
    PADDR   <= addr;
    PWRITE  <= 1'b0;
    PSTRB   <= 4'hF;
    // ACCESS phase: regfile has clocked rd_data from prior rd_en
    @(posedge clk);
    PENABLE <= 1'b1;
    // Capture PRDATA = rd_data (registered in regfile, valid after ACCESS posedge)
    @(posedge clk);
    rdata   = PRDATA;
    // Deassert
    PSEL    <= 1'b0;
    PENABLE <= 1'b0;
  end
endtask

// ---------------------------------------------------------------------------
// assert_eq — compare two 32-bit values; call $finish(1) on mismatch
// ---------------------------------------------------------------------------
task automatic assert_eq;
  input logic [31:0] actual;
  input logic [31:0] expected;
  input string       msg;
  begin
    if (actual !== expected) begin
      $display("FAIL [assert_eq] %s : got 0x%08h, expected 0x%08h",
               msg, actual, expected);
      $finish(1);
    end
  end
endtask

// ---------------------------------------------------------------------------
// burst_write / burst_read — intentionally not implemented with unpacked array
// parameters because Icarus Verilog does not support subroutine ports with
// unpacked dimensions.  Directed tests use sequential write_reg / read_reg
// calls instead.  Provide empty stubs so the file compiles everywhere.
// ---------------------------------------------------------------------------
task automatic burst_write;
  input logic [11:0] base_addr;
  input logic [31:0] d0, d1, d2, d3; // four fixed-word version (Icarus-safe)
  begin
    write_reg(base_addr,          d0, 4'hF);
    write_reg(base_addr + 12'h4,  d1, 4'hF);
    write_reg(base_addr + 12'h8,  d2, 4'hF);
    write_reg(base_addr + 12'hC,  d3, 4'hF);
  end
endtask

task automatic burst_read;
  input  logic [11:0] base_addr;
  output logic [31:0] r0, r1, r2, r3; // four fixed-word version (Icarus-safe)
  begin
    read_reg(base_addr,          r0);
    read_reg(base_addr + 12'h4,  r1);
    read_reg(base_addr + 12'h8,  r2);
    read_reg(base_addr + 12'hC,  r3);
  end
endtask
