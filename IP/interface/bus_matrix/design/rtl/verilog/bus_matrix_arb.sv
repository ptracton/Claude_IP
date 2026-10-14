// bus_matrix_arb.sv — Bus Matrix arbiter for one slave port.
//
// One instance per slave. Picks one requesting master when the slave is free
// and locks that grant until the transaction completes, so a higher-priority
// request can never take the slave away mid-transaction.
//
//   Fixed priority (ARB_MODE=0): lowest M_PRIORITY value wins; ties go to
//     the lower master index.
//   Round robin   (ARB_MODE=1): the first requester after the last granted
//     master wins (master 0 is first after reset).
//
// Grant timing: gnt is registered. It is set on the clock edge after a
// request is seen with the slave free, held while the owner keeps requesting,
// and cleared on the edge where `done` is high (or the owner stops
// requesting). No new grant is made on the edge that releases one, so every
// transaction is followed by one idle cycle on the slave.

module bus_matrix_arb #(
  parameter int unsigned NUM_MASTERS = 2,                    // 1-16 active masters
  parameter int unsigned ARB_MODE    = 0,                    // 0=fixed-priority, 1=round-robin
  parameter logic [NUM_MASTERS*4-1:0] M_PRIORITY = '0       // master i priority at [i*4+:4]
) (
  input  logic                    clk,   // system clock
  input  logic                    rst_n, // synchronous active-low reset
  input  logic [NUM_MASTERS-1:0]  req,   // master i is requesting this slave
  input  logic                    done,  // owner's transaction completes this cycle
  output logic [NUM_MASTERS-1:0]  gnt    // one-hot grant (registered)
);

  localparam logic [NUM_MASTERS-1:0] ONE = NUM_MASTERS'(1);

  logic [NUM_MASTERS-1:0] pick; // one-hot winner among the requesters
  logic                   take; // make a new grant on this edge

  genvar gi, gj;
  generate
    if (ARB_MODE == 0) begin : gen_fp
      // ---------------------------------------------------------------------
      // Fixed priority: master i wins unless another requester j beats it with
      // a strictly lower priority value, or the same value and a lower index.
      // ---------------------------------------------------------------------
      for (gi = 0; gi < NUM_MASTERS; gi++) begin : gen_m
        logic [NUM_MASTERS-1:0] beats; // beats[j] = requester j beats master i

        for (gj = 0; gj < NUM_MASTERS; gj++) begin : gen_cmp
          if (gj < gi) begin : gen_lo
            assign beats[gj] = req[gj] && (M_PRIORITY[gj*4+:4] <= M_PRIORITY[gi*4+:4]);
          end else if (gj > gi) begin : gen_hi
            assign beats[gj] = req[gj] && (M_PRIORITY[gj*4+:4] <  M_PRIORITY[gi*4+:4]);
          end else begin : gen_self
            assign beats[gj] = 1'b0;
          end
        end

        assign pick[gi] = req[gi] & ~(|beats);
      end
    end else begin : gen_rr
      // ---------------------------------------------------------------------
      // Round robin: the lowest requester above the last granted master, else
      // the lowest requester overall (wrap). last_q is one-hot; resetting it to
      // the top master makes master 0 first after reset.
      // ---------------------------------------------------------------------
      logic [NUM_MASTERS-1:0] last_q;  // one-hot last granted master
      logic [NUM_MASTERS-1:0] above;   // masters strictly above last_q
      logic [NUM_MASTERS-1:0] req_hi;  // requesters above last_q

      assign above  = ~((last_q << 1) - ONE);
      assign req_hi = req & above;
      assign pick   = (|req_hi) ? (req_hi & (~req_hi + ONE)) : (req & (~req + ONE));

      always_ff @(posedge clk) begin : p_last
        if (!rst_n) begin
          last_q <= ONE << (NUM_MASTERS - 1);
        end else if (take) begin
          last_q <= pick;
        end
      end
    end
  endgenerate

  // -------------------------------------------------------------------------
  // Grant lock
  // -------------------------------------------------------------------------
  logic busy;        // a grant is held
  logic owner_req;   // the granted master is still requesting
  logic release_gnt; // drop the grant on this edge

  assign busy        = |gnt;
  assign owner_req   = |(gnt & req);
  assign release_gnt = busy && (done || !owner_req);
  assign take        = !busy && (|req);

  always_ff @(posedge clk) begin : p_gnt
    if (!rst_n) begin
      gnt <= '0;
    end else if (release_gnt) begin
      gnt <= '0;
    end else if (take) begin
      gnt <= pick;
    end
  end

endmodule : bus_matrix_arb
