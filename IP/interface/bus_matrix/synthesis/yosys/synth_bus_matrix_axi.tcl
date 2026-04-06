# synth_bus_matrix_axi.tcl — Yosys synthesis script for bus_matrix_axi.
#
# Usage:
#   cd IP/interface/bus_matrix
#   source setup.sh
#   yosys synthesis/yosys/synth_bus_matrix_axi.tcl

set DESIGN_DIR  ../../design/rtl/verilog
set OUT_DIR     synthesis/yosys/output

file mkdir $OUT_DIR

yosys plugin -i slang
yosys read_slang \
    $DESIGN_DIR/bus_matrix_arb.sv \
    $DESIGN_DIR/bus_matrix_decoder.sv \
    $DESIGN_DIR/bus_matrix_core.sv \
    $DESIGN_DIR/bus_matrix_axi.sv

yosys hierarchy -check -top bus_matrix_axi
yosys proc
yosys flatten
yosys opt -full
yosys opt_clean -purge
yosys synth -top bus_matrix_axi

yosys write_json  $OUT_DIR/bus_matrix_axi.json
yosys write_verilog -noattr $OUT_DIR/bus_matrix_axi_synth.v
yosys stat -top bus_matrix_axi

yosys log "Synthesis complete. Outputs in $OUT_DIR/"
