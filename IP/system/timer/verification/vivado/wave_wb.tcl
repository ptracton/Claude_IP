# wave_wb.tcl — Vivado xsim wave configuration for Wishbone B4 timer testbench
#
# Sourced automatically when simulation runs (xsim.simulate.custom_tcl).
# Can also be sourced manually from the Vivado Tcl console after
# launching simulation.
#
# Note: Wishbone uses active-high synchronous RST_I instead of rst_n.

add_wave_divider "Clock & Reset"
add_wave /tb_timer_wb/clk
add_wave /tb_timer_wb/RST_I

add_wave_divider "Wishbone Bus"
add_wave /tb_timer_wb/CYC_I
add_wave /tb_timer_wb/STB_I
add_wave /tb_timer_wb/WE_I
add_wave -radix hex /tb_timer_wb/ADR_I
add_wave -radix hex /tb_timer_wb/DAT_I
add_wave -radix hex /tb_timer_wb/SEL_I
add_wave -radix hex /tb_timer_wb/DAT_O
add_wave /tb_timer_wb/ACK_O
add_wave /tb_timer_wb/ERR_O

add_wave_divider "IP Outputs"
add_wave /tb_timer_wb/irq
add_wave /tb_timer_wb/trigger_out

add_wave_divider "DUT: regfile ports"
add_wave /tb_timer_wb/u_dut/u_regfile/clk
add_wave /tb_timer_wb/u_dut/u_regfile/rst_n
add_wave /tb_timer_wb/u_dut/u_regfile/wr_en
add_wave -radix hex /tb_timer_wb/u_dut/u_regfile/wr_addr
add_wave -radix hex /tb_timer_wb/u_dut/u_regfile/wr_data
add_wave -radix hex /tb_timer_wb/u_dut/u_regfile/wr_strb
add_wave /tb_timer_wb/u_dut/u_regfile/rd_en
add_wave -radix hex /tb_timer_wb/u_dut/u_regfile/rd_addr
add_wave -radix hex /tb_timer_wb/u_dut/u_regfile/rd_data
add_wave /tb_timer_wb/u_dut/u_regfile/hw_intr_set
add_wave /tb_timer_wb/u_dut/u_regfile/hw_ovf_set
add_wave /tb_timer_wb/u_dut/u_regfile/hw_active
add_wave /tb_timer_wb/u_dut/u_regfile/ctrl_en
add_wave /tb_timer_wb/u_dut/u_regfile/ctrl_mode
add_wave /tb_timer_wb/u_dut/u_regfile/ctrl_intr_en
add_wave /tb_timer_wb/u_dut/u_regfile/ctrl_trig_en
add_wave -radix hex /tb_timer_wb/u_dut/u_regfile/ctrl_prescale
add_wave /tb_timer_wb/u_dut/u_regfile/ctrl_restart
add_wave /tb_timer_wb/u_dut/u_regfile/ctrl_irq_mode
add_wave -radix hex /tb_timer_wb/u_dut/u_regfile/load_val
add_wave /tb_timer_wb/u_dut/u_regfile/status_intr

add_wave_divider "DUT: regfile storage"
add_wave -radix hex /tb_timer_wb/u_dut/u_regfile/ctrl_q
add_wave -radix hex /tb_timer_wb/u_dut/u_regfile/status_q
add_wave -radix hex /tb_timer_wb/u_dut/u_regfile/load_q
add_wave -radix hex /tb_timer_wb/u_dut/u_regfile/count_q
add_wave -radix hex /tb_timer_wb/u_dut/u_regfile/capture_q

add_wave_divider "DUT: core internals"
add_wave /tb_timer_wb/u_dut/u_core/ctrl_en
add_wave /tb_timer_wb/u_dut/u_core/ctrl_mode
add_wave /tb_timer_wb/u_dut/u_core/ctrl_irq_mode
add_wave -radix hex /tb_timer_wb/u_dut/u_core/ctrl_prescale
add_wave -radix hex /tb_timer_wb/u_dut/u_core/load_val
add_wave -radix hex /tb_timer_wb/u_dut/u_core/count_q
add_wave -radix hex /tb_timer_wb/u_dut/u_core/prescale_cnt_q
add_wave /tb_timer_wb/u_dut/u_core/tick
add_wave /tb_timer_wb/u_dut/u_core/hw_intr_set
add_wave /tb_timer_wb/u_dut/u_core/hw_ovf_set
add_wave /tb_timer_wb/u_dut/u_core/hw_active
