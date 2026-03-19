// test_strobe.sv — Timer IP directed test: byte-enable / write-strobe.
//
// Verifies byte-enable (write strobe) behavior on the CTRL and LOAD registers.
// Each byte is written independently and the result is checked against the
// expected merge.
//
// CTRL register field map (bits [11:0] only; bits [31:12] always 0):
//   bit  0    : EN
//   bit  1    : MODE
//   bit  2    : INTR_EN
//   bit  3    : TRIG_EN
//   bits[11:4]: PRESCALE[7:0]
//
// Depends on: write_reg, read_reg (BFM), check_eq / test_start / test_done (timer_test_pkg.sv)

task automatic test_strobe;
  logic [31:0] rdata;
  begin
    test_start("test_strobe");

    // -----------------------------------------------------------------------
    // LOAD register — write each byte independently (fully RW, 32-bit)
    // -----------------------------------------------------------------------
    write_reg(12'h008, 32'h0000_0000, 4'hF);

    write_reg(12'h008, 32'hAA_BB_CC_11, 4'b0001);
    read_reg (12'h008, rdata);
    check_eq(rdata, 32'h0000_0011, "LOAD byte0 only");

    write_reg(12'h008, 32'hAA_BB_22_DD, 4'b0010);
    read_reg (12'h008, rdata);
    check_eq(rdata, 32'h0000_2211, "LOAD byte1 only");

    write_reg(12'h008, 32'hAA_33_CC_DD, 4'b0100);
    read_reg (12'h008, rdata);
    check_eq(rdata, 32'h0033_2211, "LOAD byte2 only");

    write_reg(12'h008, 32'h44_BB_CC_DD, 4'b1000);
    read_reg (12'h008, rdata);
    check_eq(rdata, 32'h4433_2211, "LOAD byte3 only");

    write_reg(12'h008, 32'h55_BB_66_CC, 4'b0101);
    read_reg (12'h008, rdata);
    check_eq(rdata, 32'h44BB_22CC, "LOAD bytes 0 and 2");

    write_reg(12'h008, 32'hFFFF_FFFF, 4'b0000);
    read_reg (12'h008, rdata);
    check_eq(rdata, 32'h44BB_22CC, "LOAD strobe=0 (no change)");

    write_reg(12'h008, 32'h0000_0000, 4'hF);

    // -----------------------------------------------------------------------
    // CTRL register — byte-enable behavior
    // Only bits [11:0] are implemented; bits [31:12] masked to 0.
    // -----------------------------------------------------------------------
    write_reg(12'h000, 32'h0000_0000, 4'hF);

    write_reg(12'h000, 32'h0000_0005, 4'b0001);
    read_reg (12'h000, rdata);
    check_eq(rdata, 32'h0000_0005, "CTRL byte0 (EN|INTR_EN)");

    write_reg(12'h000, 32'h0000_0A00, 4'b0010);
    read_reg (12'h000, rdata);
    check_eq(rdata, 32'h0000_0A05, "CTRL byte1 (PRESCALE[7:4]=0xA)");

    write_reg(12'h000, 32'hFFFF_FFFF, 4'b0000);
    read_reg (12'h000, rdata);
    check_eq(rdata, 32'h0000_0A05, "CTRL strobe=0 (no change)");

    write_reg(12'h000, 32'hFFFF_FFFF, 4'b1100);
    read_reg (12'h000, rdata);
    check_eq(rdata, 32'h0000_0A05, "CTRL bytes2/3 ignored");

    write_reg(12'h000, 32'h0000_0000, 4'hF);

    test_done("test_strobe");
    $display("test_strobe: PASS");
  end
endtask
