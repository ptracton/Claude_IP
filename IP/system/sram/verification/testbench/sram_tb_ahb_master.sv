// sram_tb_ahb_master.sv — Pipelined AHB-Lite master BFM of any data width.
//
// Used by tb_sram_ahb.sv, one instance per master port. The shared
// IP/common tasks_ahb.sv is fixed at 32 bits, so this BFM is separate.
//
// A transaction is a list of beats loaded into the beat arrays (bt_*), then
// run with run_beats(n). Every beat has its own direction, address, size,
// HTRANS (NONSEQ or SEQ), HBURST and a number of BUSY cycles issued before
// it. Beats are fully pipelined: the address phase of beat i overlaps the
// data phase of beat i-1, so INCR/WRAP bursts and back-to-back singles both
// run at the slave's best rate. A beat that gets an ERROR response does not
// stop the sequence (AHB lets the master continue a burst).
//
// After run_beats(n): bt_rdata[i] / bt_err[i] hold beat i's response,
// last_cycles the clock edges from the first address phase to the end of
// the last data phase, and last_wait the cycles with HREADY low.
//
// Helpers (sram_tb_master_common.svh, shared with the other protocols'
// BFMs) build the common cases: single (one transfer of 2**size bytes) and
// burst (INCR4/8/16, WRAP4/8/16 or undefined-length INCR, with an optional
// BUSY cycle before chosen beats). Signals are driven with
// nonblocking assignments after a rising edge and sampled at the edge.

`timescale 1ns / 1ps

module sram_tb_ahb_master #(
  parameter int unsigned DW     = 32,      // data width
  parameter int unsigned AW     = 32,      // address width
  parameter int unsigned MAXB   = 64,      // longest beat list
  parameter int unsigned TMO    = 50000    // cycles before a stuck transfer fails
) (
  input  logic          HCLK,
  output logic          HSEL,
  output logic [AW-1:0] HADDR,
  output logic [1:0]    HTRANS,
  output logic          HWRITE,
  output logic [2:0]    HSIZE,
  output logic [2:0]    HBURST,
  output logic [DW-1:0] HWDATA,
  output logic [DW/8-1:0] HWSTRB,
  input  logic          HREADY,
  input  logic [DW-1:0] HRDATA,
  input  logic          HRESP
);

  `include "sram_tb_master_common.svh"

  initial begin
    HSEL   = 1'b0;
    HADDR  = '0;
    HTRANS = IDLE;
    HWRITE = 1'b0;
    HSIZE  = 3'd0;
    HBURST = B_SINGLE;
    HWDATA = '0;
    HWSTRB = '0;
  end

  // ---------------------------------------------------------------------------
  // run_beats — issue beats 0..n-1 pipelined and collect their responses.
  // ---------------------------------------------------------------------------
  task automatic run_beats(input int unsigned n);
    int unsigned nxt;       // next beat to put in an address phase
    int          apb;       // beat in the address phase (-1: none / BUSY)
    int          dpb;       // beat in the data phase (-1: none)
    int unsigned busy_left; // BUSY cycles still to issue before beat nxt
    int unsigned cyc;

    nxt         = 0;
    dpb         = -1;
    last_cycles = 0;
    last_wait   = 0;
    busy_left   = 0;
    cyc         = 0;
    @(posedge HCLK);
    // First address phase (BUSY cycles before beat 0 are not allowed).
    present(0);
    apb = 0;
    nxt = 1;
    if (n > 1) busy_left = bt_busy[1];
    forever begin
      @(posedge HCLK);
      last_cycles++;
      cyc++;
      if (cyc > TMO) begin
        $display("FAIL [%m] transfer stuck (HREADY low for %0d cycles) at %0t", TMO, $time);
        $finish(1);
      end
      if (HREADY !== 1'b1) begin
        last_wait++;
        continue;
      end
      cyc = 0;
      // The data phase in progress (if any) ends at this edge.
      if (dpb >= 0) begin
        bt_rdata[dpb] = HRDATA;
        bt_err[dpb]   = (HRESP === 1'b1);
      end
      // The address phase presented (if a transfer) becomes the data phase.
      dpb = apb;
      if (dpb >= 0) begin
        HWDATA <= bt_we[dpb] ? bt_wdata[dpb] : '0;
        HWSTRB <= bt_we[dpb] ? bt_strb[dpb]  : '0;
      end
      // Next address phase.
      if (nxt < n && busy_left > 0) begin
        busy_left--;
        HSEL   <= 1'b1;
        HADDR  <= bt_addr[nxt];
        HWRITE <= bt_we[nxt];
        HSIZE  <= bt_size[nxt];
        HBURST <= bt_burst[nxt];
        HTRANS <= BUSY;
        apb = -1;
      end else if (nxt < n) begin
        present(nxt);
        apb = nxt;
        nxt++;
        if (nxt < n) busy_left = bt_busy[nxt];
      end else begin
        HSEL   <= 1'b0;
        HTRANS <= IDLE;
        HWRITE <= 1'b0;
        HBURST <= B_SINGLE;
        apb = -1;
        if (dpb < 0) break;
      end
    end
  endtask

  task automatic present(input int unsigned i);
    HSEL   <= 1'b1;
    HADDR  <= bt_addr[i];
    HWRITE <= bt_we[i];
    HSIZE  <= bt_size[i];
    HBURST <= bt_burst[i];
    HTRANS <= bt_trans[i];
  endtask

endmodule : sram_tb_ahb_master
