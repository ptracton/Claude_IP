// claude_axi4l_mem_if_fv.sv — Formal harness for claude_axi4l_mem_if (bound into it).
//
// Every port is an input (bind-friendly, SV and VHDL). The solver plays a
// legal AXI4-Lite master (claude_axi4l_fv, MASTER_IS_ENV=1: at most one
// write and one read outstanding) and a legal memory (claude_mem_fv). The
// adapter must obey both protocols and map every write and every read to
// exactly one memory request with the same fields.
//
// A write and a read can complete (B and R handshakes) in the same cycle, so
// the end-to-end check uses two claude_mem_xfer_fv instances: one sees only
// write requests and write responses, the other only reads.
//
// Parameters are literals matching the RTL defaults: an SV bind cannot see
// VHDL generics.

module claude_axi4l_mem_if_fv #(
  parameter int unsigned DATA_W   = 32,
  parameter int unsigned ADDR_W   = 32,
  parameter int unsigned MEM_WAIT = 2    // memory grant / response bound
) (
  input  logic                  ACLK,
  input  logic                  ARESETn,
  input  logic                  AWVALID,
  input  logic                  AWREADY,
  input  logic [ADDR_W-1:0]     AWADDR,
  input  logic                  WVALID,
  input  logic                  WREADY,
  input  logic [DATA_W-1:0]     WDATA,
  input  logic [DATA_W/8-1:0]   WSTRB,
  input  logic                  BVALID,
  input  logic                  BREADY,
  input  logic [1:0]            BRESP,
  input  logic                  ARVALID,
  input  logic                  ARREADY,
  input  logic [ADDR_W-1:0]     ARADDR,
  input  logic                  RVALID,
  input  logic                  RREADY,
  input  logic [DATA_W-1:0]     RDATA,
  input  logic [1:0]            RRESP,
  input  logic                  mem_req_o,
  input  logic                  mem_gnt_i,
  input  logic                  mem_we_o,
  input  logic [ADDR_W-1:0]     mem_addr_o,
  input  logic [DATA_W/8-1:0]   mem_be_o,
  input  logic [DATA_W-1:0]     mem_wdata_o,
  input  logic                  mem_rvalid_i,
  input  logic [DATA_W-1:0]     mem_rdata_i,
  input  logic                  mem_err_i
);

  localparam int unsigned ObsW = 4;  // observer word-address width (unused)
  localparam logic [1:0] RESP_OKAY   = 2'b00;
  localparam logic [1:0] RESP_SLVERR = 2'b10;

  logic rst;
  assign rst = ~ARESETn;

  default clocking cb @(posedge ACLK); endclocking
  default disable iff (rst);

  // -------------------------------------------------------------------------
  // Reference model of the bus side: captured AW/W/AR, pending transfers.
  // -------------------------------------------------------------------------
  logic aw_hs, w_hs, ar_hs, b_hs, r_hs;
  assign aw_hs = AWVALID & AWREADY;
  assign w_hs  = WVALID  & WREADY;
  assign ar_hs = ARVALID & ARREADY;
  assign b_hs  = BVALID  & BREADY;
  assign r_hs  = RVALID  & RREADY;

  logic                aw_done_q, w_done_q, ar_done_q;
  logic [ADDR_W-1:0]   aw_addr_q, ar_addr_q;
  logic [DATA_W-1:0]   w_data_q;
  logic [DATA_W/8-1:0] w_strb_q;

  always_ff @(posedge ACLK) begin
    if (rst) begin
      aw_done_q <= 1'b0;
      w_done_q  <= 1'b0;
      ar_done_q <= 1'b0;
      aw_addr_q <= '0;
      ar_addr_q <= '0;
      w_data_q  <= '0;
      w_strb_q  <= '0;
    end else begin
      if (aw_hs) begin
        aw_done_q <= 1'b1;
        aw_addr_q <= AWADDR;
      end else if (b_hs) begin
        aw_done_q <= 1'b0;
      end
      if (w_hs) begin
        w_done_q <= 1'b1;
        w_data_q <= WDATA;
        w_strb_q <= WSTRB;
      end else if (b_hs) begin
        w_done_q <= 1'b0;
      end
      if (ar_hs) begin
        ar_done_q <= 1'b1;
        ar_addr_q <= ARADDR;
      end else if (r_hs) begin
        ar_done_q <= 1'b0;
      end
    end
  end

  // The outstanding memory request is a write (captured at its handshake).
  logic outst_write_q;
  always_ff @(posedge ACLK) begin
    if (rst) begin
      outst_write_q <= 1'b0;
    end else if (mem_req_o && mem_gnt_i) begin
      outst_write_q <= mem_we_o;
    end
  end

  // Per-direction views of the memory bus.
  logic wr_req, rd_req, wr_rvalid, rd_rvalid;
  assign wr_req    = mem_req_o &  mem_we_o;
  assign rd_req    = mem_req_o & ~mem_we_o;
  assign wr_rvalid = mem_rvalid_i &  outst_write_q;
  assign rd_rvalid = mem_rvalid_i & ~outst_write_q;

  // -------------------------------------------------------------------------
  // Checkers
  // -------------------------------------------------------------------------
  logic                obs_wr_vld, obs_wr_busy, obs_rd_req, obs_rd_vld;
  logic [ObsW-1:0]     obs_wr_addr, obs_rd_addr;
  logic [DATA_W-1:0]   obs_wr_data, obs_rd_data;
  logic [DATA_W/8-1:0] obs_wr_strb;
  logic                mem_outstanding;

  claude_axi4l_fv #(
    .DATA_W       (DATA_W),
    .ADDR_W       (ObsW),
    .AXADDR_W     (ADDR_W),
    .MASTER_IS_ENV(1'b1)
  ) u_bus (
    .ACLK       (ACLK),
    .ARESETn    (ARESETn),
    .AWVALID    (AWVALID),
    .AWREADY    (AWREADY),
    .AWADDR     (AWADDR),
    .WVALID     (WVALID),
    .WREADY     (WREADY),
    .WDATA      (WDATA),
    .WSTRB      (WSTRB),
    .BVALID     (BVALID),
    .BREADY     (BREADY),
    .BRESP      (BRESP),
    .ARVALID    (ARVALID),
    .ARREADY    (ARREADY),
    .ARADDR     (ARADDR),
    .RVALID     (RVALID),
    .RREADY     (RREADY),
    .RDATA      (RDATA),
    .RRESP      (RRESP),
    .obs_wr_vld (obs_wr_vld),
    .obs_wr_addr(obs_wr_addr),
    .obs_wr_data(obs_wr_data),
    .obs_wr_strb(obs_wr_strb),
    .obs_wr_busy(obs_wr_busy),
    .obs_rd_req (obs_rd_req),
    .obs_rd_vld (obs_rd_vld),
    .obs_rd_addr(obs_rd_addr),
    .obs_rd_data(obs_rd_data)
  );

  claude_mem_fv #(
    .DATA_W          (DATA_W),
    .ADDR_W          (ADDR_W),
    .INITIATOR_IS_DUT(1'b1),
    .MAX_WAIT        (MEM_WAIT)
  ) u_mem (
    .clk        (ACLK),
    .rst        (rst),
    .mem_req    (mem_req_o),
    .mem_gnt    (mem_gnt_i),
    .mem_we     (mem_we_o),
    .mem_addr   (mem_addr_o),
    .mem_be     (mem_be_o),
    .mem_wdata  (mem_wdata_o),
    .mem_rvalid (mem_rvalid_i),
    .mem_rdata  (mem_rdata_i),
    .mem_err    (mem_err_i),
    .outstanding(mem_outstanding)
  );

  claude_mem_xfer_fv #(
    .DATA_W(DATA_W),
    .ADDR_W(ADDR_W),
    .WRITES(1'b1),
    .READS (1'b0)
  ) u_xfer_wr (
    .clk       (ACLK),
    .rst       (rst),
    .mem_req   (wr_req),
    .mem_gnt   (mem_gnt_i),
    .mem_we    (mem_we_o),
    .mem_addr  (mem_addr_o),
    .mem_be    (mem_be_o),
    .mem_wdata (mem_wdata_o),
    .mem_rvalid(wr_rvalid),
    .mem_rdata (mem_rdata_i),
    .mem_err   (mem_err_i),
    .bus_busy  (aw_done_q && w_done_q && !BVALID),
    .bus_done  (b_hs),
    .bus_we    (1'b1),
    .bus_addr  (aw_addr_q),
    .bus_be    (w_strb_q),
    .bus_wdata (w_data_q),
    .bus_rdata ('0),
    .bus_err   (BRESP == RESP_SLVERR)
  );

  claude_mem_xfer_fv #(
    .DATA_W(DATA_W),
    .ADDR_W(ADDR_W),
    .WRITES(1'b0),
    .READS (1'b1)
  ) u_xfer_rd (
    .clk       (ACLK),
    .rst       (rst),
    .mem_req   (rd_req),
    .mem_gnt   (mem_gnt_i),
    .mem_we    (mem_we_o),
    .mem_addr  (mem_addr_o),
    .mem_be    (mem_be_o),
    .mem_wdata (mem_wdata_o),
    .mem_rvalid(rd_rvalid),
    .mem_rdata (mem_rdata_i),
    .mem_err   (mem_err_i),
    .bus_busy  (ar_done_q && !RVALID),
    .bus_done  (r_hs),
    .bus_we    (1'b0),
    .bus_addr  (ar_addr_q),
    .bus_be    ({(DATA_W/8){1'b1}}),
    .bus_wdata (w_data_q),
    .bus_rdata (RDATA),
    .bus_err   (RRESP == RESP_SLVERR)
  );

  // Only OKAY and SLVERR are ever returned.
  a_bresp_legal: assert property (BVALID |-> (BRESP == RESP_OKAY || BRESP == RESP_SLVERR));
  a_rresp_legal: assert property (RVALID |-> (RRESP == RESP_OKAY || RRESP == RESP_SLVERR));

  // Read and write both pending: both get served (round robin).
  c_rd_wr_contend: cover property (aw_done_q && w_done_q && ar_done_q && !BVALID && !RVALID
                                   ##[1:$] (BVALID && RVALID));
  c_b_r_same_cycle: cover property (b_hs && r_hs);

endmodule : claude_axi4l_mem_if_fv
