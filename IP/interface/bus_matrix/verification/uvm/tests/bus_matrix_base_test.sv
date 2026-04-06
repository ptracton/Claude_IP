// bus_matrix_base_test.sv — Base UVM test: builds env, configures virtual interfaces.

`ifndef BUS_MATRIX_BASE_TEST_SV
`define BUS_MATRIX_BASE_TEST_SV

class bus_matrix_base_test extends uvm_test;
  `uvm_component_utils(bus_matrix_base_test)

  bus_matrix_env env;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    env = bus_matrix_env::type_id::create("env", this);
  endfunction

  task run_phase(uvm_phase phase);
    phase.raise_objection(this);
    `uvm_info("TEST", "Base test — no sequences run", UVM_MEDIUM)
    #100;
    phase.drop_objection(this);
  endtask

  function void final_phase(uvm_phase phase);
    uvm_report_server svr = uvm_report_server::get_server();
    if (svr.get_severity_count(UVM_ERROR) > 0 ||
        svr.get_severity_count(UVM_FATAL) > 0)
      `uvm_info("TEST", "*** TEST FAILED ***", UVM_NONE)
    else
      `uvm_info("TEST", "*** TEST PASSED ***", UVM_NONE)
  endfunction

endclass : bus_matrix_base_test

`endif // BUS_MATRIX_BASE_TEST_SV
