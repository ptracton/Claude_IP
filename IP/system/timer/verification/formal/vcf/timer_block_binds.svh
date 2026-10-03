// timer_block_binds.svh — bind statements shared by every timer top-level.
//
// Included inside each timer_<proto>_fv_bind module. timer_core and
// timer_regfile are identical in all four top-levels (and have the same
// port names in SV and VHDL), so their checkers are bound the same way.

bind timer_core timer_core_fv #(.DATA_W(32)) u_core_fv (
  .clk(clk), .rst_n(rst_n),
  .ctrl_en(ctrl_en), .ctrl_mode(ctrl_mode), .ctrl_intr_en(ctrl_intr_en),
  .ctrl_trig_en(ctrl_trig_en), .ctrl_prescale(ctrl_prescale),
  .ctrl_restart(ctrl_restart), .ctrl_irq_mode(ctrl_irq_mode),
  .load_val(load_val), .status_intr(status_intr),
  .hw_count_val(hw_count_val), .hw_intr_set(hw_intr_set),
  .hw_ovf_set(hw_ovf_set), .hw_active(hw_active),
  .irq(irq), .trigger_out(trigger_out)
);

bind timer_regfile timer_regfile_fv u_regfile_fv (
  .clk(clk), .rst_n(rst_n),
  .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data), .wr_strb(wr_strb),
  .rd_en(rd_en), .rd_addr(rd_addr), .rd_data(rd_data),
  .hw_count_val(hw_count_val), .hw_intr_set(hw_intr_set),
  .hw_ovf_set(hw_ovf_set), .hw_active(hw_active),
  .ctrl_en(ctrl_en), .ctrl_mode(ctrl_mode), .ctrl_intr_en(ctrl_intr_en),
  .ctrl_trig_en(ctrl_trig_en), .ctrl_prescale(ctrl_prescale),
  .ctrl_restart(ctrl_restart), .ctrl_irq_mode(ctrl_irq_mode),
  .load_val(load_val), .status_intr(status_intr)
);
