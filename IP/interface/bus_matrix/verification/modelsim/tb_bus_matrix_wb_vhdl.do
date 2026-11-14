# tb_bus_matrix_wb_vhdl.do — ModelSim GUI script for the Wishbone B4 bus_matrix VHDL testbench
#
# VHDL twin of tb_bus_matrix_wb.do (VHDL-2008 RTL + VHDL testbench).
#
# Usage (from ModelSim Transcript or File > Run Script):
#   do /path/to/verification/modelsim/tb_bus_matrix_wb_vhdl.do
#
# Requires CLAUDE_BUS_MATRIX_PATH and IP_COMMON_PATH environment variables, OR
# run from the IP/interface/bus_matrix directory so that relative paths resolve.
# Batch runs use sim_bus_matrix.py --sim modelsim --lang vhdl instead.
#
# Waveform groups:
#   Clock & Reset | Master ports | Slave ports | Core handshake | Arbiters

# ---------------------------------------------------------------------------
# Path setup
# ---------------------------------------------------------------------------
if {[info exists env(CLAUDE_BUS_MATRIX_PATH)]} {
    set BM     $env(CLAUDE_BUS_MATRIX_PATH)
} else {
    # Assume script is in verification/modelsim/ — step up two levels
    set BM     [file normalize [file dirname [info script]]/../..]
}

if {[info exists env(IP_COMMON_PATH)]} {
    set COMMON $env(IP_COMMON_PATH)
} else {
    set COMMON [file normalize ${BM}/../../common]
}

set RTL    ${BM}/design/rtl/vhdl
set TB     ${BM}/verification/testbench
set WORK   ${BM}/verification/work/modelsim/wb_vhdl

# ---------------------------------------------------------------------------
# Create work library
# ---------------------------------------------------------------------------
# Work from ${WORK} with a local "work" library (as sim_bus_matrix.py does):
# no vmap, so no modelsim.ini is written and each run gets its own library.
file mkdir ${WORK}
cd ${WORK}
vlib work

# ---------------------------------------------------------------------------
# Compile RTL and testbench (VHDL-2008, dependency order)
# ---------------------------------------------------------------------------
vcom -2008 -work work ${RTL}/bus_matrix_pkg.vhd
vcom -2008 -work work ${RTL}/bus_matrix_decoder.vhd
vcom -2008 -work work ${RTL}/bus_matrix_arb.vhd
vcom -2008 -work work ${RTL}/bus_matrix_core.vhd
vcom -2008 -work work ${RTL}/bus_matrix_wb_tgt.vhd
vcom -2008 -work work ${RTL}/bus_matrix_wb_ini.vhd
vcom -2008 -work work ${RTL}/bus_matrix_wb.vhd
vcom -2008 -work work ${COMMON}/design/rtl/vhdl/claude_wb_if.vhd
vcom -2008 -work work ${COMMON}/verification/tests/ip_test_pkg.vhd
vcom -2008 -work work ${TB}/bus_matrix_tb_mem.vhd
vcom -2008 -work work ${TB}/bus_matrix_tb_wb_master.vhd
vcom -2008 -work work ${TB}/tb_bus_matrix_wb.vhd

# ---------------------------------------------------------------------------
# Start simulation
# ---------------------------------------------------------------------------
vsim -voptargs=+acc work.tb_bus_matrix_wb

# ---------------------------------------------------------------------------
# Load waveform configuration and run
# ---------------------------------------------------------------------------
do ${BM}/verification/modelsim/tb_bus_matrix_wb_vhdl_wave.do

run -all

wave zoom full
