# synth_bus_matrix_wb.tcl — Quartus Prime Analysis & Synthesis for bus_matrix_wb.
#
# Target: Cyclone V SE (5CSEMA4U23C6)
#
# Usage:
#   cd IP/interface/bus_matrix
#   source setup.sh
#   quartus_sh -t synthesis/quartus/synth_bus_matrix_wb.tcl

package require ::quartus::project
package require ::quartus::flow

set DEVICE     "5CSEMA4U23C6"
set TOP        "bus_matrix_wb"
set DESIGN_DIR "$::env(CLAUDE_BUS_MATRIX_PATH)/design/rtl/verilog"
set WORK_DIR   "$::env(CLAUDE_BUS_MATRIX_PATH)/synthesis/quartus/work/$TOP"

file mkdir $WORK_DIR

# Create or overwrite project
if {[project_exists $WORK_DIR/$TOP]} {
    project_open -force $WORK_DIR/$TOP
} else {
    project_new -overwrite -part $DEVICE $WORK_DIR/$TOP
}

# Source files
foreach sv_file [list \
    $DESIGN_DIR/bus_matrix_decoder.sv \
    $DESIGN_DIR/bus_matrix_arb.sv \
    $DESIGN_DIR/bus_matrix_core.sv \
    $DESIGN_DIR/bus_matrix_wb.sv \
] {
    set_global_assignment -name SYSTEMVERILOG_FILE $sv_file
}

# Project settings
set_global_assignment -name TOP_LEVEL_ENTITY $TOP
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE $DEVICE

# Write SDC if it does not exist
set sdc_file "$WORK_DIR/${TOP}.sdc"
if {![file exists $sdc_file]} {
    set fh [open $sdc_file w]
    puts $fh "create_clock -period 10.000 -name PCLK \[get_ports clk\]"
    close $fh
}
set_global_assignment -name SDC_FILE $sdc_file

# Run Analysis & Synthesis only (no Fitter)
execute_module -tool map

project_close

puts "Quartus synthesis of $TOP complete."
