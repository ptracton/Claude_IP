// test_route.sv — Every master reaches every slave, and each slave only sees
// its own region: a value written through one master is read back through
// the other, and slaves do not alias each other.

task automatic test_route;
  logic [31:0] rdata;
  logic [31:0] d0, d1;
  begin
    test_start("test_route");
    // Distinct data per (master, slave)
    for (int j = 0; j < bus_matrix_pkg::BM_NUM_SLAVES; j++) begin
      d0 = 32'hA000_0000 | (j << 8) | 32'h10;
      d1 = 32'h5000_0000 | (j << 8) | 32'h20;
      u_m0.write_reg(slv_addr(j, 12'h010), d0, 4'hF);
      u_m1.write_reg(slv_addr(j, 12'h020), d1, 4'hF);
    end
    // Cross read-back
    for (int j = 0; j < bus_matrix_pkg::BM_NUM_SLAVES; j++) begin
      d0 = 32'hA000_0000 | (j << 8) | 32'h10;
      d1 = 32'h5000_0000 | (j << 8) | 32'h20;
      u_m1.read_reg(slv_addr(j, 12'h010), rdata);
      check_eq(rdata, d0, $sformatf("M0 write -> S%0d -> M1 read", j));
      u_m0.read_reg(slv_addr(j, 12'h020), rdata);
      check_eq(rdata, d1, $sformatf("M1 write -> S%0d -> M0 read", j));
    end
    // Highest offset inside each slave's 4 KB window
    for (int j = 0; j < bus_matrix_pkg::BM_NUM_SLAVES; j++) begin
      u_m0.write_reg(slv_addr(j, 12'hFFC), 32'hC0DE_0000 | j, 4'hF);
    end
    for (int j = 0; j < bus_matrix_pkg::BM_NUM_SLAVES; j++) begin
      u_m1.read_reg(slv_addr(j, 12'hFFC), rdata);
      check_eq(rdata, 32'hC0DE_0000 | j, $sformatf("S%0d offset 0xFFC", j));
    end
    test_done("test_route");
  end
endtask
