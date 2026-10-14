# wave_apb.tcl — Vivado xsim wave configuration for the APB4 bus_matrix testbench
#
# Sourced automatically when simulation runs (xsim.simulate.custom_tcl).
# Can also be sourced manually from the Vivado Tcl console after
# launching simulation.

add_wave_divider "Clock & Reset"
add_wave /tb_bus_matrix_apb/clk
add_wave /tb_bus_matrix_apb/rst_n

add_wave_divider "Master ports"
add_wave -radix hex /tb_bus_matrix_apb/M_PSEL
add_wave -radix hex /tb_bus_matrix_apb/M_PENABLE
add_wave -radix hex /tb_bus_matrix_apb/M_PADDR
add_wave -radix hex /tb_bus_matrix_apb/M_PWRITE
add_wave -radix hex /tb_bus_matrix_apb/M_PWDATA
add_wave -radix hex /tb_bus_matrix_apb/M_PSTRB
add_wave -radix hex /tb_bus_matrix_apb/M_PRDATA
add_wave -radix hex /tb_bus_matrix_apb/M_PREADY
add_wave -radix hex /tb_bus_matrix_apb/M_PSLVERR

add_wave_divider "Slave ports"
add_wave -radix hex /tb_bus_matrix_apb/S_PSEL
add_wave -radix hex /tb_bus_matrix_apb/S_PENABLE
add_wave -radix hex /tb_bus_matrix_apb/S_PADDR
add_wave -radix hex /tb_bus_matrix_apb/S_PWRITE
add_wave -radix hex /tb_bus_matrix_apb/S_PWDATA
add_wave -radix hex /tb_bus_matrix_apb/S_PSTRB
add_wave -radix hex /tb_bus_matrix_apb/S_PRDATA
add_wave -radix hex /tb_bus_matrix_apb/S_PREADY
add_wave -radix hex /tb_bus_matrix_apb/S_PSLVERR

add_wave_divider "Core handshake"
add_wave -radix hex /tb_bus_matrix_apb/u_dut/u_core/mst_req
add_wave -radix hex /tb_bus_matrix_apb/u_dut/u_core/mst_addr
add_wave -radix hex /tb_bus_matrix_apb/u_dut/u_core/mst_we
add_wave -radix hex /tb_bus_matrix_apb/u_dut/u_core/mst_done
add_wave -radix hex /tb_bus_matrix_apb/u_dut/u_core/mst_err
add_wave -radix hex /tb_bus_matrix_apb/u_dut/u_core/slv_req
add_wave -radix hex /tb_bus_matrix_apb/u_dut/u_core/slv_addr
add_wave -radix hex /tb_bus_matrix_apb/u_dut/u_core/slv_we
add_wave -radix hex /tb_bus_matrix_apb/u_dut/u_core/slv_done
add_wave -radix hex /tb_bus_matrix_apb/u_dut/u_core/slv_err

add_wave_divider "Arbiters"
# xsim names generate scopes "\gen_arb[j].u_arb ", so add the core's grant
# array (one entry per slave) instead of each arbiter's gnt.
add_wave {/tb_bus_matrix_apb/u_dut/u_core/gnt}
