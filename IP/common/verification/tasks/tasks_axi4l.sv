// tasks_axi4l.sv — AXI4-Lite Bus Functional Model task library.
//
// Provides common tasks for driving AXI4-Lite transactions in simulation.
// Intended for reuse across all IP blocks that include an AXI4-Lite interface.
//
// Required signals in the including scope (all logic):
//   clk, rst_n        — clock and active-low reset
//   AWVALID, AWREADY, AWADDR[11:0]
//   WVALID, WREADY, WDATA[31:0], WSTRB[3:0]
//   BVALID, BREADY, BRESP[1:0]
//   ARVALID, ARREADY, ARADDR[11:0]
//   RVALID, RREADY, RDATA[31:0], RRESP[1:0]
//
// Tasks provided:
//   apply_reset  — deassert/assert/deassert reset sequence
//   write_reg    — AW + W + B handshake
//   read_reg     — AR + R handshake
//   assert_eq    — compare two values; $finish(1) on mismatch
//   burst_write  — N consecutive AXI4-Lite writes
//   burst_read   — N consecutive AXI4-Lite reads

// Deviation: tasks defined in a standalone file for `include inside TB modules.

// ---------------------------------------------------------------------------
// apply_reset
// ---------------------------------------------------------------------------
task automatic apply_reset;
  input integer n_cycles;
  integer idx_r;
  begin
    rst_n   <= 1'b0;
    AWVALID <= 1'b0;
    AWADDR  <= 12'h000;
    WVALID  <= 1'b0;
    WDATA   <= 32'h0000_0000;
    WSTRB   <= 4'hF;
    BREADY  <= 1'b1;
    ARVALID <= 1'b0;
    ARADDR  <= 12'h000;
    RREADY  <= 1'b1;
    for (idx_r = 0; idx_r < n_cycles; idx_r = idx_r + 1) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);
  end
endtask

// ---------------------------------------------------------------------------
// write_reg — AXI4-Lite write transaction
// The slave has AWREADY=WREADY=1 always; present AW and W simultaneously.
// ---------------------------------------------------------------------------
task automatic write_reg;
  input  logic [11:0] addr;
  input  logic [31:0] data;
  input  logic [3:0]  strb;
  begin
    // Present AW and W simultaneously
    @(posedge clk);
    AWVALID <= 1'b1;
    AWADDR  <= addr;
    WVALID  <= 1'b1;
    WDATA   <= data;
    WSTRB   <= strb;
    BREADY  <= 1'b1;
    // Both handshakes accepted this cycle (AWREADY=WREADY=1)
    @(posedge clk);
    AWVALID <= 1'b0;
    WVALID  <= 1'b0;
    // Wait for write response
    while (!BVALID) @(posedge clk);
    BREADY <= 1'b1;
    @(posedge clk);
    BREADY <= 1'b0;
  end
endtask

// ---------------------------------------------------------------------------
// read_reg — AXI4-Lite read transaction
// ---------------------------------------------------------------------------
task automatic read_reg;
  input  logic [11:0] addr;
  output logic [31:0] rdata;
  begin
    @(posedge clk);
    ARVALID <= 1'b1;
    ARADDR  <= addr;
    RREADY  <= 1'b1;
    // AR handshake accepted this cycle (ARREADY=1)
    @(posedge clk);
    ARVALID <= 1'b0;
    // Wait for RVALID
    while (!RVALID) @(posedge clk);
    rdata  = RDATA;
    RREADY <= 1'b1;
    @(posedge clk);
    RREADY <= 1'b0;
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
