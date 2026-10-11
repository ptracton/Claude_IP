// test_contention.sv — Both masters run at the same time, first on the same
// slave (arbitration) and then on different slaves (parallel paths). Every
// transfer must complete with its own data.

task automatic test_contention;
  logic [31:0] rdata;
  begin
    test_start("test_contention");
    // Same slave (SRAM): interleaved writes
    fork
      begin
        for (int k = 0; k < 8; k++) begin
          u_m0.write_reg(slv_addr(1, 12'h200 + 12'(4*k)), 32'h0A00_0000 | k, 4'hF);
        end
      end
      begin
        for (int k = 0; k < 8; k++) begin
          u_m1.write_reg(slv_addr(1, 12'h300 + 12'(4*k)), 32'h0B00_0000 | k, 4'hF);
        end
      end
    join
    // Same slave: interleaved reads, each master reads the other's data
    fork
      begin
        logic [31:0] r;
        for (int k = 0; k < 8; k++) begin
          u_m0.read_reg(slv_addr(1, 12'h300 + 12'(4*k)), r);
          check_eq(r, 32'h0B00_0000 | k, $sformatf("M0 reads M1 word %0d", k));
        end
      end
      begin
        logic [31:0] r;
        for (int k = 0; k < 8; k++) begin
          u_m1.read_reg(slv_addr(1, 12'h200 + 12'(4*k)), r);
          check_eq(r, 32'h0A00_0000 | k, $sformatf("M1 reads M0 word %0d", k));
        end
      end
    join
    // Different slaves in parallel: M0 -> Peripherals, M1 -> External
    fork
      begin
        for (int k = 0; k < 4; k++) begin
          u_m0.write_reg(slv_addr(2, 12'h400 + 12'(4*k)), 32'h0C00_0000 | k, 4'hF);
        end
      end
      begin
        for (int k = 0; k < 4; k++) begin
          u_m1.write_reg(slv_addr(3, 12'h400 + 12'(4*k)), 32'h0D00_0000 | k, 4'hF);
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
