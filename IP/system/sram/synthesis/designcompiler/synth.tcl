#!/bin/sh
# synth.tcl — Design Compiler synthesis script for the sram IP
# Usage: dc_shell -f synth.tcl   (normally via synthesis/run_vendor_synth.py,
#        which runs each PDK x configuration in its own work directory)
#
# One run synthesizes one configuration (SRAM_CFG) for one PDK (PDK_TARGET)
# on all eight tops of that configuration (4 buses x SV / VHDL):
#
#   SRAM_CFG=base  sram_<proto>     WIDTH 32, DEPTH 1024, BYTE_EN, PWR_GATE
#                                   (RTL defaults, plan D5)
#   SRAM_CFG=opts  sram_<proto>     base + ECC_EN, BANK_PG (2 banks), BIST_EN,
#                                   READ_LATENCY 2
#   SRAM_CFG=dp    sram_<proto>_dp  opts + port B 8 bits wide on its own clock
#                                   (WIDTH_B 8, COMMON_CLK 0); SAED14 uses
#                                   COMMON_CLK 1 (its SRAM2RW has one write
#                                   clock, sram_core refuses COMMON_CLK 0)
#
# PDK_TARGET   saed90 | saed32 | saed14 | sky130
#   saed90  requires SAED90_PDK  (.../SAED90_EDK/SAED_EDK90nm)
#   saed32  requires SAED32_EDK  (/opt/ECE_Lib/SAED32_EDK) and SAED32_SRAM_DB
#           (patched sram_lp .db, see build_saed32_sram_libs.py)
#   saed14  requires SAED14_EDK  (/opt/ECE_Lib/SAED14nm_EDK_03_2025)
#   sky130  requires SKY130_PDK, SKY130_STDLIB_DB and SKY130_SRAM_DBS (the
#           runner compiles the ASCII .lib files to .db with lc_shell, see
#           IP/common/synthesis/designcompiler/build_sky130_libs.py)
# CLAUDE_SRAM_PATH and IP_COMMON_PATH locate the RTL (source setup.sh).
# SRAM_OUT_DIR is where reports/ and netlists/ go (default: the directory
# above the work directory, i.e. synthesis/designcompiler).
#
# Each macro family is linked at the corner of its standard cells; the
# SKY130 OpenRAM macros exist only at TT 1.8 V 25 C, so SKY130 links the TT
# macro .db with the SS standard cells (see synthesis/known_issues.md).

# =========================================================================
# PDK selection
# =========================================================================

proc need_env { name } {
    global env
    if { ! [info exists env($name)] } {
        puts "ERROR: $name environment variable not set"
        exit 1
    }
    return $env($name)
}

set PDK_TARGET [expr {[info exists env(PDK_TARGET)] ? $env(PDK_TARGET) : "saed90"}]
set SRAM_CFG   [expr {[info exists env(SRAM_CFG)]   ? $env(SRAM_CFG)   : "base"}]

if { $PDK_TARGET eq "saed90" } {
    set PDK_PATH [need_env SAED90_PDK]
    set TECH     3
    set STDLIB   "$PDK_PATH/Digital_Standard_cell_Library/synopsys/models/saed90nm_max.db"
    # One .db per macro (SRAM<w>x<d>_1rw and the two-port SRAM<w>x<d>), worst case
    set MACROS   [lsort [glob -nocomplain "$PDK_PATH/Memories/synopsys/models/SRAM*_max.db"]]
} elseif { $PDK_TARGET eq "saed32" } {
    set PDK_PATH [need_env SAED32_EDK]
    set TECH     4
    # RVT worst case (SS, 0.95 V, 125 C); the low-power SRAM library at the same corner
    set STDLIB   "$PDK_PATH/lib/stdcell_rvt/db_nldm/saed32rvt_ss0p95v125c.db"
    # The vendor sram_lp liberty lacks the macros' SD / LS / DS pins (they are
    # in the LEF and Verilog model); the runner passes a patched copy built by
    # IP/common/synthesis/designcompiler/build_saed32_sram_libs.py.
    set MACROS   [list [need_env SAED32_SRAM_DB]]
} elseif { $PDK_TARGET eq "saed14" } {
    set PDK_PATH [need_env SAED14_EDK]
    set TECH     5
    # RVT base worst case (SS, 0.72 V, 125 C); SRAM library at the same corner
    set STDLIB   "$PDK_PATH/SAED14nm_EDK_STD_RVT/liberty/nldm/base/saed14rvt_base_ss0p72v125c.db"
    set MACROS   [list "$PDK_PATH/SAED14nm_EDK_SRAM/liberty/nldm/saed14sram_ss0p72v125c.db"]
} elseif { $PDK_TARGET eq "sky130" } {
    set PDK_PATH [need_env SKY130_PDK]
    set TECH     6
    # sky130_fd_sc_hd SS 1.60 V 100 C, compiled from the PDK's ASCII .lib
    set STDLIB   [need_env SKY130_STDLIB_DB]
    set MACROS   [need_env SKY130_SRAM_DBS]
} else {
    puts "ERROR: Unknown PDK_TARGET '$PDK_TARGET' — must be saed90, saed32, saed14, or sky130"
    exit 1
}

