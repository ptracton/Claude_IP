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
//   2'b01 = BUSY   (burst pause; only with CLAUDE_BFM_AHB_HSIZE)
//   2'b10 = NONSEQ (new transfer)
//   2'b11 = SEQ    (burst continuation; only with CLAUDE_BFM_AHB_HSIZE)
//
// Optional: define CLAUDE_BFM_AHB_HSIZE before including this file when the
// slave has an HSIZE input (e.g. claude_ahb_mem_if). The including scope must
// then also declare HSIZE [2:0]. write_reg/read_reg drive HSIZE = word, and
// these extra tasks become available:
//   write_sized      single write of 2**size bytes
//   read_sized       single read of 2**size bytes (full HRDATA returned)
//   burst_incr4_write  pipelined INCR4 word write burst (NONSEQ + 3 SEQ),
//                      optionally with one BUSY cycle before the third beat
//   burst_incr4_read   pipelined INCR4 word read burst, same options
// Burst tasks set bfm_err if any beat got an ERROR response. Without the
// define, the file is exactly the single-transfer BFM above.

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
`ifdef CLAUDE_BFM_AHB_HSIZE
    HSIZE   <= 3'b010; // word
`endif
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
`ifdef CLAUDE_BFM_AHB_HSIZE
    HSIZE  <= 3'b010; // word
`endif
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
`ifdef CLAUDE_BFM_AHB_HSIZE
    HSIZE  <= 3'b010; // word
`endif
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

`ifdef CLAUDE_BFM_AHB_HSIZE
// ---------------------------------------------------------------------------
// write_sized / read_sized — single transfer of 2**size bytes. The data is
// given on the full 32-bit bus (byte lanes chosen by the address); read_sized
// returns the full HRDATA word.
// ---------------------------------------------------------------------------
task automatic write_sized;
  input  logic [`CLAUDE_BFM_ADDR_W-1:0] addr;
  input  logic [31:0]                   data;
  input  logic [2:0]                    size;
  input  logic [3:0]                    strb;
  begin
    @(posedge clk);
    HSEL   <= 1'b1;
    HADDR  <= addr;
    HTRANS <= 2'b10; // NONSEQ
    HWRITE <= 1'b1;
    HSIZE  <= size;
    ahb_wait_ready("sized write address phase");
    HWDATA <= data;
    HWSTRB <= strb;
    HTRANS <= 2'b00; // IDLE
    HSEL   <= 1'b0;
    HWRITE <= 1'b0;
    HSIZE  <= 3'b010;
    ahb_wait_ready("sized write data phase");
    bfm_err = HRESP;
  end
endtask

task automatic read_sized;
  input  logic [`CLAUDE_BFM_ADDR_W-1:0] addr;
  input  logic [2:0]                    size;
  output logic [31:0]                   rdata;
  begin
    @(posedge clk);
    HSEL   <= 1'b1;
    HADDR  <= addr;
    HTRANS <= 2'b10; // NONSEQ
    HWRITE <= 1'b0;
    HSIZE  <= size;
    ahb_wait_ready("sized read address phase");
    HTRANS <= 2'b00; // IDLE
    HSEL   <= 1'b0;
    HSIZE  <= 3'b010;
    ahb_wait_ready("sized read data phase");
    rdata   = HRDATA;
    bfm_err = HRESP;
  end
endtask

// ---------------------------------------------------------------------------
// burst_incr4_write / burst_incr4_read — pipelined INCR4 word bursts: the
// address phase of beat n overlaps the data phase of beat n-1. With
// insert_busy = 1, one BUSY cycle is issued before the third beat (after the
// second beat's data phase completes).
// ---------------------------------------------------------------------------
task automatic burst_incr4_write;
  input logic [`CLAUDE_BFM_ADDR_W-1:0] base_addr;
  input logic [31:0]                   d0, d1, d2, d3;
  input logic                          insert_busy;
  integer beat;
  logic   err_any;
  begin
    err_any = 1'b0;
    @(posedge clk);
    HSEL   <= 1'b1;
    HADDR  <= base_addr;
    HTRANS <= 2'b10; // NONSEQ
    HWRITE <= 1'b1;
    HSIZE  <= 3'b010;
    ahb_wait_ready("burst write beat 0 address");
    for (beat = 1; beat < 4; beat = beat + 1) begin
      // Data for the previous beat.
      case (beat)
        1:       HWDATA <= d0;
        2:       HWDATA <= d1;
        default: HWDATA <= d2;
      endcase
      HWSTRB <= 4'hF;
      HADDR  <= base_addr + (beat * 4);
      if (insert_busy && beat == 2) begin
        HTRANS <= 2'b01; // BUSY: ends the previous data phase, no transfer
        ahb_wait_ready("burst write BUSY");
        err_any = err_any | HRESP;
      end
      HTRANS <= 2'b11; // SEQ
      ahb_wait_ready("burst write beat address");
      err_any = err_any | HRESP;
    end
    HWDATA <= d3;
    HTRANS <= 2'b00; // IDLE
    HSEL   <= 1'b0;
    HWRITE <= 1'b0;
    ahb_wait_ready("burst write last data phase");
    err_any = err_any | HRESP;
    bfm_err = err_any;
  end
endtask

task automatic burst_incr4_read;
  input  logic [`CLAUDE_BFM_ADDR_W-1:0] base_addr;
  input  logic                          insert_busy;
  output logic [31:0]                   r0, r1, r2, r3;
  integer beat;
  logic   err_any;
  begin
    err_any = 1'b0;
    @(posedge clk);
    HSEL   <= 1'b1;
    HADDR  <= base_addr;
    HTRANS <= 2'b10; // NONSEQ
    HWRITE <= 1'b0;
    HSIZE  <= 3'b010;
    ahb_wait_ready("burst read beat 0 address");
    for (beat = 1; beat < 4; beat = beat + 1) begin
      HADDR <= base_addr + (beat * 4);
      if (insert_busy && beat == 2) begin
        HTRANS <= 2'b01; // BUSY: ends the previous data phase, no transfer
        ahb_wait_ready("burst read BUSY");
        r1      = HRDATA;
        err_any = err_any | HRESP;
        HTRANS <= 2'b11; // SEQ
        ahb_wait_ready("burst read beat address");
      end else begin
        HTRANS <= 2'b11; // SEQ
        ahb_wait_ready("burst read beat address");
        case (beat)
          1:       r0 = HRDATA;
          2:       r1 = HRDATA;
          default: r2 = HRDATA;
        endcase
        err_any = err_any | HRESP;
      end
    end
    HTRANS <= 2'b00; // IDLE
    HSEL   <= 1'b0;
    ahb_wait_ready("burst read last data phase");
    r3      = HRDATA;
    err_any = err_any | HRESP;
    bfm_err = err_any;
  end
endtask
`endif
