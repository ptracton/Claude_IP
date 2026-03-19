// tasks_wb.sv — Wishbone B4 Bus Functional Model task library.
//
// Provides common tasks for driving Wishbone B4 transactions in simulation.
// Intended for reuse across all IP blocks that include a Wishbone B4 interface.
//
// Required signals in the including scope (all logic):
//   clk             — clock
//   RST_I           — synchronous active-high Wishbone reset
//   CYC_I, STB_I    — bus cycle valid, strobe
//   WE_I            — write enable
//   ADR_I  [11:0]   — byte address
//   DAT_I  [31:0]   — write data
//   SEL_I  [3:0]    — byte selects
//   DAT_O  [31:0]   — read data (from DUT)
//   ACK_O           — acknowledge (from DUT)
//   ERR_O           — error (from DUT)
//
// Note: Wishbone uses active-high synchronous RST_I (not active-low rst_n).
//
// Tasks provided:
//   apply_reset  — assert/deassert RST_I
//   write_reg    — single 32-bit Wishbone write
//   read_reg     — single 32-bit Wishbone read
//   assert_eq    — compare two values; $finish(1) on mismatch
//   burst_write  — N consecutive Wishbone writes
//   burst_read   — N consecutive Wishbone reads

// Deviation: tasks defined in a standalone file for `include inside TB modules.

// ---------------------------------------------------------------------------
// apply_reset
// ---------------------------------------------------------------------------
task automatic apply_reset;
  input integer n_cycles;
  integer idx_r;
  begin
    RST_I <= 1'b1;
    CYC_I <= 1'b0;
    STB_I <= 1'b0;
    WE_I  <= 1'b0;
    ADR_I <= 12'h000;
    DAT_I <= 32'h0000_0000;
    SEL_I <= 4'hF;
    for (idx_r = 0; idx_r < n_cycles; idx_r = idx_r + 1) @(posedge clk);
    RST_I <= 1'b0;
    @(posedge clk);
  end
endtask

// ---------------------------------------------------------------------------
// write_reg — single Wishbone write
// ACK_O arrives one cycle after the first STB_I (registered in wb_if).
// ---------------------------------------------------------------------------
task automatic write_reg;
  input  logic [11:0] addr;
  input  logic [31:0] data;
  input  logic [3:0]  strb;
  begin
    @(posedge clk);
    CYC_I <= 1'b1;
    STB_I <= 1'b1;
    WE_I  <= 1'b1;
    ADR_I <= addr;
    DAT_I <= data;
    SEL_I <= strb;
    // wr_en fires this cycle (CYC & STB & WE & ~stb_prev)
    // ACK_O arrives next posedge
    @(posedge clk);
    while (!ACK_O) @(posedge clk);
    CYC_I <= 1'b0;
    STB_I <= 1'b0;
    WE_I  <= 1'b0;
    @(posedge clk);
  end
endtask

// ---------------------------------------------------------------------------
// read_reg — single Wishbone read
// ---------------------------------------------------------------------------
task automatic read_reg;
  input  logic [11:0] addr;
  output logic [31:0] rdata;
  begin
    @(posedge clk);
    CYC_I <= 1'b1;
    STB_I <= 1'b1;
    WE_I  <= 1'b0;
    ADR_I <= addr;
    SEL_I <= 4'hF;
    // rd_en fires this cycle; regfile clocks rd_data next posedge
    // ACK_O also arrives next posedge; DAT_O = rd_data (combinational)
    @(posedge clk);
    while (!ACK_O) @(posedge clk);
    rdata  = DAT_O;
    CYC_I <= 1'b0;
    STB_I <= 1'b0;
    @(posedge clk);
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
