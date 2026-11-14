// sram_tb_axi4l_master.sv — AXI4-Lite master BFM of any data width.
//
// Used by tb_sram_axi4l.sv, one instance per master port. Same task API as
// sram_tb_ahb_master.sv (beat list in sram_tb_master_common.svh): load beats,
// run_beats(n), read bt_rdata / bt_err / last_cycles / last_wait.
// One transaction at a time: a write raises AWVALID and WVALID together
// (each drops on its own handshake) and ends with the B response; a read
// raises ARVALID and ends with the R beat. BREADY / RREADY are always high.
// AXI4-Lite has no size signal: a write's WSTRB is the beat's strobes ANDed
// with the lanes of its size at its address; reads return the whole word.
// Any response other than OKAY is an error. The BUSY count of a beat becomes
// idle cycles before it.
//
// Pipelined mode (set_pipelined(1)): beats are issued in list order, one per
// cycle at most, without waiting for earlier responses. A write's AW/W wait
// only for the previous AW/W handshakes and a read's AR for the previous AR
// handshake, so reads and writes overlap and each channel can hold its next
// request while the slave works on the current one. Like a real AXI master,
// the BFM keeps program order between a read and a write of the same word:
// a beat waits while a transaction of the other direction to its word is
// in flight. B and R responses come in order per channel. last_cycles counts
// from the first beat to the last response; last_wait counts the cycles in
// which no response arrived.

