# synth.tcl — Vivado OOC synthesis for timer_apb
#
# Target device : xc7z010clg400-1 (Zynq-7010, CLG400 package, speed grade -1)
# Board         : Zybo-Z7-10 (Digilent)
# Top module    : timer_apb
# Clock target  : 100 MHz (10 ns period)
#
# Run from the repository root:
#   source /opt/Xilinx/Vivado/2023.2/settings64.sh
#   vivado -mode batch -source synthesis/vivado/synth.tcl -nojournal -nolog 2>&1

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
# Create an in-memory project (OOC — no implementation)
# -------------------------------------------------------------------------
create_project -in_memory -part xc7z010clg400-1

set_property default_lib work [current_project]
set_property target_language Verilog [current_project]

# Read all RTL sources
foreach f $rtl_files {
    if {![file exists $f]} {
        error "RTL file not found: $f"
    }
    read_verilog -sv $f
}

# -------------------------------------------------------------------------
# Set top module
# -------------------------------------------------------------------------
set_property top timer_apb [current_fileset]

# -------------------------------------------------------------------------
# Clock constraint (10 ns = 100 MHz)
# -------------------------------------------------------------------------
# Write the OOC XDC to a temp file then read it (stdin not supported in batch)
set xdc_file [file join $script_dir "timer_apb_ooc.xdc"]
set xdc_fh [open $xdc_file w]
puts $xdc_fh "create_clock -period 10.000 -name PCLK \[get_ports PCLK\]"
close $xdc_fh
read_xdc $xdc_file

# -------------------------------------------------------------------------
# Run synthesis
# -------------------------------------------------------------------------
synth_design -top timer_apb \
             -part xc7z010clg400-1 \
             -mode out_of_context \
             -flatten_hierarchy rebuilt

# -------------------------------------------------------------------------
# Reports
# -------------------------------------------------------------------------
set rpt_dir "$script_dir"
report_utilization -file "$rpt_dir/utilization.rpt"
report_timing_summary -file "$rpt_dir/timing_summary.rpt" -warn_on_violation

puts "Synthesis complete. Reports written to $rpt_dir"
