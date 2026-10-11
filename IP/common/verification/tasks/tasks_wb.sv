// tasks_wb.sv — Wishbone B4 Bus Functional Model task library.
//
// Provides common tasks for driving Wishbone B4 classic single-cycle
// transactions in simulation. Intended for reuse across all IP blocks that
// include a Wishbone B4 interface.
//
// Required signals in the including scope (all logic):
//   clk               — clock
//   RST_I             — active-high synchronous reset
//   CYC_I, STB_I      — bus cycle / strobe (to DUT)
//   WE_I              — write enable (to DUT)
//   ADR_I  [AW-1:0]   — byte address (AW = `CLAUDE_BFM_ADDR_W, default 12)
//   DAT_I  [31:0]     — write data (to DUT)
//   SEL_I  [3:0]      — byte selects (to DUT)
//   DAT_O  [31:0]     — read data (from DUT)
//   ACK_O             — acknowledge (from DUT)
//   ERR_O             — error (from DUT)
//
// Declared here for the including scope:
//   bfm_err           — 1 if the last write_reg/read_reg ended with ERR_O
//
// Tasks provided:
//   apply_reset  — assert/deassert reset sequence
//   write_reg    — single classic write
//   read_reg     — single classic read
//   assert_eq    — compare two values; $finish(1) on mismatch
//   burst_write  — four consecutive writes
//   burst_read   — four consecutive reads
//
// Timing: CYC/STB are held until ACK_O or ERR_O is high at a clock edge;
// DAT_O is sampled at that edge. One idle cycle follows every transfer. A
// transfer that does not terminate within `CLAUDE_BFM_TIMEOUT cycles fails
// the simulation.

// Deviation: tasks defined in a standalone file for `include inside TB modules.

`ifndef CLAUDE_BFM_ADDR_W
`define CLAUDE_BFM_ADDR_W 12
`endif
`ifndef CLAUDE_BFM_TIMEOUT
`define CLAUDE_BFM_TIMEOUT 1000
`endif

logic bfm_err; // last transfer ended with ERR_O

// ---------------------------------------------------------------------------
// wb_wait_term — advance to the next clock edge at which ACK_O or ERR_O is high
// ---------------------------------------------------------------------------
task automatic wb_wait_term;
  integer cycles;
  begin
    @(posedge clk);
    cycles = 1;
    while (ACK_O !== 1'b1 && ERR_O !== 1'b1) begin
      @(posedge clk);
      cycles = cycles + 1;
      if (cycles > `CLAUDE_BFM_TIMEOUT) begin
        $display("FAIL [tasks_wb] timeout waiting for ACK_O/ERR_O");
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
    RST_I  <= 1'b1;
    CYC_I  <= 1'b0;
    STB_I  <= 1'b0;
    WE_I   <= 1'b0;
    ADR_I  <= '0;
    DAT_I  <= 32'h0000_0000;
    SEL_I  <= 4'hF;
    bfm_err = 1'b0;
    for (idx_r = 0; idx_r < n_cycles; idx_r = idx_r + 1) @(posedge clk);
    RST_I <= 1'b0;
    @(posedge clk);
  end
endtask

// ---------------------------------------------------------------------------
// write_reg
// ---------------------------------------------------------------------------
task automatic write_reg;
  input  logic [`CLAUDE_BFM_ADDR_W-1:0] addr;
  input  logic [31:0]                   data;
  input  logic [3:0]                    strb;
  begin
    @(posedge clk);
    CYC_I <= 1'b1;
    STB_I <= 1'b1;
    WE_I  <= 1'b1;
    ADR_I <= addr;
    DAT_I <= data;
    SEL_I <= strb;
    wb_wait_term();
    bfm_err = ERR_O;
    CYC_I <= 1'b0;
    STB_I <= 1'b0;
    WE_I  <= 1'b0;
    @(posedge clk);
  end
endtask

// ---------------------------------------------------------------------------
// read_reg
// ---------------------------------------------------------------------------
task automatic read_reg;
  input  logic [`CLAUDE_BFM_ADDR_W-1:0] addr;
  output logic [31:0]                   rdata;
  begin
    @(posedge clk);
    CYC_I <= 1'b1;
    STB_I <= 1'b1;
    WE_I  <= 1'b0;
    ADR_I <= addr;
    SEL_I <= 4'hF;
    wb_wait_term();
    rdata   = DAT_O;
    bfm_err = ERR_O;
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
