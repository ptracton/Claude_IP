// bus_matrix_core.sv — Bus Matrix protocol-agnostic crossbar core.
//
// Routes transactions from NUM_MASTERS master ports to NUM_SLAVES slave ports.
// Instantiates one bus_matrix_decoder per master and one bus_matrix_arb per slave.
// All bus sizing is determined by NUM_MASTERS and NUM_SLAVES parameters.
// No runtime registers: address map and arbitration are fully parameterised.

module bus_matrix_core #(
  parameter int NUM_MASTERS = 2,                             // 1-16 active masters
  parameter int NUM_SLAVES  = 2,                             // 1-32 active slaves
  parameter int DATA_W      = 32,                            // data bus width
  parameter int ADDR_W      = 32,                            // address width
  parameter int ARB_MODE    = 0,                             // 0=fixed-priority, 1=round-robin
  parameter logic [NUM_MASTERS*4-1:0]  M_PRIORITY = '0,     // master i priority at [i*4+:4]
  parameter logic [NUM_SLAVES*32-1:0]  S_BASE     = '0,     // slave j base addr at [j*32+:32]
  parameter logic [NUM_SLAVES*32-1:0]  S_MASK     = '0      // slave j addr mask at [j*32+:32]
) (
  input  logic                            clk,       // system clock
  input  logic                            rst_n,     // synchronous active-low reset

  // Master-side internal protocol (flat-packed, NUM_MASTERS slots)
  input  logic [NUM_MASTERS-1:0]          mst_req,    // request from master i at bit i
  input  logic [NUM_MASTERS*ADDR_W-1:0]   mst_addr,   // address from master i
  input  logic [NUM_MASTERS*DATA_W-1:0]   mst_wdata,  // write data from master i
  input  logic [NUM_MASTERS-1:0]          mst_we,     // write enable from master i
  input  logic [NUM_MASTERS*4-1:0]        mst_be,     // byte enables from master i
  output logic [NUM_MASTERS-1:0]          mst_gnt,    // grant to master i
  output logic [NUM_MASTERS*DATA_W-1:0]   mst_rdata,  // read data to master i
  output logic [NUM_MASTERS-1:0]          mst_rvalid, // read data valid for master i
  output logic [NUM_MASTERS-1:0]          mst_err,    // error for master i

  // Slave-side internal protocol (flat-packed, NUM_SLAVES slots)
  output logic [NUM_SLAVES-1:0]           slv_req,    // request to slave j
  output logic [NUM_SLAVES*ADDR_W-1:0]    slv_addr,   // address to slave j
  output logic [NUM_SLAVES*DATA_W-1:0]    slv_wdata,  // write data to slave j
  output logic [NUM_SLAVES-1:0]           slv_we,     // write enable to slave j
  output logic [NUM_SLAVES*4-1:0]         slv_be,     // byte enables to slave j
  input  logic [NUM_SLAVES-1:0]           slv_gnt,    // acknowledge from slave j
  input  logic [NUM_SLAVES*DATA_W-1:0]    slv_rdata,  // read data from slave j
  input  logic [NUM_SLAVES-1:0]           slv_rvalid  // read data valid from slave j
);

  // -------------------------------------------------------------------------
  // Decoder outputs: one decoder instance per master
  // -------------------------------------------------------------------------
  logic [NUM_SLAVES-1:0]  dec_slave_sel [0:NUM_MASTERS-1];
  logic [NUM_MASTERS-1:0] dec_err;

  genvar gi;
  generate
    for (gi = 0; gi < NUM_MASTERS; gi = gi + 1) begin : gen_decoder
      bus_matrix_decoder #(
        .NUM_SLAVES (NUM_SLAVES),
        .ADDR_W     (ADDR_W),
        .S_BASE     (S_BASE),
        .S_MASK     (S_MASK)
      ) u_dec (
        .addr      (mst_addr[gi*ADDR_W+:ADDR_W]),
        .slave_sel (dec_slave_sel[gi]),
        .decode_err(dec_err[gi])
      );
    end
  endgenerate

  // -------------------------------------------------------------------------
  // Per-slave request vectors: which masters are requesting each slave
  // per_slv_req[j][i] = master i requests slave j
  // -------------------------------------------------------------------------
  logic [NUM_MASTERS-1:0] per_slv_req [0:NUM_SLAVES-1];

  always_comb begin : p_per_slv_req
    for (int j = 0; j < NUM_SLAVES; j = j + 1) begin
      per_slv_req[j] = '0;
      for (int i = 0; i < NUM_MASTERS; i = i + 1) begin
        per_slv_req[j][i] = mst_req[i] & dec_slave_sel[i][j];
      end
    end
  end

  // -------------------------------------------------------------------------
  // Arbitration outputs: one arbiter per slave
  // -------------------------------------------------------------------------
  logic [NUM_MASTERS-1:0] arb_gnt [0:NUM_SLAVES-1];
  logic [NUM_SLAVES-1:0]  valid_trx_slv;

  assign valid_trx_slv = slv_req;

  generate
    for (gi = 0; gi < NUM_SLAVES; gi = gi + 1) begin : gen_arb
      bus_matrix_arb #(
        .NUM_MASTERS (NUM_MASTERS),
        .ARB_MODE    (ARB_MODE),
        .M_PRIORITY  (M_PRIORITY)
      ) u_arb (
        .clk      (clk),
        .rst_n    (rst_n),
        .req      (per_slv_req[gi]),
        .valid_trx(valid_trx_slv[gi]),
        .slv_gnt  (slv_gnt[gi]),
        .gnt      (arb_gnt[gi])
      );
    end
  endgenerate

  // -------------------------------------------------------------------------
  // Route master requests to slave ports based on arbitration grants
  // -------------------------------------------------------------------------
  always_comb begin : p_slave_route
    for (int j = 0; j < NUM_SLAVES; j = j + 1) begin
      slv_req[j]                        = 1'b0;
      slv_addr[j*ADDR_W+:ADDR_W]       = {ADDR_W{1'b0}};
      slv_wdata[j*DATA_W+:DATA_W]      = {DATA_W{1'b0}};
      slv_we[j]                         = 1'b0;
      slv_be[j*4+:4]                    = 4'h0;
    end

    for (int j = 0; j < NUM_SLAVES; j = j + 1) begin
      for (int i = 0; i < NUM_MASTERS; i = i + 1) begin
        if (arb_gnt[j][i]) begin
          slv_req[j]                   = 1'b1;
          slv_addr[j*ADDR_W+:ADDR_W]  = mst_addr[i*ADDR_W+:ADDR_W];
          slv_wdata[j*DATA_W+:DATA_W] = mst_wdata[i*DATA_W+:DATA_W];
          slv_we[j]                   = mst_we[i];
          slv_be[j*4+:4]              = mst_be[i*4+:4];
        end
      end
    end
  end

  // -------------------------------------------------------------------------
  // Route slave responses back to masters
  // -------------------------------------------------------------------------
  always_comb begin : p_master_resp
    for (int i = 0; i < NUM_MASTERS; i = i + 1) begin
      mst_gnt[i]                   = 1'b0;
      mst_rdata[i*DATA_W+:DATA_W] = {DATA_W{1'b0}};
      mst_rvalid[i]                = 1'b0;
      mst_err[i]                   = 1'b0;
    end

    // Decode error: immediate error + grant to unblock master
    for (int i = 0; i < NUM_MASTERS; i = i + 1) begin
      if (mst_req[i] && dec_err[i]) begin
        mst_err[i] = 1'b1;
        mst_gnt[i] = 1'b1;
      end
    end

    // Route slave responses to granted masters
    for (int j = 0; j < NUM_SLAVES; j = j + 1) begin
      for (int i = 0; i < NUM_MASTERS; i = i + 1) begin
        if (arb_gnt[j][i]) begin
          mst_gnt[i]                   = slv_gnt[j];
          mst_rdata[i*DATA_W+:DATA_W] = slv_rdata[j*DATA_W+:DATA_W];
          mst_rvalid[i]                = slv_rvalid[j];
        end
      end
    end
  end

endmodule : bus_matrix_core
