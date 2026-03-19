// test_back2back.sv — Timer IP directed test: back-to-back transactions.
//
// Issues consecutive write and read transactions with no idle cycles between
// them, verifying that the bus interface and register file handle pipelined
// access correctly.
//
// Note: burst_write/burst_read are NOT used here because Icarus Verilog does
// not support subroutine ports with unpacked array dimensions.
//
// Depends on: write_reg, read_reg (BFM), check_eq / test_start / test_done (timer_test_pkg.sv)

task automatic test_back2back;
  logic [31:0] rdata0, rdata1, rdata2, rdata3;
  logic [31:0] saved_count;
  begin
    test_start("test_back2back");

    // --- Back-to-back writes to CTRL then LOAD (no idle cycles) ---
    write_reg(12'h000, 32'h0000_0030, 4'hF); // CTRL: PRESCALE=3
    write_reg(12'h008, 32'h0000_00FF, 4'hF); // LOAD: value=255

    read_reg(12'h000, rdata0);
    check_eq(rdata0, 32'h0000_0030, "CTRL after back-to-back write");
    read_reg(12'h008, rdata0);
    check_eq(rdata0, 32'h0000_00FF, "LOAD after back-to-back write");

    // Read COUNT baseline before write attempt — timer is disabled so
    // COUNT is frozen; hardware may hold any value here.
    read_reg(12'h00C, saved_count);

    // --- Sequential write all 4 addresses ---
    write_reg(12'h000, 32'h0000_0020, 4'hF); // CTRL
    write_reg(12'h004, 32'h0000_0020, 4'hF); // STATUS: W1C fields, harmless
    write_reg(12'h008, 32'hCAFE_CAFE, 4'hF); // LOAD
    write_reg(12'h00C, 32'hBEEF_BEEF, 4'hF); // COUNT: RO, write ignored

    read_reg(12'h000, rdata0);
    check_eq(rdata0, 32'h0000_0020, "CTRL after seq write");
    read_reg(12'h004, rdata1);
    check_eq(rdata1, 32'h0000_0000, "STATUS unaffected");
    read_reg(12'h008, rdata2);
    check_eq(rdata2, 32'hCAFE_CAFE, "LOAD after seq write");
    read_reg(12'h00C, rdata3);
    check_eq(rdata3, saved_count, "COUNT RO");

    // --- Sequential read all 4 registers back-to-back ---
    read_reg(12'h000, rdata0);
    read_reg(12'h004, rdata1);
    read_reg(12'h008, rdata2);
    read_reg(12'h00C, rdata3);
    check_eq(rdata0, 32'h0000_0020, "seq_read CTRL");
    check_eq(rdata1, 32'h0000_0000, "seq_read STATUS");
    check_eq(rdata2, 32'hCAFE_CAFE, "seq_read LOAD");
    check_eq(rdata3, saved_count, "seq_read COUNT");

    write_reg(12'h000, 32'h0000_0000, 4'hF);
    write_reg(12'h008, 32'h0000_0000, 4'hF);

    test_done("test_back2back");
    $display("test_back2back: PASS");
  end
endtask
