// sram_model.sv — Behavioral reference model for the sram IP.
//
// Non-synthesizable, transaction-level model for the directed tests (Step 4)
// and the UVM scoreboard (Step 6). It watches the Claude memory bus between
// the bus adapter and sram_core (so it works for every bus protocol) plus
// the side-band controls, predicts each response, and compares it with the
// response the RTL gives.
//
// What it models:
//   - contents: byte-lane merges (BYTE_EN), full-word writes otherwise;
//     words never written read as X ("unknown") unless ECC_EN (cleared at reset)
//   - bus errors: address beyond DEPTH, partial write with BYTE_EN = 0 and
//     PARTIAL_WR_ERR, access to a domain whose requested mode is DS or SD
//     (sampled when the request is granted)
//   - shutdown: when a domain's acknowledged mode becomes SD its words become
//     unknown; when it acknowledges RUN again they are zero (auto-clear)
//   - clr_req_i: zeroes the domains requested RUN or LS at request time, when
//     clr_done_o pulses
//   - BIST: every word is zero after bist_done_o
//   - ECC injection (ECC_EN): ecc_inj_i arms a fault on the next write;
//     a single-bit fault reads back corrected, a double-bit fault makes the
//     word read as an error until it is fully rewritten
// Unknown expected data (X bits) is not compared.
//
// Outputs: exp_* for the response in flight, mismatch_o pulses on a wrong
// response, and n_checked / n_mismatch counters.
//
// This file uses non-synthesizable constructs and must NOT be placed in
// synthesis file lists.

