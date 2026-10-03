# claude_vcf_fpv.tcl — Generic VC Formal FPV run script for Claude IP blocks.
#
# Run with:  vcf -f claude_vcf_fpv.tcl -batch     (cwd = the run directory)
#
# Nothing here is IP-specific: the caller (normally
# ${IP_COMMON_PATH}/verification/tools/claude_vcf.py) describes the run through
# environment variables:
#
#   FV_TOP            top-level module/entity name
#   FV_LANG           sv | vhdl  (language of the RTL; checkers are always SVA)
#   FV_RTL_FILES      RTL files in compile order (whitespace separated)
#   FV_SVA_FILES      checker + bind files (whitespace separated)
#   FV_INCDIRS        +incdir directories for the SVA files
#   FV_BIND           name of the bind-only module to apply
#   FV_CLOCK          clock port of FV_TOP
#   FV_RESET          reset port of FV_TOP
#   FV_RESET_SENSE    low | high
#   FV_MAX_TIME       per-run time budget (e.g. 30M, 2H)
#   FV_REPORT         file that receives "report_fv -list"
#   FV_TRACE_DIR      optional: write one FSDB counterexample per falsified
#                     assertion into this directory
#
# The reset is applied with the tool's reset simulation (sim_run -stable /
# sim_save_reset), so every proof starts from the design's reset state and
# the reset input is held inactive during formal analysis.

proc fv_env {name {default ""}} {
  if {[info exists ::env($name)] && $::env($name) ne ""} {
    return $::env($name)
  }
  if {$default eq ""} {
    puts "CLAUDE_VCF_ERROR: environment variable $name is not set"
    exit 2
  }
  return $default
}

set top        [fv_env FV_TOP]
set lang       [fv_env FV_LANG]
set rtl_files  [fv_env FV_RTL_FILES]
set sva_files  [fv_env FV_SVA_FILES]
set incdirs    [fv_env FV_INCDIRS " "]
set bind_mod   [fv_env FV_BIND]
set clk        [fv_env FV_CLOCK]
set rst        [fv_env FV_RESET]
set rst_sense  [fv_env FV_RESET_SENSE low]
set max_time   [fv_env FV_MAX_TIME 30M]
set report     [fv_env FV_REPORT]

set inc_opts ""
foreach d $incdirs { append inc_opts " +incdir+$d" }

set_fml_appmode FPV
set_fml_var fml_max_time $max_time
set_fml_var fml_witness_on true

# ---------------------------------------------------------------------------
# Compile
# ---------------------------------------------------------------------------
if {$lang eq "vhdl"} {
  analyze -format vhdl -vcs "-vhdl08 [join $rtl_files { }]"
} else {
  analyze -format sverilog -vcs "-sverilog $inc_opts [join $rtl_files { }]"
}
analyze -format sverilog -vcs "-sverilog $inc_opts [join $sva_files { }]"
elaborate $top -sva -vcs "-lca -sva_bind_enable $bind_mod"

# ---------------------------------------------------------------------------
# Clock / reset
# ---------------------------------------------------------------------------
create_clock $clk -period 100
create_reset $rst -sense $rst_sense
sim_run -stable
sim_save_reset

# ---------------------------------------------------------------------------
# Prove and report
# ---------------------------------------------------------------------------
check_fv -block
report_fv -list > $report

# Counterexample waveforms (FSDB) for every falsified assertion.
set trace_dir [fv_env FV_TRACE_DIR " "]
if {[string trim $trace_dir] ne ""} {
  file mkdir $trace_dir
  foreach_in_collection p [get_props -usage assert -status falsified] {
    set name [get_attribute $p name]
    regsub -all {[^A-Za-z0-9_]} $name {_} fname
    fvtrace -property $name -file [file join $trace_dir "$fname.fsdb"]
  }
}
puts "CLAUDE_VCF_DONE"
quit