if { [llength $MACROS] == 0 } {
    puts "ERROR: no SRAM macro libraries found for $PDK_TARGET"
    exit 1
}
foreach lib [concat [list $STDLIB] $MACROS] {
    if { ! [file exists $lib] } {
        puts "ERROR: Library not found: $lib"
        exit 1
    }
}

# =========================================================================
# Configuration
# =========================================================================

set OPTS "ECC_EN=1,BANK_PG=1,NUM_BANKS=2,BIST_EN=1,READ_LATENCY=2"
if { $SRAM_CFG eq "base" } {
    set TOP_SUFFIX ""
    set NAME_SUFFIX ""
    set PARAMS "TECH=$TECH"
    set DUAL 0
} elseif { $SRAM_CFG eq "opts" } {
    set TOP_SUFFIX ""
    set NAME_SUFFIX "_opts"
    set PARAMS "TECH=$TECH,$OPTS"
    set DUAL 0
} elseif { $SRAM_CFG eq "dp" } {
    set TOP_SUFFIX "_dp"
    set NAME_SUFFIX ""
    set COMMON_CLK [expr {$PDK_TARGET eq "saed14" ? 1 : 0}]
    set PARAMS "TECH=$TECH,$OPTS,WIDTH_B=8,COMMON_CLK=$COMMON_CLK"
    set DUAL 1
} else {
    puts "ERROR: Unknown SRAM_CFG '$SRAM_CFG' — must be base, opts, or dp"
    exit 1
}

# SRAM_PROTOS / SRAM_LANGS narrow a run (debugging); default all.
set PROTOS [expr {[info exists env(SRAM_PROTOS)] ? $env(SRAM_PROTOS) : "apb ahb axi4l wb"}]
set LANGS  [expr {[info exists env(SRAM_LANGS)]  ? $env(SRAM_LANGS)  : "sv vhdl"}]

puts "Setting up Design Compiler synthesis..."
puts "  PDK target : $PDK_TARGET"
puts "  PDK path   : $PDK_PATH"
puts "  Stdlib     : $STDLIB"
puts "  Macros     : [llength $MACROS] .db"
puts "  Config     : $SRAM_CFG ($PARAMS)"

# =========================================================================
# Design Compiler configuration
# =========================================================================

set_app_var hdlin_vhdl_std    2008

# DesignWare Foundation: comparators and adders of the address decode, the
# clear / BIST address counters and the power-sequencing counters.
set_app_var synthetic_library dw_foundation.sldb
set_app_var target_library    $STDLIB
set_app_var link_library      [concat [list * $STDLIB] $MACROS [list dw_foundation.sldb]]

set SRAM_PATH   [need_env CLAUDE_SRAM_PATH]
set COMMON_PATH [need_env IP_COMMON_PATH]
set_app_var search_path [list \
    "$SRAM_PATH/design/rtl/verilog" \
    "$COMMON_PATH/design/rtl/verilog" \
    "$SRAM_PATH/design/rtl/vhdl" \
    "$COMMON_PATH/design/rtl/vhdl" \
]

suppress_message "WARNI*"
suppress_message "INFOI*"

set OUT_DIR [expr {[info exists env(SRAM_OUT_DIR)] ? $env(SRAM_OUT_DIR) : [file normalize ..]}]
set RPT_DIR "$OUT_DIR/reports/$PDK_TARGET"
set NET_DIR "$OUT_DIR/netlists/$PDK_TARGET"
file mkdir $RPT_DIR
file mkdir $NET_DIR

# =========================================================================
# Timing constraints
# =========================================================================

# 100 MHz bus clock(s).
set CLK_PERIOD 10.0

# The SRAM is a bus slave: the master drives its inputs and samples its
# outputs on the same clock. Each external block is budgeted 30 % of the
# period on its side of every port (as the bus_matrix).
set IO_DELAY [expr {0.3 * $CLK_PERIOD}]

# Setup margin DC compiles with, not written to the .sdc (see below).
set SYN_MARGIN 0.2

# SAED90/32/14 wire-load models (the same names in all three libraries);
# SKY130's library has one model ("Small", top mode) and keeps it.
set SAED [string match "saed*" $PDK_TARGET]
set WLM_NAMES {8000 16000 35000 70000 140000 280000 540000 1000000 2000000 4000000 8000000}

# Maximum fan-out per net: the array's address / write-data / lane-enable
# nets fan out to every macro column and bank.
set MAX_FANOUT 16

