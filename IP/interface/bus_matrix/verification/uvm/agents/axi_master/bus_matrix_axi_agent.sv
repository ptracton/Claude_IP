// bus_matrix_axi_agent.sv — UVM agent for AXI4-Lite master port.
//
// Active agent: contains driver, sequencer, and monitor.
// Set is_active=UVM_PASSIVE to disable driver+sequencer (monitor-only mode).

`ifndef BUS_MATRIX_AXI_AGENT_SV
`define BUS_MATRIX_AXI_AGENT_SV

class bus_matrix_axi_agent extends uvm_agent;
  `uvm_component_utils(bus_matrix_axi_agent)

  bus_matrix_axi_driver    drv;
  bus_matrix_axi_sequencer seqr;
  bus_matrix_axi_monitor   mon;

  uvm_analysis_port #(bus_matrix_axi_seq_item) ap;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    ap  = new("ap", this);
    mon = bus_matrix_axi_monitor::type_id::create("mon", this);
    if (get_is_active() == UVM_ACTIVE) begin
      drv  = bus_matrix_axi_driver::type_id::create("drv", this);
      seqr = bus_matrix_axi_sequencer::type_id::create("seqr", this);
    end
  endfunction

  function void connect_phase(uvm_phase phase);
    mon.ap.connect(ap);
    if (get_is_active() == UVM_ACTIVE)
      drv.seq_item_port.connect(seqr.seq_item_export);
  endfunction

endclass : bus_matrix_axi_agent

`endif // BUS_MATRIX_AXI_AGENT_SV
