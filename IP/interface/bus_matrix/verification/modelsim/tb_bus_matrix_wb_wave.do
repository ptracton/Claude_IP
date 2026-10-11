onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Clock & Reset}
add wave -noupdate -radix binary /tb_bus_matrix_wb/clk
add wave -noupdate -radix binary /tb_bus_matrix_wb/rst_n
add wave -noupdate -divider {Master ports}
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/M_CYC
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/M_STB
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/M_WE
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/M_ADR
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/M_DAT_I
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/M_SEL
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/M_DAT_O
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/M_ACK
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/M_ERR
add wave -noupdate -divider {Slave ports}
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/S_CYC
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/S_STB
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/S_WE
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/S_ADR
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/S_DAT_O
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/S_SEL
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/S_DAT_I
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/S_ACK
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/S_ERR
add wave -noupdate -divider {Core handshake}
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/u_dut/u_core/mst_req
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/u_dut/u_core/mst_addr
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/u_dut/u_core/mst_we
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/u_dut/u_core/mst_done
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/u_dut/u_core/mst_err
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/u_dut/u_core/slv_req
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/u_dut/u_core/slv_addr
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/u_dut/u_core/slv_we
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/u_dut/u_core/slv_done
add wave -noupdate -radix hexadecimal /tb_bus_matrix_wb/u_dut/u_core/slv_err
add wave -noupdate -divider {Arbiters}
add wave -noupdate -radix binary {/tb_bus_matrix_wb/u_dut/u_core/gen_arb[0]/u_arb/gnt}
add wave -noupdate -radix binary {/tb_bus_matrix_wb/u_dut/u_core/gen_arb[1]/u_arb/gnt}
add wave -noupdate -radix binary {/tb_bus_matrix_wb/u_dut/u_core/gen_arb[2]/u_arb/gnt}
add wave -noupdate -radix binary {/tb_bus_matrix_wb/u_dut/u_core/gen_arb[3]/u_arb/gnt}
TreeUpdate [SetDefaultTree]
configure wave -namecolwidth 260
configure wave -timelineunits ns
update
