// sram_bus_agent.sv — Active agent of one sram bus port (sequencer, driver,
// monitor). The sequencer keeps a handle to its driver so sequences can wait
// for the port to go idle (sram_bus_sequencer::wait_idle).

`ifndef SRAM_BUS_AGENT_SV
`define SRAM_BUS_AGENT_SV

class sram_bus_sequencer extends uvm_sequencer #(sram_bus_item);
  `uvm_component_utils(sram_bus_sequencer)

  sram_bus_driver drv;
  sram_uvm_cfg    cfg;
  int unsigned    port;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task wait_idle();
    drv.wait_idle();
  endtask

endclass : sram_bus_sequencer

class sram_bus_agent extends uvm_agent;
  `uvm_component_utils(sram_bus_agent)

  sram_bus_sequencer sqr;
  sram_bus_driver    drv;
  sram_bus_monitor   mon;
  int unsigned       port;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    void'(uvm_config_db #(int unsigned)::get(this, "", "port", port));
    uvm_config_db #(int unsigned)::set(this, "*", "port", port);
    sqr = sram_bus_sequencer::type_id::create("sqr", this);
    drv = sram_bus_driver::type_id::create("drv", this);
    mon = sram_bus_monitor::type_id::create("mon", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    drv.seq_item_port.connect(sqr.seq_item_export);
    sqr.drv  = drv;
    sqr.port = port;
    void'(uvm_config_db #(sram_uvm_cfg)::get(this, "", "cfg", sqr.cfg));
  endfunction

endclass : sram_bus_agent

`endif // SRAM_BUS_AGENT_SV
