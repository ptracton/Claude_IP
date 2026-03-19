// timer_uvm_pkg.sv — UVM package for Timer APB4 testbench.
//
// Collects all UVM classes in dependency order.  The top-level testbench
// module (tb_timer_uvm.sv) imports this package.
//
// NOTE: Requires a UVM-capable simulator (VCS, Questasim, or Riviera-PRO).
//       Not compatible with Icarus Verilog or GHDL.

package timer_uvm_pkg;

  import uvm_pkg::*;
  `include "uvm_macros.svh"

  // Sequence item must come first (referenced by all other classes)
  `include "timer_seq_item.sv"

  // Sequencer depends only on the item
  `include "timer_sequencer.sv"

  // Driver depends on item and sequencer
  `include "timer_apb_driver.sv"

  // Monitor depends on item
  `include "timer_apb_monitor.sv"

  // Scoreboard depends on item
  `include "timer_scoreboard.sv"

  // Sequences depend on item, sequencer
  `include "timer_base_seq.sv"

  // Environment depends on driver, sequencer, monitor, scoreboard
  `include "timer_env.sv"

  // Test depends on environment and sequences
  `include "timer_base_test.sv"

endpackage : timer_uvm_pkg
