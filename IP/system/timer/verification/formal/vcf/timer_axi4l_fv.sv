// timer_axi4l_fv.sv — VC Formal top-level checker for timer_axi4l (SV and VHDL).
//
// Combines the common AXI4-Lite protocol checker/observer with the
// protocol-neutral timer register-map checker. Bound to timer_axi4l by
// timer_axi4l_fv_bind.

module timer_axi4l_fv #(
  parameter int unsigned DATA_W = 32,
  parameter int unsigned ADDR_W = 4
) (
  input  logic                  ACLK,
  input  logic                  ARESETn,
  input  logic                  AWVALID,
  input  logic                  AWREADY,
  input  logic [11:0]           AWADDR,
  input  logic                  WVALID,
  input  logic                  WREADY,
  input  logic [DATA_W-1:0]     WDATA,
  input  logic [DATA_W/8-1:0]   WSTRB,
  input  logic                  BVALID,
  input  logic                  BREADY,
  input  logic [1:0]            BRESP,
  input  logic                  ARVALID,
  input  logic                  ARREADY,
  input  logic [11:0]           ARADDR,
  input  logic                  RVALID,
  input  logic                  RREADY,
  input  logic [DATA_W-1:0]     RDATA,
  input  logic [1:0]            RRESP,
  input  logic                  irq,
  input  logic                  trigger_out
);

  logic                obs_wr_vld, obs_wr_busy, obs_rd_req, obs_rd_vld;
  logic [ADDR_W-1:0]   obs_wr_addr, obs_rd_addr;
  logic [DATA_W-1:0]   obs_wr_data, obs_rd_data;
  logic [DATA_W/8-1:0] obs_wr_strb;

  claude_axi4l_fv #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_bus (
    .ACLK, .ARESETn, .AWVALID, .AWREADY, .AWADDR, .WVALID, .WREADY, .WDATA, .WSTRB, .BVALID, .BREADY, .BRESP, .ARVALID, .ARREADY, .ARADDR, .RVALID, .RREADY, .RDATA, .RRESP,
    .obs_wr_vld, .obs_wr_addr, .obs_wr_data, .obs_wr_strb, .obs_wr_busy,
    .obs_rd_req, .obs_rd_vld, .obs_rd_addr, .obs_rd_data
  );

  timer_regmap_fv #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_regmap (
    .clk(ACLK), .rst_n(ARESETn),
    .obs_wr_vld, .obs_wr_addr, .obs_wr_data, .obs_wr_strb, .obs_wr_busy,
    .obs_rd_req, .obs_rd_vld, .obs_rd_addr, .obs_rd_data
  );

  default clocking cb @(posedge ACLK); endclocking
  // The timer always responds OKAY.
  p_bresp_okay: assert property (disable iff (!ARESETn) BVALID |-> BRESP == 2'b00);
  p_rresp_okay: assert property (disable iff (!ARESETn) RVALID |-> RRESP == 2'b00);

endmodule : timer_axi4l_fv
