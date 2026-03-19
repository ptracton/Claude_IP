# create_project_wb.tcl — Vivado project for timer Wishbone B4 simulation
#
# Usage:
#   vivado -mode tcl -source create_project_wb.tcl
#   or: source create_project_wb.tcl   (from the Vivado Tcl console)
#
# Creates a project targeting xc7z010clg400-1 (Zynq-7010, same as synthesis).
# Note: Wishbone uses active-high synchronous RST_I (not PRESETn/HRESETn).

# ---------------------------------------------------------------------------
# Path setup
# ---------------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]

if {[info exists ::env(CLAUDE_TIMER_PATH)]} {
    set timer_dir $::env(CLAUDE_TIMER_PATH)
} else {
    set timer_dir [file normalize "${script_dir}/../.."]
}

if {[info exists ::env(IP_COMMON_PATH)]} {
    set common_dir $::env(IP_COMMON_PATH)
} else {
    set common_dir [file normalize "${timer_dir}/../../common"]
}

set rtl_dir   "${timer_dir}/design/rtl/verilog"
set tasks_dir "${common_dir}/verification/tasks"
set tests_dir "${timer_dir}/verification/tests"
set tb_dir    "${timer_dir}/verification/testbench"
set work_dir  "${timer_dir}/verification/vivado/work/wb"
set wave_tcl  "${script_dir}/wave_wb.tcl"

# ---------------------------------------------------------------------------
# Create project
# ---------------------------------------------------------------------------
create_project tb_timer_wb "${work_dir}" -part xc7z010clg400-1 -force
set_property simulator_language Mixed [current_project]
set_property target_language Verilog  [current_project]

# ---------------------------------------------------------------------------
# Add RTL design sources
# ---------------------------------------------------------------------------
add_files -norecurse [list \
    "${rtl_dir}/timer_reg_pkg.sv" \
    "${rtl_dir}/timer_regfile.sv" \
    "${rtl_dir}/timer_core.sv"    \
    "${rtl_dir}/timer_wb_if.sv"   \
    "${rtl_dir}/timer_wb.sv"      \
]

foreach f [get_files -of_objects [get_filesets sources_1] -filter {FILE_EXT == ".sv"}] {
    set_property file_type SystemVerilog $f
}

# ---------------------------------------------------------------------------
# Add simulation-only sources (testbench)
# ---------------------------------------------------------------------------
add_files -norecurse -sim_only "${tb_dir}/tb_timer_wb.sv"
set_property file_type SystemVerilog [get_files tb_timer_wb.sv]

# ---------------------------------------------------------------------------
# Simulation fileset configuration
# ---------------------------------------------------------------------------
set_property top              tb_timer_wb        [get_filesets sim_1]
set_property top_lib          xil_defaultlib     [get_filesets sim_1]
set_property include_dirs     [list "${tasks_dir}" "${tests_dir}"] \
                              [get_filesets sim_1]
set_property -name {xsim.simulate.runtime}    -value {1ms}       -objects [get_filesets sim_1]
set_property -name {xsim.simulate.custom_tcl} -value "${wave_tcl}" -objects [get_filesets sim_1]

# ---------------------------------------------------------------------------
# Update compile order
# ---------------------------------------------------------------------------
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "Project created: ${work_dir}/tb_timer_wb.xpr"
puts "To simulate:     File > Open Project > work/wb/tb_timer_wb.xpr"
puts "                 then Flow > Run Simulation > Run Behavioral Simulation"