# Clock and reset port names per protocol (dual-port tops prefix A_ / B_).
array set CLK_PORT { apb PCLK    ahb HCLK    axi4l ACLK    wb CLK_I }
array set RST_PORT { apb PRESETn ahb HRESETn axi4l ARESETn wb RST_I }

# Compile order (dependencies first), as sim_sram.py / lint_sram.py.
set SRAM_UNITS {
    sram_pkg sram_ecc_enc sram_ecc_dec
    sram_macro_generic sram_macro_saed90 sram_macro_saed32 sram_macro_saed14
    sram_macro_sky130 sram_macro_xilinx sram_macro_altera
    sram_macro_dp_generic sram_macro_dp_saed90 sram_macro_dp_saed32
    sram_macro_dp_saed14 sram_macro_dp_sky130 sram_macro_dp_xilinx
    sram_macro_dp_altera
    sram_macro sram_macro_dp sram_array sram_pwr_ctrl sram_clr sram_bist
    sram_port sram_cdc sram_core
}

# The SV and VHDL twins have the same design-unit names, so each variant
# analyzes its own language's copy of every unit immediately before it is
# elaborated (as the bus_matrix).
proc analyze_lang { lang proto top } {
    global SRAM_UNITS
    set ext   [expr {$lang eq "sv" ? "sv" : "vhd"}]
    set fmt   [expr {$lang eq "sv" ? "sverilog" : "vhdl"}]
    set files [list "claude_sync.$ext" "claude_pulse_sync.$ext" "claude_${proto}_mem_if.$ext"]
    foreach u $SRAM_UNITS { lappend files "$u.$ext" }
    lappend files "$top.$ext"
    analyze -format $fmt $files
}

# =========================================================================
# Helper: compile one design and write reports + netlist
# =========================================================================

