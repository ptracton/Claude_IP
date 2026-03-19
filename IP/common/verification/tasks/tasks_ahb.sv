// tasks_ahb.sv — AHB-Lite Bus Functional Model task library.
//
// Provides common tasks for driving AHB-Lite transactions in simulation.
// Intended for reuse across all IP blocks that include an AHB-Lite interface.
//
// Required signals in the including scope (all logic):
//   clk, rst_n        — clock and active-low reset
//   HSEL              — AHB slave select
//   HADDR  [11:0]     — AHB byte address
//   HTRANS [1:0]      — AHB transfer type
//   HWRITE            — AHB write enable
//   HWDATA [31:0]     — AHB write data
//   HWSTRB [3:0]      — AHB byte strobes
//   HRDATA [31:0]     — AHB read data (from DUT)
//   HREADY            — AHB ready (from DUT)
//   HRESP             — AHB response (from DUT)
//
// Tasks provided:
//   apply_reset  — deassert/assert/deassert reset sequence
//   write_reg    — single 32-bit AHB write
//   read_reg     — single 32-bit AHB read
//   assert_eq    — compare two values; $finish(1) on mismatch
//   burst_write  — N consecutive AHB writes
//   burst_read   — N consecutive AHB reads
//
// AHB HTRANS values used:
//   2'b00 = IDLE   (no transfer)
//   2'b10 = NONSEQ (new transfer)

// Deviation: tasks defined in a standalone file for `include inside TB modules.

// ---------------------------------------------------------------------------
// apply_reset
// ---------------------------------------------------------------------------
task automatic apply_reset;
  input integer n_cycles;
  integer idx_r;
  begin
    rst_n  <= 1'b0;
    HSEL   <= 1'b0;
    HADDR  <= 12'h000;
    HTRANS <= 2'b00; // IDLE
    HWRITE <= 1'b0;
    HWDATA <= 32'h0000_0000;
    HWSTRB <= 4'hF;
    for (idx_r = 0; idx_r < n_cycles; idx_r = idx_r + 1) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);
  end
endtask

// ---------------------------------------------------------------------------
// write_reg — AHB-Lite write (address phase then data phase)
// ---------------------------------------------------------------------------
task automatic write_reg;
  input  logic [11:0] addr;
  input  logic [31:0] data;
  input  logic [3:0]  strb;
  begin
    // Address phase: present address and control (HTRANS=NONSEQ)
    @(posedge clk);
    HSEL   <= 1'b1;
    HADDR  <= addr;
    HTRANS <= 2'b10; // NONSEQ
    HWRITE <= 1'b1;
    // Data phase: present write data; return to IDLE
    @(posedge clk);
    HWDATA <= data;
    HWSTRB <= strb;
    HTRANS <= 2'b00; // IDLE
    HSEL   <= 1'b0;
    HWRITE <= 1'b0;
    // Wait one extra cycle for the write to complete in the regfile
    @(posedge clk);
  end
endtask

// ---------------------------------------------------------------------------
// read_reg — AHB-Lite read
//
// AHB pipeline:
//   Edge 1: TB presents HADDR/HTRANS=NONSEQ (NBA). DUT sees old signals.
//   Edge 2: DUT samples HTRANS=NONSEQ → dphase_valid_q<=1 (NBA). TB goes IDLE.
//           rd_en is combinational (= dphase_valid_q), still 0 at this edge eval.
//   Edge 3: DUT sees dphase_valid_q=1 → rd_en=1. Regfile clocks rd_data_reg (NBA).
//   Edge 4: rd_data_reg is stable. TB captures HRDATA = rd_data_reg.
// ---------------------------------------------------------------------------
task automatic read_reg;
  input  logic [11:0] addr;
  output logic [31:0] rdata;
  begin
    // Edge 1: present address
    @(posedge clk);
    HSEL   <= 1'b1;
    HADDR  <= addr;
    HTRANS <= 2'b10; // NONSEQ
    HWRITE <= 1'b0;
    // Edge 2: DUT captures address phase; TB returns to IDLE
    @(posedge clk);
    HTRANS <= 2'b00; // IDLE
    HSEL   <= 1'b0;
    // Edge 3: regfile clocks rd_data (rd_en was high from NBA after edge 2)
    @(posedge clk);
    // Edge 4: rd_data_reg now stable; capture it
    @(posedge clk);
    rdata = HRDATA;
  end
endtask

// ---------------------------------------------------------------------------
// assert_eq
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
// burst_write / burst_read — four-word Icarus-compatible versions.
// Icarus Verilog does not support unpacked array subroutine ports.
// ---------------------------------------------------------------------------
task automatic burst_write;
  input logic [11:0] base_addr;
  input logic [31:0] d0, d1, d2, d3;
  begin
    write_reg(base_addr,          d0, 4'hF);
    write_reg(base_addr + 12'h4,  d1, 4'hF);
    write_reg(base_addr + 12'h8,  d2, 4'hF);
    write_reg(base_addr + 12'hC,  d3, 4'hF);
  end
endtask

task automatic burst_read;
  input  logic [11:0] base_addr;
  output logic [31:0] r0, r1, r2, r3;
  begin
    read_reg(base_addr,          r0);
    read_reg(base_addr + 12'h4,  r1);
    read_reg(base_addr + 12'h8,  r2);
    read_reg(base_addr + 12'hC,  r3);
  end
endtask
