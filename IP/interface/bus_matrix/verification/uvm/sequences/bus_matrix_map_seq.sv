// bus_matrix_map_seq.sv — walks the whole address map from one master.
//
// For every slave of the bus_matrix_pkg map:
//   1. num_words full-word writes, then read-back
//   2. every write-strobe pattern on one word (byte lanes, halves, full),
//      checking the merged value after each write
//   3. the last word of the region and a word in the middle of the region
//   4. S2/S3 only: write and read in the slave's error page (0xE00-0xEFF),
//      which must answer SLVERR and leave the slave's memory unchanged
// Each master works in its own part of each slave's 4 KB window (offsets
// master_id*0x400 ..), so two instances can run in parallel and contend
// for every slave while their read-back checks stay deterministic.

`ifndef BUS_MATRIX_MAP_SEQ_SV
`define BUS_MATRIX_MAP_SEQ_SV

class bus_matrix_map_seq extends bus_matrix_base_seq;
  `uvm_object_utils(bus_matrix_map_seq)

  int unsigned master_id = 0; // 0 or 1: selects this master's offsets
  int unsigned num_words = 8;

  function new(string name = "bus_matrix_map_seq");
    super.new(name);
  endfunction

  task body();
    logic [31:0] exp;
    logic [31:0] strbs [7] = '{4'h1, 4'h2, 4'h4, 4'h8, 4'h3, 4'hC, 4'hF};

    for (int j = 0; j < bus_matrix_pkg::BM_NUM_SLAVES; j++) begin
      logic [31:0] base = slv_base(j);
      logic [31:0] size = slv_size(j);
      logic [31:0] off  = master_id * 32'h400;
      `uvm_info("MAP_SEQ", $sformatf("M%0d: slave %0d @0x%08x", master_id, j, base), UVM_MEDIUM)

      // 1. full words
      for (int i = 0; i < num_words; i++)
        do_write(base + off + i*4, {4'(master_id), 4'(j), 8'(i), 16'hA5A5});
      for (int i = 0; i < num_words; i++)
        check_read(base + off + i*4, {4'(master_id), 4'(j), 8'(i), 16'hA5A5},
                   $sformatf("S%0d word %0d", j, i));

      // 2. strobes, merging into one word
      exp = 32'h0;
      do_write(base + off + 32'h100, exp);
      foreach (strbs[k]) begin
        logic [31:0] d = {4'(k), 4'(j), 4'(master_id), 4'h7, 16'(k * 32'h1111)};
        do_write(base + off + 32'h100, d, strbs[k][3:0]);
        for (int b = 0; b < 4; b++)
          if (strbs[k][b]) exp[b*8+:8] = d[b*8+:8];
        check_read(base + off + 32'h100, exp, $sformatf("S%0d strobe %04b", j, strbs[k][3:0]));
      end

      // 3. last word of the region (aliases to the top of the 4 KB window:
      //    0xFFC for M0, 0xFF8 for M1) and a word in the middle of the region
      do_write(base + size - 4 - master_id*4, 32'h1A57_0000 | (j << 8) | master_id);
      check_read(base + size - 4 - master_id*4, 32'h1A57_0000 | (j << 8) | master_id,
                 $sformatf("S%0d last word", j));
      do_write(base + size/2 + off + 32'h200, 32'h0D1D_0000 | (j << 8) | master_id);
      check_read(base + size/2 + off + 32'h200, 32'h0D1D_0000 | (j << 8) | master_id,
                 $sformatf("S%0d mid-region", j));

      // 4. slave error page
      if (SLV_ERR_SLAVES[j]) begin
        logic [31:0] err_addr = base + {SLV_ERR_PAGE, 8'h00} + master_id * 32'h80;
        logic [31:0] rdata;
        do_write(err_addr, 32'hBAD0_0000 | j, 4'hF, 1'b1);
        do_read(err_addr, rdata, 1'b1);
        do_write(err_addr + 4, 32'hBAD1_0000 | j, 4'h3, 1'b1);
        do_read(err_addr + 4, rdata, 1'b1);
        // the error did not disturb the slave: word 0 still reads back
        check_read(base + off, {4'(master_id), 4'(j), 8'(0), 16'hA5A5},
                   $sformatf("S%0d word 0 after slave errors", j));
      end
    end
  endtask

endclass : bus_matrix_map_seq

`endif // BUS_MATRIX_MAP_SEQ_SV
