# sim_bus_matrix_axi_wave.do — ModelSim waveform setup for AXI4-Lite bus_matrix testbench.
# Source this file after the simulation has started:
#   vsim work.tb_bus_matrix_axi -voptargs="+acc"
#   source sim_bus_matrix_axi_wave.do
#   run -all

onerror {resume}
quietly WaveActivateNextPane {} 0

# ---- Clock and Reset --------------------------------------------------------
add wave -divider "Clock / Reset"
add wave -noupdate -label clk   /tb_bus_matrix_axi/clk
add wave -noupdate -label rst_n /tb_bus_matrix_axi/rst_n

# ---- Master 0 AXI4-Lite Write -----------------------------------------------
add wave -divider "Master 0 Write (AXI4-L)"
add wave -noupdate -label M0_AWVALID /tb_bus_matrix_axi/u_dut/M_AWVALID[0]
add wave -noupdate -label M0_AWREADY /tb_bus_matrix_axi/u_dut/M_AWREADY[0]
add wave -noupdate -label M0_AWADDR  -radix hex /tb_bus_matrix_axi/u_dut/M_AWADDR[31:0]
add wave -noupdate -label M0_WVALID  /tb_bus_matrix_axi/u_dut/M_WVALID[0]
add wave -noupdate -label M0_WREADY  /tb_bus_matrix_axi/u_dut/M_WREADY[0]
add wave -noupdate -label M0_WDATA   -radix hex /tb_bus_matrix_axi/u_dut/M_WDATA[31:0]
add wave -noupdate -label M0_BVALID  /tb_bus_matrix_axi/u_dut/M_BVALID[0]
add wave -noupdate -label M0_BREADY  /tb_bus_matrix_axi/u_dut/M_BREADY[0]
add wave -noupdate -label M0_BRESP   -radix hex /tb_bus_matrix_axi/u_dut/M_BRESP[1:0]

# ---- Master 0 AXI4-Lite Read ------------------------------------------------
add wave -divider "Master 0 Read (AXI4-L)"
add wave -noupdate -label M0_ARVALID /tb_bus_matrix_axi/u_dut/M_ARVALID[0]
add wave -noupdate -label M0_ARREADY /tb_bus_matrix_axi/u_dut/M_ARREADY[0]
add wave -noupdate -label M0_ARADDR  -radix hex /tb_bus_matrix_axi/u_dut/M_ARADDR[31:0]
add wave -noupdate -label M0_RVALID  /tb_bus_matrix_axi/u_dut/M_RVALID[0]
add wave -noupdate -label M0_RREADY  /tb_bus_matrix_axi/u_dut/M_RREADY[0]
add wave -noupdate -label M0_RDATA   -radix hex /tb_bus_matrix_axi/u_dut/M_RDATA[31:0]
add wave -noupdate -label M0_RRESP   -radix hex /tb_bus_matrix_axi/u_dut/M_RRESP[1:0]

# ---- Slave 0 AXI4-Lite Write ------------------------------------------------
add wave -divider "Slave 0 Write (AXI4-L)"
add wave -noupdate -label S0_AWVALID /tb_bus_matrix_axi/u_dut/S_AWVALID[0]
add wave -noupdate -label S0_AWREADY /tb_bus_matrix_axi/u_dut/S_AWREADY[0]
add wave -noupdate -label S0_AWADDR  -radix hex /tb_bus_matrix_axi/u_dut/S_AWADDR[31:0]
add wave -noupdate -label S0_WVALID  /tb_bus_matrix_axi/u_dut/S_WVALID[0]
add wave -noupdate -label S0_WREADY  /tb_bus_matrix_axi/u_dut/S_WREADY[0]
add wave -noupdate -label S0_WDATA   -radix hex /tb_bus_matrix_axi/u_dut/S_WDATA[31:0]
add wave -noupdate -label S0_BVALID  /tb_bus_matrix_axi/u_dut/S_BVALID[0]
add wave -noupdate -label S0_BREADY  /tb_bus_matrix_axi/u_dut/S_BREADY[0]

# ---- Slave 0 AXI4-Lite Read -------------------------------------------------
add wave -divider "Slave 0 Read (AXI4-L)"
add wave -noupdate -label S0_ARVALID /tb_bus_matrix_axi/u_dut/S_ARVALID[0]
add wave -noupdate -label S0_ARREADY /tb_bus_matrix_axi/u_dut/S_ARREADY[0]
add wave -noupdate -label S0_ARADDR  -radix hex /tb_bus_matrix_axi/u_dut/S_ARADDR[31:0]
add wave -noupdate -label S0_RVALID  /tb_bus_matrix_axi/u_dut/S_RVALID[0]
add wave -noupdate -label S0_RREADY  /tb_bus_matrix_axi/u_dut/S_RREADY[0]
add wave -noupdate -label S0_RDATA   -radix hex /tb_bus_matrix_axi/u_dut/S_RDATA[31:0]

# ---- Internal core signals --------------------------------------------------
add wave -divider "Core internals"
add wave -noupdate -label mst_req    -radix hex /tb_bus_matrix_axi/u_dut/u_core/mst_req
add wave -noupdate -label mst_gnt    -radix hex /tb_bus_matrix_axi/u_dut/u_core/mst_gnt
add wave -noupdate -label slv_req    -radix hex /tb_bus_matrix_axi/u_dut/u_core/slv_req
add wave -noupdate -label slv_gnt    -radix hex /tb_bus_matrix_axi/u_dut/u_core/slv_gnt
add wave -noupdate -label slv_we     -radix hex /tb_bus_matrix_axi/u_dut/u_core/slv_we

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
