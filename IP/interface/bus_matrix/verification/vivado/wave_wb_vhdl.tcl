# wave_wb_vhdl.tcl — Vivado xsim wave configuration for the VHDL Wishbone B4 bus_matrix testbench
#
# Sourced automatically when simulation runs (xsim.simulate.custom_tcl).
# Can also be sourced manually from the Vivado Tcl console after
# launching simulation (`restart` first: the script ends with `run -all`).

add_wave_divider "Clock & Reset"
add_wave /tb_bus_matrix_wb/clk
add_wave /tb_bus_matrix_wb/rst_n

add_wave_divider "Master ports"
add_wave -radix hex /tb_bus_matrix_wb/M_CYC
add_wave -radix hex /tb_bus_matrix_wb/M_STB
add_wave -radix hex /tb_bus_matrix_wb/M_WE
add_wave -radix hex /tb_bus_matrix_wb/M_ADR
add_wave -radix hex /tb_bus_matrix_wb/M_DAT_I
add_wave -radix hex /tb_bus_matrix_wb/M_SEL
add_wave -radix hex /tb_bus_matrix_wb/M_DAT_O
add_wave -radix hex /tb_bus_matrix_wb/M_ACK
add_wave -radix hex /tb_bus_matrix_wb/M_ERR

add_wave_divider "Slave ports"
add_wave -radix hex /tb_bus_matrix_wb/S_CYC
add_wave -radix hex /tb_bus_matrix_wb/S_STB
add_wave -radix hex /tb_bus_matrix_wb/S_WE
add_wave -radix hex /tb_bus_matrix_wb/S_ADR
add_wave -radix hex /tb_bus_matrix_wb/S_DAT_O
add_wave -radix hex /tb_bus_matrix_wb/S_SEL
add_wave -radix hex /tb_bus_matrix_wb/S_DAT_I
add_wave -radix hex /tb_bus_matrix_wb/S_ACK
add_wave -radix hex /tb_bus_matrix_wb/S_ERR

add_wave_divider "Core handshake"
add_wave -radix hex /tb_bus_matrix_wb/u_dut/u_core/mst_req
add_wave -radix hex /tb_bus_matrix_wb/u_dut/u_core/mst_addr
add_wave -radix hex /tb_bus_matrix_wb/u_dut/u_core/mst_we
add_wave -radix hex /tb_bus_matrix_wb/u_dut/u_core/mst_done
add_wave -radix hex /tb_bus_matrix_wb/u_dut/u_core/mst_err
add_wave -radix hex /tb_bus_matrix_wb/u_dut/u_core/slv_req
add_wave -radix hex /tb_bus_matrix_wb/u_dut/u_core/slv_addr
add_wave -radix hex /tb_bus_matrix_wb/u_dut/u_core/slv_we
add_wave -radix hex /tb_bus_matrix_wb/u_dut/u_core/slv_done
add_wave -radix hex /tb_bus_matrix_wb/u_dut/u_core/slv_err

add_wave_divider "Arbiters"
# The core's grant vector (NUM_MASTERS bits per slave), as in wave_wb.tcl.
add_wave {/tb_bus_matrix_wb/u_dut/u_core/gnt}

# xsim.simulate.custom_tcl replaces Vivado's default simulate script, which
# would otherwise issue the run command, so run the testbench to its end here.
run -all
