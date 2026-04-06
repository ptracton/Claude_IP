# synth_bus_matrix_axi.tcl — Vivado OOC synthesis for bus_matrix_axi.
#
# Target: Zynq-7010 (xc7z010clg400-1)
#
# Usage:
#   cd IP/interface/bus_matrix
#   source setup.sh
#   vivado -mode batch -source synthesis/vivado/synth_bus_matrix_axi.tcl

set PART       "xc7z010clg400-1"
set TOP        "bus_matrix_axi"
set DESIGN_DIR "$::env(CLAUDE_BUS_MATRIX_PATH)/design/rtl/verilog"
set OUT_DIR    "$::env(CLAUDE_BUS_MATRIX_PATH)/synthesis/vivado/work"

file mkdir $OUT_DIR

# Create in-memory project
create_project -in_memory -part $PART
set_property target_language Verilog [current_project]

# Read SV RTL sources
read_verilog -sv $DESIGN_DIR/bus_matrix_decoder.sv
read_verilog -sv $DESIGN_DIR/bus_matrix_arb.sv
read_verilog -sv $DESIGN_DIR/bus_matrix_core.sv
read_verilog -sv $DESIGN_DIR/bus_matrix_axi.sv

# Write OOC clock constraint to a temp XDC file
set xdc_file "$OUT_DIR/${TOP}_ooc.xdc"
set fh [open $xdc_file w]
puts $fh "create_clock -period 10.000 -name PCLK \[get_ports clk\]"
close $fh
read_xdc $xdc_file

# Synthesize
synth_design -top $TOP -part $PART \
    -flatten_hierarchy rebuilt \
    -mode out_of_context

# Reports
report_utilization     -file $OUT_DIR/${TOP}_utilization.rpt
report_timing_summary  -file $OUT_DIR/${TOP}_timing_summary.rpt

puts "Vivado synthesis of $TOP complete."
