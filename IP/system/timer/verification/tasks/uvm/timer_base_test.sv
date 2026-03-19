// timer_base_test.sv — UVM base test for Timer APB4 testbench.
//
// Creates the timer_env, runs timer_reg_rw_seq then timer_irq_seq,
// and manages UVM objection properly.
//
// This test is the entry point when the simulator calls run_test("timer_base_test").
//
// NOTE: Requires a UVM-capable simulator (VCS, Questasim, or Riviera-PRO).
//       Not compatible with Icarus Verilog or GHDL.

class timer_base_test extends uvm_test;

  // -------------------------------------------------------------------------
  // UVM factory registration
  // -------------------------------------------------------------------------
  `uvm_component_utils(timer_base_test)

  // -------------------------------------------------------------------------
  // Environment handle
  // -------------------------------------------------------------------------
  timer_env u_env;

  // -------------------------------------------------------------------------
  // Constructor
  // -------------------------------------------------------------------------
  function new(string name = "timer_base_test", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // -------------------------------------------------------------------------
  // build_phase — create environment
  // -------------------------------------------------------------------------
  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    u_env = timer_env::type_id::create("u_env", this);
  endfunction

  // -------------------------------------------------------------------------
  // run_phase — raise objection, run sequences, drop objection
  // -------------------------------------------------------------------------
  task run_phase(uvm_phase phase);
    timer_reg_rw_seq rw_seq;
    timer_irq_seq    irq_seq;

    phase.raise_objection(this, "timer_base_test: starting sequences");
    `uvm_info("TEST", "=== timer_base_test run_phase START ===", UVM_LOW)

    // ------------------------------------------------------------------
    // Sequence 1: register read-write verification
    // ------------------------------------------------------------------
    rw_seq = timer_reg_rw_seq::type_id::create("rw_seq");
    rw_seq.start(u_env.u_sequencer);

    // ------------------------------------------------------------------
    // Sequence 2: IRQ generation and W1C clear
    // ------------------------------------------------------------------
    irq_seq = timer_irq_seq::type_id::create("irq_seq");
    irq_seq.start(u_env.u_sequencer);

    `uvm_info("TEST", "=== timer_base_test run_phase END ===", UVM_LOW)
    phase.drop_objection(this, "timer_base_test: all sequences complete");
  endtask

  // -------------------------------------------------------------------------
  // report_phase — final test status
  // -------------------------------------------------------------------------
  function void report_phase(uvm_phase phase);
    uvm_report_server srv = uvm_report_server::get_server();
    int unsigned err_count = srv.get_severity_count(UVM_ERROR)
                           + srv.get_severity_count(UVM_FATAL);
    if (err_count == 0) begin
      `uvm_info("TEST", "*** TEST PASSED ***", UVM_NONE)
    end else begin
      `uvm_error("TEST",
        $sformatf("*** TEST FAILED *** (%0d error(s))", err_count))
    end
  endfunction

endclass : timer_base_test
