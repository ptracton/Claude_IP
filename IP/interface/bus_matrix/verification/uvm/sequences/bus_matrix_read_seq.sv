// bus_matrix_read_seq.sv — Reads back from all slave regions and checks expected data.

`ifndef BUS_MATRIX_READ_SEQ_SV
`define BUS_MATRIX_READ_SEQ_SV

class bus_matrix_read_seq extends bus_matrix_base_seq;
  `uvm_object_utils(bus_matrix_read_seq)

  localparam logic [31:0] S0_BASE = 32'h1000_0000;
  localparam logic [31:0] S1_BASE = 32'h2000_0000;

  int unsigned num_words = 8;

  // Expected data arrays (populated by write_seq or test)
  logic [31:0] exp_s0 [0:255];
  logic [31:0] exp_s1 [0:255];

  function new(string name = "bus_matrix_read_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0] rdata;
    `uvm_info("READ_SEQ", "Starting read-back sequence", UVM_MEDIUM)
    for (int i = 0; i < num_words; i++) begin
      do_read(S0_BASE + (i * 4), rdata);
      if (rdata !== exp_s0[i])
        `uvm_error("READ_SEQ", $sformatf(
          "S0[%0d] mismatch: got 0x%08x exp 0x%08x", i, rdata, exp_s0[i]))

      do_read(S1_BASE + (i * 4), rdata);
      if (rdata !== exp_s1[i])
        `uvm_error("READ_SEQ", $sformatf(
          "S1[%0d] mismatch: got 0x%08x exp 0x%08x", i, rdata, exp_s1[i]))
    end
    `uvm_info("READ_SEQ", "Read-back sequence complete", UVM_MEDIUM)
  endtask

endclass : bus_matrix_read_seq

`endif // BUS_MATRIX_READ_SEQ_SV
