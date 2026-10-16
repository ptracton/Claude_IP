// claude_ahb_mem_if_fv.sv — Formal harness for claude_ahb_mem_if (bound into it).
//
// Every port is an input (bind-friendly, SV and VHDL). The solver plays a
// legal AHB-Lite master issuing any mix of NONSEQ/SEQ/BUSY/IDLE transfers of
// any legal size (claude_ahb_fv with SINGLE_ONLY=0, plus the size/alignment
// rules below) and a legal memory (claude_mem_fv). The adapter must obey both
// protocols and map every AHB transfer to exactly one memory request with the
// same fields (claude_mem_xfer_fv); the expected byte lanes are computed here
// independently of the RTL.
//
// Single-slave system: the bus HREADY is this slave's HREADYOUT (assumed).
//
// Parameters are literals matching the RTL defaults: an SV bind cannot see
// VHDL generics.

module claude_ahb_mem_if_fv #(
  parameter int unsigned DATA_W   = 32,
  parameter int unsigned ADDR_W   = 32,
  parameter int unsigned MEM_WAIT = 2    // memory grant / response bound
) (
  input  logic                  HCLK,
  input  logic                  HRESETn,
  input  logic                  HSEL,
  input  logic [ADDR_W-1:0]     HADDR,
  input  logic [1:0]            HTRANS,
  input  logic                  HWRITE,
  input  logic [2:0]            HSIZE,
  input  logic [DATA_W-1:0]     HWDATA,
  input  logic [DATA_W/8-1:0]   HWSTRB,
  input  logic                  HREADY,
  input  logic [DATA_W-1:0]     HRDATA,
  input  logic                  HREADYOUT,
  input  logic                  HRESP,
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

  localparam int unsigned ObsW    = 4;               // observer word-address width (unused)
  localparam int unsigned StrbW   = DATA_W / 8;
  localparam int unsigned MaxSize = $clog2(StrbW);   // largest legal HSIZE

  localparam logic [1:0] HTRANS_BUSY = 2'b01;
  localparam logic [1:0] HTRANS_SEQ  = 2'b11;

  logic rst;
  assign rst = ~HRESETn;

  default clocking cb @(posedge HCLK); endclocking
  default disable iff (rst);

  // -------------------------------------------------------------------------
  // Environment: single slave, legal sizes, aligned addresses.
  // -------------------------------------------------------------------------
  logic aphase;
  assign aphase = HSEL & HTRANS[1];

  m_single_slave: assume property (HREADY == HREADYOUT);
  m_size_legal:   assume property (aphase |-> (HSIZE <= 3'(MaxSize)));
  m_addr_aligned: assume property (aphase |->
                    ((HADDR & ((ADDR_W'(1) << HSIZE) - ADDR_W'(1))) == '0));

  // -------------------------------------------------------------------------
  // Reference data phase, with byte lanes computed independently:
  // ((1 << 2**size) - 1) shifted to the byte offset.
  // -------------------------------------------------------------------------
  logic                dvalid_q;
  logic                dwrite_q;
  logic [ADDR_W-1:0]   daddr_q;
  logic [StrbW-1:0]    dlanes_q;
  logic [StrbW-1:0]    lanes;
  logic [StrbW-1:0]    bus_be;
  logic                bus_done;

  always_comb begin
    logic [2*StrbW-1:0] ones;
    ones  = (2*StrbW)'((64'd1 << (64'd1 << HSIZE)) - 64'd1);
    lanes = StrbW'(ones << (HADDR % StrbW));
  end

  always_ff @(posedge HCLK) begin
    if (rst) begin
      dvalid_q <= 1'b0;
      dwrite_q <= 1'b0;
      daddr_q  <= '0;
      dlanes_q <= '0;
    end else if (HREADY) begin
      dvalid_q <= aphase;
      dwrite_q <= HWRITE;
      daddr_q  <= HADDR;
      dlanes_q <= lanes;
    end
  end

  assign bus_done = dvalid_q & HREADY;
  assign bus_be   = dwrite_q ? (dlanes_q & HWSTRB) : dlanes_q;

  // -------------------------------------------------------------------------
  // Checkers
  // -------------------------------------------------------------------------
  logic                obs_wr_vld, obs_wr_busy, obs_rd_req, obs_rd_vld;
  logic [ObsW-1:0]     obs_wr_addr, obs_rd_addr;
  logic [DATA_W-1:0]   obs_wr_data, obs_rd_data;
  logic [DATA_W/8-1:0] obs_wr_strb;
  logic                mem_outstanding;

  // The bus checker sees the bus HREADY, which is HREADYOUT here.
  claude_ahb_fv #(
    .DATA_W       (DATA_W),
    .ADDR_W       (ObsW),
    .HADDR_W      (ADDR_W),
    .MASTER_IS_ENV(1'b1),
    .SINGLE_ONLY  (1'b0)
  ) u_bus (
    .HCLK       (HCLK),
    .HRESETn    (HRESETn),
    .HSEL       (HSEL),
    .HADDR      (HADDR),
    .HTRANS     (HTRANS),
    .HWRITE     (HWRITE),
    .HWDATA     (HWDATA),
    .HWSTRB     (HWSTRB),
    .HRDATA     (HRDATA),
    .HREADY     (HREADYOUT),
    .HRESP      (HRESP),
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
    .clk        (HCLK),
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
    .ADDR_W(ADDR_W)
  ) u_xfer (
    .clk       (HCLK),
    .rst       (rst),
    .mem_req   (mem_req_o),
    .mem_gnt   (mem_gnt_i),
    .mem_we    (mem_we_o),
    .mem_addr  (mem_addr_o),
    .mem_be    (mem_be_o),
    .mem_wdata (mem_wdata_o),
    .mem_rvalid(mem_rvalid_i),
    .mem_rdata (mem_rdata_i),
    .mem_err   (mem_err_i),
    .bus_busy  (dvalid_q),
    .bus_done  (bus_done),
    .bus_we    (dwrite_q),
    .bus_addr  (daddr_q),
    .bus_be    (bus_be),
    .bus_wdata (HWDATA),
    .bus_rdata (HRDATA),
    .bus_err   (HRESP)
  );

  // -------------------------------------------------------------------------
  // Bursts and narrow transfers are reachable.
  // -------------------------------------------------------------------------
  c_seq_beat:     cover property (aphase && HREADY && HTRANS == HTRANS_SEQ);
  c_busy_in_burst: cover property (HSEL && HTRANS == HTRANS_BUSY ##1
                                   (aphase && HTRANS == HTRANS_SEQ && HREADY));
  c_byte_write:   cover property (bus_done && dwrite_q && $countones(dlanes_q) == 1);
  c_half_read:    cover property (bus_done && !dwrite_q && $countones(dlanes_q) == 2);
  c_err_then_seq: cover property (HRESP && HREADY ##1 (aphase && HTRANS == HTRANS_SEQ));

endmodule : claude_ahb_mem_if_fv
