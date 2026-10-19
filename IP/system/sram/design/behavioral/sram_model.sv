// sram_model.sv — Behavioral reference model for the sram IP.
//
// Non-synthesizable, transaction-level model for the directed tests (Step 4)
// and the UVM scoreboard (Step 6). It watches the Claude memory bus between
// each bus adapter and sram_core (so it works for every bus protocol) plus
// the side-band controls, predicts each response, and compares it with the
// response the RTL gives.
//
// What it models:
//   - contents: byte-lane merges (BYTE_EN), full-word writes otherwise;
//     words never written read as X ("unknown") unless ECC_EN (cleared at reset)
//   - bus errors: address beyond the port's last word, partial write with
//     BYTE_EN = 0 and PARTIAL_WR_ERR, write to a READ_ONLY_B port B, access to
//     a domain whose requested mode is DS or SD (sampled at the grant)
//   - shutdown: when a domain's acknowledged mode becomes SD its words become
//     unknown; when it acknowledges RUN again they are zero (auto-clear)
//   - clr_req: zeroes the domains requested RUN or LS at request time, when
//     clr_done pulses
//   - BIST: every word is zero after bist_done
//   - ECC injection (ECC_EN): ecc_inj arms a fault on the next port-A write
//     that reaches the array; it lands in that word's first codeword if the
//     write stores it. A single-bit fault reads back corrected; a double-bit
//     fault makes reads that check the codeword (and read-modify-writes that
//     write it back) answer with an error until the codeword is rewritten.
//     A failed read-modify-write does not consume the injection.
//   - DUAL_PORT: port B (WIDTH_B wide, its own clock clk_b) shares the
//     storage. Narrow word j is bits [(j % R) * N +: N] of wide word j / R
//     (little-endian, R = width ratio, N = narrow width). ECC codewords are
//     N bits wide (WIDTH bits for a single port or equal widths).
//     Same-word accesses from both ports are modeled in grant order, so the
//     model is exact with COMMON_CLK = 1 and for separate clocks when the
//     testbench keeps the two ports off the same word at the same time.
//     Side-band effects on port B (power errors) are taken at B's grant;
//     with separate clocks keep port B off a domain while its mode changes.
// Word strides are powers of two (a 24-bit word takes 4 bytes of address).
// Backdoor bit flips are reported with set_fault(unit, kind).
// Unknown expected data (X bits) is not compared.
//
// Outputs: mismatch_o pulses on a wrong port-A response, mismatch_b_o on a
// wrong port-B response; n_checked / n_mismatch count both ports.
//
// This file uses non-synthesizable constructs and must NOT be placed in
// synthesis file lists.

