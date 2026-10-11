// bus_matrix_props.sv — SymbiYosys harness for bus_matrix_core (standard hosts).
//
// Yosys-compatible: immediate assert/assume/cover in always @(posedge clk).
// The harness's inputs are free, so the solver plays every master and slave.
// It checks the core of the default configuration (2 masters, the 4-slave
// bus_matrix_pkg address map) in either arbitration mode (ARB_MODE, set per
// task in bus_matrix_core.sby). The same properties are proven unbounded on
// csun.edu with VC Formal (verification/formal/vcf/bus_matrix_core_fv.sv,
// bus_matrix_arb_fv.sv); this is the bounded, open-source equivalent.
//
// Environment (assumed):
//   E1  a master holds mst_req and its request fields until mst_done
//   E2  a slave completes (slv_done) only while it is requested (slv_req)
// Properties (asserted):
//   P1  mst_done[i] only while mst_req[i]
//   P2  a request that matches no slave is answered, with an error, next cycle
//   P3  slv_req[j] carries the fields of a requesting master that addressed j
//   P4  every slave completion is returned to such a master with its data/err
//   P5  a slave's request fields are stable until it completes
//   P6  a slave never sees two consecutive transactions (idle cycle between grants)

module bus_matrix_props #(
  parameter ARB_MODE = 1
) (
  input wire        clk,
  input wire        rst_n,
  input wire [1:0]  mst_req,
  input wire [63:0] mst_addr,
  input wire [63:0] mst_wdata,
  input wire [1:0]  mst_we,
  input wire [7:0]  mst_be,
  input wire [3:0]  slv_done,
  input wire [127:0] slv_rdata,
  input wire [3:0]  slv_err
);

  localparam NM = 2;
  localparam NS = 4;
  localparam [NS*32-1:0] S_BASE = {32'h6000_0000, 32'h4000_0000, 32'h2000_0000, 32'h0000_0000};
  localparam [NS*32-1:0] S_MASK = {32'hF000_0000, 32'hFFFF_0000, 32'hFFFE_0000, 32'hFFFF_0000};

  wire [NM-1:0]    mst_done;
  wire [NM*32-1:0] mst_rdata;
  wire [NM-1:0]    mst_err;
  wire [NS-1:0]    slv_req;
  wire [NS*32-1:0] slv_addr;
  wire [NS*32-1:0] slv_wdata;
  wire [NS-1:0]    slv_we;
  wire [NS*4-1:0]  slv_be;

  bus_matrix_core #(
    .NUM_MASTERS (NM),
    .NUM_SLAVES  (NS),
    .DATA_W      (32),
    .ADDR_W      (32),
    .ARB_MODE    (ARB_MODE),
    .M_PRIORITY  (8'h10),
    .S_BASE      (S_BASE),
    .S_MASK      (S_MASK)
  ) u_dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .mst_req   (mst_req),
    .mst_addr  (mst_addr),
    .mst_wdata (mst_wdata),
    .mst_we    (mst_we),
    .mst_be    (mst_be),
    .mst_done  (mst_done),
    .mst_rdata (mst_rdata),
    .mst_err   (mst_err),
    .slv_req   (slv_req),
    .slv_addr  (slv_addr),
    .slv_wdata (slv_wdata),
    .slv_we    (slv_we),
    .slv_be    (slv_be),
    .slv_done  (slv_done),
    .slv_rdata (slv_rdata),
    .slv_err   (slv_err)
  );

  // Address decode restated from the map (lowest matching slave wins).
  function [NS-1:0] decode;
    input [31:0] a;
    integer j;
    begin
      decode = 0;
      for (j = NS - 1; j >= 0; j = j - 1)
        if ((a & S_MASK[j*32+:32]) == (S_BASE[j*32+:32] & S_MASK[j*32+:32]))
          decode = (1 << j);
    end
  endfunction

  wire [NS-1:0] sel0 = decode(mst_addr[31:0]);
  wire [NS-1:0] sel1 = decode(mst_addr[63:32]);

  // Slave j carries master i's request fields.
  function same;
    input integer j;
    input integer i;
    begin
      same = (slv_addr[j*32+:32]  == mst_addr[i*32+:32]) &&
             (slv_wdata[j*32+:32] == mst_wdata[i*32+:32]) &&
             (slv_we[j]           == mst_we[i]) &&
             (slv_be[j*4+:4]      == mst_be[i*4+:4]);
    end
  endfunction

  reg        f_past_valid = 1'b0;
  reg [1:0]  req_q, done_q;
  reg [63:0] addr_q, wdata_q;
  reg [1:0]  we_q;
  reg [7:0]  be_q;
  reg [3:0]  sreq_q, sdone_q;
  reg [NS*32-1:0] saddr_q, swdata_q;
  reg [NS-1:0]    swe_q;
  reg [NS*4-1:0]  sbe_q;
  reg [1:0]  decerr_pend_q;

  always @(posedge clk) begin
    f_past_valid  <= 1'b1;
    req_q         <= mst_req;
    done_q        <= mst_done;
    addr_q        <= mst_addr;
    wdata_q       <= mst_wdata;
    we_q          <= mst_we;
    be_q          <= mst_be;
    sreq_q        <= slv_req;
    sdone_q       <= slv_done;
    saddr_q       <= slv_addr;
    swdata_q      <= slv_wdata;
    swe_q         <= slv_we;
    sbe_q         <= slv_be;
    decerr_pend_q <= mst_req & ~mst_done & {(sel1 == 0), (sel0 == 0)};
  end

  // Reset in the first cycle.
  always @(*) if (!f_past_valid) assume (!rst_n);

  integer i, j;
  always @(posedge clk) begin
    if (f_past_valid && rst_n) begin
      // E1: masters hold request and fields until done
      for (i = 0; i < NM; i = i + 1)
        if (req_q[i] && !done_q[i])
          assume (mst_req[i] &&
                  mst_addr[i*32+:32]  == addr_q[i*32+:32] &&
                  mst_wdata[i*32+:32] == wdata_q[i*32+:32] &&
                  mst_we[i] == we_q[i] && mst_be[i*4+:4] == be_q[i*4+:4]);
    end
    // E2: slaves complete only while requested
    for (j = 0; j < NS; j = j + 1)
      if (!slv_req[j]) assume (!slv_done[j]);
  end

  always @(posedge clk) begin
    if (f_past_valid && rst_n) begin
      // P1
      for (i = 0; i < NM; i = i + 1)
        if (mst_done[i]) assert (mst_req[i]);

      // P2
      for (i = 0; i < NM; i = i + 1)
        if (decerr_pend_q[i] && $past(rst_n)) assert (mst_done[i] && mst_err[i]);

      for (j = 0; j < NS; j = j + 1) begin
        // P3
        if (slv_req[j])
          assert ((mst_req[0] && sel0[j] && same(j, 0)) ||
                  (mst_req[1] && sel1[j] && same(j, 1)));
        // P4
        if (slv_req[j] && slv_done[j])
          assert ((mst_req[0] && sel0[j] && same(j, 0) && mst_done[0] &&
                   mst_rdata[31:0] == slv_rdata[j*32+:32] && mst_err[0] == slv_err[j]) ||
                  (mst_req[1] && sel1[j] && same(j, 1) && mst_done[1] &&
                   mst_rdata[63:32] == slv_rdata[j*32+:32] && mst_err[1] == slv_err[j]));
        // P5
        if (sreq_q[j] && !sdone_q[j] && $past(rst_n))
          assert (slv_req[j] &&
                  slv_addr[j*32+:32]  == saddr_q[j*32+:32] &&
                  slv_wdata[j*32+:32] == swdata_q[j*32+:32] &&
                  slv_we[j] == swe_q[j] && slv_be[j*4+:4] == sbe_q[j*4+:4]);
        // P6
        if (sreq_q[j] && sdone_q[j] && $past(rst_n))
          assert (!slv_req[j]);
      end

      // Reachability
      cover (slv_req[0] && slv_done[0]);
      cover (slv_req[3] && slv_done[3]);
      cover (mst_done[0] && mst_err[0] && sel0 == 0);
      cover (slv_done[1] && slv_done[2]);                      // two slaves in parallel
      cover (mst_req[0] && mst_req[1] && sel0 == sel1 && sel0 != 0); // contention
    end
  end

endmodule
