// bus_matrix_rw_seq.sv — Write then read-back sequence with data checking.

`ifndef BUS_MATRIX_RW_SEQ_SV
`define BUS_MATRIX_RW_SEQ_SV

class bus_matrix_rw_seq extends bus_matrix_base_seq;
  `uvm_object_utils(bus_matrix_rw_seq)

  localparam logic [31:0] S0_BASE = 32'h1000_0000;
  localparam logic [31:0] S1_BASE = 32'h2000_0000;

  int unsigned num_words = 16;

  function new(string name = "bus_matrix_rw_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0] wdata_s0[0:255];
    logic [31:0] wdata_s1[0:255];
    logic [31:0] rdata;

    `uvm_info("RW_SEQ", "Phase 1: writes", UVM_MEDIUM)
    for (int i = 0; i < num_words; i++) begin
      wdata_s0[i] = $urandom();
      wdata_s1[i] = $urandom();
      do_write(S0_BASE + (i * 4), wdata_s0[i]);
      do_write(S1_BASE + (i * 4), wdata_s1[i]);
    end

    `uvm_info("RW_SEQ", "Phase 2: read-back", UVM_MEDIUM)
    for (int i = 0; i < num_words; i++) begin
      do_read(S0_BASE + (i * 4), rdata);
      if (rdata !== wdata_s0[i])
        `uvm_error("RW_SEQ", $sformatf(
          "S0[%0d] MISMATCH: got 0x%08x exp 0x%08x", i, rdata, wdata_s0[i]))

      do_read(S1_BASE + (i * 4), rdata);
      if (rdata !== wdata_s1[i])
        `uvm_error("RW_SEQ", $sformatf(
          "S1[%0d] MISMATCH: got 0x%08x exp 0x%08x", i, rdata, wdata_s1[i]))
    end
    `uvm_info("RW_SEQ", "RW sequence PASSED", UVM_MEDIUM)
  endtask

endclass : bus_matrix_rw_seq

`endif // BUS_MATRIX_RW_SEQ_SV
