onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Clock & Reset}
add wave -noupdate -radix binary /tb_bus_matrix_axi4l/clk
add wave -noupdate -radix binary /tb_bus_matrix_axi4l/rst_n
add wave -noupdate -divider {Master ports}
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_AWVALID
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_AWREADY
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_AWADDR
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_WVALID
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_WREADY
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_WDATA
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_WSTRB
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_BVALID
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_BREADY
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_BRESP
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_ARVALID
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_ARREADY
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_ARADDR
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_RVALID
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_RREADY
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_RDATA
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/M_RRESP
add wave -noupdate -divider {Slave ports}
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_AWVALID
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_AWREADY
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_AWADDR
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_WVALID
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_WREADY
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_WDATA
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_WSTRB
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_BVALID
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_BREADY
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_BRESP
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_ARVALID
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_ARREADY
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_ARADDR
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_RVALID
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_RREADY
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_RDATA
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/S_RRESP
add wave -noupdate -divider {Core handshake}
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/u_dut/u_core/mst_req
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/u_dut/u_core/mst_addr
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/u_dut/u_core/mst_we
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/u_dut/u_core/mst_done
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/u_dut/u_core/mst_err
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/u_dut/u_core/slv_req
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/u_dut/u_core/slv_addr
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/u_dut/u_core/slv_we
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/u_dut/u_core/slv_done
add wave -noupdate -radix hexadecimal /tb_bus_matrix_axi4l/u_dut/u_core/slv_err
add wave -noupdate -divider {Arbiters}
add wave -noupdate -radix binary {/tb_bus_matrix_axi4l/u_dut/u_core/gen_arb[0]/u_arb/gnt}
add wave -noupdate -radix binary {/tb_bus_matrix_axi4l/u_dut/u_core/gen_arb[1]/u_arb/gnt}
add wave -noupdate -radix binary {/tb_bus_matrix_axi4l/u_dut/u_core/gen_arb[2]/u_arb/gnt}
add wave -noupdate -radix binary {/tb_bus_matrix_axi4l/u_dut/u_core/gen_arb[3]/u_arb/gnt}
TreeUpdate [SetDefaultTree]
configure wave -namecolwidth 260
configure wave -timelineunits ns
update
