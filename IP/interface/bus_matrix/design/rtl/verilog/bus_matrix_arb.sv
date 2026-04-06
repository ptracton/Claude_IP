// bus_matrix_arb.sv — Bus Matrix arbitration for one slave port.
//
// Implements fixed-priority and round-robin arbitration.
// One instance per slave. Selects at most one master per cycle.
// Configuration is entirely via parameters — no runtime register ports.
//
// Fixed-priority: master with lowest priority value wins.
//   Ties broken by lower master index.
// Round-robin: rotating pointer, starting from master after last granted.
//   Holds grant stable while valid_trx is asserted.
//
// gnt output is registered to prevent glitching.
// slv_gnt input: slave acknowledge (HREADY for AHB, BVALID/RVALID for AXI,
//   ACK for Wishbone). When valid_trx && slv_gnt, the current transaction
//   completes this cycle; gnt is cleared next cycle.

module bus_matrix_arb #(
  parameter int NUM_MASTERS = 2,                             // 1-16 active masters
  parameter int ARB_MODE    = 0,                             // 0=fixed-priority, 1=round-robin
  parameter logic [NUM_MASTERS*4-1:0] M_PRIORITY = '0       // master i priority at [i*4+:4]
                                                             // lower value = higher priority
) (
  input  logic                    clk,       // system clock
  input  logic                    rst_n,     // synchronous active-low reset
  input  logic [NUM_MASTERS-1:0]  req,       // request from each master
  input  logic                    valid_trx, // transaction being served; suppress arb change
  input  logic                    slv_gnt,   // slave acknowledge; clears grant when done
  output logic [NUM_MASTERS-1:0]  gnt        // one-hot grant output
);

  // -------------------------------------------------------------------------
  // Fixed-priority arbitration (combinational)
  // beaten[i] = 1 if some other requesting master j has strictly lower
  //   priority value OR same value and lower index.
  // fp_gnt = req & ~beaten  → exactly one winner.
  // -------------------------------------------------------------------------
  logic [NUM_MASTERS-1:0] beaten;
  logic [NUM_MASTERS-1:0] fp_gnt;

  always_comb begin : p_fp_gnt
    beaten = '0;
    for (int i = 0; i < NUM_MASTERS; i = i + 1) begin
      for (int j = 0; j < NUM_MASTERS; j = j + 1) begin
        if (j != i && req[j]) begin
          // j beats i if j has strictly lower priority value
          if (M_PRIORITY[j*4+:4] < M_PRIORITY[i*4+:4])
            beaten[i] = 1'b1;
          // or same value and lower index (lower index = higher natural priority)
          else if ((M_PRIORITY[j*4+:4] == M_PRIORITY[i*4+:4]) && (j < i))
            beaten[i] = 1'b1;
        end
      end
    end
    fp_gnt = req & ~beaten;
  end

  // -------------------------------------------------------------------------
  // Round-robin arbitration
  // Two-pass scan: first above rr_ptr_q, then 0..rr_ptr_q (wrap).
  // -------------------------------------------------------------------------
  localparam int PTR_W = (NUM_MASTERS > 1) ? $clog2(NUM_MASTERS) : 1;

  logic [PTR_W-1:0]       rr_ptr_q;    // last-granted master index
  logic [NUM_MASTERS-1:0] rr_gnt_q;    // registered round-robin grant
  logic [NUM_MASTERS-1:0] rr_gnt_next; // combinational next RR grant

  always_comb begin : p_rr_comb
    rr_gnt_next = '0;
    if (|req) begin
      // First pass: masters strictly above rr_ptr_q (lowest index wins)
      for (int k = 0; k < NUM_MASTERS; k = k + 1) begin
        if ((k > int'(rr_ptr_q)) && req[k] && (rr_gnt_next == '0))
          rr_gnt_next[k] = 1'b1;
      end
      // Second pass (wrap): masters 0..rr_ptr_q (lowest index wins)
      if (rr_gnt_next == '0) begin
        for (int k = 0; k < NUM_MASTERS; k = k + 1) begin
          if ((k <= int'(rr_ptr_q)) && req[k] && (rr_gnt_next == '0))
            rr_gnt_next[k] = 1'b1;
        end
      end
    end
  end

  always_ff @(posedge clk) begin : p_rr_reg
    if (!rst_n) begin
      rr_ptr_q <= '0;
      rr_gnt_q <= '0;
    end else if (!valid_trx) begin
      rr_gnt_q <= rr_gnt_next;
      if (|rr_gnt_next) begin
        for (int k = 0; k < NUM_MASTERS; k = k + 1) begin
          if (rr_gnt_next[k]) rr_ptr_q <= PTR_W'(k);
        end
      end
    end
  end

  // -------------------------------------------------------------------------
  // Mux and registered grant output
  // When transaction completes (valid_trx & slv_gnt), force gnt_next=0
  // so the registered output de-asserts next cycle instead of holding.
  // -------------------------------------------------------------------------
  logic [NUM_MASTERS-1:0] gnt_next;
  assign gnt_next = (valid_trx & slv_gnt) ? '0 :
                    (ARB_MODE != 0        ? rr_gnt_q : fp_gnt);

  always_ff @(posedge clk) begin : p_gnt_reg
    if (!rst_n)
      gnt <= '0;
    else
      gnt <= gnt_next;
  end

endmodule : bus_matrix_arb
