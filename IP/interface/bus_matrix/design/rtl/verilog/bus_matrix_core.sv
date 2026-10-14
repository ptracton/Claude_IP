// bus_matrix_core.sv — Bus Matrix protocol-agnostic crossbar core.
//
// Routes transactions from NUM_MASTERS master ports to NUM_SLAVES slave ports.
// One bus_matrix_decoder per master selects the target slave; one
// bus_matrix_arb per slave picks and locks an owner.
//
// Internal handshake (identical on every protocol variant):
//   Master side: a target adapter raises mst_req[i] and holds it, together
//     with mst_addr/wdata/we/be, until mst_done[i] pulses for one cycle.
//     mst_rdata[i] and mst_err[i] are valid in that cycle.
//   Slave side: slv_req[j] is high while slave j is granted to a requesting
//     master; its initiator adapter runs exactly one bus transaction and
//     pulses slv_done[j] (with slv_rdata[j], slv_err[j]) when it completes.
//   Decode error: a request that matches no slave never reaches an arbiter;
//     the core answers it itself with mst_done + mst_err one cycle later.

module bus_matrix_core #(
  parameter int unsigned NUM_MASTERS = 2,                    // 1-16 active masters
  parameter int unsigned NUM_SLAVES  = 4,                    // 1-32 active slaves
  parameter int unsigned DATA_W      = 32,                   // data bus width
  parameter int unsigned ADDR_W      = 32,                   // address width (must be 32)
  parameter int unsigned ARB_MODE    = 0,                    // 0=fixed-priority, 1=round-robin
  parameter logic [NUM_MASTERS*4-1:0]  M_PRIORITY = '0,     // master i priority at [i*4+:4]
  parameter logic [NUM_SLAVES*32-1:0]  S_BASE     = '0,     // slave j base addr at [j*32+:32]
  parameter logic [NUM_SLAVES*32-1:0]  S_MASK     = '0      // slave j addr mask at [j*32+:32]
) (
  input  logic                            clk,       // system clock
  input  logic                            rst_n,     // synchronous active-low reset

  // Master side (from target adapters), master i at [i*W+:W]
  input  logic [NUM_MASTERS-1:0]          mst_req,   // request held until mst_done
  input  logic [NUM_MASTERS*ADDR_W-1:0]   mst_addr,  // byte address
  input  logic [NUM_MASTERS*DATA_W-1:0]   mst_wdata, // write data
  input  logic [NUM_MASTERS-1:0]          mst_we,    // 1 = write
  input  logic [NUM_MASTERS*DATA_W/8-1:0] mst_be,    // byte enables
  output logic [NUM_MASTERS-1:0]          mst_done,  // one-cycle completion
  output logic [NUM_MASTERS*DATA_W-1:0]   mst_rdata, // read data (valid with mst_done)
  output logic [NUM_MASTERS-1:0]          mst_err,   // error (valid with mst_done)

  // Slave side (to initiator adapters), slave j at [j*W+:W]
  output logic [NUM_SLAVES-1:0]           slv_req,   // run one transaction
  output logic [NUM_SLAVES*ADDR_W-1:0]    slv_addr,  // byte address
  output logic [NUM_SLAVES*DATA_W-1:0]    slv_wdata, // write data
  output logic [NUM_SLAVES-1:0]           slv_we,    // 1 = write
  output logic [NUM_SLAVES*DATA_W/8-1:0]  slv_be,    // byte enables
  input  logic [NUM_SLAVES-1:0]           slv_done,  // one-cycle completion
  input  logic [NUM_SLAVES*DATA_W-1:0]    slv_rdata, // read data (valid with slv_done)
  input  logic [NUM_SLAVES-1:0]           slv_err    // error (valid with slv_done)
);

  localparam int unsigned STRB_W = DATA_W / 8;

  // -------------------------------------------------------------------------
  // Address decode: one decoder per master
  // -------------------------------------------------------------------------
  logic [NUM_SLAVES-1:0]  dec_sel [NUM_MASTERS];
  logic [NUM_MASTERS-1:0] dec_err;

  genvar gi, gj;
  generate
    for (gi = 0; gi < NUM_MASTERS; gi++) begin : gen_decoder
      bus_matrix_decoder #(
        .NUM_SLAVES (NUM_SLAVES),
        .ADDR_W     (ADDR_W),
        .S_BASE     (S_BASE),
        .S_MASK     (S_MASK)
      ) u_dec (
        .addr       (mst_addr[gi*ADDR_W+:ADDR_W]),
        .slave_sel  (dec_sel[gi]),
        .decode_err (dec_err[gi])
      );
    end
  endgenerate

  // -------------------------------------------------------------------------
  // Per-slave request vectors: slv_mreq[j][i] = master i requests slave j
  // -------------------------------------------------------------------------
  logic [NUM_MASTERS-1:0] slv_mreq [NUM_SLAVES];

  always_comb begin : p_slv_mreq
    for (int j = 0; j < NUM_SLAVES; j++) begin
      for (int i = 0; i < NUM_MASTERS; i++) begin
        slv_mreq[j][i] = mst_req[i] & dec_sel[i][j];
      end
    end
  end

  // -------------------------------------------------------------------------
  // Arbitration: one arbiter per slave
  // -------------------------------------------------------------------------
  logic [NUM_MASTERS-1:0] gnt [NUM_SLAVES];

  generate
    for (gj = 0; gj < NUM_SLAVES; gj++) begin : gen_arb
      bus_matrix_arb #(
        .NUM_MASTERS (NUM_MASTERS),
        .ARB_MODE    (ARB_MODE),
        .M_PRIORITY  (M_PRIORITY)
      ) u_arb (
        .clk   (clk),
        .rst_n (rst_n),
        .req   (slv_mreq[gj]),
        .done  (slv_done[gj]),
        .gnt   (gnt[gj])
      );
    end
  endgenerate

  // -------------------------------------------------------------------------
  // Slave-side routing: AND-OR mux of the owner's request fields. The grant
  // is one-hot, so OR-accumulating each master's gated fields along a chain
  // selects the owner's. Fields packed as {we, be, wdata, addr}.
  // -------------------------------------------------------------------------
  localparam int unsigned FLD_W = 1 + STRB_W + DATA_W + ADDR_W;

  generate
    for (gj = 0; gj < NUM_SLAVES; gj++) begin : gen_route
      logic [FLD_W-1:0] fld_acc [NUM_MASTERS+1]; // fld_acc[i] = OR of masters < i

      assign fld_acc[0] = '0;
      for (gi = 0; gi < NUM_MASTERS; gi++) begin : gen_m
        assign fld_acc[gi+1] = fld_acc[gi] |
                               ({FLD_W{gnt[gj][gi]}} & {mst_we[gi],
                                                        mst_be[gi*STRB_W+:STRB_W],
                                                        mst_wdata[gi*DATA_W+:DATA_W],
                                                        mst_addr[gi*ADDR_W+:ADDR_W]});
      end

      // Registered grant only: the owner holds its request until done and the
      // grant clears on the done edge, so gating with the request is
      // redundant and would put the address decoder in front of slv_req.
      assign slv_req[gj] = |gnt[gj];
      assign {slv_we[gj],
              slv_be[gj*STRB_W+:STRB_W],
              slv_wdata[gj*DATA_W+:DATA_W],
              slv_addr[gj*ADDR_W+:ADDR_W]} = fld_acc[NUM_MASTERS];
    end
  endgenerate

  // -------------------------------------------------------------------------
  // Decode-error responder: one-cycle done + err, the cycle after a request
  // that matches no slave.
  // -------------------------------------------------------------------------
  logic [NUM_MASTERS-1:0] derr_q;

  always_ff @(posedge clk) begin : p_derr
    if (!rst_n) begin
      derr_q <= '0;
    end else begin
      derr_q <= mst_req & dec_err & ~derr_q;
    end
  end

  // -------------------------------------------------------------------------
  // Master-side responses: master i takes the response of the slave it owns
  // (at most one), or its own decode-error response.
  // -------------------------------------------------------------------------
  generate
    for (gi = 0; gi < NUM_MASTERS; gi++) begin : gen_resp
      logic [NUM_SLAVES-1:0] owns;                  // owns[j] = master i holds slave j
      logic [DATA_W-1:0]     rdata_acc [NUM_SLAVES+1]; // rdata_acc[j] = OR of slaves < j

      assign rdata_acc[0] = '0;
      for (gj = 0; gj < NUM_SLAVES; gj++) begin : gen_s
        assign owns[gj]        = gnt[gj][gi];
        assign rdata_acc[gj+1] = rdata_acc[gj] |
                                 ({DATA_W{owns[gj]}} & slv_rdata[gj*DATA_W+:DATA_W]);
      end

      assign mst_done[gi]                = derr_q[gi] | (|(owns & slv_done));
      assign mst_err[gi]                 = derr_q[gi] | (|(owns & slv_err));
      assign mst_rdata[gi*DATA_W+:DATA_W] = rdata_acc[NUM_SLAVES];
    end
  endgenerate

endmodule : bus_matrix_core
