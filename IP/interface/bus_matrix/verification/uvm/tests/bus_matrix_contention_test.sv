// bus_matrix_contention_test.sv — Two-master simultaneous access contention test.
//
// Forks sequences on m0_agent and m1_agent simultaneously so both masters
// contend for the same slave, exercising the arbiter.

`ifndef BUS_MATRIX_CONTENTION_TEST_SV
`define BUS_MATRIX_CONTENTION_TEST_SV

class bus_matrix_contention_test extends bus_matrix_base_test;
  `uvm_component_utils(bus_matrix_contention_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    bus_matrix_contention_half_seq seq0, seq1;
    phase.raise_objection(this);

    seq0 = bus_matrix_contention_half_seq::type_id::create("seq0");
    seq1 = bus_matrix_contention_half_seq::type_id::create("seq1");
    seq0.num_words = 16; seq0.master_id = 0;
    seq1.num_words = 16; seq1.master_id = 1;

    // Launch both masters simultaneously
    fork
      seq0.start(env.m0_agent.seqr);
      seq1.start(env.m1_agent.seqr);
    join

    `uvm_info("CONTENTION_TEST", "Both masters completed — contention test done", UVM_MEDIUM)
    phase.drop_objection(this);
  endtask

endclass : bus_matrix_contention_test

`endif // BUS_MATRIX_CONTENTION_TEST_SV
