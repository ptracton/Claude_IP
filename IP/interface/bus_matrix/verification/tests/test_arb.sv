// test_arb.sv — Round-robin arbitration (the default ARB_MODE): when both
// masters request the same slave in the same cycle, the master that was not
// served last on that slave goes first. Observed at the slave's memory, which
// logs the word address of every write in order.
//
//   run 0: M0 was served last on S1 -> M1 wins the tie, then M0
//   run 1: M1 was served last on S1 -> M0 wins the tie, then M1
// Each run is checked with both start orders of the testbench processes.

task automatic test_arb;
  logic [11:0] first_off, second_off;
  begin
    test_start("test_arb");
    for (int run = 0; run < 4; run++) begin
      // Make the other master the last one served on S1
      if (run < 2) begin
        u_m0.write_reg(slv_addr(1, 12'h700), 32'h0000_0700, 4'hF);
        first_off  = 12'h600;  // M1
        second_off = 12'h500;  // M0
      end else begin
        u_m1.write_reg(slv_addr(1, 12'h700), 32'h0000_0700, 4'hF);
        first_off  = 12'h500;  // M0
        second_off = 12'h600;  // M1
      end
      @(posedge clk);
      gen_slv[1].u_mem.clear_log();
      if (run % 2 == 0) begin
        fork
          u_m0.write_reg(slv_addr(1, 12'h500), 32'h0000_0500, 4'hF);
          u_m1.write_reg(slv_addr(1, 12'h600), 32'h0000_0600, 4'hF);
        join
      end else begin
        fork
          u_m1.write_reg(slv_addr(1, 12'h600), 32'h0000_0600, 4'hF);
          u_m0.write_reg(slv_addr(1, 12'h500), 32'h0000_0500, 4'hF);
        join
      end
      @(posedge clk); // the last write lands in the memory on the edge that ends it
      check_eq(gen_slv[1].u_mem.wr_count, 32'd2, $sformatf("run %0d: two writes", run));
      check_eq(32'(gen_slv[1].u_mem.wr_log[0]), 32'(first_off >> 2),
               $sformatf("run %0d: winner first", run));
      check_eq(32'(gen_slv[1].u_mem.wr_log[1]), 32'(second_off >> 2),
               $sformatf("run %0d: other second", run));
    end
    test_done("test_arb");
  end
endtask
