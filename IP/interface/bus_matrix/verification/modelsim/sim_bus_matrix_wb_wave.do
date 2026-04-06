# sim_bus_matrix_wb_wave.do — ModelSim waveform setup for Wishbone bus_matrix testbench.
# Source this file after the simulation has started:
#   vsim work.tb_bus_matrix_wb -voptargs="+acc"
#   source sim_bus_matrix_wb_wave.do
#   run -all

onerror {resume}
quietly WaveActivateNextPane {} 0

# ---- Clock and Reset --------------------------------------------------------
add wave -divider "Clock / Reset"
add wave -noupdate -label clk   /tb_bus_matrix_wb/clk
add wave -noupdate -label rst_n /tb_bus_matrix_wb/rst_n

# ---- Master 0 Wishbone interface --------------------------------------------
add wave -divider "Master 0 (Wishbone)"
add wave -noupdate -label M0_CYC   /tb_bus_matrix_wb/u_dut/M_CYC[0]
add wave -noupdate -label M0_STB   /tb_bus_matrix_wb/u_dut/M_STB[0]
add wave -noupdate -label M0_WE    /tb_bus_matrix_wb/u_dut/M_WE[0]
add wave -noupdate -label M0_ADR   -radix hex /tb_bus_matrix_wb/u_dut/M_ADR[31:0]
add wave -noupdate -label M0_DAT_O -radix hex /tb_bus_matrix_wb/u_dut/M_DAT_O[31:0]
add wave -noupdate -label M0_DAT_I -radix hex /tb_bus_matrix_wb/u_dut/M_DAT_I[31:0]
add wave -noupdate -label M0_SEL   -radix hex /tb_bus_matrix_wb/u_dut/M_SEL[3:0]
add wave -noupdate -label M0_ACK   /tb_bus_matrix_wb/u_dut/M_ACK[0]
add wave -noupdate -label M0_ERR   /tb_bus_matrix_wb/u_dut/M_ERR[0]

# ---- Master 1 Wishbone interface --------------------------------------------
add wave -divider "Master 1 (Wishbone)"
add wave -noupdate -label M1_CYC   /tb_bus_matrix_wb/u_dut/M_CYC[1]
add wave -noupdate -label M1_STB   /tb_bus_matrix_wb/u_dut/M_STB[1]
add wave -noupdate -label M1_WE    /tb_bus_matrix_wb/u_dut/M_WE[1]
add wave -noupdate -label M1_ADR   -radix hex /tb_bus_matrix_wb/u_dut/M_ADR[63:32]
add wave -noupdate -label M1_DAT_O -radix hex /tb_bus_matrix_wb/u_dut/M_DAT_O[63:32]
add wave -noupdate -label M1_DAT_I -radix hex /tb_bus_matrix_wb/u_dut/M_DAT_I[63:32]
add wave -noupdate -label M1_SEL   -radix hex /tb_bus_matrix_wb/u_dut/M_SEL[7:4]
add wave -noupdate -label M1_ACK   /tb_bus_matrix_wb/u_dut/M_ACK[1]
add wave -noupdate -label M1_ERR   /tb_bus_matrix_wb/u_dut/M_ERR[1]

# ---- Slave 0 Wishbone interface ---------------------------------------------
add wave -divider "Slave 0 (Wishbone)"
add wave -noupdate -label S0_CYC   /tb_bus_matrix_wb/u_dut/S_CYC[0]
add wave -noupdate -label S0_STB   /tb_bus_matrix_wb/u_dut/S_STB[0]
add wave -noupdate -label S0_WE    /tb_bus_matrix_wb/u_dut/S_WE[0]
add wave -noupdate -label S0_ADR   -radix hex /tb_bus_matrix_wb/u_dut/S_ADR[31:0]
add wave -noupdate -label S0_DAT_O -radix hex /tb_bus_matrix_wb/u_dut/S_DAT_O[31:0]
add wave -noupdate -label S0_DAT_I -radix hex /tb_bus_matrix_wb/u_dut/S_DAT_I[31:0]
add wave -noupdate -label S0_SEL   -radix hex /tb_bus_matrix_wb/u_dut/S_SEL[3:0]
add wave -noupdate -label S0_ACK   /tb_bus_matrix_wb/u_dut/S_ACK[0]

# ---- Slave 1 Wishbone interface ---------------------------------------------
add wave -divider "Slave 1 (Wishbone)"
add wave -noupdate -label S1_CYC   /tb_bus_matrix_wb/u_dut/S_CYC[1]
add wave -noupdate -label S1_STB   /tb_bus_matrix_wb/u_dut/S_STB[1]
add wave -noupdate -label S1_WE    /tb_bus_matrix_wb/u_dut/S_WE[1]
add wave -noupdate -label S1_ADR   -radix hex /tb_bus_matrix_wb/u_dut/S_ADR[63:32]
add wave -noupdate -label S1_DAT_O -radix hex /tb_bus_matrix_wb/u_dut/S_DAT_O[63:32]
add wave -noupdate -label S1_DAT_I -radix hex /tb_bus_matrix_wb/u_dut/S_DAT_I[63:32]
add wave -noupdate -label S1_SEL   -radix hex /tb_bus_matrix_wb/u_dut/S_SEL[7:4]
add wave -noupdate -label S1_ACK   /tb_bus_matrix_wb/u_dut/S_ACK[1]

# ---- Internal core signals --------------------------------------------------
add wave -divider "Core internals"
add wave -noupdate -label mst_req  -radix hex /tb_bus_matrix_wb/u_dut/u_core/mst_req
add wave -noupdate -label mst_gnt  -radix hex /tb_bus_matrix_wb/u_dut/u_core/mst_gnt
add wave -noupdate -label slv_req  -radix hex /tb_bus_matrix_wb/u_dut/u_core/slv_req
add wave -noupdate -label slv_gnt  -radix hex /tb_bus_matrix_wb/u_dut/u_core/slv_gnt

TreeUpdate [SetDefaultTree]
WaveRestoreCursors {{Cursor 1} {0 ns} 0}
configure wave -namecolwidth 160
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
configure wave -timelineunits ns
update
WaveRestoreZoom {0 ns} {500 ns}