proc synth_variant { lang proto } {
    global CLK_PERIOD IO_DELAY MAX_FANOUT CLK_PORT RST_PORT PARAMS DUAL
    global TOP_SUFFIX NAME_SUFFIX RPT_DIR NET_DIR PDK_TARGET COMMON_CLK SAED WLM_NAMES SYN_MARGIN

    set top    "sram_${proto}${TOP_SUFFIX}"
    set suffix [expr {$lang eq "vhdl" ? "_vhdl" : ""}]
    set name   "${top}${NAME_SUFFIX}${suffix}"

    puts "\n=========================================="
    puts "Synthesizing: $name ($PARAMS)"
    puts "=========================================="

    analyze_lang $lang $proto $top
    if { ! [elaborate $top -parameters $PARAMS] } {
        puts "ERROR: elaborate $top failed"
        exit 1
    }
    # The elaborated design is named after its parameters; give it a stable
    # name (the netlist's top module, used by STA and gate-level simulation).
    set elab [get_object_name [current_design]]
    if { $elab ne $name } {
        rename_design $elab $name
        current_design $name
    }
    if { ! [link] } {
        puts "ERROR: link $name failed"
        exit 1
    }

    if { $DUAL } {
        set clk_a "A_$CLK_PORT($proto)"
        set clk_b "B_$CLK_PORT($proto)"
        set rst   [list "A_$RST_PORT($proto)" "B_$RST_PORT($proto)"]
        if { $COMMON_CLK } {
            # One clock drives both clock pins (sram_core: "connect both").
            create_clock -name clk_a -period $CLK_PERIOD [get_ports [list $clk_a $clk_b]]
            set clocks [list clk_a]
            set b_clock clk_a
        } else {
            # Unrelated clocks: every crossing is in sram_cdc / claude_sync.
            create_clock -name clk_a -period $CLK_PERIOD [get_ports $clk_a]
            create_clock -name clk_b -period $CLK_PERIOD [get_ports $clk_b]
            set_clock_groups -asynchronous -group [get_clocks clk_a] -group [get_clocks clk_b]
            set clocks [list clk_a clk_b]
            set b_clock clk_b
        }
        set clk_ports [list $clk_a $clk_b]
    } else {
        set clk_ports [list $CLK_PORT($proto)]
        set rst       [list $RST_PORT($proto)]
        create_clock -name clk_a -period $CLK_PERIOD [get_ports $clk_ports]
        set clocks  [list clk_a]
        set b_clock clk_a
    }
    set_clock_transition 0.1 [get_clocks $clocks]
    set_clock_latency    0.2 [get_clocks $clocks]

    # Port budget (see IO_DELAY). Port B's pins (B_*) are timed on port B's
    # clock; everything else (port A, side band) on port A's. The resets are
    # synchronous inputs like any other and keep their input delay.
    set data_in  [remove_from_collection [all_inputs] [get_ports $clk_ports]]
    set data_out [all_outputs]
    set b_in     [filter_collection $data_in  "full_name =~ B_*"]
    set b_out    [filter_collection $data_out "full_name =~ B_*"]
    set a_in     [remove_from_collection $data_in  $b_in]
    set a_out    [remove_from_collection $data_out $b_out]
    set_input_delay  $IO_DELAY -clock clk_a $a_in
    set_output_delay $IO_DELAY -clock clk_a $a_out
    if { [sizeof_collection $b_in] > 0 } {
        set_input_delay  $IO_DELAY -clock $b_clock $b_in
        set_output_delay $IO_DELAY -clock $b_clock $b_out
    }

    # Mark the clock and synchronous reset ports as ideal networks. Both fan
    # out to every DFF; DC's wire-load model assigns a very large RC to such
    # nets, producing a huge INTERCONNECT entry in the SDF that breaks
    # gate-level simulation (found on the timer: a 6595.71 ns clock-port
    # interconnect delay in the SAED90 SDF).
    set_ideal_network [get_ports $clk_ports]
    set_ideal_network [get_ports $rst]

    set_max_fanout $MAX_FANOUT [current_design]
    set_cost_priority -delay

    # SAED: one wire-load model for every net (top mode), chosen from the
    # logic area after the first compile (see below); start from the smallest.
    if { $SAED } {
        set_app_var auto_wire_load_selection false
        set_wire_load_mode top
        set_wire_load_model -name [lindex $WLM_NAMES 0]
    }

    # Written before compile so it reflects the constraints as specified,
    # for PrimeTime STA to re-apply against this same netlist (see
    # synthesis/primetime/) and for PrimePower to take the clocks from.
    write_sdc "${NET_DIR}/${name}.sdc"
    puts "Wrote SDC: ${NET_DIR}/${name}.sdc"

    # Synthesis margin (user decision 2026-11-25): DC compiles against
    # SYN_MARGIN ns less setup time than the .sdc above specifies, so
    # PrimeTime's slightly more pessimistic delay calculation (about 0.03 ns
    # on the SKY130 SS ECC write-back path) still meets the real 10 ns.
    # Set after write_sdc on purpose: STA and post-synthesis simulation check
    # the unmodified constraints. DC's own reports include the margin.
    set_clock_uncertainty -setup $SYN_MARGIN [all_clocks]

    # compile_ultra: timing-driven mapping with DesignWare architecture
    # selection. -no_autoungroup keeps the u_if / u_core / u_array hierarchy
    # that PrimeTime and PrimePower report against.
    compile_ultra -no_autoungroup
    if { $SAED } {
        # The SAED libraries pick a wire-load model from each design's
        # area, and the SRAM macros dominate that area (32 x 1024 is
        # ~580,000 on SAED90 against ~3,400 of logic). The pick was then
        # the largest model, and a single NAND2 net carried 12 ns of wire
        # delay. Select the model for the logic alone: the one the
        # library's wire_load_from_area table gives for the cell area
        # without the macros (models are named by their upper area bound).
        redirect -variable area_txt { report_area }
        regexp {Total cell area:\s+([0-9.]+)} $area_txt -> total_area
        set macro_area 0.0
        regexp {Macro/Black Box area:\s+([0-9.]+)} $area_txt -> macro_area
        set logic_area [expr {$total_area - $macro_area}]
        set wlm [lindex $WLM_NAMES end]
        foreach w $WLM_NAMES {
            if { $logic_area <= $w } { set wlm $w; break }
        }
        puts "Wire-load model: $wlm (logic area $logic_area, macro area $macro_area)"
        set_wire_load_model -name $wlm
    }
    compile_ultra -no_autoungroup -incremental

    redirect ${RPT_DIR}/${name}_area.rpt   { report_area -hier }
    redirect ${RPT_DIR}/${name}_timing.rpt { report_timing -max_paths 10 }
    redirect ${RPT_DIR}/${name}_qor.rpt    { report_qor }
    redirect ${RPT_DIR}/${name}_ref.rpt    { report_reference -hier }
    redirect ${RPT_DIR}/${name}_constraint.rpt { report_constraint -all_violators }
    redirect -append ${RPT_DIR}/${name}_constraint.rpt { check_timing }
    report_area
    report_timing -max_paths 1

    write -format verilog -hier -o "${NET_DIR}/${name}.v"
    puts "Wrote netlist: ${NET_DIR}/${name}.v"

    write_sdf "${NET_DIR}/${name}.sdf"
    puts "Wrote SDF: ${NET_DIR}/${name}.sdf"

    remove_design -all
}

foreach lang $LANGS {
    foreach proto $PROTOS {
        synth_variant $lang $proto
    }
}

puts "\n=========================================="
puts "Synthesis complete ($PDK_TARGET, $SRAM_CFG)"
puts "=========================================="

exit 0
