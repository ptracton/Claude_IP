# sta.tcl — PrimeTime STA for the sram IP (csun.edu only)
# Usage: pt_shell -f sta.tcl   (driven by synthesis/run_primetime_sta.py)
#
# Static timing analysis of Design Compiler's gate-level netlists for one
# target: a SAED PDK (the single worst-case corner each EDK ships, the one
# synth.tcl compiled against) or one SKY130 standard-cell corner (ss / tt /
# ff), all three rechecked against the one SKY130 netlist set. The SRAM
# macros are linked from the same .db files synthesis used; SKY130's OpenRAM
# macros exist only at TT 1.8 V 25 C, so they keep TT timing at every corner
# (synthesis/known_issues.md).
#
# No parasitics: delays come from the library wire-load model, the same one
# synth.tcl chose for each netlist after its first compile (from the logic
# area, see known_issues.md). That choice is made after the .sdc is written,
# so the runner reads it from DC's timing report and passes it in PT_VARIANTS.
#
# Env vars (set by run_primetime_sta.py):
#   PT_TARGET    saed90 | saed32 | saed14 | ss_100C_1v60 | tt_025C_1v80 | ff_n40C_1v95
#   PT_STDLIB    standard-cell .db of the target
#   PT_MACROS    SRAM macro .db files (space separated)
#   PT_NET_DIR   synthesis/designcompiler/netlists/<pdk> (<variant>.v + .sdc)
#   PT_RPT_DIR   this target's report directory
#   PT_VARIANTS  "<variant>:<wire-load model> ..." (model "-" = library default)
#
# Per variant it writes <variant>_{timing,hold,constraint,qor,check}.rpt and
# prints one machine-readable line the runner parses:
#   STA_RESULT <variant> setup_wns setup_tns setup_nvp hold_wns hold_tns hold_nvp

foreach v {PT_TARGET PT_STDLIB PT_MACROS PT_NET_DIR PT_RPT_DIR PT_VARIANTS} {
    if { ! [info exists env($v)] } {
        puts "ERROR: $v environment variable not set"
        exit 1
    }
}

set TARGET   $env(PT_TARGET)
set STDLIB   $env(PT_STDLIB)
set MACROS   $env(PT_MACROS)
set NET_DIR  $env(PT_NET_DIR)
set RPT_DIR  $env(PT_RPT_DIR)
set VARIANTS $env(PT_VARIANTS)

foreach db [concat [list $STDLIB] $MACROS] {
    if { ! [file exists $db] } {
        puts "ERROR: library not found: $db"
        exit 1
    }
}

puts "Setting up PrimeTime STA (sram IP)..."
puts "  Target   : $TARGET"
puts "  Std cells: $STDLIB"
puts "  Macros   : [llength $MACROS] .db"
puts "  Netlists : $NET_DIR"
puts "  Variants : [llength $VARIANTS]"

set_app_var link_path [concat [list * $STDLIB] $MACROS]

suppress_message "WARNI*"
suppress_message "INFOI*"

file mkdir $RPT_DIR

# Worst slack, total negative slack and number of violating endpoints.
proc slack_summary { delay_type } {
    set wns 0.0
    set tns 0.0
    set nvp 0
    set worst [get_timing_paths -delay_type $delay_type -max_paths 1]
    if { [sizeof_collection $worst] > 0 } {
        set s [get_attribute $worst slack]
        if { $s ne "" && $s ne "INFINITY" } { set wns $s }
    }
    set viol [get_timing_paths -delay_type $delay_type -max_paths 100000 -nworst 1 \
                  -slack_lesser_than 0]
    foreach_in_collection p $viol {
        set tns [expr {$tns + [get_attribute $p slack]}]
        incr nvp
    }
    return [list $wns $tns $nvp]
}

proc sta_variant { variant wlm } {
    global NET_DIR RPT_DIR TARGET

    set netlist "${NET_DIR}/${variant}.v"
    set sdc     "${NET_DIR}/${variant}.sdc"
    if { ! [file exists $netlist] || ! [file exists $sdc] } {
        puts "ERROR: missing $netlist or $sdc"
        puts "       Run synthesis/run_vendor_synth.py --dc for this PDK first."
        return 0
    }

    puts "\n=========================================="
    puts "STA: $variant  ($TARGET, wire-load $wlm)"
    puts "=========================================="

    read_verilog $netlist
    current_design $variant
    if { ! [link_design] } {
        puts "ERROR: link failed for $variant"
        remove_design -all
        return 0
    }
    read_sdc $sdc
    if { $wlm ne "-" } {
        set_wire_load_mode top
        set_wire_load_model -name $wlm
    }
    update_timing -full

    redirect -file ${RPT_DIR}/${variant}_timing.rpt {
        report_timing -max_paths 10 -delay_type max -nosplit
    }
    redirect -file ${RPT_DIR}/${variant}_hold.rpt {
        report_timing -max_paths 10 -delay_type min -nosplit
    }
    redirect -file ${RPT_DIR}/${variant}_constraint.rpt {
        report_constraint -all_violators -nosplit
    }
    redirect -file ${RPT_DIR}/${variant}_qor.rpt {
        report_qor
    }
    redirect -file ${RPT_DIR}/${variant}_check.rpt {
        check_timing -verbose
    }

    set s [slack_summary max]
    set h [slack_summary min]
    puts [format "STA_RESULT %s %.3f %.3f %d %.3f %.3f %d" $variant \
              [lindex $s 0] [lindex $s 1] [lindex $s 2] \
              [lindex $h 0] [lindex $h 1] [lindex $h 2]]

    remove_design -all
    return 1
}

set all_ok 1
foreach entry $VARIANTS {
    set parts [split $entry ":"]
    if { ! [sta_variant [lindex $parts 0] [lindex $parts 1]] } { set all_ok 0 }
}

puts "\n=========================================="
puts "PrimeTime STA complete ($TARGET)"
puts "=========================================="

if { $all_ok } { exit 0 } else { exit 1 }
