# tb_bus_matrix_wb.do — ModelSim GUI script for the Wishbone B4 bus_matrix testbench
#
# Usage (from ModelSim Transcript or File > Run Script):
#   do /path/to/verification/modelsim/tb_bus_matrix_wb.do
#
# Requires CLAUDE_BUS_MATRIX_PATH and IP_COMMON_PATH environment variables, OR
# run from the IP/interface/bus_matrix directory so that relative paths resolve.
# Batch runs use sim_bus_matrix.py --sim modelsim instead.
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

set RTL    ${BM}/design/rtl/verilog
set TASKS  ${COMMON}/verification/tasks
set CTESTS ${COMMON}/verification/tests
set TESTS  ${BM}/verification/tests
set TB     ${BM}/verification/testbench
set WORK   ${BM}/verification/work/modelsim/wb_sv

# ---------------------------------------------------------------------------
# Create work library
# ---------------------------------------------------------------------------
file mkdir ${WORK}
vlib ${WORK}/work
vmap work ${WORK}/work

# ---------------------------------------------------------------------------
# Compile RTL and testbench
# ---------------------------------------------------------------------------
vlog -sv -work work \
    +incdir+${TASKS}+${CTESTS}+${TESTS} \
    ${RTL}/bus_matrix_pkg.sv \
    ${RTL}/bus_matrix_decoder.sv \
    ${RTL}/bus_matrix_arb.sv \
    ${RTL}/bus_matrix_core.sv \
    ${RTL}/bus_matrix_wb_tgt.sv \
    ${RTL}/bus_matrix_wb_ini.sv \
    ${RTL}/bus_matrix_wb.sv \
    ${COMMON}/design/rtl/verilog/claude_wb_if.sv \
    ${TB}/bus_matrix_wb_bfm.sv \
    ${TB}/bus_matrix_tb_mem.sv \
    ${TB}/tb_bus_matrix_wb.sv

# ---------------------------------------------------------------------------
# Start simulation
# ---------------------------------------------------------------------------
vsim -voptargs=+acc work.tb_bus_matrix_wb

# ---------------------------------------------------------------------------
# Load waveform configuration and run
# ---------------------------------------------------------------------------
do [file join [file dirname [info script]] tb_bus_matrix_wb_wave.do]

run -all

wave zoom full
