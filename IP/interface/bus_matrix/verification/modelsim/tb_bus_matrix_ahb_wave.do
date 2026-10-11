onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Clock & Reset}
add wave -noupdate -radix binary /tb_bus_matrix_ahb/clk
add wave -noupdate -radix binary /tb_bus_matrix_ahb/rst_n
add wave -noupdate -divider {Master ports}
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/M_HSEL
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/M_HADDR
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/M_HTRANS
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/M_HWRITE
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/M_HWDATA
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/M_HWSTRB
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/M_HREADY
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/M_HRDATA
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/M_HRESP
add wave -noupdate -divider {Slave ports}
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/S_HSEL
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/S_HADDR
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/S_HTRANS
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/S_HWRITE
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/S_HWDATA
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/S_HWSTRB
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/S_HREADY
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/S_HRDATA
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/S_HRESP
add wave -noupdate -divider {Core handshake}
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/u_dut/u_core/mst_req
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/u_dut/u_core/mst_addr
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/u_dut/u_core/mst_we
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/u_dut/u_core/mst_done
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/u_dut/u_core/mst_err
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/u_dut/u_core/slv_req
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/u_dut/u_core/slv_addr
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/u_dut/u_core/slv_we
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/u_dut/u_core/slv_done
add wave -noupdate -radix hexadecimal /tb_bus_matrix_ahb/u_dut/u_core/slv_err
add wave -noupdate -divider {Arbiters}
add wave -noupdate -radix binary {/tb_bus_matrix_ahb/u_dut/u_core/gen_arb[0]/u_arb/gnt}
add wave -noupdate -radix binary {/tb_bus_matrix_ahb/u_dut/u_core/gen_arb[1]/u_arb/gnt}
add wave -noupdate -radix binary {/tb_bus_matrix_ahb/u_dut/u_core/gen_arb[2]/u_arb/gnt}
add wave -noupdate -radix binary {/tb_bus_matrix_ahb/u_dut/u_core/gen_arb[3]/u_arb/gnt}
TreeUpdate [SetDefaultTree]
configure wave -namecolwidth 260
configure wave -timelineunits ns
update
