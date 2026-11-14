# create_project_wb_vhdl.tcl — Vivado project for Wishbone B4 bus_matrix VHDL simulation
#
# VHDL twin of create_project_wb.tcl: VHDL-2008 RTL and VHDL testbench.
#
# Usage:
#   vivado -mode tcl -source create_project_wb_vhdl.tcl
#   or: source create_project_wb_vhdl.tcl   (from the Vivado Tcl console)
#
# Creates a project targeting xc7z010clg400-1 (Zynq-7010, same as synthesis).
# After creation, open the .xpr in Vivado and click Run Simulation.
# Batch runs use sim_bus_matrix.py --sim xsim --lang vhdl instead.

# ---------------------------------------------------------------------------
# Path setup
# ---------------------------------------------------------------------------
set script_dir [file normalize [file dirname [info script]]]

if {[info exists ::env(CLAUDE_BUS_MATRIX_PATH)]} {
    set bm_dir $::env(CLAUDE_BUS_MATRIX_PATH)
} else {
    set bm_dir [file normalize "${script_dir}/../.."]
}

if {[info exists ::env(IP_COMMON_PATH)]} {
    set common_dir $::env(IP_COMMON_PATH)
} else {
    set common_dir [file normalize "${bm_dir}/../../common"]
}

set rtl_dir    "${bm_dir}/design/rtl/vhdl"
set tb_dir     "${bm_dir}/verification/testbench"
set work_dir   "${bm_dir}/verification/vivado/work/wb_vhdl"
set wave_tcl   "${script_dir}/wave_wb_vhdl.tcl"

# ---------------------------------------------------------------------------
# Create project
# ---------------------------------------------------------------------------
create_project tb_bus_matrix_wb_vhdl "${work_dir}" -part xc7z010clg400-1 -force
set_property simulator_language Mixed [current_project]
set_property target_language VHDL     [current_project]

# ---------------------------------------------------------------------------
# Add RTL design sources (package first)
# ---------------------------------------------------------------------------
set rtl_files [list \
    "${rtl_dir}/bus_matrix_pkg.vhd" \
    "${rtl_dir}/bus_matrix_decoder.vhd" \
    "${rtl_dir}/bus_matrix_arb.vhd" \
    "${rtl_dir}/bus_matrix_core.vhd" \
    "${rtl_dir}/bus_matrix_wb_tgt.vhd" \
    "${rtl_dir}/bus_matrix_wb_ini.vhd" \
    "${rtl_dir}/bus_matrix_wb.vhd" \
]
add_files -norecurse $rtl_files
foreach f $rtl_files {
    set_property file_type {VHDL 2008} [get_files [file tail $f]]
}

# ---------------------------------------------------------------------------
# Add simulation-only sources (slave bridge, test package, memory, master, testbench)
# ---------------------------------------------------------------------------
set sim_files [list \
    "${common_dir}/design/rtl/vhdl/claude_wb_if.vhd" \
    "${common_dir}/verification/tests/ip_test_pkg.vhd" \
    "${tb_dir}/bus_matrix_tb_mem.vhd" \
    "${tb_dir}/bus_matrix_tb_wb_master.vhd" \
    "${tb_dir}/tb_bus_matrix_wb.vhd" \
]
add_files -norecurse -fileset sim_1 $sim_files
foreach f $sim_files {
    set_property file_type {VHDL 2008} [get_files [file tail $f]]
}

# ---------------------------------------------------------------------------
# Simulation fileset configuration
# ---------------------------------------------------------------------------
set_property top              tb_bus_matrix_wb       [get_filesets sim_1]
set_property top_lib          xil_defaultlib     [get_filesets sim_1]
set_property -name {xsim.simulate.runtime}    -value {1ms}       -objects [get_filesets sim_1]
set_property -name {xsim.simulate.custom_tcl} -value "${wave_tcl}" -objects [get_filesets sim_1]

# ---------------------------------------------------------------------------
# Update compile order
# ---------------------------------------------------------------------------
update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts ""
puts "Project created: ${work_dir}/tb_bus_matrix_wb_vhdl.xpr"
puts "To simulate:     File > Open Project > work/wb_vhdl/tb_bus_matrix_wb_vhdl.xpr"
puts "                 then Flow > Run Simulation > Run Behavioral Simulation"
