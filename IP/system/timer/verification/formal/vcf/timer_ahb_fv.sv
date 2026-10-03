// timer_ahb_fv.sv — VC Formal top-level checker for timer_ahb (SV and VHDL).
//
// Combines the common AHB-Lite protocol checker/observer with the
// protocol-neutral timer register-map checker. Bound to timer_ahb by
// timer_ahb_fv_bind.

module timer_ahb_fv #(
  parameter int unsigned DATA_W = 32,
  parameter int unsigned ADDR_W = 4
) (
  input  logic                  HCLK,
  input  logic                  HRESETn,
  input  logic                  HSEL,
  input  logic [11:0]           HADDR,
  input  logic [1:0]            HTRANS,
  input  logic                  HWRITE,
  input  logic [DATA_W-1:0]     HWDATA,
  input  logic [DATA_W/8-1:0]   HWSTRB,
  input  logic [DATA_W-1:0]     HRDATA,
  input  logic                  HREADY,
  input  logic                  HRESP,
  input  logic                  irq,
  input  logic                  trigger_out
);

  logic                obs_wr_vld, obs_wr_busy, obs_rd_req, obs_rd_vld;
  logic [ADDR_W-1:0]   obs_wr_addr, obs_rd_addr;
  logic [DATA_W-1:0]   obs_wr_data, obs_rd_data;
  logic [DATA_W/8-1:0] obs_wr_strb;

  claude_ahb_fv #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_bus (
    .HCLK, .HRESETn, .HSEL, .HADDR, .HTRANS, .HWRITE, .HWDATA, .HWSTRB, .HRDATA, .HREADY, .HRESP,
    .obs_wr_vld, .obs_wr_addr, .obs_wr_data, .obs_wr_strb, .obs_wr_busy,
    .obs_rd_req, .obs_rd_vld, .obs_rd_addr, .obs_rd_data
  );

  timer_regmap_fv #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_regmap (
    .clk(HCLK), .rst_n(HRESETn),
    .obs_wr_vld, .obs_wr_addr, .obs_wr_data, .obs_wr_strb, .obs_wr_busy,
    .obs_rd_req, .obs_rd_vld, .obs_rd_addr, .obs_rd_data
  );

  default clocking cb @(posedge HCLK); endclocking
  // The timer never signals an error response.
  p_no_error: assert property (disable iff (!HRESETn) !HRESP);

endmodule : timer_ahb_fv
