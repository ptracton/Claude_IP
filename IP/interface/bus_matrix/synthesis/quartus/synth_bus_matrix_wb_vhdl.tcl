# synth_bus_matrix_wb_vhdl.tcl — Quartus Prime Analysis & Synthesis of the VHDL-2008 bus_matrix_wb (Wishbone).
#
# Target: Cyclone V SE (5CSEMA4U23C6). Default configuration (bus_matrix_pkg).
# VHDL twin of synth_bus_matrix_wb.tcl; the project lives in work/bus_matrix_wb_vhdl/.
#
# Usage:
#   cd IP/interface/bus_matrix
#   source setup.sh
#   quartus_sh -t synthesis/quartus/synth_bus_matrix_wb_vhdl.tcl

package require ::quartus::project
package require ::quartus::flow

set DEVICE     "5CSEMA4U23C6"
set TOP        "bus_matrix_wb"
set NAME       "bus_matrix_wb_vhdl"
set DESIGN_DIR "$::env(CLAUDE_BUS_MATRIX_PATH)/design/rtl/vhdl"
set WORK_DIR   "$::env(CLAUDE_BUS_MATRIX_PATH)/synthesis/quartus/work/$NAME"

file mkdir $WORK_DIR

# Create or overwrite project
if {[project_exists $WORK_DIR/$NAME]} {
    project_open -force $WORK_DIR/$NAME
} else {
    project_new -overwrite -part $DEVICE $WORK_DIR/$NAME
}

# Source files (package first), VHDL-2008
set_global_assignment -name VHDL_INPUT_VERSION VHDL_2008
foreach vhd_file [list \
    $DESIGN_DIR/bus_matrix_pkg.vhd \
    $DESIGN_DIR/bus_matrix_decoder.vhd \
    $DESIGN_DIR/bus_matrix_arb.vhd \
    $DESIGN_DIR/bus_matrix_core.vhd \
    $DESIGN_DIR/bus_matrix_wb_tgt.vhd \
    $DESIGN_DIR/bus_matrix_wb_ini.vhd \
    $DESIGN_DIR/bus_matrix_wb.vhd \
] {
    set_global_assignment -name VHDL_FILE $vhd_file -hdl_version VHDL_2008
}

# Project settings
set_global_assignment -name TOP_LEVEL_ENTITY $TOP
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE $DEVICE

# Write SDC if it does not exist
set sdc_file "$WORK_DIR/${NAME}.sdc"
if {![file exists $sdc_file]} {
    set fh [open $sdc_file w]
    puts $fh "create_clock -period 10.000 -name clk \[get_ports clk\]"
    close $fh
}
set_global_assignment -name SDC_FILE $sdc_file

# Run Analysis & Synthesis only (no Fitter)
execute_module -tool map

project_close

puts "Quartus synthesis of $NAME complete."
