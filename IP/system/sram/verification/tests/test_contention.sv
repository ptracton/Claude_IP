// test_contention.sv — Two masters on one matrix (X32: CPU u_m0, DMA u_m1).
//
//   - both masters burst into the same SRAM at once (different words), then
//     each reads back the other's words
//   - both write different byte lanes of the same words at once
//   - each master works on a different SRAM at the same time (s32 / s32e)
// Round-robin arbitration interleaves the beats; the shadow and the
// reference models check every word.

task automatic two_masters(input int sa, input int sb2, input int base_a, input int base_b,
                           input string what);
  int unsigned c0, c1;
  fork
    begin
      // u_m0 (slave sa)
      for (int i = 0; i < 4; i++) burst(sa, 1'b1, base_a + 64 * i, 3'd2, B_INCR16, 16, '0, what, c0);
    end
    begin
      // u_m1, the DMA master
      for (int i = 0; i < 4; i++) burst(sb2, 1'b1, base_b + 64 * i, 3'd2, B_INCR16, 16, '0, what,
                                        c1, 1);
    end
  join
endtask

task automatic test_contention();
  int unsigned c;
  logic [63:0] v;
  test_start("test_contention");
  // Same SRAM, different words; then cross-read with the other master.
  two_masters(SL_S32, SL_S32, 'h400, 'h800, "same sram");
  for (int i = 0; i < 4; i++) burst(SL_S32, 1'b0, 'h800 + 64 * i, 3'd2, B_INCR16, 16, '0, "cross", c);
  for (int i = 0; i < 4; i++) burst(SL_S32, 1'b0, 'h400 + 64 * i, 3'd2, B_INCR16, 16, '0, "cross",
                                    c, 1);
  row("CPU and DMA burst into s32 together, each reads the other's words");
  // Different lanes of the same words.
  for (int i = 0; i < 16; i++) wr(SL_S32, 32 + i, 64'h0);
  fork
    for (int i = 0; i < 16; i++) wr(SL_S32, 32 + i, 64'hA5A5_0000 | i, 8'b1100);
    for (int i = 0; i < 16; i++) wr(SL_S32, 32 + i, 64'h0000_5A00 | i, 8'b0011, 0, "lanes", 1);
  join
  for (int i = 0; i < 16; i++) rd_chk(SL_S32, 32 + i, 0, "lanes");
  row("CPU writes upper halves, DMA lower halves of the same 16 words at once");
  // Different SRAMs at the same time.
  two_masters(SL_S32, SL_S32E, 'h000, 'h000, "two srams");
  for (int i = 0; i < 4; i++) begin
    burst(SL_S32, 1'b0, 64 * i, 3'd2, B_INCR16, 16, '0, "two srams", c);
    burst(SL_S32E, 1'b0, 64 * i, 3'd2, B_INCR16, 16, '0, "two srams", c);
  end
  row("CPU on s32 while DMA on s32e");
  test_done("test_contention");
endtask
