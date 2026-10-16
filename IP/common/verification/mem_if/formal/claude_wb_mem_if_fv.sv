// claude_wb_mem_if_fv.sv — Formal harness for claude_wb_mem_if (bound into it).
//
// Every port is an input (bind-friendly, SV and VHDL). The solver plays a
// legal Wishbone B4 classic master (claude_wb_fv, MASTER_IS_ENV=1) and a
// legal memory (claude_mem_fv); the adapter must obey both protocols and map
// every Wishbone transfer to exactly one memory request with the same fields
// (claude_mem_xfer_fv).
//
// Parameters are literals matching the RTL defaults: an SV bind cannot see
// VHDL generics.

module claude_wb_mem_if_fv #(
  parameter int unsigned DATA_W   = 32,
  parameter int unsigned ADDR_W   = 32,
  parameter int unsigned MEM_WAIT = 2    // memory grant / response bound
) (
  input  logic                  CLK_I,
  input  logic                  RST_I,
  input  logic                  CYC_I,
  input  logic                  STB_I,
  input  logic                  WE_I,
  input  logic [ADDR_W-1:0]     ADR_I,
  input  logic [DATA_W-1:0]     DAT_I,
  input  logic [DATA_W/8-1:0]   SEL_I,
  input  logic [DATA_W-1:0]     DAT_O,
  input  logic                  ACK_O,
  input  logic                  ERR_O,
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

  logic req;
  logic bus_done;

  assign req      = CYC_I & STB_I;
  assign bus_done = req & (ACK_O | ERR_O);

  // Observer outputs of the bus checker are not needed here.
  logic                obs_wr_vld, obs_wr_busy, obs_rd_req, obs_rd_vld;
  logic [ObsW-1:0]     obs_wr_addr, obs_rd_addr;
  logic [DATA_W-1:0]   obs_wr_data, obs_rd_data;
  logic [DATA_W/8-1:0] obs_wr_strb;
  logic                mem_outstanding;

  claude_wb_fv #(
    .DATA_W       (DATA_W),
    .ADDR_W       (ObsW),
    .ADR_W        (ADDR_W),
    .MASTER_IS_ENV(1'b1)
  ) u_bus (
    .CLK_I      (CLK_I),
    .RST_I      (RST_I),
    .CYC_I      (CYC_I),
    .STB_I      (STB_I),
    .WE_I       (WE_I),
    .ADR_I      (ADR_I),
    .DAT_I      (DAT_I),
    .SEL_I      (SEL_I),
    .DAT_O      (DAT_O),
    .ACK_O      (ACK_O),
    .ERR_O      (ERR_O),
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
    .clk        (CLK_I),
    .rst        (RST_I),
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
    .clk       (CLK_I),
    .rst       (RST_I),
    .mem_req   (mem_req_o),
    .mem_gnt   (mem_gnt_i),
    .mem_we    (mem_we_o),
    .mem_addr  (mem_addr_o),
    .mem_be    (mem_be_o),
    .mem_wdata (mem_wdata_o),
    .mem_rvalid(mem_rvalid_i),
    .mem_rdata (mem_rdata_i),
    .mem_err   (mem_err_i),
    .bus_busy  (req),
    .bus_done  (bus_done),
    .bus_we    (WE_I),
    .bus_addr  (ADR_I),
    .bus_be    (SEL_I),
    .bus_wdata (DAT_I),
    .bus_rdata (DAT_O),
    .bus_err   (ERR_O)
  );

  default clocking cb @(posedge CLK_I); endclocking
  default disable iff (RST_I);

  // Fastest termination: ACK one cycle after the first STB cycle.
  c_ack_next_cycle: cover property ((req && !$past(req)) ##1 ACK_O);

endmodule : claude_wb_mem_if_fv
