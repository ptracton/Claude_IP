// bus_matrix_contention_seq.sv — Two-master contention sequence.
//
// Sends transactions from master 0 and master 1 targeting the same slave
// to exercise the arbiter. Runs on both sequencers in parallel (fork/join).
// The test must start this sequence on both m0_seqr and m1_seqr.

`ifndef BUS_MATRIX_CONTENTION_SEQ_SV
`define BUS_MATRIX_CONTENTION_SEQ_SV

// Single-master half of the contention test
class bus_matrix_contention_half_seq extends bus_matrix_base_seq;
  `uvm_object_utils(bus_matrix_contention_half_seq)

  localparam logic [31:0] S0_BASE = 32'h1000_0000;

  int unsigned num_words = 8;
  int unsigned master_id = 0;  // 0 or 1 — used for data pattern only

  function new(string name = "bus_matrix_contention_half_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0] rdata;
    `uvm_info("CONTENTION_SEQ",
      $sformatf("Master %0d starting contention writes", master_id), UVM_MEDIUM)

    for (int i = 0; i < num_words; i++) begin
      // Write a distinct pattern per master
      do_write(S0_BASE + (i * 4), (master_id == 0) ? (32'hCAFE_0000 + i)
                                                    : (32'hBEEF_0000 + i));
    end

    // Read back what this master last wrote
    for (int i = 0; i < num_words; i++) begin
      do_read(S0_BASE + (i * 4), rdata);
      // Relaxed check: just verify no X/Z (arbitration winner may differ)
      if ($isunknown(rdata))
        `uvm_error("CONTENTION_SEQ",
          $sformatf("Master %0d: read returned X/Z at S0[%0d]", master_id, i))
    end

    `uvm_info("CONTENTION_SEQ",
      $sformatf("Master %0d contention sequence done", master_id), UVM_MEDIUM)
  endtask

endclass : bus_matrix_contention_half_seq

`endif // BUS_MATRIX_CONTENTION_SEQ_SV
