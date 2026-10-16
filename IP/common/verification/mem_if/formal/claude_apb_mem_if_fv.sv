// claude_apb_mem_if_fv.sv — Formal harness for claude_apb_mem_if (bound into it).
//
// Every port is an input (bind-friendly, SV and VHDL). The solver plays a
// legal APB4 master (claude_apb_fv, MASTER_IS_ENV=1) and a legal memory
// (claude_mem_fv, INITIATOR_IS_DUT=1); the adapter must obey both protocols
// and map every APB transfer to exactly one memory request with the same
// fields (claude_mem_xfer_fv).
//
// Parameters are literals matching the RTL defaults: an SV bind cannot see
// VHDL generics.

module claude_apb_mem_if_fv #(
  parameter int unsigned DATA_W   = 32,
  parameter int unsigned ADDR_W   = 32,
  parameter int unsigned MEM_WAIT = 2    // memory grant / response bound
) (
  input  logic                  PCLK,
  input  logic                  PRESETn,
  input  logic                  PSEL,
  input  logic                  PENABLE,
  input  logic [ADDR_W-1:0]     PADDR,
  input  logic                  PWRITE,
  input  logic [DATA_W-1:0]     PWDATA,
  input  logic [DATA_W/8-1:0]   PSTRB,
  input  logic [DATA_W-1:0]     PRDATA,
  input  logic                  PREADY,
  input  logic                  PSLVERR,
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

  logic                rst;
  logic                bus_done;
  logic [DATA_W/8-1:0] bus_be;

  assign rst      = ~PRESETn;
  assign bus_done = PSEL & PENABLE & PREADY;
  assign bus_be   = PWRITE ? PSTRB : {(DATA_W/8){1'b1}};

  // Observer outputs of the bus checker are not needed here.
  logic                obs_wr_vld, obs_wr_busy, obs_rd_req, obs_rd_vld;
  logic [ObsW-1:0]     obs_wr_addr, obs_rd_addr;
  logic [DATA_W-1:0]   obs_wr_data, obs_rd_data;
  logic [DATA_W/8-1:0] obs_wr_strb;
  logic                mem_outstanding;

  claude_apb_fv #(
    .DATA_W       (DATA_W),
    .ADDR_W       (ObsW),
    .PADDR_W      (ADDR_W),
    .MASTER_IS_ENV(1'b1)
  ) u_bus (
    .PCLK       (PCLK),
    .PRESETn    (PRESETn),
    .PSEL       (PSEL),
    .PENABLE    (PENABLE),
    .PADDR      (PADDR),
    .PWRITE     (PWRITE),
    .PWDATA     (PWDATA),
    .PSTRB      (PSTRB),
    .PRDATA     (PRDATA),
    .PREADY     (PREADY),
    .PSLVERR    (PSLVERR),
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
    .clk        (PCLK),
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
    .clk       (PCLK),
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
    .bus_busy  (PSEL),
    .bus_done  (bus_done),
    .bus_we    (PWRITE),
    .bus_addr  (PADDR),
    .bus_be    (bus_be),
    .bus_wdata (PWDATA),
    .bus_rdata (PRDATA),
    .bus_err   (PSLVERR)
  );

  default clocking cb @(posedge PCLK); endclocking
  default disable iff (rst);

  // Zero-wait transfer against a memory that answers at once.
  c_zero_wait: cover property ((PSEL && !PENABLE) ##1 (PENABLE && PREADY));
  // PSLVERR is only ever driven in a completing ACCESS cycle.
  a_slverr_only_on_ready: assert property (PSLVERR |-> PREADY);

endmodule : claude_apb_mem_if_fv
