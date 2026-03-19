// test_reset.sv — Timer IP directed test: reset state verification.
//
// Verifies all registers return to their documented reset values after reset.
//
// Register reset values:
//   CTRL   @ 0x00 : 0x00000000
//   STATUS @ 0x04 : 0x00000000
//   LOAD   @ 0x08 : 0x00000000
//   COUNT  @ 0x0C : 0x00000000
//
// Depends on: read_reg (BFM), check_eq / test_start / test_done (timer_test_pkg.sv)

task automatic test_reset;
  logic [31:0] rdata;
  begin
    test_start("test_reset");

    read_reg(12'h000, rdata);
    check_eq(rdata, 32'h0000_0000, "CTRL reset value");

    read_reg(12'h004, rdata);
    check_eq(rdata, 32'h0000_0000, "STATUS reset value");

    read_reg(12'h008, rdata);
    check_eq(rdata, 32'h0000_0000, "LOAD reset value");

    read_reg(12'h00C, rdata);
    check_eq(rdata, 32'h0000_0000, "COUNT reset value");

    test_done("test_reset");
    $display("test_reset: PASS");
  end
endtask
