# synth_bus_matrix_ahb_vhdl.tcl — Vivado OOC synthesis of the VHDL-2008 bus_matrix_ahb (AHB-Lite).
#
# Target: Zynq-7010 (xc7z010clg400-1), 100 MHz. Default configuration
# (bus_matrix_pkg). VHDL twin of synth_bus_matrix_ahb.tcl; outputs are named
# bus_matrix_ahb_vhdl_* so both can share work/.
#
# Usage:
#   cd IP/interface/bus_matrix
#   source setup.sh
#   vivado -mode batch -source synthesis/vivado/synth_bus_matrix_ahb_vhdl.tcl

set PART       "xc7z010clg400-1"
set TOP        "bus_matrix_ahb"
set NAME       "bus_matrix_ahb_vhdl"
set DESIGN_DIR "$::env(CLAUDE_BUS_MATRIX_PATH)/design/rtl/vhdl"
set OUT_DIR    "$::env(CLAUDE_BUS_MATRIX_PATH)/synthesis/vivado/work"

file mkdir $OUT_DIR

# Create in-memory project
create_project -in_memory -part $PART
set_property target_language VHDL [current_project]

# Read VHDL-2008 RTL sources (package first)
foreach f [list \
    $DESIGN_DIR/bus_matrix_pkg.vhd \
    $DESIGN_DIR/bus_matrix_decoder.vhd \
    $DESIGN_DIR/bus_matrix_arb.vhd \
    $DESIGN_DIR/bus_matrix_core.vhd \
    $DESIGN_DIR/bus_matrix_ahb_tgt.vhd \
    $DESIGN_DIR/bus_matrix_ahb_ini.vhd \
    $DESIGN_DIR/bus_matrix_ahb.vhd \
] {
    read_vhdl -vhdl2008 $f
}

# Write OOC clock constraint to a temp XDC file
set xdc_file "$OUT_DIR/${NAME}_ooc.xdc"
set fh [open $xdc_file w]
puts $fh "create_clock -period 10.000 -name clk \[get_ports clk\]"
close $fh
read_xdc $xdc_file

# Synthesize
synth_design -top $TOP -part $PART \
    -flatten_hierarchy rebuilt \
    -mode out_of_context

# Reports
report_utilization     -file $OUT_DIR/${NAME}_utilization.rpt
report_timing_summary  -file $OUT_DIR/${NAME}_timing_summary.rpt

puts "Vivado synthesis of $NAME complete."
