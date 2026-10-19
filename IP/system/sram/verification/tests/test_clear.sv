// test_clear.sv — Clear engine (clr_req_i / clr_done_o).
//
//   - every word is zero after clr_done_o (s32, ECC s32e and s64, PWR_GATE = 0
//     s16w, dual port dp2 through both ports)
//   - a bus read issued right after clr_req_i stalls until the pass ends and
//     returns zero; busy_o is high during the pass
//   - banked s24b with domains in RUN / LS / DS / SD: RUN domains and the LS
//     domain (woken for the pass) are cleared, the DS domain is skipped (kept),
//     the SD domain was already lost
//   - a second request during a pass joins it; a later one runs a new pass
//   - the pass length is reported

task automatic clear_and_read(input int s, input string what);
  int          sb;
  int unsigned d0, b0;
  logic [63:0] rd;
  logic        er;
  sb = slv[s].sb;
  d0 = n_clr_done[sb];
  b0 = n_busy[sb];
  sb_cyc(sb, 1);
  clr_req[sb] <= 1'b1;
  sb_cyc(sb, 1);
  clr_req[sb] <= 1'b0;
  // Domains requested RUN / LS are cleared (all of them here).
  for (int d = 0; d < slv[s].npd; d++) begin
    if (!slv[s].pg || pwr_req[sb][2*d +: 2] inside {RUN, LS}) sh_fill_dom(sb, d, 8'h00);
  end
  rd_raw(s, 3, rd, er);                       // stalls until the pass ends
  chk(n_clr_done[sb] > d0, $sformatf("%s: read waited for clr_done_o", what));
  chk(er === 1'b0, $sformatf("%s: read after clear OKAY", what));
  cmp_lanes(s, 3, rd, all_lanes(s), what);
  chk(n_busy[sb] - b0 >= slv[s].depth, $sformatf("%s: busy_o during the pass (%0d cycles)",
                                                  what, n_busy[sb] - b0));
endtask

task automatic test_clear();
  int          sl [5];
  int          s, sb;
  int unsigned c, d0, t0;
  sl = '{SL_S32, SL_S32E, SL_S64, SL_S16W, SL_DP2A};
  test_start("test_clear");
  foreach (sl[n]) begin
    s  = sl[n];
    sb = slv[s].sb;
    for (int i = 0; i < slv[s].depth; i += 7) wr(s, i, rnd(s));
    wr(s, slv[s].depth - 1, rnd(s));
    t0 = n_busy[sb];
    clear_and_read(s, slv[s].name);
    for (int i = 0; i < slv[s].depth; i += 7) rd_chk(s, i, 0, "cleared");
    rd_chk(s, slv[s].depth - 1, 0, "cleared");
    if (slv[s].peer >= 0) begin
      for (int i = 0; i < slv[slv[s].peer].depth; i += 13) rd_chk(slv[s].peer, i, 0, "cleared B");
    end
    row($sformatf("%-6s clear: all zero, read stalled until clr_done_o, busy_o %0d cycles",
                  slv[s].name, n_busy[sb] - t0));
  end
  // Every other instance
  for (int sbi = 0; sbi < NSB; sbi++) begin
    s = a_slave[sbi];
    if (s inside {SL_S32, SL_S32E, SL_S64, SL_S16W, SL_DP2A}) continue;
    wr(s, 3, rnd(s));
    wr(s, slv[s].depth - 1, rnd(s));
    clear_and_read(s, slv[s].name);
    rd_chk(s, slv[s].depth - 1, 0, "cleared");
    row($sformatf("%-6s clear: zero, read stalled until clr_done_o", slv[s].name));
  end
  // Banked: modes per domain
  s  = SL_S24B;
  sb = slv[s].sb;
  for (int d = 0; d < 4; d++) wr(s, dom_word(s, d), rnd(s));
  set_mode(sb, 1, SD);
  set_mode(sb, 2, DS);
  set_mode(sb, 3, LS);
  wait_mode(sb, 1, SD, c);
  wait_mode(sb, 2, DS, c);
  wait_mode(sb, 3, LS, c);
  sh_fill_dom(sb, 1, 8'hxx);
  clear_and_read(s, "s24b modes");
  for (int d = 1; d < 4; d++) set_mode(sb, d, RUN);
  for (int d = 1; d < 4; d++) wait_mode(sb, d, RUN, c);
  sh_fill_dom(sb, 1, 8'h00);
  for (int d = 0; d < 4; d++) rd_chk(s, dom_word(s, d), 0, "after banked clear");
  row("s24b   clear with domains RUN/SD/DS/LS: RUN and LS cleared, DS kept, SD lost");
  // A second request during a pass joins it (the bus is stalled, so nothing
  // can be written in between and the array ends zero either way); one
  // after the pass ends starts another pass.
  s  = SL_S32;
  sb = slv[s].sb;
  wr(s, 11, rnd(s));
  d0 = n_clr_done[sb];
  sb_cyc(sb, 1);
  clr_req[sb] <= 1'b1;
  sb_cyc(sb, 1);
  clr_req[sb] <= 1'b0;
  sb_cyc(sb, 5);
  clr_req[sb] <= 1'b1;
  sb_cyc(sb, 1);
  clr_req[sb] <= 1'b0;
  sh_fill(sb, 0, st_bytes(sb), 8'h00);
  wait_idle(sb);
  sb_cyc(sb, 4);
  chk(n_clr_done[sb] - d0 == 1, $sformatf("s32: request during a pass joins it (%0d passes)",
                                          n_clr_done[sb] - d0));
  rd_chk(s, 11, 0, "joined clear");
  wr(s, 11, rnd(s));
  clear_and_read(s, "clear after a pass");
  chk(n_clr_done[sb] - d0 == 2, "s32: request after the pass starts a new pass");
  row("s32    clr_req_i during a pass joins it; a later request runs a new pass");
  test_done("test_clear");
endtask
