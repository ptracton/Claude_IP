// timer_regmap_fv.sv — Protocol-neutral register-map checker for the timer.
//
// Driven by the transaction-observer outputs of any common
// claude_<proto>_fv checker, so the same register-map checks run unchanged
// on the APB, AHB, AXI4-Lite and Wishbone top-levels (SV and VHDL).
//
// Register map (see doc/spec.md):
//   0x00 CTRL    RW  bits 13:0 (RESTART[12] and SNAPSHOT[14] self-clear)
//   0x04 STATUS  hardware-set / W1C — only reserved bits checked here
//   0x08 LOAD    RW  all bits
//   0x0C COUNT   RO  hardware — checked in timer_regfile_fv
//   0x10 CAPTURE RO  hardware — checked in timer_regfile_fv
//   0x14–0x3C    unmapped, read as zero

module timer_regmap_fv #(
  parameter int unsigned DATA_W = 32,
  parameter int unsigned ADDR_W = 4
) (
  input  logic                  clk,
  input  logic                  rst_n,
  input  logic                  obs_wr_vld,
  input  logic [ADDR_W-1:0]     obs_wr_addr,
  input  logic [DATA_W-1:0]     obs_wr_data,
  input  logic [DATA_W/8-1:0]   obs_wr_strb,
  input  logic                  obs_wr_busy,
  input  logic                  obs_rd_req,
  input  logic                  obs_rd_vld,
  input  logic [ADDR_W-1:0]     obs_rd_addr,
  input  logic [DATA_W-1:0]     obs_rd_data
);

  localparam logic [DATA_W-1:0] CTRL_RW_MASK = 32'h0000_2FFF; // excl. RESTART, SNAPSHOT
  localparam logic [DATA_W-1:0] CTRL_ZERO    = 32'hFFFF_8000;
  localparam logic [DATA_W-1:0] STATUS_ZERO  = 32'hFFFF_FFF8;
  localparam int unsigned       NUM_MAPPED   = 5;

  // Same observer connections for every register instance.
  `define TIMER_REG_FV_OBS                                             \
    .clk(clk), .rst_n(rst_n),                                          \
    .obs_wr_vld(obs_wr_vld), .obs_wr_addr(obs_wr_addr),                \
    .obs_wr_data(obs_wr_data), .obs_wr_strb(obs_wr_strb),              \
    .obs_wr_busy(obs_wr_busy), .obs_rd_req(obs_rd_req),                \
    .obs_rd_vld(obs_rd_vld), .obs_rd_addr(obs_rd_addr),                \
    .obs_rd_data(obs_rd_data)

  claude_reg_fv #(
    .DATA_W(DATA_W), .ADDR_W(ADDR_W), .REG_ADDR(4'h0),
    .RESET_VAL('0), .RESET_MASK('1), .RW_MASK(CTRL_RW_MASK), .ZERO_MASK(CTRL_ZERO)
  ) u_ctrl (`TIMER_REG_FV_OBS);

  claude_reg_fv #(
    .DATA_W(DATA_W), .ADDR_W(ADDR_W), .REG_ADDR(4'h1),
    .RESET_VAL('0), .RESET_MASK('0), .RW_MASK('0), .ZERO_MASK(STATUS_ZERO)
  ) u_status (`TIMER_REG_FV_OBS);

  claude_reg_fv #(
    .DATA_W(DATA_W), .ADDR_W(ADDR_W), .REG_ADDR(4'h2),
    .RESET_VAL('0), .RESET_MASK('1), .RW_MASK('1), .ZERO_MASK('0)
  ) u_load (`TIMER_REG_FV_OBS);

  for (genvar a = NUM_MAPPED; a < 2**ADDR_W; a++) begin : g_unmapped
    claude_reg_fv #(
      .DATA_W(DATA_W), .ADDR_W(ADDR_W), .REG_ADDR(a),
      .RESET_VAL('0), .RESET_MASK('0), .RW_MASK('0), .ZERO_MASK('1)
    ) u_unmapped (`TIMER_REG_FV_OBS);
  end

  `undef TIMER_REG_FV_OBS

endmodule : timer_regmap_fv
