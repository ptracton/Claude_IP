// timer_apb_fv.sv — VC Formal top-level checker for timer_apb (SV and VHDL).
//
// Combines the common APB4 protocol checker/observer with the
// protocol-neutral timer register-map checker. Bound to timer_apb by
// timer_apb_fv_bind.

module timer_apb_fv #(
  parameter int unsigned DATA_W = 32,
  parameter int unsigned ADDR_W = 4
) (
  input  logic                PCLK,
  input  logic                PRESETn,
  input  logic                PSEL,
  input  logic                PENABLE,
  input  logic [11:0]         PADDR,
  input  logic                PWRITE,
  input  logic [DATA_W-1:0]   PWDATA,
  input  logic [DATA_W/8-1:0] PSTRB,
  input  logic [DATA_W-1:0]   PRDATA,
  input  logic                PREADY,
  input  logic                PSLVERR,
  input  logic                irq,
  input  logic                trigger_out
);

  logic                obs_wr_vld, obs_wr_busy, obs_rd_req, obs_rd_vld;
  logic [ADDR_W-1:0]   obs_wr_addr, obs_rd_addr;
  logic [DATA_W-1:0]   obs_wr_data, obs_rd_data;
  logic [DATA_W/8-1:0] obs_wr_strb;

  claude_apb_fv #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_bus (
    .PCLK, .PRESETn, .PSEL, .PENABLE, .PADDR, .PWRITE, .PWDATA, .PSTRB,
    .PRDATA, .PREADY, .PSLVERR,
    .obs_wr_vld, .obs_wr_addr, .obs_wr_data, .obs_wr_strb, .obs_wr_busy,
    .obs_rd_req, .obs_rd_vld, .obs_rd_addr, .obs_rd_data
  );

  timer_regmap_fv #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_regmap (
    .clk(PCLK), .rst_n(PRESETn),
    .obs_wr_vld, .obs_wr_addr, .obs_wr_data, .obs_wr_strb, .obs_wr_busy,
    .obs_rd_req, .obs_rd_vld, .obs_rd_addr, .obs_rd_data
  );

  // APB4 slave in this IP never signals an error.
  default clocking cb @(posedge PCLK); endclocking
  p_no_slverr: assert property (disable iff (!PRESETn) !PSLVERR);

endmodule : timer_apb_fv
