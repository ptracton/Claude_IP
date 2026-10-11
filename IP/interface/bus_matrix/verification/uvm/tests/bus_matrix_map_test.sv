// bus_matrix_map_test.sv — full address-map test from both masters at once.
//
// Phase 1: bus_matrix_map_seq on M0 and M1 in parallel — both masters walk
//          every slave (full words, every strobe, region boundaries, the
//          S2/S3 slave-error page), contending for each slave in turn.
// Phase 2: bus_matrix_decerr_seq on both masters in parallel — decode errors
//          on every gap of the map; M0 also checks that no slave was touched.

`ifndef BUS_MATRIX_MAP_TEST_SV
`define BUS_MATRIX_MAP_TEST_SV

class bus_matrix_map_test extends bus_matrix_base_test;
  `uvm_component_utils(bus_matrix_map_test)

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  task run_phase(uvm_phase phase);
    bus_matrix_map_seq    map0, map1;
    bus_matrix_decerr_seq err0, err1;
    phase.raise_objection(this);

    map0 = bus_matrix_map_seq::type_id::create("map0");
    map1 = bus_matrix_map_seq::type_id::create("map1");
    map0.master_id = 0;
    map1.master_id = 1;
    fork
      map0.start(env.m0_agent.seqr);
      map1.start(env.m1_agent.seqr);
    join

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

endclass : bus_matrix_map_test

`endif // BUS_MATRIX_MAP_TEST_SV
