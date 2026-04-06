# synth_bus_matrix_ahb.tcl — Yosys synthesis script for bus_matrix_ahb.
#
# Targets generic liberty/JSON output (technology-independent netlist).
# For FPGA targets use synth_ice40 or synth_xilinx instead of synth.
#
# Usage:
#   cd IP/interface/bus_matrix
#   source setup.sh
#   yosys synthesis/yosys/synth_bus_matrix_ahb.tcl

set DESIGN_DIR  ../../design/rtl/verilog
set OUT_DIR     synthesis/yosys/output

file mkdir $OUT_DIR

# ---- Read design sources (slang plugin for full SV-2012 package support) ---
yosys plugin -i slang
yosys read_slang \
    $DESIGN_DIR/bus_matrix_arb.sv \
    $DESIGN_DIR/bus_matrix_decoder.sv \
    $DESIGN_DIR/bus_matrix_core.sv \
    $DESIGN_DIR/bus_matrix_ahb.sv

# ---- Elaborate and check ---------------------------------------------------
yosys hierarchy -check -top bus_matrix_ahb
yosys proc
yosys flatten

# ---- Optimise --------------------------------------------------------------
yosys opt -full
yosys opt_clean -purge

# ---- Technology-independent synthesis -------------------------------------
yosys synth -top bus_matrix_ahb

# ---- Write outputs ---------------------------------------------------------
yosys write_json  $OUT_DIR/bus_matrix_ahb.json
yosys write_verilog -noattr $OUT_DIR/bus_matrix_ahb_synth.v

# ---- Statistics ------------------------------------------------------------
yosys stat -top bus_matrix_ahb

yosys log "Synthesis complete. Outputs in $OUT_DIR/"
