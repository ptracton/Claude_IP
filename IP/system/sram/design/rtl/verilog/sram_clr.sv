// sram_clr.sv — Clear engine for the sram IP: writes zero to whole domains.
//
// Requests:
//   start_i + mask_i    software clear (clr_req_i) of the domains in mask_i
//   auto_i[d]           domain d woke from shutdown and must be cleared
// Requests are collected in a pending mask. When the engine is idle, has
// work, and the bus port has nothing in flight (port_idle_i), it starts a
// pass over the array: one word per cycle in every selected domain, the
// other domains skipped a whole domain at a time. A selected domain that is
// asleep is woken (wake_o) if it can be (wakeable_i, i.e. RUN/LS requested),
// otherwise skipped. pending_o tells the core to stop granting bus requests
// (they stall until the pass ends).
//
// Zero data is a valid SECDED codeword (all-zero), so the engine writes the
// stored word directly with every lane enabled.
//
// Outputs at the end of a pass: done_o (one cycle) and dom_done_o (one cycle,
// the domains that pass cleared).
//
// CLEAR_ON_RESET: every domain is pending when reset is released, so the
// array is zeroed before the first bus access (used with ECC, where an
// uninitialised word would read as an ECC error).

module sram_clr #(
  parameter int unsigned DEPTH = 1024,  // words
  parameter int unsigned NPD   = 1,     // power domains (equal-size slices)
  parameter bit          CLEAR_ON_RESET = 0  // clear everything after reset
) (
  input  logic                     clk,          // clock
  input  logic                     rst_n,        // synchronous active-low reset
  input  logic                     start_i,      // software clear request (pulse)
  input  logic [NPD-1:0]           mask_i,       // domains for start_i
  input  logic [NPD-1:0]           auto_i,       // domains needing a clear after shutdown
  input  logic                     port_idle_i,  // bus port has nothing in flight
  input  logic [NPD-1:0]           ok_i,         // domain accepts engine writes
  input  logic [NPD-1:0]           wakeable_i,   // domain may be woken (RUN/LS requested)
  output logic [NPD-1:0]           wake_o,       // wake this domain for the engine
  output logic                     pending_o,    // work pending or running: stall the bus
  output logic                     busy_o,       // a pass is running
  output logic                     done_o,       // pass finished (pulse)
  output logic [NPD-1:0]           dom_done_o,   // domains cleared by that pass (pulse)
  output logic                     cs_o,         // array write this cycle
  output logic [$clog2(DEPTH)-1:0] idx_o         // word index written
);

  localparam int unsigned IdxW = $clog2(DEPTH);
  localparam int unsigned DomW = (NPD > 1) ? $clog2(NPD) : 1;
  localparam int unsigned DomD = DEPTH / NPD;     // words per domain
  localparam int unsigned DomSh = $clog2(DomD);   // index bits inside a domain

  logic            active_q;
  logic [NPD-1:0]  pend_q, pend_d;
  logic [NPD-1:0]  cur_q;       // domains of the running pass
  logic [IdxW:0]   idx_q, idx_d; // one extra bit: pass ends when it overflows
  logic [DomW-1:0] dom;          // domain of idx_q
  logic            last;         // this cycle finishes the pass
  logic            step;         // advance one word
  logic            skip;         // advance to the next domain
  logic            start_pass;

  if (NPD > 1) begin : g_dom
    assign dom = DomW'(idx_q[IdxW-1:0] >> DomSh);
  end else begin : g_one_dom
    assign dom = '0;
  end

  // Work in the current domain: write, wait for a wake-up, or skip it.
  always_comb begin : p_step
    step   = 1'b0;
    skip   = 1'b0;
    wake_o = '0;
    cs_o   = 1'b0;
    if (active_q) begin
      if (!cur_q[dom]) begin
        skip = 1'b1;
      end else if (ok_i[dom]) begin
        cs_o = 1'b1;
        step = 1'b1;
      end else if (wakeable_i[dom]) begin
        wake_o[dom] = 1'b1;
      end else begin
        skip = 1'b1;
      end
    end
  end

  always_comb begin : p_next_idx
    idx_d = idx_q;
    if (step) begin
      idx_d = idx_q + (IdxW + 1)'(1);
    end else if (skip) begin
      idx_d = (IdxW + 1)'((int'(dom) + 1) * DomD);
    end
  end

  assign last       = active_q && idx_d[IdxW];
  assign start_pass = !active_q && (pend_q != '0) && port_idle_i;

  // New requests join the pending mask, except domains this pass already
  // covers (auto_i stays high until the domain sees dom_done_o).
  always_comb begin : p_pending
    pend_d = pend_q | (start_i ? mask_i : '0) | auto_i;
    if (active_q) begin
      pend_d = pend_d & ~cur_q;
    end
    if (start_pass) begin
      pend_d = '0;
    end
  end

  // Pass control, pending mask and word index.
  always_ff @(posedge clk) begin : p_regs
    if (!rst_n) begin
      active_q <= 1'b0;
      pend_q   <= CLEAR_ON_RESET ? {NPD{1'b1}} : '0;
      cur_q    <= '0;
      idx_q    <= '0;
    end else begin
      pend_q <= pend_d;
      if (start_pass) begin
        active_q <= 1'b1;
        cur_q    <= pend_q;
        idx_q    <= '0;
      end else if (last) begin
        active_q <= 1'b0;
        cur_q    <= '0;
        idx_q    <= '0;
      end else begin
        idx_q <= idx_d;
      end
    end
  end

  assign idx_o      = idx_q[IdxW-1:0];
  assign busy_o     = active_q;
  assign pending_o  = active_q || (pend_q != '0);
  assign done_o     = last;
  assign dom_done_o = last ? cur_q : '0;

endmodule : sram_clr
