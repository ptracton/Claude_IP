// test_burst.sv — AHB bursts on every slave port.
//
// Through the bus_matrix (each beat becomes a single transfer at the SRAM)
// and on the two directly attached SRAMs (beats pipelined into the SRAM's
// AHB adapter):
//   - INCR4 / INCR8 / INCR16 and undefined-length INCR (5 and 13 beats),
//     full-word size, written then read back with a different burst type
//   - WRAP4 / WRAP8 / WRAP16 starting in the middle of the wrap block
//   - BUSY cycles inside write and read bursts
//   - byte-size INCR8 bursts on buses wider than 8 bits (sub-word beats;
//     a read-modify-write per beat on ECC ports)
// Bursts never cross a 1 KB boundary (AHB rule). The cycle count of an
// INCR16 write and read is reported for every port.
// APB / AXI4-Lite / Wishbone have no bursts: the same address sequences run
// as back-to-back single transfers, and BUSY becomes idle cycles.

task automatic test_burst();
  logic [2:0]  kinds [7];
  int          beats [7];
  int unsigned c, cw, cr;
  int          s, off, span;
  kinds = '{B_INCR4, B_INCR8, B_INCR16, B_WRAP4, B_WRAP8, B_WRAP16, B_INCR};
  beats = '{4, 8, 16, 4, 8, 16, 13};
  test_start("test_burst");
  for (s = 0; s < NSL; s++) begin
    if (slv[s].ro) begin
      burst(s, 1'b0, 0, fsz(s), B_INCR8, 8, '0, "ro burst", c);
      row($sformatf("%-6s read-only: INCR8 read burst", slv[s].name));
      continue;
    end
    for (int k = 0; k < 7; k++) begin
      span = beats[k] << offw(s);
      // Start 1 KB-aligned region chosen inside the array, plus a mid-block
      // start for WRAP bursts.
      off = ((woff(s, slv[s].depth / 4) + 1023) & ~1023) % (woff(s, slv[s].depth) - span + 1);
      off = off & ~(span - 1);
      if (kinds[k] inside {B_WRAP4, B_WRAP8, B_WRAP16}) off += span / 2 + (1 << offw(s));
      if (!slv[s].be) begin
        // BYTE_EN = 0: full-word beats only.
      end
      burst(s, 1'b1, off, fsz(s), kinds[k], beats[k], '0, "burst write", cw);
      burst(s, 1'b0, off, fsz(s), kinds[k], beats[k], '0, "burst read", cr);
      if (kinds[k] == B_INCR16) begin
        row($sformatf("%-6s 16 beats: write %0d cycles, read %0d cycles (%s)", slv[s].name, cw, cr,
                      slv[s].m >= 6 ? "direct" : "through bus_matrix"));
      end
    end
    row($sformatf("%-6s INCR4/8/16, INCR x13, WRAP4/8/16 (mid-block start)%s", slv[s].name,
                  IS_AHB ? "" : " address sequences"));
    // BUSY cycles before beats 1, 2 and 5.
    off = woff(s, 8);
    burst(s, 1'b1, off, fsz(s), B_INCR8, 8, 64'b100110, "busy write", c);
    burst(s, 1'b0, off, fsz(s), B_INCR8, 8, 64'b100110, "busy read", c);
    burst(s, 1'b1, off + (1 << offw(s)), fsz(s), B_WRAP4, 4, 64'b0110, "busy wrap write", c);
    burst(s, 1'b0, off, fsz(s), B_INCR, 8, 64'b11111110, "busy read", c);
    row($sformatf("%-6s %s inside INCR8 / WRAP4 / INCR bursts", slv[s].name,
                  IS_AHB ? "BUSY cycles" : "idle cycles"));
    // Byte-size bursts.
    if (nb(s) > 1) begin
      off = woff(s, 32) + 1;
      burst(s, 1'b1, off, 3'd0, B_INCR8, 8, '0, "byte burst", c);
      burst(s, 1'b0, off - 1, fsz(s), B_INCR4, 4, '0, "byte burst check", c);
      burst(s, 1'b0, off, 3'd0, B_INCR8, 8, '0, "byte burst read", c);
      row($sformatf("%-6s byte-size INCR8 burst%s", slv[s].name,
                    !slv[s].be ? (slv[s].pwe ? " (every beat ERROR)" : " (full-word writes)") :
                    (slv[s].ecc && cw_bytes(s) > 1) ? " (RMW per beat)" : ""));
    end
  end
  test_done("test_burst");
endtask
