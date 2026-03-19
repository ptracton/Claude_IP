onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Clock & Reset}
add wave -noupdate -radix binary /tb_timer_apb/clk
add wave -noupdate -radix binary /tb_timer_apb/rst_n
add wave -noupdate -divider {APB Bus}
add wave -noupdate -radix hexadecimal /tb_timer_apb/PSEL
add wave -noupdate -radix hexadecimal /tb_timer_apb/PENABLE
add wave -noupdate -radix hexadecimal /tb_timer_apb/PWRITE
add wave -noupdate -radix hexadecimal /tb_timer_apb/PADDR
add wave -noupdate -radix hexadecimal /tb_timer_apb/PWDATA
add wave -noupdate -radix hexadecimal /tb_timer_apb/PSTRB
add wave -noupdate -radix hexadecimal /tb_timer_apb/PRDATA
add wave -noupdate -radix hexadecimal /tb_timer_apb/PREADY
add wave -noupdate -radix hexadecimal /tb_timer_apb/PSLVERR
add wave -noupdate -divider {IP Outputs}
add wave -noupdate -radix binary /tb_timer_apb/irq
add wave -noupdate -radix binary /tb_timer_apb/trigger_out
add wave -noupdate -divider {DUT: regfile}
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/clk
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/rst_n
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/wr_en
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/wr_addr
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/wr_data
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/wr_strb
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/rd_en
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/rd_addr
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/rd_data
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/hw_count_val
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/hw_intr_set
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/hw_ovf_set
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/hw_active
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/ctrl_en
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/ctrl_mode
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/ctrl_intr_en
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/ctrl_trig_en
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/ctrl_prescale
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/ctrl_restart
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/ctrl_irq_mode
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/load_val
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/status_intr
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/ctrl_q
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/status_q
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/load_q
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/count_q
add wave -noupdate -radix hexadecimal /tb_timer_apb/u_dut/u_regfile/capture_q
TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ps} 0}
quietly wave cursor active 0
configure wave -namecolwidth 217
configure wave -valuecolwidth 100
configure wave -justifyvalue left
configure wave -signalnamewidth 0
configure wave -snapdistance 10
configure wave -datasetprefix 0
configure wave -rowmargin 4
configure wave -childrowmargin 2
configure wave -gridoffset 0
configure wave -gridperiod 1
configure wave -griddelta 40
configure wave -timeline 0
configure wave -timelineunits ps
update
WaveRestoreZoom {0 ps} {624750 ps}
