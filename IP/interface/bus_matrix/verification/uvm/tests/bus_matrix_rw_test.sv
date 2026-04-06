// bus_matrix_rw_test.sv — Write then read-back test on both slave regions.

`ifndef BUS_MATRIX_RW_TEST_SV
`define BUS_MATRIX_RW_TEST_SV

class bus_matrix_rw_test extends bus_matrix_base_test;
  `uvm_component_utils(bus_matrix_rw_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    bus_matrix_rw_seq seq;
    phase.raise_objection(this);
    seq = bus_matrix_rw_seq::type_id::create("rw_seq");
    seq.num_words = 32;
    seq.start(env.m0_agent.seqr);
    phase.drop_objection(this);
  endtask

endclass : bus_matrix_rw_test

`endif // BUS_MATRIX_RW_TEST_SV
