// test_decode_err.sv — Addresses outside the map get an error response from
// the matrix itself (no slave is accessed), and normal traffic continues.

task automatic test_decode_err;
  logic [31:0] rdata;
  begin
    test_start("test_decode_err");
    for (int k = 0; k < 4; k++) begin
      u_m0.write_reg(UNMAPPED_ADDR[k], 32'hBAD0_0000 | k, 4'hF);
      check_eq({31'h0, u_m0.bfm_err}, 32'h1, $sformatf("M0 write 0x%08h -> error", UNMAPPED_ADDR[k]));
      u_m1.read_reg(UNMAPPED_ADDR[k], rdata);
      check_eq({31'h0, u_m1.bfm_err}, 32'h1, $sformatf("M1 read  0x%08h -> error", UNMAPPED_ADDR[k]));
    end
    // Back-to-back errors, then a good access on the same master
    u_m0.read_reg(UNMAPPED_ADDR[0], rdata);
    u_m0.read_reg(UNMAPPED_ADDR[3], rdata);
    check_eq({31'h0, u_m0.bfm_err}, 32'h1, "second consecutive error");
    u_m0.write_reg(slv_addr(2, 12'h040), 32'h600D_600D, 4'hF);
    check_eq({31'h0, u_m0.bfm_err}, 32'h0, "good write after errors");
    u_m0.read_reg(slv_addr(2, 12'h040), rdata);
    check_eq(rdata, 32'h600D_600D, "good read after errors");
    check_eq({31'h0, u_m0.bfm_err}, 32'h0, "good read response OKAY");
    // The rejected write to the gap must not have reached any slave
    for (int j = 0; j < bus_matrix_pkg::BM_NUM_SLAVES; j++) begin
      u_m1.read_reg(slv_addr(j, 12'h000), rdata);
      check_eq(rdata, 32'h0000_0000, $sformatf("S%0d untouched by errors", j));
    end
    test_done("test_decode_err");
  end
endtask
