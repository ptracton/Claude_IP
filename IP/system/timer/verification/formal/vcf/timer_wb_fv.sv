// timer_wb_fv.sv — VC Formal top-level checker for timer_wb (SV and VHDL).
//
// Combines the common Wishbone B4 protocol checker/observer with the
// protocol-neutral timer register-map checker. Bound to timer_wb by
// timer_wb_fv_bind.

module timer_wb_fv #(
  parameter int unsigned DATA_W = 32,
  parameter int unsigned ADDR_W = 4
) (
  input  logic                  CLK_I,
  input  logic                  RST_I,
  input  logic                  CYC_I,
  input  logic                  STB_I,
  input  logic                  WE_I,
  input  logic [11:0]           ADR_I,
  input  logic [DATA_W-1:0]     DAT_I,
  input  logic [DATA_W/8-1:0]   SEL_I,
  input  logic [DATA_W-1:0]     DAT_O,
  input  logic                  ACK_O,
  input  logic                  ERR_O,
  input  logic                  irq,
  input  logic                  trigger_out
);

  logic                obs_wr_vld, obs_wr_busy, obs_rd_req, obs_rd_vld;
  logic [ADDR_W-1:0]   obs_wr_addr, obs_rd_addr;
  logic [DATA_W-1:0]   obs_wr_data, obs_rd_data;
  logic [DATA_W/8-1:0] obs_wr_strb;

  claude_wb_fv #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_bus (
    .CLK_I, .RST_I, .CYC_I, .STB_I, .WE_I, .ADR_I, .DAT_I, .SEL_I, .DAT_O, .ACK_O, .ERR_O,
    .obs_wr_vld, .obs_wr_addr, .obs_wr_data, .obs_wr_strb, .obs_wr_busy,
    .obs_rd_req, .obs_rd_vld, .obs_rd_addr, .obs_rd_data
  );

  timer_regmap_fv #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) u_regmap (
    .clk(CLK_I), .rst_n(!RST_I),
    .obs_wr_vld, .obs_wr_addr, .obs_wr_data, .obs_wr_strb, .obs_wr_busy,
    .obs_rd_req, .obs_rd_vld, .obs_rd_addr, .obs_rd_data
  );

  default clocking cb @(posedge CLK_I); endclocking
  // The timer never signals an error.
  p_no_err: assert property (disable iff (RST_I) !ERR_O);

endmodule : timer_wb_fv
