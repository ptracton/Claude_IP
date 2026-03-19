// timer_sequencer.sv — UVM sequencer for Timer APB4 testbench.
//
// Standard UVM sequencer parameterized on timer_seq_item.
// Sequences pull items through this sequencer to the driver.
//
// NOTE: Requires a UVM-capable simulator (VCS, Questasim, or Riviera-PRO).
//       Not compatible with Icarus Verilog or GHDL.

class timer_sequencer extends uvm_sequencer #(timer_seq_item);

  // -------------------------------------------------------------------------
  // UVM factory registration
  // -------------------------------------------------------------------------
  `uvm_component_utils(timer_sequencer)

  // -------------------------------------------------------------------------
  // Constructor
  // -------------------------------------------------------------------------
  function new(string name = "timer_sequencer", uvm_component parent = null);
    super.new(name, parent);
  endfunction

endclass : timer_sequencer
