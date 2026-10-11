# wave_axi4l.tcl — Vivado xsim wave configuration for the AXI4-Lite bus_matrix testbench
#
# Sourced automatically when simulation runs (xsim.simulate.custom_tcl).
# Can also be sourced manually from the Vivado Tcl console after
# launching simulation.

add_wave_divider "Clock & Reset"
add_wave /tb_bus_matrix_axi4l/clk
add_wave /tb_bus_matrix_axi4l/rst_n

add_wave_divider "Master ports"
add_wave -radix hex /tb_bus_matrix_axi4l/M_AWVALID
add_wave -radix hex /tb_bus_matrix_axi4l/M_AWREADY
add_wave -radix hex /tb_bus_matrix_axi4l/M_AWADDR
add_wave -radix hex /tb_bus_matrix_axi4l/M_WVALID
add_wave -radix hex /tb_bus_matrix_axi4l/M_WREADY
add_wave -radix hex /tb_bus_matrix_axi4l/M_WDATA
add_wave -radix hex /tb_bus_matrix_axi4l/M_WSTRB
add_wave -radix hex /tb_bus_matrix_axi4l/M_BVALID
add_wave -radix hex /tb_bus_matrix_axi4l/M_BREADY
add_wave -radix hex /tb_bus_matrix_axi4l/M_BRESP
add_wave -radix hex /tb_bus_matrix_axi4l/M_ARVALID
add_wave -radix hex /tb_bus_matrix_axi4l/M_ARREADY
add_wave -radix hex /tb_bus_matrix_axi4l/M_ARADDR
add_wave -radix hex /tb_bus_matrix_axi4l/M_RVALID
add_wave -radix hex /tb_bus_matrix_axi4l/M_RREADY
add_wave -radix hex /tb_bus_matrix_axi4l/M_RDATA
add_wave -radix hex /tb_bus_matrix_axi4l/M_RRESP

add_wave_divider "Slave ports"
add_wave -radix hex /tb_bus_matrix_axi4l/S_AWVALID
add_wave -radix hex /tb_bus_matrix_axi4l/S_AWREADY
add_wave -radix hex /tb_bus_matrix_axi4l/S_AWADDR
add_wave -radix hex /tb_bus_matrix_axi4l/S_WVALID
add_wave -radix hex /tb_bus_matrix_axi4l/S_WREADY
add_wave -radix hex /tb_bus_matrix_axi4l/S_WDATA
add_wave -radix hex /tb_bus_matrix_axi4l/S_WSTRB
add_wave -radix hex /tb_bus_matrix_axi4l/S_BVALID
add_wave -radix hex /tb_bus_matrix_axi4l/S_BREADY
add_wave -radix hex /tb_bus_matrix_axi4l/S_BRESP
add_wave -radix hex /tb_bus_matrix_axi4l/S_ARVALID
add_wave -radix hex /tb_bus_matrix_axi4l/S_ARREADY
add_wave -radix hex /tb_bus_matrix_axi4l/S_ARADDR
add_wave -radix hex /tb_bus_matrix_axi4l/S_RVALID
add_wave -radix hex /tb_bus_matrix_axi4l/S_RREADY
add_wave -radix hex /tb_bus_matrix_axi4l/S_RDATA
add_wave -radix hex /tb_bus_matrix_axi4l/S_RRESP

add_wave_divider "Core handshake"
add_wave -radix hex /tb_bus_matrix_axi4l/u_dut/u_core/mst_req
add_wave -radix hex /tb_bus_matrix_axi4l/u_dut/u_core/mst_addr
add_wave -radix hex /tb_bus_matrix_axi4l/u_dut/u_core/mst_we
add_wave -radix hex /tb_bus_matrix_axi4l/u_dut/u_core/mst_done
add_wave -radix hex /tb_bus_matrix_axi4l/u_dut/u_core/mst_err
add_wave -radix hex /tb_bus_matrix_axi4l/u_dut/u_core/slv_req
add_wave -radix hex /tb_bus_matrix_axi4l/u_dut/u_core/slv_addr
add_wave -radix hex /tb_bus_matrix_axi4l/u_dut/u_core/slv_we
add_wave -radix hex /tb_bus_matrix_axi4l/u_dut/u_core/slv_done
add_wave -radix hex /tb_bus_matrix_axi4l/u_dut/u_core/slv_err

add_wave_divider "Arbiters"
add_wave {/tb_bus_matrix_axi4l/u_dut/u_core/gen_arb[0]/u_arb/gnt}
add_wave {/tb_bus_matrix_axi4l/u_dut/u_core/gen_arb[1]/u_arb/gnt}
add_wave {/tb_bus_matrix_axi4l/u_dut/u_core/gen_arb[2]/u_arb/gnt}
add_wave {/tb_bus_matrix_axi4l/u_dut/u_core/gen_arb[3]/u_arb/gnt}
