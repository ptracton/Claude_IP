// bus_matrix_axi_sequencer.sv — UVM sequencer for AXI4-Lite master port.

`ifndef BUS_MATRIX_AXI_SEQUENCER_SV
`define BUS_MATRIX_AXI_SEQUENCER_SV

class bus_matrix_axi_sequencer extends uvm_sequencer #(bus_matrix_axi_seq_item);
  `uvm_component_utils(bus_matrix_axi_sequencer)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : bus_matrix_axi_sequencer

`endif // BUS_MATRIX_AXI_SEQUENCER_SV
