#!/bin/sh
# sta.tcl — PrimeTime STA script for timer IP (csun.edu only)
# Usage: pt_shell -f sta.tcl
#
# Runs static timing analysis on Design Compiler's gate-level netlists for
# one target — a SAED PDK (single, worst-case corner each) or one SKY130
# PVT corner (ss/tt/ff, all rechecked against the one SKY130 netlist set,
# synthesized to the typical corner). Driven entirely by run_primetime_sta.py;
# see that script for why SKY130 gets 3 corners and SAED gets 1 each.
#
# Env vars (set by run_primetime_sta.py):
#   PT_TARGET   target name: saed90 | saed32 | saed14 |
#               ss_100C_1v60 | tt_025C_1v80 | ff_n40C_1v95
#   PT_DB       path to that target's .db (SAED: the same one synth.tcl
#               synthesized against; sky130: from the shared
#               IP/common/synthesis/designcompiler/sky130_lib/ cache)
#   PT_NET_DIR  synthesis/designcompiler/netlists/<pdk> (DC output: reads
#               <variant>[_vhdl].v and the matching .sdc from there)
#   PT_RPT_DIR  this run's report output directory

foreach v {PT_TARGET PT_DB PT_NET_DIR PT_RPT_DIR} {
    if { ! [info exists env($v)] } {
        puts "ERROR: $v environment variable not set"
        exit 1
    }
}

set TARGET  $env(PT_TARGET)
set DB      $env(PT_DB)
set NET_DIR $env(PT_NET_DIR)
set RPT_DIR $env(PT_RPT_DIR)

if { ! [file exists $DB] } {
    puts "ERROR: library not found: $DB"
    exit 1
}

puts "Setting up PrimeTime STA..."
puts "  Target   : $TARGET"
puts "  Library  : $DB"
puts "  Netlists : $NET_DIR"

set_app_var link_library   [list * $DB]
set_app_var target_library $DB

suppress_message "WARNI*"
suppress_message "INFOI*"

file mkdir $RPT_DIR

# =========================================================================
# Helper: STA one variant/suffix (suffix "" = SystemVerilog, "_vhdl" = VHDL)
# =========================================================================

proc sta_variant { variant suffix } {
    global NET_DIR RPT_DIR TARGET

    set netlist "${NET_DIR}/${variant}${suffix}.v"
    set sdc     "${NET_DIR}/${variant}${suffix}.sdc"

    if { ! [file exists $netlist] || ! [file exists $sdc] } {
        puts "ERROR: missing $netlist or $sdc"
        puts "       Run the matching synthesis/run_vendor_synth.py DC step for this PDK first."
        return 0
    }

    puts "\n=========================================="
    puts "STA: $variant$suffix  ($TARGET)"
    puts "=========================================="

    read_verilog $netlist
    current_design $variant
    link

    read_sdc $sdc
    update_timing

    redirect -file ${RPT_DIR}/${variant}${suffix}_timing.rpt {
        report_timing -max_paths 10 -delay_type max
    }
    redirect -file ${RPT_DIR}/${variant}${suffix}_qor.rpt {
        report_qor
    }
    redirect -file ${RPT_DIR}/${variant}${suffix}_constraint.rpt {
        report_constraint -all_violators
    }

    report_qor

    remove_design -all
    return 1
}

set variants {timer_apb timer_ahb timer_axi4l timer_wb}

set all_ok 1
foreach variant $variants {
    if { ! [sta_variant $variant ""] }      { set all_ok 0 }
}
foreach variant $variants {
    if { ! [sta_variant $variant "_vhdl"] } { set all_ok 0 }
}

puts "\n=========================================="
puts "PrimeTime STA complete ($TARGET)"
puts "=========================================="

if { $all_ok } { exit 0 } else { exit 1 }
