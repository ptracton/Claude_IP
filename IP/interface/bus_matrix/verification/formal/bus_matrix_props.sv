// bus_matrix_props.sv — Formal property module for bus_matrix_core verification.
//
// Yosys-compatible. Uses always @(posedge clk) with assert/assume/cover
// for SymbiYosys bounded model checking.
//
// Properties verified (hold for registered-grant crossbar):
//   P1_ONE_HOT       : At most one master granted at a time (mst_gnt one-hot)
//   P5_DECODE_ONEHOT : slv_req is zero or one-hot (single slave per cycle)
//   P7_SLV_REQ_ONEHOT: when any slave is requested, at most one master granted

module bus_matrix_props #(
  parameter NUM_MASTERS = 2,
  parameter NUM_SLAVES  = 2,
  parameter DATA_W      = 32,
  parameter ADDR_W      = 32,
  parameter ARB_MODE    = 0,
  parameter [NUM_MASTERS*4-1:0]  M_PRIORITY = {NUM_MASTERS*4{1'b0}},
  parameter [NUM_SLAVES*32-1:0]  S_BASE     = {NUM_SLAVES*32{1'b0}},
  parameter [NUM_SLAVES*32-1:0]  S_MASK     = {NUM_SLAVES*32{1'b0}}
) (
  input wire clk,
  input wire rst_n,

  // Master-side inputs
  input wire [NUM_MASTERS-1:0]          mst_req,
  input wire [NUM_MASTERS*ADDR_W-1:0]   mst_addr,
  input wire [NUM_MASTERS*DATA_W-1:0]   mst_wdata,
  input wire [NUM_MASTERS-1:0]          mst_we,
  input wire [NUM_MASTERS*4-1:0]        mst_be,

  // Slave-side inputs (responses from slave)
  input wire [NUM_SLAVES-1:0]           slv_gnt,
  input wire [NUM_SLAVES*DATA_W-1:0]    slv_rdata,
  input wire [NUM_SLAVES-1:0]           slv_rvalid
);

  // DUT outputs (driven by bus_matrix_core)
  wire [NUM_MASTERS-1:0]         mst_gnt;
  wire [NUM_MASTERS*DATA_W-1:0]  mst_rdata;
  wire [NUM_MASTERS-1:0]         mst_rvalid_out;
  wire [NUM_MASTERS-1:0]         mst_err;
  wire [NUM_SLAVES-1:0]          slv_req;
  wire [NUM_SLAVES*ADDR_W-1:0]   slv_addr;
  wire [NUM_SLAVES*DATA_W-1:0]   slv_wdata_out;
  wire [NUM_SLAVES-1:0]          slv_we_out;
  wire [NUM_SLAVES*4-1:0]        slv_be_out;

  // -------------------------------------------------------------------------
  // DUT instantiation
  // -------------------------------------------------------------------------
  bus_matrix_core #(
    .NUM_MASTERS (NUM_MASTERS),
    .NUM_SLAVES  (NUM_SLAVES),
    .DATA_W      (DATA_W),
    .ADDR_W      (ADDR_W),
    .ARB_MODE    (ARB_MODE),
    .M_PRIORITY  (M_PRIORITY),
    .S_BASE      (S_BASE),
    .S_MASK      (S_MASK)
  ) u_dut (
    .clk        (clk),
    .rst_n      (rst_n),
    .mst_req    (mst_req),
    .mst_addr   (mst_addr),
    .mst_wdata  (mst_wdata),
    .mst_we     (mst_we),
    .mst_be     (mst_be),
    .mst_gnt    (mst_gnt),
    .mst_rdata  (mst_rdata),
    .mst_rvalid (mst_rvalid_out),
    .mst_err    (mst_err),
    .slv_req    (slv_req),
    .slv_addr   (slv_addr),
    .slv_wdata  (slv_wdata_out),
    .slv_we     (slv_we_out),
    .slv_be     (slv_be_out),
    .slv_gnt    (slv_gnt),
    .slv_rdata  (slv_rdata),
    .slv_rvalid (slv_rvalid)
  );

  // -------------------------------------------------------------------------
  // Helper wires: one-hot or zero check (x & (x-1) == 0)
  // -------------------------------------------------------------------------
  wire onehot_mst_gnt = (mst_gnt & (mst_gnt - 1)) == 0;
  wire onehot_slv_req = (slv_req & (slv_req - 1)) == 0;

  // -------------------------------------------------------------------------
  // Reset assumption: rst_n low on first cycle, then stays high
  // -------------------------------------------------------------------------
  reg f_past_valid;
  initial f_past_valid = 1'b0;
  always @(posedge clk) f_past_valid <= 1'b1;

  always @(posedge clk) begin
    if (!f_past_valid)
      assume (!rst_n);
    else
      assume (rst_n);
  end

  // -------------------------------------------------------------------------
  // Assume constraints: slave grant only when requested
  // -------------------------------------------------------------------------
  generate
    genvar gi;
    for (gi = 0; gi < NUM_SLAVES; gi = gi + 1) begin : gen_assume_slv_gnt
      always @(posedge clk) begin
        if (rst_n) begin
          assume (!(slv_gnt[gi]) || slv_req[gi]);
        end
      end
    end
  endgenerate

  // =========================================================================
  // P1 — At most one master granted (mst_gnt one-hot or zero)
  // =========================================================================
  always @(posedge clk) begin
    if (f_past_valid && rst_n) begin
      P1_ONE_HOT: assert (onehot_mst_gnt);
    end
  end

  // =========================================================================
  // P5 — Decode one-hot: slv_req is zero or one-hot (one slave per cycle)
  // =========================================================================
  always @(posedge clk) begin
    if (f_past_valid && rst_n) begin
      P5_DECODE_ONEHOT: assert (onehot_slv_req);
    end
  end

  // =========================================================================
  // P7 — When any slave is requested, at most one master is granted
  // =========================================================================
  always @(posedge clk) begin
    if (f_past_valid && rst_n) begin
      P7_SLV_REQ_ONEHOT: assert (!(|slv_req) || onehot_mst_gnt);
    end
  end

  // =========================================================================
  // Cover points — verify interesting scenarios are reachable
  // =========================================================================
  always @(posedge clk) begin
    if (f_past_valid && rst_n) begin
      COV_MST0_GRANTED:      cover (mst_gnt[0] && mst_req[0]);
      COV_MST1_GRANTED:      cover (mst_gnt[1] && mst_req[1]);
      COV_CONTENTION:        cover (mst_req[0] && mst_req[1]);
      COV_DECODE_ERROR:      cover (|mst_err && |mst_req);
      COV_SLV0_TXN_COMPLETE: cover (slv_req[0] && slv_gnt[0]);
      COV_SLV1_TXN_COMPLETE: cover (slv_req[1] && slv_gnt[1]);
    end
  end

endmodule
