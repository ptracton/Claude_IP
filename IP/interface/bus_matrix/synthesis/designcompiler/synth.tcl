#!/bin/sh
# synth.tcl — Design Compiler synthesis script for bus_matrix IP
# Usage: dc_shell -f synth.tcl
#
# Supports SAED90 (90nm), SAED32 (32nm), and SAED14 (14nm) PDKs.
# Select via PDK_TARGET environment variable (default: saed90).
#
#   PDK_TARGET=saed90  requires SAED90_PDK  pointing to the SAED90 installation
#   PDK_TARGET=saed32  requires SAED32_EDK  pointing to /opt/ECE_Lib/SAED32_EDK
#   PDK_TARGET=saed14  requires SAED14_EDK  pointing to /opt/ECE_Lib/SAED14nm_EDK_03_2025

# =========================================================================
# PDK selection
# =========================================================================

if { [info exists env(PDK_TARGET)] } {
    set PDK_TARGET $env(PDK_TARGET)
} else {
    set PDK_TARGET "saed90"
}

if { $PDK_TARGET eq "saed90" } {
    if { ! [info exists env(SAED90_PDK)] } {
        puts "ERROR: SAED90_PDK environment variable not set"
        exit 1
    }
    set PDK_PATH $env(SAED90_PDK)
    set STDLIB "$PDK_PATH/Digital_Standard_cell_Library/synopsys/models/saed90nm_max.db"
} elseif { $PDK_TARGET eq "saed32" } {
    if { ! [info exists env(SAED32_EDK)] } {
        puts "ERROR: SAED32_EDK environment variable not set"
        exit 1
    }
    set PDK_PATH $env(SAED32_EDK)
    # RVT worst-case corner (SS, 0.95 V, 125 °C)
    set STDLIB "$PDK_PATH/lib/stdcell_rvt/db_nldm/saed32rvt_ss0p95v125c.db"
} elseif { $PDK_TARGET eq "saed14" } {
    if { ! [info exists env(SAED14_EDK)] } {
        puts "ERROR: SAED14_EDK environment variable not set"
        exit 1
    }
    set PDK_PATH $env(SAED14_EDK)
    # RVT base worst-case corner (SS, 0.72 V, 125 °C)
    set STDLIB "$PDK_PATH/SAED14nm_EDK_STD_RVT/liberty/nldm/base/saed14rvt_base_ss0p72v125c.db"
} else {
    puts "ERROR: Unknown PDK_TARGET '$PDK_TARGET' — must be saed90, saed32, or saed14"
    exit 1
}

if { ! [file exists $STDLIB] } {
    puts "ERROR: Library not found: $STDLIB"
    exit 1
}

puts "Setting up Design Compiler synthesis..."
puts "  PDK target : $PDK_TARGET"
puts "  PDK path   : $PDK_PATH"
puts "  Stdlib     : $STDLIB"

# =========================================================================
# Design Compiler configuration
# =========================================================================

set_app_var verilog_mode      2012
set_app_var hdlin_vhdl_std    2008

set_app_var target_library $STDLIB
set_app_var link_library   [list * $STDLIB]

set_app_var search_path [list \
    "./../../design/rtl/verilog" \
    "./../../design/rtl/vhdl" \
]

suppress_message "WARNI*"
suppress_message "INFOI*"

# Reports and netlists land in PDK-tagged subdirectories so all three runs coexist
set RPT_DIR  "reports/$PDK_TARGET"
set NET_DIR  "netlists/$PDK_TARGET"
file mkdir $RPT_DIR
file mkdir $NET_DIR

# =========================================================================
# Analyze shared RTL (SV + VHDL)
# =========================================================================

puts "Reading RTL sources..."

analyze -format sverilog {bus_matrix_decoder.sv bus_matrix_arb.sv bus_matrix_core.sv}
analyze -format vhdl     {bus_matrix_decoder.vhd bus_matrix_arb.vhd bus_matrix_core.vhd}

# =========================================================================
# Helper: compile one design and write reports + netlist
# =========================================================================

proc synth_variant { variant clk_port rpt_dir net_dir suffix } {
    puts "\n=========================================="
    puts "Synthesizing: $variant$suffix"
    puts "=========================================="

    elaborate $variant
    link

    create_clock -period 10 $clk_port
    set_clock_transition 0.1 $clk_port
    set_clock_latency    0.2 $clk_port

    compile -map_effort low

    puts "\n--- Report Area ---"
    redirect -append ${rpt_dir}/${variant}${suffix}_area.rpt   { report_area -hier }
    report_area -hier

    puts "\n--- Report Timing ---"
    redirect -append ${rpt_dir}/${variant}${suffix}_timing.rpt { report_timing -max_paths 10 }
    report_timing -max_paths 10

    write -format verilog -hier -o "${net_dir}/${variant}${suffix}.v"
    puts "Wrote netlist: ${net_dir}/${variant}${suffix}.v"

    write_sdf "${net_dir}/${variant}${suffix}.sdf"
    puts "Wrote SDF: ${net_dir}/${variant}${suffix}.sdf"

    remove_design -hier $variant
}

# =========================================================================
# SystemVerilog variants (clock port is always 'clk')
# =========================================================================

foreach variant {bus_matrix_ahb bus_matrix_axi bus_matrix_wb} {
    analyze -format sverilog "${variant}.sv"
    synth_variant $variant clk $RPT_DIR $NET_DIR ""
}

# =========================================================================
# VHDL variants (clock port is 'clk' for all bus_matrix variants)
# =========================================================================

foreach variant {bus_matrix_ahb bus_matrix_axi bus_matrix_wb} {
    analyze -format vhdl "${variant}.vhd"
    synth_variant $variant clk $RPT_DIR $NET_DIR "_vhdl"
}

puts "\n=========================================="
puts "Synthesis complete ($PDK_TARGET)"
puts "=========================================="

exit 0
