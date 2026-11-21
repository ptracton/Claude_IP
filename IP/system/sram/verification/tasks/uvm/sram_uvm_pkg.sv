// sram_uvm_pkg.sv — UVM package of the sram bench (Step 6): every class, in
// dependency order. Include directories: this directory and its agents/bus,
// agents/sb, env, sequences and tests subdirectories.

`ifndef SRAM_UVM_PKG_SV
`define SRAM_UVM_PKG_SV

`include "uvm_macros.svh"

package sram_uvm_pkg;
  import uvm_pkg::*;

  `include "sram_uvm_cfg.sv"
  `include "sram_bus_item.sv"
  `include "sram_bus_driver.sv"
  `include "sram_bus_monitor.sv"
  `include "sram_bus_agent.sv"
  `include "sram_sb_item.sv"
  `include "sram_sb_agent.sv"
  `include "sram_coverage.sv"
  `include "sram_scoreboard.sv"
  `include "sram_env.sv"
  `include "sram_bus_seqs.sv"
  `include "sram_vseqs.sv"
  `include "sram_tests.sv"

endpackage : sram_uvm_pkg

`endif // SRAM_UVM_PKG_SV
