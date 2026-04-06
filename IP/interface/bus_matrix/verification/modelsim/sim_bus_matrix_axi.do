# sim_bus_matrix_axi.do — ModelSim compile and simulate for AXI4-Lite bus_matrix testbench.
# Usage: vsim -do sim_bus_matrix_axi.do
# Waveforms: source sim_bus_matrix_axi_wave.do  (inside ModelSim after sim starts)

quietly set DESIGN_DIR   ../../design/rtl/verilog
quietly set TB_DIR       ../testbench
quietly set TESTS_DIR    ../tests
quietly set COMMON_TESTS ../../../../common/verification/tests
quietly set COMMON_TASKS ../../../../common/verification/tasks

# Create and map work library
if {[file exists work]} { vdel -lib work -all }
vlib work
vmap work work

# Compile design RTL
vlog -sv -work work \
    +incdir+$DESIGN_DIR \
    $DESIGN_DIR/bus_matrix_arb.sv \
    $DESIGN_DIR/bus_matrix_decoder.sv \
    $DESIGN_DIR/bus_matrix_core.sv \
    $DESIGN_DIR/bus_matrix_axi.sv

# Compile BFMs
vlog -sv -work work \
    +incdir+$TB_DIR \
    $TB_DIR/bus_matrix_axi_master.sv \
    $TB_DIR/bus_matrix_axi_slave.sv

# Compile testbench (SV)
vlog -sv -work work \
    +incdir+$TB_DIR \
    +incdir+$TESTS_DIR \
    +incdir+$COMMON_TESTS \
    +incdir+$COMMON_TASKS \
    $TB_DIR/tb_bus_matrix_axi.sv

# Simulate
vsim -t 1ns -lib work work.tb_bus_matrix_axi \
    -voptargs="+acc"
set StdArithNoWarnings 1
set NumericStdNoWarnings 1
run -all
quit -f
