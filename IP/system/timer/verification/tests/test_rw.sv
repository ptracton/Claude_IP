// test_rw.sv — Timer IP directed test: register read/write verification.
//
// Writes non-zero values to each RW register (CTRL, LOAD), reads back and
// checks the value matches (with applicable field masks). Verifies COUNT is
// read-only (write is ignored).
//
// CTRL field mask: bits [11:0] only (reserved bits [31:12] always 0).
// STATUS: INTR is W1C and ACTIVE is RO; skip write-and-read-back.
//
// Depends on: read_reg, write_reg (BFM), check_eq / test_start / test_done (timer_test_pkg.sv)

task automatic test_rw;
  logic [31:0] rdata;
  logic [31:0] saved_count;
  begin
    test_start("test_rw");

    // --- CTRL (0x00) — only bits [11:0] are implemented ---
    write_reg(12'h000, 32'h0000_0F0F, 4'hF);
    read_reg (12'h000, rdata);
    check_eq(rdata, 32'h0000_0F0F, "CTRL read-back");

    write_reg(12'h000, 32'h0000_0000, 4'hF);
    read_reg (12'h000, rdata);
    check_eq(rdata, 32'h0000_0000, "CTRL clear");

    // --- LOAD (0x08) — fully RW ---
    write_reg(12'h008, 32'hDEAD_BEEF, 4'hF);
    read_reg (12'h008, rdata);
    check_eq(rdata, 32'hDEAD_BEEF, "LOAD read-back");

    write_reg(12'h008, 32'h0000_0010, 4'hF);
    read_reg (12'h008, rdata);
    check_eq(rdata, 32'h0000_0010, "LOAD second write");

    // --- COUNT (0x0C) — RO: write is ignored ---
    // Read baseline before write attempt; hardware may hold any value here.
    read_reg (12'h00C, saved_count);
    write_reg(12'h00C, 32'hFFFF_FFFF, 4'hF);   // should be a no-op
    read_reg (12'h00C, rdata);
    check_eq(rdata, saved_count, "COUNT is read-only");

    write_reg(12'h008, 32'h0000_0000, 4'hF);

    test_done("test_rw");
    $display("test_rw: PASS");
  end
endtask
