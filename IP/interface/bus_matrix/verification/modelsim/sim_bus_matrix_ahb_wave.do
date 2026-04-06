# sim_bus_matrix_ahb_wave.do — ModelSim waveform setup for AHB bus_matrix testbench.
# Source this file after the simulation has started:
#   vsim work.tb_bus_matrix_ahb -voptargs="+acc"
#   source sim_bus_matrix_ahb_wave.do
#   run -all

onerror {resume}
quietly WaveActivateNextPane {} 0

# ---- Clock and Reset --------------------------------------------------------
add wave -divider "Clock / Reset"
add wave -noupdate -label clk   /tb_bus_matrix_ahb/clk
add wave -noupdate -label rst_n /tb_bus_matrix_ahb/rst_n

# ---- Master 0 AHB interface -------------------------------------------------
add wave -divider "Master 0 (AHB)"
add wave -noupdate -label M0_HSEL     /tb_bus_matrix_ahb/u_dut/M_HSEL[0]
add wave -noupdate -label M0_HTRANS   -radix hex /tb_bus_matrix_ahb/u_dut/M_HTRANS[1:0]
add wave -noupdate -label M0_HADDR    -radix hex /tb_bus_matrix_ahb/u_dut/M_HADDR[31:0]
add wave -noupdate -label M0_HWRITE   /tb_bus_matrix_ahb/u_dut/M_HWRITE[0]
add wave -noupdate -label M0_HWDATA   -radix hex /tb_bus_matrix_ahb/u_dut/M_HWDATA[31:0]
add wave -noupdate -label M0_HRDATA   -radix hex /tb_bus_matrix_ahb/u_dut/M_HRDATA[31:0]
add wave -noupdate -label M0_HREADY   /tb_bus_matrix_ahb/u_dut/M_HREADY[0]
add wave -noupdate -label M0_HRESP    /tb_bus_matrix_ahb/u_dut/M_HRESP[0]

# ---- Master 1 AHB interface -------------------------------------------------
add wave -divider "Master 1 (AHB)"
add wave -noupdate -label M1_HSEL     /tb_bus_matrix_ahb/u_dut/M_HSEL[1]
add wave -noupdate -label M1_HTRANS   -radix hex /tb_bus_matrix_ahb/u_dut/M_HTRANS[3:2]
add wave -noupdate -label M1_HADDR    -radix hex /tb_bus_matrix_ahb/u_dut/M_HADDR[63:32]
add wave -noupdate -label M1_HWRITE   /tb_bus_matrix_ahb/u_dut/M_HWRITE[1]
add wave -noupdate -label M1_HWDATA   -radix hex /tb_bus_matrix_ahb/u_dut/M_HWDATA[63:32]
add wave -noupdate -label M1_HRDATA   -radix hex /tb_bus_matrix_ahb/u_dut/M_HRDATA[63:32]
add wave -noupdate -label M1_HREADY   /tb_bus_matrix_ahb/u_dut/M_HREADY[1]
add wave -noupdate -label M1_HRESP    /tb_bus_matrix_ahb/u_dut/M_HRESP[1]

# ---- Slave 0 AHB interface --------------------------------------------------
add wave -divider "Slave 0 (AHB)"
add wave -noupdate -label S0_HSEL     /tb_bus_matrix_ahb/u_dut/S_HSEL[0]
add wave -noupdate -label S0_HTRANS   -radix hex /tb_bus_matrix_ahb/u_dut/S_HTRANS[1:0]
add wave -noupdate -label S0_HADDR    -radix hex /tb_bus_matrix_ahb/u_dut/S_HADDR[31:0]
add wave -noupdate -label S0_HWRITE   /tb_bus_matrix_ahb/u_dut/S_HWRITE[0]
add wave -noupdate -label S0_HWDATA   -radix hex /tb_bus_matrix_ahb/u_dut/S_HWDATA[31:0]
add wave -noupdate -label S0_HRDATA   -radix hex /tb_bus_matrix_ahb/u_dut/S_HRDATA[31:0]
add wave -noupdate -label S0_HREADY   /tb_bus_matrix_ahb/u_dut/S_HREADY[0]
add wave -noupdate -label S0_HRESP    /tb_bus_matrix_ahb/u_dut/S_HRESP[0]

# ---- Slave 1 AHB interface --------------------------------------------------
add wave -divider "Slave 1 (AHB)"
add wave -noupdate -label S1_HSEL     /tb_bus_matrix_ahb/u_dut/S_HSEL[1]
add wave -noupdate -label S1_HTRANS   -radix hex /tb_bus_matrix_ahb/u_dut/S_HTRANS[3:2]
add wave -noupdate -label S1_HADDR    -radix hex /tb_bus_matrix_ahb/u_dut/S_HADDR[63:32]
add wave -noupdate -label S1_HWRITE   /tb_bus_matrix_ahb/u_dut/S_HWRITE[1]
add wave -noupdate -label S1_HWDATA   -radix hex /tb_bus_matrix_ahb/u_dut/S_HWDATA[63:32]
add wave -noupdate -label S1_HRDATA   -radix hex /tb_bus_matrix_ahb/u_dut/S_HRDATA[63:32]
add wave -noupdate -label S1_HREADY   /tb_bus_matrix_ahb/u_dut/S_HREADY[1]
add wave -noupdate -label S1_HRESP    /tb_bus_matrix_ahb/u_dut/S_HRESP[1]

# ---- Internal core signals --------------------------------------------------
add wave -divider "Core internals"
add wave -noupdate -label mst_req    -radix hex /tb_bus_matrix_ahb/u_dut/u_core/mst_req
add wave -noupdate -label mst_gnt    -radix hex /tb_bus_matrix_ahb/u_dut/u_core/mst_gnt
add wave -noupdate -label slv_req    -radix hex /tb_bus_matrix_ahb/u_dut/u_core/slv_req
add wave -noupdate -label slv_gnt    -radix hex /tb_bus_matrix_ahb/u_dut/u_core/slv_gnt

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
