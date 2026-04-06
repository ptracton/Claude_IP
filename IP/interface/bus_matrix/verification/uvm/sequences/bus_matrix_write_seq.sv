// bus_matrix_write_seq.sv — Writes a pattern to all four slave regions.

`ifndef BUS_MATRIX_WRITE_SEQ_SV
`define BUS_MATRIX_WRITE_SEQ_SV

class bus_matrix_write_seq extends bus_matrix_base_seq;
  `uvm_object_utils(bus_matrix_write_seq)

  // Base addresses for the two slave regions (match testbench register config)
  localparam logic [31:0] S0_BASE = 32'h1000_0000;
  localparam logic [31:0] S1_BASE = 32'h2000_0000;

  int unsigned num_words = 8;

  function new(string name = "bus_matrix_write_seq");
    super.new(name);
  endfunction

  task body();
    `uvm_info("WRITE_SEQ", "Starting write sequence", UVM_MEDIUM)
    for (int i = 0; i < num_words; i++) begin
      do_write(S0_BASE + (i * 4), 32'hA000_0000 + i);
      do_write(S1_BASE + (i * 4), 32'hB000_0000 + i);
    end
    `uvm_info("WRITE_SEQ", $sformatf("Wrote %0d words to each slave", num_words), UVM_MEDIUM)
  endtask

endclass : bus_matrix_write_seq

`endif // BUS_MATRIX_WRITE_SEQ_SV
