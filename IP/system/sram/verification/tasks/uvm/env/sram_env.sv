// sram_env.sv — UVM environment of the sram bench: one bus agent per port,
// the side-band agent, scoreboard, coverage and the virtual sequencer.

`ifndef SRAM_ENV_SV
`define SRAM_ENV_SV

class sram_vsequencer extends uvm_sequencer;
  `uvm_component_utils(sram_vsequencer)

  sram_uvm_cfg                  cfg;
  sram_bus_sequencer            bus_sqr [2];
  uvm_sequencer #(sram_sb_item) sb_sqr;
  sram_scoreboard               sb;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

endclass : sram_vsequencer

class sram_env extends uvm_env;
  `uvm_component_utils(sram_env)

  sram_uvm_cfg    cfg;
  sram_bus_agent  bus [2];
  sram_sb_agent   sba;
  sram_scoreboard sb;
  sram_coverage   cov;
  sram_vsequencer vsqr;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(sram_uvm_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("ENV", "no sram_uvm_cfg (cfg)")
    end
    for (int unsigned p = 0; p < cfg.nports(); p++) begin
      string n;
      n = (p == 0) ? "bus_a" : "bus_b";
      uvm_config_db #(int unsigned)::set(this, n, "port", p);
      uvm_config_db #(int unsigned)::set(this, {n, ".*"}, "port", p);
      bus[p] = sram_bus_agent::type_id::create(n, this);
    end
    sba  = sram_sb_agent::type_id::create("sba", this);
    sb   = sram_scoreboard::type_id::create("sb", this);
    cov  = sram_coverage::type_id::create("cov", this);
    vsqr = sram_vsequencer::type_id::create("vsqr", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    for (int unsigned p = 0; p < cfg.nports(); p++) begin
      bus[p].mon.ap.connect(sb.bus_export);
      vsqr.bus_sqr[p] = bus[p].sqr;
    end
    sba.mon.ap.connect(sb.sb_export);
    sb.cov      = cov;
    vsqr.cfg    = cfg;
    vsqr.sb_sqr = sba.sqr;
    vsqr.sb     = sb;
  endfunction

endclass : sram_env

`endif // SRAM_ENV_SV
