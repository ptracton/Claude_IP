# sim_bus_matrix_wb.do — ModelSim compile and simulate for Wishbone bus_matrix testbench.
# Usage: vsim -do sim_bus_matrix_wb.do
# Waveforms: source sim_bus_matrix_wb_wave.do  (inside ModelSim after sim starts)

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
    $DESIGN_DIR/bus_matrix_wb.sv

# Compile BFMs
vlog -sv -work work \
    +incdir+$TB_DIR \
    $TB_DIR/bus_matrix_wb_master.sv \
    $TB_DIR/bus_matrix_wb_slave.sv

# Compile testbench (SV)
vlog -sv -work work \
    +incdir+$TB_DIR \
    +incdir+$TESTS_DIR \
    +incdir+$COMMON_TESTS \
    +incdir+$COMMON_TASKS \
    $TB_DIR/tb_bus_matrix_wb.sv

# Simulate
vsim -t 1ns -lib work work.tb_bus_matrix_wb \
    -voptargs="+acc"
set StdArithNoWarnings 1
set NumericStdNoWarnings 1
run -all
quit -f
