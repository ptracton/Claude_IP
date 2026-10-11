// bus_matrix_decerr_test.sv — decode errors only.
//
// bus_matrix_decerr_seq on M0 (with the guard check: no slave may be written
// by a decode error) and, at the same time, on M1 walking the gaps in the
// opposite order, so the matrix answers decode errors on both masters
// concurrently.

`ifndef BUS_MATRIX_DECERR_TEST_SV
`define BUS_MATRIX_DECERR_TEST_SV

class bus_matrix_decerr_test extends bus_matrix_base_test;
  `uvm_component_utils(bus_matrix_decerr_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    bus_matrix_decerr_seq err0, err1;
    phase.raise_objection(this);
    err0 = bus_matrix_decerr_seq::type_id::create("err0");
    err1 = bus_matrix_decerr_seq::type_id::create("err1");
    err0.master_id = 0; err0.check_guards = 1'b1;
    err1.master_id = 1; err1.check_guards = 1'b0;
    fork
      err0.start(env.m0_agent.seqr);
      err1.start(env.m1_agent.seqr);
    join
    phase.drop_objection(this);
  endtask

endclass : bus_matrix_decerr_test

`endif // BUS_MATRIX_DECERR_TEST_SV
