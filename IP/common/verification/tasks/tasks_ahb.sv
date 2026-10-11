// tasks_ahb.sv — AHB-Lite Bus Functional Model task library.
//
// Provides common tasks for driving AHB-Lite transactions in simulation.
// Intended for reuse across all IP blocks that include an AHB-Lite interface.
//
// Required signals in the including scope (all logic):
//   clk, rst_n        — clock and active-low reset
//   HSEL              — AHB slave select
//   HADDR  [AW-1:0]   — AHB byte address (AW = `CLAUDE_BFM_ADDR_W, default 12)
//   HTRANS [1:0]      — AHB transfer type
//   HWRITE            — AHB write enable
//   HWDATA [31:0]     — AHB write data
//   HWSTRB [3:0]      — AHB byte strobes
//   HRDATA [31:0]     — AHB read data (from DUT)
//   HREADY            — AHB ready (from DUT)
//   HRESP             — AHB response (from DUT)
//
// Declared here for the including scope:
//   bfm_err           — 1 if the last write_reg/read_reg got an ERROR response
//
// Tasks provided:
//   apply_reset  — deassert/assert/deassert reset sequence
//   write_reg    — single 32-bit AHB write
//   read_reg     — single 32-bit AHB read
//   assert_eq    — compare two values; $finish(1) on mismatch
//   burst_write  — N consecutive AHB writes
//   burst_read   — N consecutive AHB reads
//
// Timing: both phases wait for HREADY, so any number of slave wait states
// (and the two-cycle ERROR response) is handled. HREADY/HRESP/HRDATA are
// sampled at the clock edge that ends a phase. A transfer that does not
// complete within `CLAUDE_BFM_TIMEOUT cycles fails the simulation.
//
// AHB HTRANS values used:
//   2'b00 = IDLE   (no transfer)
//   2'b10 = NONSEQ (new transfer)

// Deviation: tasks defined in a standalone file for `include inside TB modules.

`ifndef CLAUDE_BFM_ADDR_W
`define CLAUDE_BFM_ADDR_W 12
`endif
`ifndef CLAUDE_BFM_TIMEOUT
`define CLAUDE_BFM_TIMEOUT 1000
`endif

logic bfm_err; // last transfer ended with an ERROR response

// ---------------------------------------------------------------------------
// ahb_wait_ready — advance to the next clock edge at which HREADY is high
// ---------------------------------------------------------------------------
task automatic ahb_wait_ready;
  input string what;
  integer cycles;
  begin
    @(posedge clk);
    cycles = 1;
    while (HREADY !== 1'b1) begin
      @(posedge clk);
      cycles = cycles + 1;
      if (cycles > `CLAUDE_BFM_TIMEOUT) begin
        $display("FAIL [tasks_ahb] timeout waiting for HREADY (%s)", what);
        $finish(1);
      end
    end
  end
endtask

// ---------------------------------------------------------------------------
// apply_reset
// ---------------------------------------------------------------------------
task automatic apply_reset;
  input integer n_cycles;
  integer idx_r;
  begin
    rst_n   <= 1'b0;
    HSEL    <= 1'b0;
    HADDR   <= '0;
    HTRANS  <= 2'b00; // IDLE
    HWRITE  <= 1'b0;
    HWDATA  <= 32'h0000_0000;
    HWSTRB  <= 4'hF;
    bfm_err  = 1'b0;
    for (idx_r = 0; idx_r < n_cycles; idx_r = idx_r + 1) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);
  end
endtask

// ---------------------------------------------------------------------------
// write_reg — AHB-Lite write (address phase then data phase)
// ---------------------------------------------------------------------------
task automatic write_reg;
  input  logic [`CLAUDE_BFM_ADDR_W-1:0] addr;
  input  logic [31:0]                   data;
  input  logic [3:0]                    strb;
  begin
    // Address phase: present address and control (HTRANS=NONSEQ)
    @(posedge clk);
    HSEL   <= 1'b1;
    HADDR  <= addr;
    HTRANS <= 2'b10; // NONSEQ
    HWRITE <= 1'b1;
    ahb_wait_ready("write address phase");
    // Data phase: present write data; return to IDLE
    HWDATA <= data;
    HWSTRB <= strb;
    HTRANS <= 2'b00; // IDLE
    HSEL   <= 1'b0;
    HWRITE <= 1'b0;
    ahb_wait_ready("write data phase");
    bfm_err = HRESP;
  end
endtask

// ---------------------------------------------------------------------------
// read_reg — AHB-Lite read
//
// Address phase until HREADY, then data phase until HREADY; HRDATA is
// captured at the edge that ends the data phase. Against claude_ahb_if
// (one read wait state) this is four edges from the start of the task.
// ---------------------------------------------------------------------------
task automatic read_reg;
  input  logic [`CLAUDE_BFM_ADDR_W-1:0] addr;
  output logic [31:0]                   rdata;
  begin
    @(posedge clk);
    HSEL   <= 1'b1;
    HADDR  <= addr;
    HTRANS <= 2'b10; // NONSEQ
    HWRITE <= 1'b0;
    ahb_wait_ready("read address phase");
    HTRANS <= 2'b00; // IDLE
    HSEL   <= 1'b0;
    ahb_wait_ready("read data phase");
    rdata   = HRDATA;
    bfm_err = HRESP;
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
  input logic [`CLAUDE_BFM_ADDR_W-1:0] base_addr;
  input logic [31:0] d0, d1, d2, d3;
  begin
    write_reg(base_addr,      d0, 4'hF);
    write_reg(base_addr + 4,  d1, 4'hF);
    write_reg(base_addr + 8,  d2, 4'hF);
    write_reg(base_addr + 12, d3, 4'hF);
  end
endtask

task automatic burst_read;
  input  logic [`CLAUDE_BFM_ADDR_W-1:0] base_addr;
  output logic [31:0] r0, r1, r2, r3;
  begin
    read_reg(base_addr,      r0);
    read_reg(base_addr + 4,  r1);
    read_reg(base_addr + 8,  r2);
    read_reg(base_addr + 12, r3);
  end
endtask
