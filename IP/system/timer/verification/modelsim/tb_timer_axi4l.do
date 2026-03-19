# tb_timer_axi4l.do — ModelSim GUI script for AXI4-Lite timer testbench
#
# Usage (from ModelSim Transcript or File > Run Script):
#   do /path/to/verification/modelsim/tb_timer_axi4l.do
#
# Requires CLAUDE_TIMER_PATH and IP_COMMON_PATH environment variables, OR
# run from the IP/system/timer directory so that relative paths resolve.

# ---------------------------------------------------------------------------
# Path setup
# ---------------------------------------------------------------------------
if {[info exists env(CLAUDE_TIMER_PATH)]} {
    set TIMER  $env(CLAUDE_TIMER_PATH)
} else {
    set TIMER  [file normalize [file dirname [info script]]/../..]
}

if {[info exists env(IP_COMMON_PATH)]} {
    set COMMON $env(IP_COMMON_PATH)
} else {
    set COMMON [file normalize ${TIMER}/../../common]
}

set RTL    ${TIMER}/design/rtl/verilog
set TASKS  ${COMMON}/verification/tasks
set TESTS  ${TIMER}/verification/tests
set TB     ${TIMER}/verification/testbench
set WORK   ${TIMER}/verification/work/modelsim/axi4l_sv

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
    +incdir+${TASKS}+${TESTS} \
    ${RTL}/timer_reg_pkg.sv \
    ${RTL}/timer_regfile.sv \
    ${RTL}/timer_core.sv \
    ${RTL}/timer_axi4l_if.sv \
    ${RTL}/timer_axi4l.sv \
    ${TB}/tb_timer_axi4l.sv

# ---------------------------------------------------------------------------
# Start simulation
# ---------------------------------------------------------------------------
vsim -voptargs=+acc work.tb_timer_axi4l

# ---------------------------------------------------------------------------
# Load waveform configuration and run
# ---------------------------------------------------------------------------
do [file join [file dirname [info script]] tb_timer_axi4l_wave.do]

run -all

wave zoom full
