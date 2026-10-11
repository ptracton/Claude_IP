// test_reset.sv — After reset every slave is reachable from both masters and
// returns its reset contents with an OKAY response.

task automatic test_reset;
  logic [31:0] rdata;
  begin
    test_start("test_reset");
    for (int j = 0; j < bus_matrix_pkg::BM_NUM_SLAVES; j++) begin
      u_m0.read_reg(slv_addr(j, 12'h000), rdata);
      check_eq(rdata, 32'h0000_0000, $sformatf("M0 read S%0d after reset", j));
      check_eq({31'h0, u_m0.bfm_err}, 32'h0, $sformatf("M0 S%0d response OKAY", j));
      u_m1.read_reg(slv_addr(j, 12'h004), rdata);
      check_eq(rdata, 32'h0000_0000, $sformatf("M1 read S%0d after reset", j));
      check_eq({31'h0, u_m1.bfm_err}, 32'h0, $sformatf("M1 S%0d response OKAY", j));
    end
    test_done("test_reset");
  end
endtask
