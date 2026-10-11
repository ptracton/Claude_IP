onerror {resume}
quietly WaveActivateNextPane {} 0
add wave -noupdate -divider {Clock & Reset}
add wave -noupdate -radix binary /tb_bus_matrix_apb/clk
add wave -noupdate -radix binary /tb_bus_matrix_apb/rst_n
add wave -noupdate -divider {Master ports}
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/M_PSEL
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/M_PENABLE
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/M_PADDR
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/M_PWRITE
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/M_PWDATA
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/M_PSTRB
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/M_PRDATA
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/M_PREADY
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/M_PSLVERR
add wave -noupdate -divider {Slave ports}
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/S_PSEL
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/S_PENABLE
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/S_PADDR
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/S_PWRITE
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/S_PWDATA
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/S_PSTRB
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/S_PRDATA
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/S_PREADY
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/S_PSLVERR
add wave -noupdate -divider {Core handshake}
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/u_dut/u_core/mst_req
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/u_dut/u_core/mst_addr
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/u_dut/u_core/mst_we
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/u_dut/u_core/mst_done
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/u_dut/u_core/mst_err
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/u_dut/u_core/slv_req
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/u_dut/u_core/slv_addr
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/u_dut/u_core/slv_we
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/u_dut/u_core/slv_done
add wave -noupdate -radix hexadecimal /tb_bus_matrix_apb/u_dut/u_core/slv_err
add wave -noupdate -divider {Arbiters}
add wave -noupdate -radix binary {/tb_bus_matrix_apb/u_dut/u_core/gen_arb[0]/u_arb/gnt}
add wave -noupdate -radix binary {/tb_bus_matrix_apb/u_dut/u_core/gen_arb[1]/u_arb/gnt}
add wave -noupdate -radix binary {/tb_bus_matrix_apb/u_dut/u_core/gen_arb[2]/u_arb/gnt}
add wave -noupdate -radix binary {/tb_bus_matrix_apb/u_dut/u_core/gen_arb[3]/u_arb/gnt}
TreeUpdate [SetDefaultTree]
configure wave -namecolwidth 260
configure wave -timelineunits ns
update
