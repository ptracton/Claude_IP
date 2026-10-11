// bus_matrix_env.sv — UVM environment for the bus_matrix AXI4-Lite variant.
//
// One active AXI4-Lite master agent per master port (m0_agent = CPU,
// m1_agent = DMA); both monitors feed the scoreboard and the coverage
// collector. The slaves are passive memories in the testbench top.

`ifndef BUS_MATRIX_ENV_SV
`define BUS_MATRIX_ENV_SV

class bus_matrix_env extends uvm_env;
  `uvm_component_utils(bus_matrix_env)

  bus_matrix_axi_agent  m0_agent;
  bus_matrix_axi_agent  m1_agent;
  bus_matrix_scoreboard sb;
  bus_matrix_coverage   cov;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m0_agent = bus_matrix_axi_agent::type_id::create("m0_agent", this);
    m1_agent = bus_matrix_axi_agent::type_id::create("m1_agent", this);
    sb       = bus_matrix_scoreboard::type_id::create("sb", this);
    cov      = bus_matrix_coverage::type_id::create("cov", this);
  endfunction

  function void connect_phase(uvm_phase phase);
    m0_agent.ap.connect(sb.m0_export);
    m1_agent.ap.connect(sb.m1_export);
    m0_agent.ap.connect(cov.m0_export);
    m1_agent.ap.connect(cov.m1_export);
  endfunction

endclass : bus_matrix_env

`endif // BUS_MATRIX_ENV_SV