`timescale 1ns / 1ps

module sram_tb_axi4l_master #(
  parameter int unsigned DW   = 32,      // data width
  parameter int unsigned AW   = 32,      // address width
  parameter int unsigned MAXB = 64,      // longest beat list
  parameter int unsigned TMO    = 50000    // cycles before a stuck transfer fails
) (
  input  logic            ACLK,
  output logic            AWVALID,
  input  logic            AWREADY,
  output logic [AW-1:0]   AWADDR,
  output logic            WVALID,
  input  logic            WREADY,
  output logic [DW-1:0]   WDATA,
  output logic [DW/8-1:0] WSTRB,
  input  logic            BVALID,
  output logic            BREADY,
  input  logic [1:0]      BRESP,
  output logic            ARVALID,
  input  logic            ARREADY,
  output logic [AW-1:0]   ARADDR,
  input  logic            RVALID,
  output logic            RREADY,
  input  logic [DW-1:0]   RDATA,
  input  logic [1:0]      RRESP
);

  `include "sram_tb_master_common.svh"

  initial begin
    AWVALID = 1'b0;
    AWADDR  = '0;
    WVALID  = 1'b0;
    WDATA   = '0;
    WSTRB   = '0;
    BREADY  = 1'b1;
    ARVALID = 1'b0;
    ARADDR  = '0;
    RREADY  = 1'b1;
  end

  task automatic run_beats(input int unsigned n);
    bit          aw_done, w_done, ar_done;
    int unsigned w;
    logic        awr, wr, bv, arr, rv;  // inputs sampled at the edge
    logic [1:0]  br, rr;
    logic [DW-1:0] rd;
    if (pipelined) begin
      run_beats_pipelined(n);
      return;
    end
    last_cycles = 0;
    last_wait   = 0;
    @(posedge ACLK);
    `TB_DRV;
    for (int unsigned i = 0; i < n; i++) begin
      repeat (bt_busy[i]) begin
        @(posedge ACLK);
        last_cycles++;
      end
      if (bt_busy[i] > 0) `TB_DRV;
      w = 0;
      if (bt_we[i]) begin
        AWVALID <= 1'b1;
        AWADDR  <= bt_addr[i];
        WVALID  <= 1'b1;
        WDATA   <= bt_wdata[i];
        WSTRB   <= bt_strb[i] & lane_mask(bt_size[i], bt_addr[i]);
        aw_done = 1'b0;
        w_done  = 1'b0;
        forever begin
          @(posedge ACLK);
          last_cycles++;
          awr = AWREADY;
          wr  = WREADY;
          bv  = BVALID;
          br  = BRESP;
          `TB_DRV;
          if (!aw_done && awr === 1'b1) begin
            aw_done = 1'b1;
            AWVALID <= 1'b0;
          end
          if (!w_done && wr === 1'b1) begin
            w_done = 1'b1;
            WVALID <= 1'b0;
          end
          if (bv === 1'b1) begin
            bt_err[i]   = (br !== 2'b00);
            bt_rdata[i] = '0;
            break;
          end
          last_wait++;
          if (++w > TMO) begin
            $display("FAIL [%m] write stuck for %0d cycles at %0t", TMO, $time);
            $finish(1);
          end
        end
      end else begin
        ARVALID <= 1'b1;
        ARADDR  <= bt_addr[i];
        ar_done = 1'b0;
        forever begin
          @(posedge ACLK);
          last_cycles++;
          arr = ARREADY;
          rv  = RVALID;
          rr  = RRESP;
          rd  = RDATA;
          `TB_DRV;
          if (!ar_done && arr === 1'b1) begin
            ar_done = 1'b1;
            ARVALID <= 1'b0;
          end
          if (rv === 1'b1) begin
            bt_err[i]   = (rr !== 2'b00);
            bt_rdata[i] = rd;
            break;
          end
          last_wait++;
          if (++w > TMO) begin
            $display("FAIL [%m] read stuck for %0d cycles at %0t", TMO, $time);
            $finish(1);
          end
        end
      end
    end
  endtask

  // word — word address of a byte address (the read/write hazard key)
  function automatic logic [AW-1:0] word(input logic [AW-1:0] a);
    return a >> OffW;
  endfunction

  // run_beats_pipelined — pipelined mode of run_beats (see the header).
  task automatic run_beats_pipelined(input int unsigned n);
    int unsigned wq[$];   // writes in flight (beat index), oldest first
    int unsigned rq[$];   // reads in flight
    int unsigned ni;      // next beat to issue
    int unsigned done;    // responses received
    int unsigned busy;    // idle cycles left before beat ni
    int unsigned idle;    // cycles without a response, for the timeout
    bit          aw_v, w_v, ar_v, resp, hazard;
    logic        awr, wr, bv, arr, rv;  // inputs sampled at the edge
    logic [1:0]  br, rr;
    logic [DW-1:0] rd;
    last_cycles = 0;
    last_wait   = 0;
    ni   = 0;
    done = 0;
    idle = 0;
    aw_v = 1'b0;
    w_v  = 1'b0;
    ar_v = 1'b0;
    busy = (n > 0) ? bt_busy[0] : 0;
    @(posedge ACLK);
    while (done < n) begin
      awr = AWREADY;
      wr  = WREADY;
      arr = ARREADY;
      bv  = BVALID;
      br  = BRESP;
      rv  = RVALID;
      rr  = RRESP;
      rd  = RDATA;
      `TB_DRV;
      // Responses (BREADY / RREADY are always high)
      resp = 1'b0;
      if (bv === 1'b1 && wq.size() > 0) begin
        bt_err[wq[0]]   = (br !== 2'b00);
        bt_rdata[wq[0]] = '0;
        void'(wq.pop_front());
        done++;
        resp = 1'b1;
      end
      if (rv === 1'b1 && rq.size() > 0) begin
        bt_err[rq[0]]   = (rr !== 2'b00);
        bt_rdata[rq[0]] = rd;
        void'(rq.pop_front());
        done++;
        resp = 1'b1;
      end
      if (last_cycles > 0) begin
        if (!resp) last_wait++;
        idle = resp ? 0 : idle + 1;
        if (idle > TMO) begin
          $display("FAIL [%m] pipelined run stuck for %0d cycles at %0t", TMO, $time);
          $finish(1);
        end
      end
      // Address / data handshakes of the previous cycle's requests
      if (aw_v && awr === 1'b1) begin
        aw_v = 1'b0;
        AWVALID <= 1'b0;
      end
      if (w_v && wr === 1'b1) begin
        w_v = 1'b0;
        WVALID <= 1'b0;
      end
      if (ar_v && arr === 1'b1) begin
        ar_v = 1'b0;
        ARVALID <= 1'b0;
      end
      // Issue the next beat
      if (ni < n) begin
        if (busy > 0) begin
          busy--;
        end else begin
          hazard = 1'b0;
          if (bt_we[ni]) begin
            foreach (rq[k]) if (word(bt_addr[rq[k]]) == word(bt_addr[ni])) hazard = 1'b1;
            if (!aw_v && !w_v && !hazard) begin
              AWVALID <= 1'b1;
              AWADDR  <= bt_addr[ni];
              WVALID  <= 1'b1;
              WDATA   <= bt_wdata[ni];
              WSTRB   <= bt_strb[ni] & lane_mask(bt_size[ni], bt_addr[ni]);
              aw_v = 1'b1;
              w_v  = 1'b1;
              wq.push_back(ni);
              ni++;
              busy = (ni < n) ? bt_busy[ni] : 0;
            end
          end else begin
            foreach (wq[k]) if (word(bt_addr[wq[k]]) == word(bt_addr[ni])) hazard = 1'b1;
            if (!ar_v && !hazard) begin
              ARVALID <= 1'b1;
              ARADDR  <= bt_addr[ni];
              ar_v = 1'b1;
              rq.push_back(ni);
              ni++;
              busy = (ni < n) ? bt_busy[ni] : 0;
            end
          end
        end
      end
      if (done == n) break;
      @(posedge ACLK);
      last_cycles++;
    end
  endtask

endmodule : sram_tb_axi4l_master
