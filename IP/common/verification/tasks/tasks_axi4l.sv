// tasks_axi4l.sv — AXI4-Lite Bus Functional Model task library.
//
// Provides common tasks for driving AXI4-Lite transactions in simulation.
// Intended for reuse across all IP blocks that include an AXI4-Lite interface.
//
// Required signals in the including scope (all logic):
//   clk, rst_n         — clock and active-low reset
//   AWVALID, AWREADY   — write address handshake
//   AWADDR [AW-1:0]    — write byte address (AW = `CLAUDE_BFM_ADDR_W, default 12)
//   WVALID, WREADY     — write data handshake
//   WDATA  [31:0]      — write data
//   WSTRB  [3:0]       — write byte strobes
//   BVALID, BREADY     — write response handshake
//   BRESP  [1:0]       — write response (from DUT)
//   ARVALID, ARREADY   — read address handshake
//   ARADDR [AW-1:0]    — read byte address
//   RVALID, RREADY     — read data handshake
//   RDATA  [31:0]      — read data (from DUT)
//   RRESP  [1:0]       — read response (from DUT)
//
// Declared here for the including scope:
//   bfm_err            — 1 if the last write_reg/read_reg got SLVERR/DECERR
//
// Tasks provided:
//   apply_reset  — deassert/assert/deassert reset sequence
//   write_reg    — single AXI4-Lite write (AW + W, then B)
//   read_reg     — single AXI4-Lite read  (AR, then R)
//   assert_eq    — compare two values; $finish(1) on mismatch
//   burst_write  — four consecutive writes
//   burst_read   — four consecutive reads
//
// Timing: every VALID is held until its READY is high at a clock edge, as
// AXI requires; AW and W are presented together and complete independently.
// B/R are taken at the first edge where BVALID/RVALID is high (BREADY/RREADY
// are high while waiting). A transfer that does not complete within
// `CLAUDE_BFM_TIMEOUT cycles fails the simulation.

// Deviation: tasks defined in a standalone file for `include inside TB modules.

`ifndef CLAUDE_BFM_ADDR_W
`define CLAUDE_BFM_ADDR_W 12
`endif
`ifndef CLAUDE_BFM_TIMEOUT
`define CLAUDE_BFM_TIMEOUT 1000
`endif

logic bfm_err; // last transfer ended with SLVERR or DECERR

// ---------------------------------------------------------------------------
// axi_timeout_check
// ---------------------------------------------------------------------------
task automatic axi_timeout_check;
  input integer cycles;
  input string  what;
  begin
    if (cycles > `CLAUDE_BFM_TIMEOUT) begin
      $display("FAIL [tasks_axi4l] timeout waiting for %s", what);
      $finish(1);
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
    AWVALID <= 1'b0;
    AWADDR  <= '0;
    WVALID  <= 1'b0;
    WDATA   <= 32'h0000_0000;
    WSTRB   <= 4'hF;
    BREADY  <= 1'b0;
    ARVALID <= 1'b0;
    ARADDR  <= '0;
    RREADY  <= 1'b0;
    bfm_err  = 1'b0;
    for (idx_r = 0; idx_r < n_cycles; idx_r = idx_r + 1) @(posedge clk);
    rst_n <= 1'b1;
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
  integer cycles;
  logic   aw_pend;
  logic   w_pend;
  begin
    @(posedge clk);
    AWVALID <= 1'b1;
    AWADDR  <= addr;
    WVALID  <= 1'b1;
    WDATA   <= data;
    WSTRB   <= strb;
    BREADY  <= 1'b1;
    aw_pend  = 1'b1;
    w_pend   = 1'b1;
    cycles   = 0;
    // AW and W handshakes, in either order
    while (aw_pend || w_pend) begin
      @(posedge clk);
      cycles = cycles + 1;
      axi_timeout_check(cycles, "AWREADY/WREADY");
      if (aw_pend && AWREADY === 1'b1) begin
        aw_pend  = 1'b0;
        AWVALID <= 1'b0;
      end
      if (w_pend && WREADY === 1'b1) begin
        w_pend  = 1'b0;
        WVALID <= 1'b0;
      end
    end
    // Write response
    @(posedge clk);
    cycles = 1;
    while (BVALID !== 1'b1) begin
      @(posedge clk);
      cycles = cycles + 1;
      axi_timeout_check(cycles, "BVALID");
    end
    bfm_err = BRESP[1];
    BREADY <= 1'b0;
  end
endtask

// ---------------------------------------------------------------------------
// read_reg
// ---------------------------------------------------------------------------
task automatic read_reg;
  input  logic [`CLAUDE_BFM_ADDR_W-1:0] addr;
  output logic [31:0]                   rdata;
  integer cycles;
  begin
    @(posedge clk);
    ARVALID <= 1'b1;
    ARADDR  <= addr;
    RREADY  <= 1'b1;
    // AR handshake
    @(posedge clk);
    cycles = 1;
    while (ARREADY !== 1'b1) begin
      @(posedge clk);
      cycles = cycles + 1;
      axi_timeout_check(cycles, "ARREADY");
    end
    ARVALID <= 1'b0;
    // Read data
    @(posedge clk);
    cycles = 1;
    while (RVALID !== 1'b1) begin
      @(posedge clk);
      cycles = cycles + 1;
      axi_timeout_check(cycles, "RVALID");
    end
    rdata   = RDATA;
    bfm_err = RRESP[1];
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