`ifndef SYNTHESIS

module sram_model #(
  parameter int unsigned ADDR_W         = 32,
  parameter int unsigned WIDTH          = 32,
  parameter int unsigned DEPTH          = 1024,
  parameter bit          BYTE_EN        = 1,
  parameter bit          PARTIAL_WR_ERR = 1,
  parameter bit          PWR_GATE       = 1,
  parameter bit          ECC_EN         = 0,
  parameter bit          BANK_PG        = 0,
  parameter int unsigned NUM_BANKS      = 1,
  localparam int unsigned NPD           = BANK_PG ? NUM_BANKS : 1
) (
  input  logic                   clk,             // clock
  input  logic                   rst_n,           // synchronous active-low reset

  // Memory bus between the adapter and sram_core
  input  logic                   mem_req,         // request
  input  logic                   mem_gnt,         // grant
  input  logic                   mem_we,          // 1 = write
  input  logic [ADDR_W-1:0]      mem_addr,        // byte address
  input  logic [WIDTH/8-1:0]     mem_be,          // byte enables
  input  logic [WIDTH-1:0]       mem_wdata,       // write data
  input  logic                   mem_rvalid,      // response
  input  logic [WIDTH-1:0]       mem_rdata,       // read data (actual)
  input  logic                   mem_err,         // error (actual)

  // Side-band
  input  logic [2*NPD-1:0]       pwr_mode_req,    // requested modes
  input  logic [2*NPD-1:0]       pwr_mode_ack,    // acknowledged modes
  input  logic                   clr_req,         // clear request
  input  logic                   clr_done,        // clear pass finished
  input  logic                   bist_done,       // BIST finished
  input  logic [1:0]             ecc_inj,         // ECC injection arm

  // Prediction and comparison
  output logic                   exp_valid,       // a response is expected now
  output logic [WIDTH-1:0]       exp_rdata,       // expected read data
  output logic                   exp_err,         // expected error flag
  output logic                   mismatch_o,      // actual response differs (pulse)
  output int unsigned            n_checked,       // responses compared
  output int unsigned            n_mismatch       // responses that differed
);

  localparam int unsigned StrbW = WIDTH / 8;
  localparam int unsigned OffW  = (StrbW > 1) ? $clog2(StrbW) : 0;
  localparam int unsigned IdxW  = $clog2(DEPTH);
  localparam int unsigned DomD  = DEPTH / NPD;

  logic [WIDTH-1:0] mem [DEPTH];
  logic [1:0]       fault [DEPTH];   // 0 none, 1 single (corrected), 2 double
  logic [1:0]       inj_armed;
  logic [NPD-1:0]   clr_mask;        // domains of a pending software clear
  logic [2*NPD-1:0] ack_q;

  // Expected response of the granted request, queued until rvalid.
  logic             pend_valid;
  logic [WIDTH-1:0] pend_rdata;
  logic             pend_err;

  function automatic logic [1:0] dom_req(int unsigned d);
    return pwr_mode_req[2*d +: 2];
  endfunction

  function automatic int unsigned dom_of(int unsigned idx);
    return idx / DomD;
  endfunction

  task automatic fill_domain(int unsigned d, logic [WIDTH-1:0] value);
    for (int unsigned w = d * DomD; w < (d + 1) * DomD; w++) begin
      mem[w]   = value;
      fault[w] = 2'd0;
    end
  endtask

  initial begin : p_init
    for (int unsigned w = 0; w < DEPTH; w++) begin
      mem[w]   = ECC_EN ? '0 : 'x;
      fault[w] = 2'd0;
    end
    inj_armed  = 2'd0;
    clr_mask   = '0;
    pend_valid = 1'b0;
    n_checked  = 0;
    n_mismatch = 0;
  end

  // Model state update and prediction (one transaction at a time).
  always @(posedge clk) begin : p_model
    logic [IdxW-1:0] idx;
    logic            oor;
    logic            full;
    int unsigned     d;
    logic [WIDTH-1:0] merged;

    mismatch_o = 1'b0;
    if (!rst_n) begin
      pend_valid = 1'b0;
      inj_armed  = 2'd0;
      clr_mask   = '0;
      ack_q      = '0;
      if (ECC_EN) begin
        for (int unsigned w = 0; w < DEPTH; w++) begin
          mem[w]   = '0;
          fault[w] = 2'd0;
        end
      end
    end else begin
      // ---- compare the response delivered this cycle -----------------------
      if (mem_rvalid) begin
        n_checked++;
        if (!pend_valid) begin
          $display("ERROR [sram_model] response without a granted request (%0t)", $time);
          mismatch_o = 1'b1;
        end else if (mem_err !== pend_err ||
                     (!pend_err && ((mem_rdata ^ pend_rdata) !== (pend_rdata ^ pend_rdata)))) begin
          // The second term ignores bits whose expected value is X.
          $display("ERROR [sram_model] response mismatch (%0t): err %b/%b data 0x%h/0x%h",
                   $time, mem_err, pend_err, mem_rdata, pend_rdata);
          mismatch_o = 1'b1;
        end
        if (mismatch_o) n_mismatch++;
        pend_valid = 1'b0;
      end

      // ---- side-band --------------------------------------------------------
      if (ECC_EN && ecc_inj != 2'b00) inj_armed = inj_armed | ecc_inj;
      if (clr_req) begin
        for (int unsigned dd = 0; dd < NPD; dd++) begin
          if (!PWR_GATE || dom_req(dd) == 2'd0 || dom_req(dd) == 2'd1) clr_mask[dd] = 1'b1;
        end
      end
      if (clr_done) begin
        for (int unsigned dd = 0; dd < NPD; dd++) begin
          if (clr_mask[dd]) fill_domain(dd, '0);
        end
        clr_mask = '0;
      end
      if (bist_done) begin
        for (int unsigned dd = 0; dd < NPD; dd++) fill_domain(dd, '0);
      end
      for (int unsigned dd = 0; dd < NPD; dd++) begin
        if (pwr_mode_ack[2*dd +: 2] == 2'd3 && ack_q[2*dd +: 2] != 2'd3) fill_domain(dd, 'x);
        if (pwr_mode_ack[2*dd +: 2] == 2'd0 && ack_q[2*dd +: 2] == 2'd3) fill_domain(dd, '0);
      end
      ack_q = pwr_mode_ack;

      // ---- predict the granted request -----------------------------------
      if (mem_req && mem_gnt) begin
        idx  = mem_addr[OffW +: IdxW];
        oor  = (ADDR_W > OffW + IdxW) ? ((mem_addr >> (OffW + IdxW)) != 0) : 1'b0;
        full = (mem_be == {StrbW{1'b1}});
        d    = dom_of(idx);
        pend_valid = 1'b1;
        pend_rdata = '0;
        pend_err   = 1'b0;
        if (oor || (PWR_GATE && (dom_req(d) == 2'd2 || dom_req(d) == 2'd3)) ||
            (!BYTE_EN && PARTIAL_WR_ERR && mem_we && !full)) begin
          pend_err = 1'b1;
        end else if (!mem_we) begin
          pend_rdata = mem[idx];
          pend_err   = (fault[idx] == 2'd2);
        end else if (ECC_EN && BYTE_EN && !full && fault[idx] == 2'd2) begin
          pend_err = 1'b1;                       // read-modify-write of a bad word
        end else begin
          merged = mem[idx];
          for (int unsigned b = 0; b < StrbW; b++) begin
            if (!BYTE_EN || mem_be[b]) merged[8*b +: 8] = mem_wdata[8*b +: 8];
          end
          mem[idx]   = merged;
          fault[idx] = inj_armed[1] ? 2'd2 : (inj_armed[0] ? 2'd1 : 2'd0);
          inj_armed  = 2'd0;
        end
      end
    end
    exp_valid = pend_valid;
    exp_rdata = pend_rdata;
    exp_err   = pend_err;
  end

endmodule : sram_model

`endif
