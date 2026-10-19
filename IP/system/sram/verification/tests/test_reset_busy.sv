// test_reset_busy.sv — Reset in the middle of operations.
//
// The whole system is reset (both clock domains) while:
//   R1  every BIST instance is in March element M0 (writing), every other
//       instance is running a clear, and every master has a read stalled
//       in its SRAM's bus adapter (waiting for the grant)
//   R2  every BIST instance is in a read element (twice, one cycle apart, so
//       both the read and the compare cycle are caught)
//   R3  every BIST instance waits for a deep-sleeping domain to wake
//   R4  a power domain is entering light sleep, R5 one is asleep
// After every reset: every domain acknowledges RUN, nothing is busy, and
// every port writes and reads back. Contents left by an interrupted engine
// are undefined, so every instance is cleared after each reset (which also
// checks a clear right after a reset) before the ports are exercised.

task automatic all_alive(input string what);
  for (int sbi = 0; sbi < NSB; sbi++) begin
    for (int d = 0; d < slv[a_slave[sbi]].npd; d++) begin
      chk(ack(sbi, d) === RUN, $sformatf("%s: %s domain %0d RUN", what, slv[a_slave[sbi]].name, d));
    end
    chk(busy[sbi] === 1'b0, $sformatf("%s: %s not busy", what, slv[a_slave[sbi]].name));
  end
  // An interrupted engine leaves undefined contents: clear every instance
  // (the reference model and the shadow then agree with the array again).
  for (int sbi = 0; sbi < NSB; sbi++) clr_req[sbi] <= 1'b1;
  cyc_a(1);
  cyc_b(1);
  for (int sbi = 0; sbi < NSB; sbi++) clr_req[sbi] <= 1'b0;
  cyc_a(2);
  for (int sbi = 0; sbi < NSB; sbi++) begin
    wait_idle(sbi);
    sh_fill(sbi, 0, st_bytes(sbi), 8'h00);
  end
  for (int s = 0; s < NSL; s++) begin
    if (!slv[s].ro) wr(s, 7, rnd(s));
    rd_chk(s, 7, 0, what);
  end
endtask

task automatic start_bists();
  for (int sbi = 0; sbi < NSB; sbi++) begin
    if (slv[a_slave[sbi]].bist) bist_start[sbi] <= 1'b1;
  end
  cyc_a(1);
  for (int sbi = 0; sbi < NSB; sbi++) bist_start[sbi] <= 1'b0;
endtask

task automatic test_reset_busy();
  int unsigned c;
  // One stalled read per master: masters 0..7 and a slave of theirs that
  // will be busy with BIST or a clear.
  int stall_sl [8];
  stall_sl = '{SL_S32E, SL_DP2B, SL_S8, SL_DP1A, SL_S24, SL_S64, SL_S32P, SL_S32Q};
  test_start("test_reset_busy");
  // ---- R1
  start_bists();
  for (int sbi = 0; sbi < NSB; sbi++) begin
    if (!slv[a_slave[sbi]].bist) clr_req[sbi] <= 1'b1;
  end
  cyc_a(1);
  cyc_b(1);
  for (int sbi = 0; sbi < NSB; sbi++) clr_req[sbi] <= 1'b0;
  cyc_a(3);
  fork
    for (int m = 0; m < 8; m++) begin
      automatic int mm = m;
      fork
        begin
          logic [63:0] rd;
          logic        er;
          xfer(stall_sl[mm], 1'b0, woff(stall_sl[mm], 9), fsz(stall_sl[mm]), '0, '0, rd, er);
        end
      join_none
    end
  join
  cyc_a(12);
  reset_all();
  wait fork;
  all_alive("reset during BIST M0 / clears / stalled reads");
  row("R1 reset during BIST writes, clears, and a stalled read in every adapter: recovers");
  // ---- R2: BIST read elements, two offsets
  for (int k = 0; k < 2; k++) begin
    start_bists();
    cyc_a(1100 + k);                             // past M0 of every instance (D <= 1024)
    reset_all();
    all_alive("reset during BIST reads");
  end
  row("R2 reset during BIST read/compare cycles (two offsets): recovers");
  // ---- R3: BIST waiting for a deep-sleeping domain
  for (int sbi = 0; sbi < NSB; sbi++) if (slv[a_slave[sbi]].bist) set_mode(sbi, 0, DS);
  for (int sbi = 0; sbi < NSB; sbi++) if (slv[a_slave[sbi]].bist) wait_mode(sbi, 0, DS, c);
  start_bists();
  cyc_a(2);
  reset_all();
  // The DS requests are still there after the reset: the domains go back to
  // DS, then wake when the requests drop.
  for (int sbi = 0; sbi < NSB; sbi++) set_mode_all(sbi, RUN);
  all_alive("reset while BIST waits for power");
  row("R3 reset while BIST waits for a deep-sleeping domain to wake: recovers");
  // ---- R4 / R5: power state machine entering, and asleep
  set_mode(SB_S32, 0, LS);
  set_mode(SB_S24B, 1, LS);
  wait_mode(SB_S24B, 1, LS, c);                  // s24b d1 asleep
  set_mode(SB_S32, 0, RUN);
  wait_mode(SB_S32, 0, RUN, c);
  set_mode(SB_S32, 0, LS);                       // s32 entering at the reset
  cyc_a(1);
  reset_all();
  for (int sbi = 0; sbi < NSB; sbi++) set_mode_all(sbi, RUN);
  all_alive("reset while entering / asleep");
  row("R4/R5 reset while a domain enters light sleep and while one sleeps: recovers");
  test_done("test_reset_busy");
endtask
