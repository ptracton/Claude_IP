# synth.tcl — Vivado out-of-context synthesis of one sram top (TECH = XILINX).
#
# Target: Zynq-7010 (xc7z010clg400-1), 100 MHz. Driven by
# synthesis/run_vendor_synth.py, which sets (one variant per run):
#   SRAM_NAME     report base name (e.g. sram_apb_opts_vhdl)
#   SRAM_TOP      top module / entity (sram_<proto> or sram_<proto>_dp)
#   SRAM_LANG     sv | vhdl
#   SRAM_FILES    RTL files in compile order (space separated)
#   SRAM_GENERICS generics, "NAME=value ..." (TECH=1 selects the XPM leaves)
#   SRAM_CLK_A    port A clock port; SRAM_CLK_B port B clock port ("" = none)
#   SRAM_OUT_DIR  where reports go (synthesis/vivado/work)
#
# The array must map to block RAM (xpm_memory_spram / xpm_memory_tdpram);
# the runner fails a variant whose utilization shows no Block RAM Tile.

set PART    "xc7z010clg400-1"
set NAME    $::env(SRAM_NAME)
set TOP     $::env(SRAM_TOP)
set LANG    $::env(SRAM_LANG)
set OUT_DIR $::env(SRAM_OUT_DIR)
set CLK_A   $::env(SRAM_CLK_A)
set CLK_B   $::env(SRAM_CLK_B)
file mkdir $OUT_DIR

create_project -in_memory -part $PART
# The VHDL leaves declare the XPM components themselves (no "library xpm").
set_property XPM_LIBRARIES {XPM_MEMORY} [current_project]

foreach f $::env(SRAM_FILES) {
    if { $LANG eq "vhdl" } {
        read_vhdl -vhdl2008 $f
    } else {
        read_verilog -sv $f
    }
}

# 100 MHz on each bus clock; port B (dual port, COMMON_CLK 0) is unrelated
set xdc_file "$OUT_DIR/${NAME}_ooc.xdc"
set fh [open $xdc_file w]
puts $fh "create_clock -period 10.000 -name clk_a \[get_ports $CLK_A\]"
if { $CLK_B ne "" } {
    puts $fh "create_clock -period 10.000 -name clk_b \[get_ports $CLK_B\]"
    puts $fh "set_clock_groups -asynchronous -group \[get_clocks clk_a\] -group \[get_clocks clk_b\]"
}
close $fh
read_xdc -mode out_of_context $xdc_file

synth_design -top $TOP -part $PART -mode out_of_context \
    -flatten_hierarchy rebuilt -generic $::env(SRAM_GENERICS)

report_utilization    -file $OUT_DIR/${NAME}_utilization.rpt
report_timing_summary -file $OUT_DIR/${NAME}_timing_summary.rpt
report_ram_utilization -file $OUT_DIR/${NAME}_ram.rpt

puts "Vivado synthesis of $NAME complete."
