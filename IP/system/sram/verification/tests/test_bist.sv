// test_bist.sv — March C- BIST through the side-band.
//
// BIST instances: s32e (2 banks, ECC, RL2), s64 (ECC, RL2), dp1 (16/64 dual
// port, common clock), dp0 (32/8 dual port, port B on its own clock):
//   - bist_start_i -> bist_done_o with bist_fail_o low; the array is zero
//     afterwards (March C- ends with w0); busy_o high while it runs
//   - bus reads issued right after the start (both ports of a dual port)
//     stall until the test ends and return zero
//   - a domain asleep (LS / SD) is brought to RUN for the test and returns
//     to its requested mode afterwards (s32e)
//   - stuck-at-0 fault on stored bit 3 of one word: bist_fail_o and
//     bist_fail_addr_o name that word; without the fault the next run passes
// The test length (cycles) is reported.

task automatic run_bist(input int sb, output int unsigned cycles);
  int unsigned d0;
  d0 = n_bist_done[sb];
  sb_cyc(sb, 1);
  bist_start[sb] <= 1'b1;
  sb_cyc(sb, 1);
  bist_start[sb] <= 1'b0;
  cycles = 1;
  while (n_bist_done[sb] == d0) begin
    sb_cyc(sb, 1);
    if (++cycles > 400000) fail($sformatf("instance %0d: no bist_done_o", sb));
  end
endtask

task automatic test_bist();
  int          sl [4];
  int          s, sb, fa;
  int unsigned c, b0, cyc;
  logic [63:0] rd, rdb;
  logic        er, erb;
  sl = '{SL_S32E, SL_S64, SL_DP1A, SL_DP0A};
  test_start("test_bist");
  foreach (sl[n]) begin
    s  = sl[n];
    sb = slv[s].sb;
    for (int i = 0; i < slv[s].depth; i += 5) wr(s, i, rnd(s));
    b0 = n_busy[sb];
    // Start, then read from both ports while the test runs.
    sh_fill(sb, 0, st_bytes(sb), 8'h00);
    fork
      run_bist(sb, cyc);
      begin
        sb_cyc(sb, 3);
        rd_raw(s, 1, rd, er);
      end
      if (slv[s].peer >= 0) begin
        sb_cyc(sb, 3);
        rd_raw(slv[s].peer, 2, rdb, erb);
      end
    join
    chk(bist_fail[sb] === 1'b0, $sformatf("%s: BIST passes", slv[s].name));
    chk(er === 1'b0 && (rd & wmask(s)) == 0, $sformatf("%s: read during BIST waits, reads 0 (%h)",
                                                        slv[s].name, rd));
    if (slv[s].peer >= 0) begin
      chk(erb === 1'b0 && (rdb & wmask(slv[s].peer)) == 0,
          $sformatf("%s: port B read during BIST waits, reads 0", slv[s].name));
    end
    for (int i = 0; i < slv[s].depth; i += 9) rd_chk(s, i, 0, "after BIST");
    chk(n_busy[sb] - b0 >= cyc / 2, $sformatf("%s: busy_o during BIST", slv[s].name));
    row($sformatf("%-6s March C- passes in %0d cycles (D=%0d); array zero; reads stall",
                  slv[s].name, cyc, slv[s].depth));
    // Stuck-at-0 fault, at two words with alternating address bits (every
    // bit of bist_fail_addr_o changes both ways)
    for (int f = 0; f < 2; f++) begin
      fa = (f ? 32'h2AAA : 32'h1555) & (slv[s].depth - 1);
      bf_addr[sb] = fa;
      bf_on[sb]   = 1'b1;
      run_bist(sb, cyc);
      bf_on[sb]   = 1'b0;
      sb_cyc(sb, 2);
      chk(bist_fail[sb] === 1'b1, $sformatf("%s: stuck-at fault detected", slv[s].name));
      // bist_fail_addr_o is $clog2(DEPTH) bits (port A words)
      chk((bist_fail_addr[sb] & 16'((1 << $clog2(slv[s].depth)) - 1)) == 16'(fa),
          $sformatf("%s: failing word %0d (exp %0d)", slv[s].name,
                    bist_fail_addr[sb] & 16'((1 << $clog2(slv[s].depth)) - 1), fa));
    end
    run_bist(sb, cyc);
    chk(bist_fail[sb] === 1'b0, $sformatf("%s: passes again without the fault", slv[s].name));
    row($sformatf("%-6s stuck-at-0 bit 3 at words 0x%0h and 0x%0h: bist_fail_o, address right",
                  slv[s].name, 32'h1555 & (slv[s].depth - 1), 32'h2AAA & (slv[s].depth - 1)));
  end
  // Sleeping domains are brought to RUN for the test (s32e: d0 LS, d1 SD).
  s  = SL_S32E;
  sb = slv[s].sb;
  set_mode(sb, 0, LS);
  set_mode(sb, 1, SD);
  wait_mode(sb, 0, LS, c);
  wait_mode(sb, 1, SD, c);
  run_bist(sb, cyc);
  chk(bist_fail[sb] === 1'b0, "s32e: BIST with sleeping domains passes");
  wait_mode(sb, 0, LS, c);
  wait_mode(sb, 1, SD, c);
  set_mode(sb, 0, RUN);
  set_mode(sb, 1, RUN);
  wait_mode(sb, 0, RUN, c);
  wait_mode(sb, 1, RUN, c);
  sh_fill(sb, 0, st_bytes(sb), 8'h00);
  rd_chk(s, 3, 0, "after BIST in sleep");
  rd_chk(s, slv[s].depth - 3, 0, "after BIST in sleep");
  row("s32e   BIST with d0 in LS and d1 in SD: both woken, test passes, modes restored");
  // Instances without BIST ignore bist_start_i.
  for (int sbi = 0; sbi < NSB; sbi++) begin
    int unsigned d0, b0;
    s = a_slave[sbi];
    if (slv[s].bist) continue;
    d0 = n_bist_done[sbi];
    b0 = n_busy[sbi];
    wr(s, 2, rnd(s));
    sb_cyc(sbi, 1);
    bist_start[sbi] <= 1'b1;
    sb_cyc(sbi, 1);
    bist_start[sbi] <= 1'b0;
    sb_cyc(sbi, 10);
    chk(n_bist_done[sbi] == d0 && n_busy[sbi] == b0 && bist_fail[sbi] !== 1'b1,
        $sformatf("%s (BIST_EN = 0): bist_start_i ignored", slv[s].name));
    rd_chk(s, 2, 0, "BIST_EN = 0: contents kept");
  end
  row("BIST_EN = 0 instances: bist_start_i ignored, contents kept");
  test_done("test_bist");
endtask
