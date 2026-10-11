// tasks_apb.sv — APB4 Bus Functional Model task library.
//
// Provides common tasks for driving APB4 transactions in simulation.
// Intended for reuse across all IP blocks that include an APB4 interface.
//
// Required signals in the including scope (all logic):
//   clk, rst_n        — clock and active-low reset
//   PSEL              — APB select
//   PENABLE           — APB enable (ACCESS phase)
//   PADDR  [AW-1:0]   — APB byte address (AW = `CLAUDE_BFM_ADDR_W, default 12)
//   PWRITE            — APB write enable
//   PWDATA [31:0]     — APB write data
//   PSTRB  [3:0]      — APB byte strobes
//   PRDATA [31:0]     — APB read data (from DUT)
//   PREADY            — APB ready (from DUT)
//   PSLVERR           — APB slave error (from DUT)
//
// Declared here for the including scope:
//   bfm_err           — 1 if the last write_reg/read_reg got PSLVERR
//
// Tasks provided:
//   apply_reset  — deassert/assert/deassert reset sequence
//   write_reg    — single 32-bit APB write (SETUP + ACCESS)
//   read_reg     — single 32-bit APB read  (SETUP + ACCESS)
//   assert_eq    — compare two values; $finish(1) on mismatch
//   burst_write  — four consecutive APB writes
//   burst_read   — four consecutive APB reads
//
// Timing: one SETUP cycle, then ACCESS until PREADY is high at a clock edge
// (PRDATA/PSLVERR are sampled at that edge). Against a zero-wait slave the
// transfer takes the two cycles the APB4 spec requires. PSTRB is driven to 0
// on reads, as APB4 requires. A transfer that does not complete within
// `CLAUDE_BFM_TIMEOUT cycles fails the simulation.

// Deviation: tasks defined in a standalone file for `include inside TB modules.

`ifndef CLAUDE_BFM_ADDR_W
`define CLAUDE_BFM_ADDR_W 12
`endif
`ifndef CLAUDE_BFM_TIMEOUT
`define CLAUDE_BFM_TIMEOUT 1000
`endif

logic bfm_err; // last transfer ended with PSLVERR

// ---------------------------------------------------------------------------
// apb_wait_ready — advance to the next clock edge at which PREADY is high
// ---------------------------------------------------------------------------
task automatic apb_wait_ready;
  integer cycles;
  begin
    @(posedge clk);
    cycles = 1;
    while (PREADY !== 1'b1) begin
      @(posedge clk);
      cycles = cycles + 1;
      if (cycles > `CLAUDE_BFM_TIMEOUT) begin
        $display("FAIL [tasks_apb] timeout waiting for PREADY");
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
    PSEL    <= 1'b0;
    PENABLE <= 1'b0;
    PWRITE  <= 1'b0;
    PADDR   <= '0;
    PWDATA  <= 32'h0000_0000;
    PSTRB   <= 4'h0;
    bfm_err  = 1'b0;
    for (idx_r = 0; idx_r < n_cycles; idx_r = idx_r + 1) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);
  end
endtask

// ---------------------------------------------------------------------------
// write_reg — APB4 write
// ---------------------------------------------------------------------------
task automatic write_reg;
  input  logic [`CLAUDE_BFM_ADDR_W-1:0] addr;
  input  logic [31:0]                   data;
  input  logic [3:0]                    strb;
  begin
    // SETUP
    @(posedge clk);
    PSEL    <= 1'b1;
    PENABLE <= 1'b0;
    PADDR   <= addr;
    PWRITE  <= 1'b1;
    PWDATA  <= data;
    PSTRB   <= strb;
    // ACCESS
    @(posedge clk);
    PENABLE <= 1'b1;
    apb_wait_ready();
    bfm_err  = PSLVERR;
    PSEL    <= 1'b0;
    PENABLE <= 1'b0;
    PWRITE  <= 1'b0;
    PSTRB   <= 4'h0;
  end
endtask

// ---------------------------------------------------------------------------
// read_reg — APB4 read
// ---------------------------------------------------------------------------
task automatic read_reg;
  input  logic [`CLAUDE_BFM_ADDR_W-1:0] addr;
  output logic [31:0]                   rdata;
  begin
    // SETUP
    @(posedge clk);
    PSEL    <= 1'b1;
    PENABLE <= 1'b0;
    PADDR   <= addr;
    PWRITE  <= 1'b0;
    PSTRB   <= 4'h0;
    // ACCESS
    @(posedge clk);
    PENABLE <= 1'b1;
    apb_wait_ready();
    rdata    = PRDATA;
    bfm_err  = PSLVERR;
    PSEL    <= 1'b0;
    PENABLE <= 1'b0;
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
