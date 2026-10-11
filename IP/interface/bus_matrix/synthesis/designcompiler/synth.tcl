#!/bin/sh
# synth.tcl — Design Compiler synthesis script for the bus_matrix IP
# Usage: dc_shell -f synth.tcl   (normally via synthesis/run_vendor_synth.py)
#
# Supports SAED90 (90nm), SAED32 (32nm), SAED14 (14nm), and SKY130 (130nm,
# SkyWater open-source PDK) targets.
# Select via PDK_TARGET environment variable (default: saed90).
#
#   PDK_TARGET=saed90   requires SAED90_PDK  pointing to the SAED90 installation
#   PDK_TARGET=saed32   requires SAED32_EDK  pointing to /opt/ECE_Lib/SAED32_EDK
#   PDK_TARGET=saed14   requires SAED14_EDK  pointing to /opt/ECE_Lib/SAED14nm_EDK_03_2025
#   PDK_TARGET=sky130   requires SKY130_PDK  pointing to the sky130A variant root
#                        (e.g. .../volare/sky130/versions/<hash>/sky130A)
#
# Every variant is synthesized with its default parameters / generics
# (bus_matrix_pkg: 2 masters, 4 slaves, round robin, the default address
# map), which is the configuration the gate-level testbench instantiates.

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
} elseif { $PDK_TARGET eq "sky130" } {
    if { ! [info exists env(SKY130_PDK)] } {
        puts "ERROR: SKY130_PDK environment variable not set"
        exit 1
    }
    if { ! [info exists env(SKY130_STDLIB_DB)] } {
        puts "ERROR: SKY130_STDLIB_DB environment variable not set"
        puts "       (run via run_vendor_synth.py, which compiles sky130's ASCII"
        puts "       .lib to .db with lc_shell before invoking dc_shell)"
        exit 1
    }
    set PDK_PATH $env(SKY130_PDK)
    # High-density std cell library, worst-case corner (SS, 1.60 V, 100 °C),
    # pre-compiled from the open PDK's ASCII .lib to .db via lc_shell — dc_shell
    # on this host cannot read ASCII .lib directly as a target_library (DB-1).
    # Which corner is used is SKY130_SYNTH_CORNER in
    # IP/common/synthesis/designcompiler/build_sky130_libs.py. The TT and FF
    # corners are compiled alongside it and checked by PrimeTime.
    set STDLIB $env(SKY130_STDLIB_DB)
} else {
    puts "ERROR: Unknown PDK_TARGET '$PDK_TARGET' — must be saed90, saed32, saed14, or sky130"
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

# DesignWare Foundation: gives compile_ultra its arithmetic and comparator
# architectures (the arbiter's priority compares and the decoders' base/mask
# compares).
set_app_var synthetic_library dw_foundation.sldb
set_app_var target_library $STDLIB
set_app_var link_library   [list * $STDLIB dw_foundation.sldb]

set_app_var search_path [list \
    "./../../design/rtl/verilog" \
    "./../../design/rtl/vhdl" \
]

suppress_message "WARNI*"
suppress_message "INFOI*"

# Reports and netlists land in PDK-tagged subdirectories so all runs coexist
set RPT_DIR  "reports/$PDK_TARGET"
set NET_DIR  "netlists/$PDK_TARGET"
file mkdir $RPT_DIR
file mkdir $NET_DIR

# Each run starts from empty reports: report_* below appends per variant.
foreach stale [glob -nocomplain "$RPT_DIR/*.rpt"] {
    file delete $stale
}

# =========================================================================
# Timing constraints (shared by every variant)
# =========================================================================

# 100 MHz system clock.
set CLK_PERIOD 10.0

# The matrix sits between masters and slaves that are themselves clocked by
# clk, and much of it is combinational from one port to another (e.g. a
# slave's HREADY/ACK/PREADY back to the master, or a Wishbone/APB master's
# address forward to the slave). Each external block is budgeted 30 % of
# the period on its side of every port, leaving 40 % for a port-to-port path
# through the matrix.
set IO_DELAY [expr {0.3 * $CLK_PERIOD}]

# Maximum fan-out per net (see set_max_fanout in synth_variant).
set MAX_FANOUT 16

# The SV and VHDL twins have the same design-unit names. Each language
# section analyzes its own copy of the shared units immediately before its
# variants, so which language a variant is built from never depends on
# analysis order.
set SV_SHARED   {bus_matrix_pkg.sv bus_matrix_decoder.sv bus_matrix_arb.sv bus_matrix_core.sv}
set VHDL_SHARED {bus_matrix_pkg.vhd bus_matrix_decoder.vhd bus_matrix_arb.vhd bus_matrix_core.vhd}

# =========================================================================
# Helper: compile one design and write reports + netlist
# =========================================================================

proc synth_variant { variant rpt_dir net_dir suffix } {
    global CLK_PERIOD IO_DELAY MAX_FANOUT

    puts "\n=========================================="
    puts "Synthesizing: $variant$suffix"
    puts "=========================================="

    elaborate $variant
    link

    create_clock -name clk -period $CLK_PERIOD [get_ports clk]
    set_clock_transition 0.1 [get_clocks clk]
    set_clock_latency    0.2 [get_clocks clk]

    # Port-to-port budget (see IO_DELAY above). The reset is a synchronous
    # input like any other and keeps its input delay.
    set data_in [remove_from_collection [all_inputs] [get_ports clk]]
    set_input_delay  $IO_DELAY -clock clk $data_in
    set_output_delay $IO_DELAY -clock clk [all_outputs]

    # Mark the clock and synchronous reset ports as ideal networks.
    # Both fan out to every DFF, making them the highest-fanout nets in the
    # design. DC's wire-load model assigns a very large RC to such nets,
    # producing a huge INTERCONNECT entry in the SDF that breaks functional
    # gate-level simulation (found on the timer: a 6595.71 ns clock-port
    # interconnect delay in the SAED90 SDF). set_ideal_network zeroes the
    # wire-load for these ports only.
    set_ideal_network [get_ports clk]
    set_ideal_network [get_ports rst_n]

    # High-fan-out nets: each arbiter grant bit selects the owner's 69-bit
    # {we, be, wdata, addr} field in the slave routing mux. Under SAED90's
    # wire-load models every buffer level of that net's tree adds ~2.5-3 ns
    # of wire delay, and with design rules outranking delay (DC's default)
    # DC left timing-critical sinks at the leaves (-1.25 ns WNS). Delay is
    # given priority; the fan-out cap keeps design-rule fixing bounded.
    set_max_fanout $MAX_FANOUT [current_design]
    set_cost_priority -delay

    # Written before compile so it reflects the constraints as specified,
    # for PrimeTime STA to re-apply against this same netlist (see
    # synthesis/primetime/) and for PrimePower to take the clock from.
    write_sdc "${net_dir}/${variant}${suffix}.sdc"
    puts "Wrote SDC: ${net_dir}/${variant}${suffix}.sdc"

    # compile_ultra: timing-driven mapping with DesignWare architecture
    # selection. -no_autoungroup keeps the u_core / gen_mst / gen_slv
    # hierarchy that PrimeTime and PrimePower report against.
    # The incremental pass re-optimizes the mapped netlist; it closed the
    # last SAED90 port-to-port paths (-0.46 ns) left by the first pass.
    compile_ultra -no_autoungroup
    compile_ultra -no_autoungroup -incremental

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
# SystemVerilog variants
# =========================================================================

foreach proto {apb ahb axi4l wb} {
    set variant "bus_matrix_${proto}"
    analyze -format sverilog $SV_SHARED
    analyze -format sverilog [list "${variant}_tgt.sv" "${variant}_ini.sv" "${variant}.sv"]
    synth_variant $variant $RPT_DIR $NET_DIR ""
}

# =========================================================================
# VHDL variants
# =========================================================================

foreach proto {apb ahb axi4l wb} {
    set variant "bus_matrix_${proto}"
    analyze -format vhdl $VHDL_SHARED
    analyze -format vhdl [list "${variant}_tgt.vhd" "${variant}_ini.vhd" "${variant}.vhd"]
    synth_variant $variant $RPT_DIR $NET_DIR "_vhdl"
}

puts "\n=========================================="
puts "Synthesis complete ($PDK_TARGET)"
puts "=========================================="

exit 0
