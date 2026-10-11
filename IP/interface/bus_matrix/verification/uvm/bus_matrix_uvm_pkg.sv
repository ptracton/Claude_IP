// bus_matrix_uvm_pkg.sv — UVM package for bus_matrix AXI4-Lite verification.
//
// Includes all UVM classes in dependency order.

`ifndef BUS_MATRIX_UVM_PKG_SV
`define BUS_MATRIX_UVM_PKG_SV

`include "uvm_macros.svh"

package bus_matrix_uvm_pkg;
  import uvm_pkg::*;

  // ---- Testbench slave behaviour (tb_bus_matrix_uvm) ------------------------
  // S2/S3 are bus_matrix_tb_axi4l_slave models: offsets 0xE00-0xEFF of their
  // 4 KB window (page SLV_ERR_PAGE) answer SLVERR. S0/S1 (claude_axi4l_if)
  // never error.
  localparam logic [3:0] SLV_ERR_SLAVES = 4'b1100;
  localparam logic [3:0] SLV_ERR_PAGE   = 4'hE;

  // ---- AXI4-Lite transaction -----------------------------------------------
  `include "agents/axi_master/bus_matrix_axi_seq_item.sv"

  // ---- AXI master agent components -----------------------------------------
  `include "agents/axi_master/bus_matrix_axi_driver.sv"
  `include "agents/axi_master/bus_matrix_axi_monitor.sv"
  `include "agents/axi_master/bus_matrix_axi_sequencer.sv"
  `include "agents/axi_master/bus_matrix_axi_agent.sv"

  // ---- Sequences -----------------------------------------------------------
  `include "sequences/bus_matrix_base_seq.sv"
  `include "sequences/bus_matrix_write_seq.sv"
  `include "sequences/bus_matrix_read_seq.sv"
  `include "sequences/bus_matrix_rw_seq.sv"
  `include "sequences/bus_matrix_contention_seq.sv"
  `include "sequences/bus_matrix_map_seq.sv"
  `include "sequences/bus_matrix_decerr_seq.sv"

  // ---- Scoreboard and coverage --------------------------------------------
  `include "env/bus_matrix_scoreboard.sv"
  `include "env/bus_matrix_coverage.sv"

  // ---- Environment --------------------------------------------------------
  `include "env/bus_matrix_env.sv"

  // ---- Tests --------------------------------------------------------------
  `include "tests/bus_matrix_base_test.sv"
  `include "tests/bus_matrix_rw_test.sv"
  `include "tests/bus_matrix_contention_test.sv"
  `include "tests/bus_matrix_map_test.sv"
  `include "tests/bus_matrix_decerr_test.sv"

endpackage : bus_matrix_uvm_pkg

`endif // BUS_MATRIX_UVM_PKG_SV