`ifndef SYNTHESIS

module sram_model #(
  parameter int unsigned ADDR_W           = 32,
  parameter int unsigned WIDTH            = 32,
  parameter int unsigned DEPTH            = 1024,
  parameter bit          BYTE_EN          = 1,
  parameter bit          PARTIAL_WR_ERR   = 1,
  parameter bit          PWR_GATE         = 1,
  parameter bit          ECC_EN           = 0,
  parameter bit          BANK_PG          = 0,
  parameter int unsigned NUM_BANKS        = 1,
  parameter bit          DUAL_PORT        = 0,
  parameter int unsigned WIDTH_B          = WIDTH,
  parameter bit          BYTE_EN_B        = BYTE_EN,
  parameter bit          PARTIAL_WR_ERR_B = PARTIAL_WR_ERR,
  parameter bit          READ_ONLY_B      = 0,
  localparam int unsigned NPD             = BANK_PG ? NUM_BANKS : 1
) (
  input  logic                   clk,             // port A / side-band clock
  input  logic                   rst_n,           // synchronous active-low reset

  // Memory bus between the port-A adapter and sram_core
  input  logic                   mem_req,         // request
  input  logic                   mem_gnt,         // grant
  input  logic                   mem_we,          // 1 = write
  input  logic [ADDR_W-1:0]      mem_addr,        // byte address
  input  logic [WIDTH/8-1:0]     mem_be,          // byte enables
  input  logic [WIDTH-1:0]       mem_wdata,       // write data
  input  logic                   mem_rvalid,      // response
  input  logic [WIDTH-1:0]       mem_rdata,       // read data (actual)
  input  logic                   mem_err,         // error (actual)

  // Port B (DUAL_PORT only; leave unconnected otherwise)
  input  logic                   clk_b,           // port B clock
  input  logic                   rst_b_n,         // port B reset
  input  logic                   mem_b_req,
  input  logic                   mem_b_gnt,
  input  logic                   mem_b_we,
  input  logic [ADDR_W-1:0]      mem_b_addr,
  input  logic [WIDTH_B/8-1:0]   mem_b_be,
  input  logic [WIDTH_B-1:0]     mem_b_wdata,
  input  logic                   mem_b_rvalid,
  input  logic [WIDTH_B-1:0]     mem_b_rdata,
  input  logic                   mem_b_err,

  // Side-band (port A clock)
  input  logic [2*NPD-1:0]       pwr_mode_req,    // requested modes
  input  logic [2*NPD-1:0]       pwr_mode_ack,    // acknowledged modes
  input  logic                   clr_req,         // clear request
  input  logic                   clr_done,        // clear pass finished
  input  logic                   bist_done,       // BIST finished
  input  logic [1:0]             ecc_inj,         // ECC injection arm

  // Comparison
  output logic                   mismatch_o,      // port-A response differs (pulse)
  output logic                   mismatch_b_o,    // port-B response differs (pulse)
  output int unsigned            n_checked,       // responses compared (both ports)
  output int unsigned            n_mismatch       // responses that differed
);

  // Storage unit: the narrower port's word (= the ECC codeword).
  localparam int unsigned WB    = DUAL_PORT ? WIDTH_B : WIDTH;
  localparam int unsigned U     = (WB < WIDTH) ? WB : WIDTH;
  localparam int unsigned UB    = U / 8;                  // bytes per unit
  localparam int unsigned NU    = DEPTH * WIDTH / U;      // units
  localparam int unsigned DomU  = NU / NPD;               // units per domain
  localparam int unsigned DEPTH_B = WIDTH * DEPTH / WB;

  logic [U-1:0]     mem   [NU];
  logic [1:0]       fault [NU];      // 0 none, 1 single (corrected), 2 double
  logic [1:0]       inj_armed;
  logic [NPD-1:0]   clr_mask;        // domains of a pending software clear
  logic [2*NPD-1:0] ack_q;

  // Expected responses of granted requests, in order.
  typedef struct {
    logic [WIDTH-1:0] rdata;
    logic             err;
  } exp_a_t;
  typedef struct {
    logic [WB-1:0] rdata;
    logic          err;
  } exp_b_t;
  exp_a_t exp_a [$];
  exp_b_t exp_b [$];

  function automatic logic [1:0] dom_req(int unsigned d);
    return pwr_mode_req[2*d +: 2];
  endfunction

  task automatic fill_domain(int unsigned d, logic [U-1:0] value);
    for (int unsigned u = d * DomU; u < (d + 1) * DomU; u++) begin
      mem[u]   = value;
      fault[u] = 2'd0;
    end
  endtask

  // ---------------------------------------------------------------------------
  // access — predict one granted request of a port whose word is W bits
  // (R = W / U units) and apply it to the storage.
  //   addr, we, be, wdata: the request; byte_en / pwe / ro: port options;
  //   inj_port: the port takes ECC injection (port A).
  // ---------------------------------------------------------------------------
  task automatic access(input int unsigned W, input int unsigned depth_p,
                        input logic [ADDR_W-1:0] addr, input logic we,
                        input logic [127:0] be, input logic [1023:0] wdata,
                        input bit byte_en, input bit pwe, input bit ro, input bit inj_port,
                        output logic [1023:0] rdata, output logic err);
    int unsigned sb, offw, idxw, idx, r, u0, d;
    logic oor, full, rmw, touch, part, bad;
    sb   = W / 8;
    offw = (sb > 1) ? $clog2(sb) : 0;
    idxw = $clog2(depth_p);
    r    = W / U;
    idx  = (addr >> offw) & ((1 << idxw) - 1);
    oor  = (ADDR_W > offw + idxw) ? ((addr >> (offw + idxw)) != 0) : 1'b0;
    full = 1'b1;
    for (int unsigned b = 0; b < sb; b++) if (!be[b]) full = 1'b0;
    u0   = idx * r;
    d    = u0 / DomU;
    rdata = '0;
    err   = 1'b0;
    if (oor || (PWR_GATE && (dom_req(d) == 2'd2 || dom_req(d) == 2'd3)) ||
        (ro && we) || (!byte_en && pwe && we && !full)) begin
      err = 1'b1;
      return;
    end
    if (!we) begin
      for (int unsigned k = 0; k < r; k++) begin
        rdata[k * U +: U] = mem[u0 + k];
        if (ECC_EN && fault[u0 + k] == 2'd2) err = 1'b1;
      end
      if (err) rdata = '0;
      return;
    end
    // Write: ECC read-modify-write when a codeword is only partly strobed.
    rmw = 1'b0;
    bad = 1'b0;
    for (int unsigned k = 0; k < r; k++) begin
      touch = 1'b0;
      part  = 1'b0;
      for (int unsigned b = 0; b < UB; b++) begin
        if (be[k * UB + b]) touch = 1'b1; else part = 1'b1;
      end
      if (touch && part) rmw = 1'b1;
    end
    rmw = ECC_EN && byte_en && rmw;
    if (rmw) begin
      for (int unsigned k = 0; k < r; k++) begin
        touch = 1'b0;
        for (int unsigned b = 0; b < UB; b++) if (be[k * UB + b]) touch = 1'b1;
        if (touch && fault[u0 + k] == 2'd2) bad = 1'b1;
      end
    end
    if (bad) begin
      err = 1'b1;                                 // no write-back
      return;
    end
    for (int unsigned k = 0; k < r; k++) begin
      touch = 1'b0;
      for (int unsigned b = 0; b < UB; b++) begin
        if (!byte_en || be[k * UB + b]) begin
          mem[u0 + k][8*b +: 8] = wdata[(k * UB + b) * 8 +: 8];
          touch = 1'b1;
        end
      end
      // ECC codewords are stored whole: a touched codeword is rewritten.
      if (touch) fault[u0 + k] = 2'd0;
      if (touch && k == 0 && inj_port && ECC_EN) begin
        fault[u0] = inj_armed[1] ? 2'd2 : (inj_armed[0] ? 2'd1 : 2'd0);
      end
    end
    if (inj_port) inj_armed = 2'd0;
  endtask

  // set_fault — the testbench changed stored bits behind the bus (backdoor):
  // unit u now holds a 0 none / 1 single / 2 double error.
  function automatic void set_fault(input int unsigned u, input logic [1:0] f);
    fault[u] = f;
  endfunction

  initial begin : p_init
    for (int unsigned u = 0; u < NU; u++) begin
      mem[u]   = ECC_EN ? '0 : 'x;
      fault[u] = 2'd0;
    end
    inj_armed  = 2'd0;
    clr_mask   = '0;
    n_checked  = 0;
    n_mismatch = 0;
  end

  // ---------------------------------------------------------------------------
  // Port A and side-band
  // ---------------------------------------------------------------------------
  always @(posedge clk) begin : p_model
    logic [1023:0] rd;
    logic          er;
    exp_a_t        e;

    mismatch_o = 1'b0;
    if (!rst_n) begin
      exp_a.delete();
      inj_armed = 2'd0;
      clr_mask  = '0;
      ack_q     = '0;
      if (ECC_EN) begin
        for (int unsigned u = 0; u < NU; u++) begin
          mem[u]   = '0;
          fault[u] = 2'd0;
        end
      end
    end else begin
      // ---- compare the response delivered this cycle -----------------------
      if (mem_rvalid) begin
        n_checked++;
        if (exp_a.size() == 0) begin
          $display("ERROR [sram_model] %m port A response without a request (%0t)", $time);
          mismatch_o = 1'b1;
        end else begin
          e = exp_a.pop_front();
          // The data term ignores bits whose expected value is X.
          if (mem_err !== e.err ||
              (!e.err && ((mem_rdata ^ e.rdata) !== (e.rdata ^ e.rdata)))) begin
            $display("ERROR [sram_model] %m port A mismatch (%0t): err %b/%b data 0x%h/0x%h",
                     $time, mem_err, e.err, mem_rdata, e.rdata);
            mismatch_o = 1'b1;
          end
        end
        if (mismatch_o) n_mismatch++;
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
        access(WIDTH, DEPTH, mem_addr, mem_we, 128'(mem_be), 1024'(mem_wdata),
               BYTE_EN, PARTIAL_WR_ERR, 1'b0, 1'b1, rd, er);
        e.rdata = rd[WIDTH-1:0];
        e.err   = er;
        exp_a.push_back(e);
      end
    end
  end

  // ---------------------------------------------------------------------------
  // Port B
  // ---------------------------------------------------------------------------
  if (DUAL_PORT) begin : g_b
    always @(posedge clk_b) begin : p_model_b
      logic [1023:0] rd;
      logic          er;
      exp_b_t        e;

      mismatch_b_o = 1'b0;
      if (!rst_b_n) begin
        exp_b.delete();
      end else begin
        if (mem_b_rvalid) begin
          n_checked++;
          if (exp_b.size() == 0) begin
            $display("ERROR [sram_model] %m port B response without a request (%0t)", $time);
            mismatch_b_o = 1'b1;
          end else begin
            e = exp_b.pop_front();
            if (mem_b_err !== e.err ||
                (!e.err && ((mem_b_rdata ^ e.rdata) !== (e.rdata ^ e.rdata)))) begin
              $display("ERROR [sram_model] %m port B mismatch (%0t): err %b/%b data 0x%h/0x%h",
                       $time, mem_b_err, e.err, mem_b_rdata, e.rdata);
              mismatch_b_o = 1'b1;
            end
          end
          if (mismatch_b_o) n_mismatch++;
        end
        if (mem_b_req && mem_b_gnt) begin
          access(WB, DEPTH_B, mem_b_addr, mem_b_we, 128'(mem_b_be), 1024'(mem_b_wdata),
                 BYTE_EN_B, PARTIAL_WR_ERR_B, READ_ONLY_B, 1'b0, rd, er);
          e.rdata = rd[WB-1:0];
          e.err   = er;
          exp_b.push_back(e);
        end
      end
    end
  end else begin : g_no_b
    assign mismatch_b_o = 1'b0;
  end

endmodule : sram_model

`endif
