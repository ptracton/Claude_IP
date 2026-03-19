# wave_apb.tcl — Vivado xsim wave configuration for APB timer testbench
#
# Sourced automatically when simulation runs (xsim.simulate.custom_tcl).
# Can also be sourced manually from the Vivado Tcl console after
# launching simulation.

add_wave_divider "Clock & Reset"
add_wave /tb_timer_apb/clk
add_wave /tb_timer_apb/rst_n

add_wave_divider "APB Bus"
add_wave /tb_timer_apb/PSEL
add_wave /tb_timer_apb/PENABLE
add_wave /tb_timer_apb/PWRITE
add_wave -radix hex /tb_timer_apb/PADDR
add_wave -radix hex /tb_timer_apb/PWDATA
add_wave -radix hex /tb_timer_apb/PSTRB
add_wave -radix hex /tb_timer_apb/PRDATA
add_wave /tb_timer_apb/PREADY
add_wave /tb_timer_apb/PSLVERR

add_wave_divider "IP Outputs"
add_wave /tb_timer_apb/irq
add_wave /tb_timer_apb/trigger_out

add_wave_divider "DUT: regfile ports"
add_wave /tb_timer_apb/u_dut/u_regfile/clk
add_wave /tb_timer_apb/u_dut/u_regfile/rst_n
add_wave /tb_timer_apb/u_dut/u_regfile/wr_en
add_wave -radix hex /tb_timer_apb/u_dut/u_regfile/wr_addr
add_wave -radix hex /tb_timer_apb/u_dut/u_regfile/wr_data
add_wave -radix hex /tb_timer_apb/u_dut/u_regfile/wr_strb
add_wave /tb_timer_apb/u_dut/u_regfile/rd_en
add_wave -radix hex /tb_timer_apb/u_dut/u_regfile/rd_addr
add_wave -radix hex /tb_timer_apb/u_dut/u_regfile/rd_data
add_wave /tb_timer_apb/u_dut/u_regfile/hw_intr_set
add_wave /tb_timer_apb/u_dut/u_regfile/hw_ovf_set
add_wave /tb_timer_apb/u_dut/u_regfile/hw_active
add_wave /tb_timer_apb/u_dut/u_regfile/ctrl_en
add_wave /tb_timer_apb/u_dut/u_regfile/ctrl_mode
add_wave /tb_timer_apb/u_dut/u_regfile/ctrl_intr_en
add_wave /tb_timer_apb/u_dut/u_regfile/ctrl_trig_en
add_wave -radix hex /tb_timer_apb/u_dut/u_regfile/ctrl_prescale
add_wave /tb_timer_apb/u_dut/u_regfile/ctrl_restart
add_wave /tb_timer_apb/u_dut/u_regfile/ctrl_irq_mode
add_wave -radix hex /tb_timer_apb/u_dut/u_regfile/load_val
add_wave /tb_timer_apb/u_dut/u_regfile/status_intr

add_wave_divider "DUT: regfile storage"
add_wave -radix hex /tb_timer_apb/u_dut/u_regfile/ctrl_q
add_wave -radix hex /tb_timer_apb/u_dut/u_regfile/status_q
add_wave -radix hex /tb_timer_apb/u_dut/u_regfile/load_q
add_wave -radix hex /tb_timer_apb/u_dut/u_regfile/count_q
add_wave -radix hex /tb_timer_apb/u_dut/u_regfile/capture_q

add_wave_divider "DUT: core internals"
add_wave /tb_timer_apb/u_dut/u_core/ctrl_en
add_wave /tb_timer_apb/u_dut/u_core/ctrl_mode
add_wave /tb_timer_apb/u_dut/u_core/ctrl_irq_mode
add_wave -radix hex /tb_timer_apb/u_dut/u_core/ctrl_prescale
add_wave -radix hex /tb_timer_apb/u_dut/u_core/load_val
add_wave -radix hex /tb_timer_apb/u_dut/u_core/count_q
add_wave -radix hex /tb_timer_apb/u_dut/u_core/prescale_cnt_q
add_wave /tb_timer_apb/u_dut/u_core/tick
add_wave /tb_timer_apb/u_dut/u_core/hw_intr_set
add_wave /tb_timer_apb/u_dut/u_core/hw_ovf_set
add_wave /tb_timer_apb/u_dut/u_core/hw_active
