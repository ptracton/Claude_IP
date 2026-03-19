// timer_env.sv — UVM environment for Timer APB4 testbench.
//
// Instantiates and connects:
//   - timer_apb_driver   (u_driver)
//   - timer_sequencer    (u_sequencer)
//   - timer_apb_monitor  (u_monitor)
//   - timer_scoreboard   (u_scoreboard)
//
// Connectivity:
//   driver.seq_item_port  -> sequencer.seq_item_export  (TLM FIFO)
//   monitor.ap            -> scoreboard.apb_export      (analysis)
//
// The virtual interface handle "timer_apb_vif" must be set in the config_db
// by the top-level testbench before the run phase.  The environment propagates
// it to driver and monitor via config_db (using the component context path).
//
// NOTE: Requires a UVM-capable simulator (VCS, Questasim, or Riviera-PRO).
//       Not compatible with Icarus Verilog or GHDL.

class timer_env extends uvm_env;

  // -------------------------------------------------------------------------
  // UVM factory registration
  // -------------------------------------------------------------------------
  `uvm_component_utils(timer_env)

  // -------------------------------------------------------------------------
  // Sub-components
  // -------------------------------------------------------------------------
  timer_apb_driver  u_driver;
  timer_sequencer   u_sequencer;
  timer_apb_monitor u_monitor;
  timer_scoreboard  u_scoreboard;

  // -------------------------------------------------------------------------
  // Constructor
  // -------------------------------------------------------------------------
  function new(string name = "timer_env", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // -------------------------------------------------------------------------
  // build_phase — create all sub-components
  // -------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);

    u_driver     = timer_apb_driver ::type_id::create("u_driver",     this);
    u_sequencer  = timer_sequencer  ::type_id::create("u_sequencer",  this);
    u_monitor    = timer_apb_monitor::type_id::create("u_monitor",    this);
    u_scoreboard = timer_scoreboard ::type_id::create("u_scoreboard", this);
  endfunction

  // -------------------------------------------------------------------------
  // connect_phase — wire TLM ports
  // -------------------------------------------------------------------------
  function void connect_phase(uvm_phase phase);
    // Driver gets items from sequencer
    u_driver.seq_item_port.connect(u_sequencer.seq_item_export);

    // Monitor broadcasts to scoreboard
    u_monitor.ap.connect(u_scoreboard.apb_export);
  endfunction

endclass : timer_env
