# synth.tcl — Quartus Prime Analysis & Synthesis for timer_apb
#
# Target device : 5CSEMA4U23C6 (Cyclone V SE A4 — DE0-Nano-SoC / Arrow SoCKit)
# Top module    : timer_apb
# Clock target  : 100 MHz (10 ns period)
#
# Run:
#   /opt/intelFPGA_lite/23.1std/quartus/bin/quartus_sh -t synthesis/quartus/synth.tcl
#
# Outputs (written to synthesis/quartus/work/timer_apb/output_files/):
#   timer_apb.map.rpt   — Analysis & Synthesis resource utilization
#   timer_apb.map.smsg  — synthesis messages summary

package require ::quartus::project
package require ::quartus::flow

# -------------------------------------------------------------------------
# Locate RTL source files
# -------------------------------------------------------------------------
set script_dir  [file normalize [file dirname [info script]]]
set rtl_dir     [file normalize "$script_dir/../../design/rtl/verilog"]
set common_dir  [file normalize "$script_dir/../../../../common/design/rtl/verilog"]

set rtl_files [list \
    "$rtl_dir/timer_reg_pkg.sv"      \
    "$rtl_dir/timer_regfile.sv"      \
    "$rtl_dir/timer_core.sv"         \
    "$common_dir/claude_apb_if.sv"   \
    "$rtl_dir/timer_apb.sv"          \
]

# -------------------------------------------------------------------------
# Project setup
# -------------------------------------------------------------------------
set proj_name "timer_apb"
set work_dir  "$script_dir/work"
file mkdir $work_dir

project_new -overwrite -revision $proj_name "$work_dir/$proj_name"

# -------------------------------------------------------------------------
# Device assignment — Cyclone V SE A4 (DE0-Nano-SoC / Arrow SoCKit)
# Comparable to Zynq-7010: dual-core ARM Cortex-A9 + ~40K LE FPGA fabric
# -------------------------------------------------------------------------
set_global_assignment -name FAMILY           "Cyclone V"
set_global_assignment -name DEVICE           "5CSEMA4U23C6"
set_global_assignment -name TOP_LEVEL_ENTITY  $proj_name

# -------------------------------------------------------------------------
# Source files
# -------------------------------------------------------------------------
foreach f $rtl_files {
    if {![file exists $f]} {
        post_message -type error "RTL file not found: $f"
        project_close
        qexit -error
    }
    set_global_assignment -name SYSTEMVERILOG_FILE $f
}

# -------------------------------------------------------------------------
# SDC timing constraint — 100 MHz on PCLK
# -------------------------------------------------------------------------
set sdc_file "$script_dir/timer_apb.sdc"
if {![file exists $sdc_file]} {
    set fh [open $sdc_file w]
    puts $fh "# timer_apb.sdc — Quartus timing constraints"
    puts $fh "create_clock -period 10.000 -name PCLK \[get_ports PCLK\]"
    close $fh
}
set_global_assignment -name SDC_FILE $sdc_file

# -------------------------------------------------------------------------
# Synthesis settings
# -------------------------------------------------------------------------
set_global_assignment -name VERILOG_INPUT_VERSION          SYSTEMVERILOG_2005
set_global_assignment -name OPTIMIZATION_MODE              "BALANCED"
set_global_assignment -name SYNTH_TIMING_DRIVEN_SYNTHESIS  ON
set_global_assignment -name NUM_PARALLEL_PROCESSORS        ALL

# -------------------------------------------------------------------------
# Run Analysis & Synthesis (map module)
# Reports are auto-written to output_files/timer_apb.map.rpt
# -------------------------------------------------------------------------
execute_module -tool map

project_close

puts ""
puts "Quartus Analysis & Synthesis complete."
puts "Report: $work_dir/$proj_name/output_files/$proj_name.map.rpt"
