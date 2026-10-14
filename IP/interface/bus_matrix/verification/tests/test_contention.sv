// test_contention.sv — Both masters run at the same time, first on the same
// slave (arbitration) and then on different slaves (parallel paths). Every
// transfer must complete with its own data.
//
// The forked branches use task-level loop counters (k0 for M0, k1 for M1).
// Declaring a variable inside a forked block, including a for-loop's int,
// crashes Vivado xsim 2023.2 when a task has more than one such fork.

task automatic test_contention;
  logic [31:0] rdata;
  logic [31:0] r0, r1;
  int          k0, k1; // loop counters of the M0 / M1 threads
  begin
    test_start("test_contention");
    // Same slave (SRAM): interleaved writes
    fork
      begin
        for (k0 = 0; k0 < 8; k0++) begin
          u_m0.write_reg(slv_addr(1, 12'h200 + 12'(4*k0)), 32'h0A00_0000 | k0, 4'hF);
        end
      end
      begin
        for (k1 = 0; k1 < 8; k1++) begin
          u_m1.write_reg(slv_addr(1, 12'h300 + 12'(4*k1)), 32'h0B00_0000 | k1, 4'hF);
        end
      end
    join
    // Same slave: interleaved reads, each master reads the other's data
    fork
      begin
        for (k0 = 0; k0 < 8; k0++) begin
          u_m0.read_reg(slv_addr(1, 12'h300 + 12'(4*k0)), r0);
          check_eq(r0, 32'h0B00_0000 | k0, $sformatf("M0 reads M1 word %0d", k0));
        end
      end
      begin
        for (k1 = 0; k1 < 8; k1++) begin
          u_m1.read_reg(slv_addr(1, 12'h200 + 12'(4*k1)), r1);
          check_eq(r1, 32'h0A00_0000 | k1, $sformatf("M1 reads M0 word %0d", k1));
        end
      end
    join
    // Different slaves in parallel: M0 -> Peripherals, M1 -> External
    fork
      begin
        for (k0 = 0; k0 < 4; k0++) begin
          u_m0.write_reg(slv_addr(2, 12'h400 + 12'(4*k0)), 32'h0C00_0000 | k0, 4'hF);
        end
      end
      begin
        for (k1 = 0; k1 < 4; k1++) begin
          u_m1.write_reg(slv_addr(3, 12'h400 + 12'(4*k1)), 32'h0D00_0000 | k1, 4'hF);
        end
      end
    join
    for (int k = 0; k < 4; k++) begin
      u_m1.read_reg(slv_addr(2, 12'h400 + 12'(4*k)), rdata);
      check_eq(rdata, 32'h0C00_0000 | k, $sformatf("S2 word %0d", k));
      u_m0.read_reg(slv_addr(3, 12'h400 + 12'(4*k)), rdata);
      check_eq(rdata, 32'h0D00_0000 | k, $sformatf("S3 word %0d", k));
    end
    test_done("test_contention");
  end
endtask
