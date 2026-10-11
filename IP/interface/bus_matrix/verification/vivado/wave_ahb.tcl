# wave_ahb.tcl — Vivado xsim wave configuration for the AHB-Lite bus_matrix testbench
#
# Sourced automatically when simulation runs (xsim.simulate.custom_tcl).
# Can also be sourced manually from the Vivado Tcl console after
# launching simulation.

add_wave_divider "Clock & Reset"
add_wave /tb_bus_matrix_ahb/clk
add_wave /tb_bus_matrix_ahb/rst_n

add_wave_divider "Master ports"
add_wave -radix hex /tb_bus_matrix_ahb/M_HSEL
add_wave -radix hex /tb_bus_matrix_ahb/M_HADDR
add_wave -radix hex /tb_bus_matrix_ahb/M_HTRANS
add_wave -radix hex /tb_bus_matrix_ahb/M_HWRITE
add_wave -radix hex /tb_bus_matrix_ahb/M_HWDATA
add_wave -radix hex /tb_bus_matrix_ahb/M_HWSTRB
add_wave -radix hex /tb_bus_matrix_ahb/M_HREADY
add_wave -radix hex /tb_bus_matrix_ahb/M_HRDATA
add_wave -radix hex /tb_bus_matrix_ahb/M_HRESP

add_wave_divider "Slave ports"
add_wave -radix hex /tb_bus_matrix_ahb/S_HSEL
add_wave -radix hex /tb_bus_matrix_ahb/S_HADDR
add_wave -radix hex /tb_bus_matrix_ahb/S_HTRANS
add_wave -radix hex /tb_bus_matrix_ahb/S_HWRITE
add_wave -radix hex /tb_bus_matrix_ahb/S_HWDATA
add_wave -radix hex /tb_bus_matrix_ahb/S_HWSTRB
add_wave -radix hex /tb_bus_matrix_ahb/S_HREADY
add_wave -radix hex /tb_bus_matrix_ahb/S_HRDATA
add_wave -radix hex /tb_bus_matrix_ahb/S_HRESP

add_wave_divider "Core handshake"
add_wave -radix hex /tb_bus_matrix_ahb/u_dut/u_core/mst_req
add_wave -radix hex /tb_bus_matrix_ahb/u_dut/u_core/mst_addr
add_wave -radix hex /tb_bus_matrix_ahb/u_dut/u_core/mst_we
add_wave -radix hex /tb_bus_matrix_ahb/u_dut/u_core/mst_done
add_wave -radix hex /tb_bus_matrix_ahb/u_dut/u_core/mst_err
add_wave -radix hex /tb_bus_matrix_ahb/u_dut/u_core/slv_req
add_wave -radix hex /tb_bus_matrix_ahb/u_dut/u_core/slv_addr
add_wave -radix hex /tb_bus_matrix_ahb/u_dut/u_core/slv_we
add_wave -radix hex /tb_bus_matrix_ahb/u_dut/u_core/slv_done
add_wave -radix hex /tb_bus_matrix_ahb/u_dut/u_core/slv_err

add_wave_divider "Arbiters"
add_wave {/tb_bus_matrix_ahb/u_dut/u_core/gen_arb[0]/u_arb/gnt}
add_wave {/tb_bus_matrix_ahb/u_dut/u_core/gen_arb[1]/u_arb/gnt}
add_wave {/tb_bus_matrix_ahb/u_dut/u_core/gen_arb[2]/u_arb/gnt}
add_wave {/tb_bus_matrix_ahb/u_dut/u_core/gen_arb[3]/u_arb/gnt}
