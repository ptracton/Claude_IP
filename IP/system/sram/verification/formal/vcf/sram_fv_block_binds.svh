// sram_fv_block_binds.svh — binds shared by every sram formal job.
//
// `include inside a bind-only module, after sram_fv_cfg.svh (generated per
// job by formal_sram.py from the job's configuration). The checkers read the
// configuration from those `defines: an SV bind cannot see VHDL generics.
//   sram_core      sram_core_fv   (ports + internal signals, see that file)
//   sram_array     sram_array_fv  (every port-A / port-B access)
//   sram_pwr_ctrl  sram_pwr_fv    (each power domain)

bind sram_core sram_core_fv #(
  .ADDR_W      (`SRAM_FV_ADDR_W),
  .WIDTH       (`SRAM_FV_WIDTH),
  .DEPTH       (`SRAM_FV_DEPTH),
  .BYTE_EN     (`SRAM_FV_BYTE_EN),
  .PWE         (`SRAM_FV_PARTIAL_WR_ERR),
  .PWR_GATE    (`SRAM_FV_PWR_GATE),
  .ECC_EN      (`SRAM_FV_ECC_EN),
  .NPD         (`SRAM_FV_NPD),
  .BIST_EN     (`SRAM_FV_BIST_EN),
  .DUAL_PORT   (`SRAM_FV_DUAL_PORT),
  .WIDTH_B     (`SRAM_FV_WIDTH_B),
  .BYTE_EN_B   (`SRAM_FV_BYTE_EN_B),
  .PWE_B       (`SRAM_FV_PARTIAL_WR_ERR_B),
  .COMMON_CLK  (`SRAM_FV_COMMON_CLK),
  .READ_ONLY_B (0),
  .MAX_WAIT    (`SRAM_FV_MAX_WAIT),
  .CHECK_BOUNDS(`SRAM_FV_CHECK_BOUNDS),
  .ENV_IS_RTL  (`SRAM_FV_ENV_IS_RTL)
) u_core_fv (
  .clk           (clk),
  .rst_n         (rst_n),
  .clk_b         (clk_b),
  .rst_b_n       (rst_b_n),
  .mem_req_i     (mem_req_i),
  .mem_gnt_o     (mem_gnt_o),
  .mem_we_i      (mem_we_i),
  .mem_addr_i    (mem_addr_i),
  .mem_be_i      (mem_be_i),
  .mem_wdata_i   (mem_wdata_i),
  .mem_rvalid_o  (mem_rvalid_o),
  .mem_rdata_o   (mem_rdata_o),
  .mem_err_o     (mem_err_o),
  .mem_b_req_i   (mem_b_req_i),
  .mem_b_gnt_o   (mem_b_gnt_o),
  .mem_b_we_i    (mem_b_we_i),
  .mem_b_addr_i  (mem_b_addr_i),
  .mem_b_be_i    (mem_b_be_i),
  .mem_b_wdata_i (mem_b_wdata_i),
  .mem_b_rvalid_o(mem_b_rvalid_o),
  .mem_b_rdata_o (mem_b_rdata_o),
  .mem_b_err_o   (mem_b_err_o),
  .pwr_mode_req_i(pwr_mode_req_i),
  .pwr_mode_ack_o(pwr_mode_ack_o),
  .clr_req_i     (clr_req_i),
  .clr_done_o    (clr_done_o),
  .ecc_inj_i     (ecc_inj_i),
  .bist_start_i  (bist_start_i),
  .bist_done_o   (bist_done_o),
  .clr_busy      (clr_busy),
  .bist_busy     (bist_busy),
  .b_cs          (b_cs),
  .a_stall       (a_stall),
  .b_stall       (b_stall),
  .a_rmw_pend    (a_rmw_pend),
  .b_rmw_pend    (b_rmw_pend),
  .b_dom_err     (b_dom_err)
);

bind sram_array sram_array_fv #(
  .DEPTH     (`SRAM_FV_DEPTH),
  .DEPTH_B   (`SRAM_FV_DEPTH * `SRAM_FV_WIDTH / `SRAM_FV_WIDTH_B),
  .NUM_BANKS (`SRAM_FV_NUM_BANKS),
  .DUAL_PORT (`SRAM_FV_DUAL_PORT),
  .PWR_GATE  (`SRAM_FV_PWR_GATE)
) u_array_fv (
  .clk    (clk),
  .cs_i   (cs_i),
  .idx_i  (idx_i),
  .ls_i   (ls_i),
  .ds_i   (ds_i),
  .sd_i   (sd_i),
  .b_clk  (b_clk),
  .b_cs_i (b_cs_i),
  .b_idx_i(b_idx_i)
);

bind sram_pwr_ctrl sram_pwr_fv #(
  .PWR_GATE (`SRAM_FV_PWR_GATE),
  .ENTER_CYC(`SRAM_FV_ENTER_CYC),
  .WAKE_LS  (`SRAM_FV_WAKE_LS),
  .WAKE_DS  (`SRAM_FV_WAKE_DS),
  .WAKE_SD  (`SRAM_FV_WAKE_SD)
) u_pwr_fv (
  .clk        (clk),
  .rst_n      (rst_n),
  .mode_req_i (mode_req_i),
  .wake_i     (wake_i),
  .idle_i     (idle_i),
  .clr_done_i (clr_done_i),
  .ls_o       (ls_o),
  .ds_o       (ds_o),
  .sd_o       (sd_o),
  .awake_o    (awake_o),
  .engine_ok_o(engine_ok_o),
  .clr_req_o  (clr_req_o),
  .busy_o     (busy_o),
  .ack_o      (ack_o)
);
