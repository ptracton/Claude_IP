// sram_tests.sv — UVM tests of the sram bench.
//
// sram_base_test builds the env, runs the virtual sequence that
// make_vseq() returns, and prints "TEST PASSED" / "TEST FAILED" (the marker
// uvm_sram.py looks for) from the UVM error / fatal counts. A test whose
// feature the build lacks runs and reports that it skipped the feature
// (uvm_sram.py only schedules the tests that apply to a configuration).

`ifndef SRAM_TESTS_SV
`define SRAM_TESTS_SV

class sram_base_test extends uvm_test;
  `uvm_component_utils(sram_base_test)

  sram_env     env;
  sram_uvm_cfg cfg;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(sram_uvm_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("TEST", "no sram_uvm_cfg (cfg)")
    end
    env = sram_env::type_id::create("env", this);
  endfunction

  virtual function sram_base_vseq make_vseq();
    sram_smoke_vseq v;
    v = sram_smoke_vseq::type_id::create("vseq");
    return v;
  endfunction

  task run_phase(uvm_phase phase);
    sram_base_vseq v;
    phase.raise_objection(this);
    `uvm_info("TEST", {"configuration: ", cfg.convert2string()}, UVM_NONE)
    @(posedge env.bus[0].drv.vif.rst_n);
    repeat (4) @(posedge env.bus[0].drv.vif.clk);
    v = make_vseq();
    v.start(env.vsqr);
    // let the last responses and status pulses arrive
    repeat (20) @(posedge env.bus[0].drv.vif.clk);
    phase.drop_objection(this);
  endtask

  function void report_phase(uvm_phase phase);
    uvm_report_server rs;
    int unsigned      n;
    rs = uvm_report_server::get_server();
    n  = rs.get_severity_count(UVM_ERROR) + rs.get_severity_count(UVM_FATAL);
    if (n == 0) `uvm_info("TEST", "TEST PASSED", UVM_NONE)
    else `uvm_info("TEST", $sformatf("TEST FAILED (%0d errors)", n), UVM_NONE)
  endfunction

endclass : sram_base_test

`define SRAM_TEST(T, V) \
  class T extends sram_base_test; \
    `uvm_component_utils(T) \
    function new(string name, uvm_component parent); \
      super.new(name, parent); \
    endfunction \
    virtual function sram_base_vseq make_vseq(); \
      V v; \
      v = V::type_id::create("vseq"); \
      return v; \
    endfunction \
  endclass : T

`SRAM_TEST(sram_smoke_test, sram_smoke_vseq)
`SRAM_TEST(sram_random_test, sram_random_vseq)
`SRAM_TEST(sram_power_test, sram_power_vseq)
`SRAM_TEST(sram_clear_test, sram_clear_vseq)
`SRAM_TEST(sram_ecc_test, sram_ecc_vseq)
`SRAM_TEST(sram_bist_test, sram_bist_vseq)
`SRAM_TEST(sram_dp_test, sram_dp_vseq)
`SRAM_TEST(sram_stress_test, sram_stress_vseq)

`endif // SRAM_TESTS_SV
