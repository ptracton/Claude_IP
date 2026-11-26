# synth.tcl — Quartus Prime Analysis & Synthesis of one sram top (TECH = ALTERA).
#
# Target: Cyclone V SE (5CSEMA4U23C6), 100 MHz. Driven by
# synthesis/run_vendor_synth.py with the same environment as
# synthesis/vivado/synth.tcl (SRAM_NAME, SRAM_TOP, SRAM_LANG, SRAM_FILES,
# SRAM_GENERICS with TECH=2, SRAM_CLK_A, SRAM_CLK_B, SRAM_OUT_DIR).
# The project lives in $SRAM_OUT_DIR/$SRAM_NAME/.
#
# The array must map to M10K blocks (altsyncram); the runner fails a variant
# whose map report shows no block memory bits. SV variants are read from the
# SystemVerilog-2005 copies written by quartus_sv.py (Quartus Lite rejects
# implicit generate regions, genvar in for headers and header localparams).

package require ::quartus::project
package require ::quartus::flow

set DEVICE   "5CSEMA4U23C6"
set NAME     $::env(SRAM_NAME)
set TOP      $::env(SRAM_TOP)
set LANG     $::env(SRAM_LANG)
set CLK_A    $::env(SRAM_CLK_A)
set CLK_B    $::env(SRAM_CLK_B)
set WORK_DIR "$::env(SRAM_OUT_DIR)/$NAME"
# A fresh project every run: project_new -overwrite keeps the assignments of an
# existing .qsf, so a re-run would also compile the previous file list.
file delete -force $WORK_DIR
file mkdir $WORK_DIR

project_new -overwrite -part $DEVICE $WORK_DIR/$NAME
set_global_assignment -name FAMILY "Cyclone V"
set_global_assignment -name DEVICE $DEVICE
set_global_assignment -name TOP_LEVEL_ENTITY $TOP

if { $LANG eq "vhdl" } {
    set_global_assignment -name VHDL_INPUT_VERSION VHDL_2008
    foreach f $::env(SRAM_FILES) {
        set_global_assignment -name VHDL_FILE $f -hdl_version VHDL_2008
    }
} else {
    foreach f $::env(SRAM_FILES) {
        set_global_assignment -name SYSTEMVERILOG_FILE $f
    }
}

foreach g $::env(SRAM_GENERICS) {
    lassign [split $g "="] k v
    set_parameter -name $k $v
}

set sdc_file "$WORK_DIR/${NAME}.sdc"
set fh [open $sdc_file w]
puts $fh "create_clock -period 10.000 -name clk_a \[get_ports $CLK_A\]"
if { $CLK_B ne "" } {
    puts $fh "create_clock -period 10.000 -name clk_b \[get_ports $CLK_B\]"
    puts $fh "set_clock_groups -asynchronous -group \[get_clocks clk_a\] -group \[get_clocks clk_b\]"
}
close $fh
set_global_assignment -name SDC_FILE $sdc_file

# Analysis & Synthesis only (no Fitter)
if { [catch { execute_module -tool map } err] } {
    puts "ERROR: Quartus synthesis of $NAME failed: $err"
    project_close
    exit 1
}
project_close
puts "Quartus synthesis of $NAME complete."
