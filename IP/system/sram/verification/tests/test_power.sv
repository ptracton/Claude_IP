// test_power.sv — Power modes through the side-band, per power domain.
//
// Single-port SRAMs (s32, s8 on clk_b, s32e with 2 banks + ECC, s24b with 4
// banks, s64 ECC), every domain:
//   - LIGHT_SLEEP: pwr_mode_ack_o follows after the entry time; an access
//     wakes the domain automatically (wait states, data kept, OKAY) and the
//     domain goes back to sleep afterwards; a write while asleep works too
//   - DEEP_SLEEP: reads and writes get ERROR and change nothing; back in RUN
//     the contents are kept
//   - SHUTDOWN: ERROR while off; back in RUN the domain is cleared (zero)
//   - moves between sleep modes without RUN in between (LS -> DS -> SD -> LS)
//   - a request withdrawn while entering, and an access while entering
//   - busy_o high during the transitions
// Banked SRAMs: other domains keep working, with no wait states, while one
// domain sleeps; four domains in four different modes at once (s24b).
// PWR_GATE = 0 (s16w): requests are ignored, ack stays RUN, accesses work.
// Every other power-gated instance goes once through LS / DS / SD per domain.
// The dual ports' power behaviour (port B through the CDC) is in test_dp.

// First word of domain d, plus k.
function automatic int dom_word(input int s, input int d, input int k = 3);
  return d * (slv[s].depth / slv[s].npd) + k;
endfunction

task automatic test_power();
  int          sl [5];
  int          s, sb, idx, oth;
  int unsigned c, c_run, c_ls, b0;
  logic [63:0] v, rd;
  logic        er;
  sl = '{SL_S32, SL_S8, SL_S32E, SL_S24B, SL_S64};
  test_start("test_power");
  foreach (sl[n]) begin
    s  = sl[n];
    sb = slv[s].sb;
    for (int d = 0; d < slv[s].npd; d++) begin
      idx = dom_word(s, d);
      oth = dom_word(s, (d + 1) % slv[s].npd, 5);
      wr(s, idx, rnd(s));
      wr(s, oth, rnd(s));
      rd_chk(s, idx);
      c_run = m_cycles(slv[s].m);
      b0 = n_busy[sb];
      // ---- LIGHT_SLEEP
      set_mode(sb, d, LS);
      wait_mode(sb, d, LS, c);
      chk(c >= 1, $sformatf("%s d%0d: LS ack after the entry time (%0d cycles)", slv[s].name,
                            d, c));
      rd_chk(s, idx, 0, "LS read");
      c_ls = m_cycles(slv[s].m);
      chk(c_ls > c_run, $sformatf("%s d%0d: LS read has wake wait states (%0d vs %0d)",
                                  slv[s].name, d, c_ls, c_run));
      wait_mode(sb, d, LS, c);                     // back to sleep after the access
      wr(s, idx, rnd(s), '1, 0, "LS write");
      wait_mode(sb, d, LS, c);
      rd_chk(s, idx, 0, "after LS write");
      if (slv[s].npd > 1) begin
        wait_mode(sb, d, LS, c);
        rd_chk(s, oth, 0, "other domain");
        chk(m_cycles(slv[s].m) == c_run, $sformatf("%s: other domain has no wait states (%0d)",
                                                   slv[s].name, m_cycles(slv[s].m)));
      end
      chk(n_busy[sb] > b0, $sformatf("%s d%0d: busy_o during LS transitions", slv[s].name, d));
      // ---- DEEP_SLEEP: errors, contents kept
      set_mode(sb, d, DS);
      wait_mode(sb, d, DS, c);
      rd_chk(s, idx, 1, "DS read");
      wr(s, idx, rnd(s), '1, 1, "DS write");
      if (slv[s].npd > 1) rd_chk(s, oth, 0, "other domain during DS");
      set_mode(sb, d, RUN);
      wait_mode(sb, d, RUN, c);
      rd_chk(s, idx, 0, "after DS");
      // ---- SHUTDOWN: errors, cleared on wake
      set_mode(sb, d, SD);
      wait_mode(sb, d, SD, c);
      sh_forget_dom(sb, d);
      rd_chk(s, idx, 1, "SD read");
      set_mode(sb, d, RUN);
      wait_mode(sb, d, RUN, c);
      sh_fill_dom(sb, d, 8'h00);
      rd_chk(s, idx, 0, "after SD (cleared)");
      rd_chk(s, dom_word(s, d, 0), 0, "after SD (cleared)");
      rd_chk(s, dom_word(s, d, slv[s].depth / slv[s].npd - 1), 0, "after SD (cleared)");
      row($sformatf("%-6s domain %0d: LS auto-wake (%0d vs %0d cycles), DS kept, SD cleared",
                    slv[s].name, d, c_ls, c_run));
      // ---- sleep-to-sleep moves and a withdrawn request
      wr(s, idx, rnd(s));
      set_mode(sb, d, LS);
      wait_mode(sb, d, LS, c);
      set_mode(sb, d, DS);
      wait_mode(sb, d, DS, c);
      set_mode(sb, d, SD);
      wait_mode(sb, d, SD, c);
      sh_forget_dom(sb, d);
      set_mode(sb, d, LS);                         // SD -> (wake, clear) -> LS
      wait_mode(sb, d, RUN, c);
      sh_fill_dom(sb, d, 8'h00);
      wait_mode(sb, d, LS, c);
      set_mode(sb, d, RUN);
      wait_mode(sb, d, RUN, c);
      rd_chk(s, idx, 0, "after SD -> LS");
      wr(s, idx, rnd(s));
      set_mode(sb, d, LS);                         // withdrawn while entering
      sb_cyc(sb, 1);
      set_mode(sb, d, RUN);
      wait_mode(sb, d, RUN, c);
      sb_cyc(sb, 12);
      chk(ack(sb, d) === RUN, $sformatf("%s d%0d: withdrawn LS ends in RUN", slv[s].name, d));
      set_mode(sb, d, LS);                         // access while entering
      sb_cyc(sb, 1);
      rd_chk(s, idx, 0, "access while entering LS");
      set_mode(sb, d, RUN);
      wait_mode(sb, d, RUN, c);
      row($sformatf("%-6s domain %0d: LS->DS->SD->LS moves, withdrawn request, access while entering",
                    slv[s].name, d));
    end
  end
  // ---- every other power-gated instance, every domain: LS access, DS error,
  // SD cleared (port A; port B behaviour is in test_dp)
  for (int sbi = 0; sbi < NSB; sbi++) begin
    s = a_slave[sbi];
    if (!slv[s].pg || s inside {SL_S32, SL_S8, SL_S32E, SL_S24B, SL_S64}) continue;
    for (int d = 0; d < slv[s].npd; d++) begin
      idx = dom_word(s, d);
      wr(s, idx, rnd(s));
      set_mode(sbi, d, LS);
      wait_mode(sbi, d, LS, c);
      rd_chk(s, idx, 0, "LS (every instance)");
      set_mode(sbi, d, DS);
      wait_mode(sbi, d, DS, c);
      rd_chk(s, idx, 1, "DS (every instance)");
      set_mode(sbi, d, SD);
      wait_mode(sbi, d, SD, c);
      sh_forget_dom(sbi, d);
      set_mode(sbi, d, RUN);
      wait_mode(sbi, d, RUN, c);
      sh_fill_dom(sbi, d, 8'h00);
      rd_chk(s, idx, 0, "SD cleared (every instance)");
    end
    row($sformatf("%-6s LS access, DS error, SD cleared (%0d domain%s)", slv[s].name,
                  slv[s].npd, slv[s].npd > 1 ? "s" : ""));
  end
  // ---- four domains in four modes at once (s24b)
  s  = SL_S24B;
  sb = slv[s].sb;
  for (int d = 0; d < 4; d++) wr(s, dom_word(s, d), rnd(s));
  rd_chk(s, dom_word(s, 0));
  c_run = m_cycles(slv[s].m);
  set_mode(sb, 1, SD);
  set_mode(sb, 2, DS);
  set_mode(sb, 3, LS);
  wait_mode(sb, 1, SD, c);
  wait_mode(sb, 2, DS, c);
  wait_mode(sb, 3, LS, c);
  sh_forget_dom(sb, 1);
  rd_chk(s, dom_word(s, 0), 0, "d0 in RUN");
  chk(m_cycles(slv[s].m) == c_run, "s24b: RUN domain has no wait states");
  rd_chk(s, dom_word(s, 1), 1, "d1 in SD");
  rd_chk(s, dom_word(s, 2), 1, "d2 in DS");
  rd_chk(s, dom_word(s, 3), 0, "d3 in LS (wakes)");
  for (int d = 1; d < 4; d++) set_mode(sb, d, RUN);
  for (int d = 1; d < 4; d++) wait_mode(sb, d, RUN, c);
  sh_fill_dom(sb, 1, 8'h00);
  for (int d = 0; d < 4; d++) rd_chk(s, dom_word(s, d), 0, "four modes");
  row("s24b   four domains in RUN / SD / DS / LS at once; SD cleared, DS and LS kept");
  // ---- PWR_GATE = 0: requests ignored
  s  = SL_S16W;
  sb = slv[s].sb;
  wr(s, 9, rnd(s));
  for (int k = 1; k <= 3; k++) begin
    logic [1:0] m;
    m = 2'(k);                                     // LS, DS, SD
    set_mode(sb, 0, m);
    sb_cyc(sb, 20);
    chk(ack(sb, 0) === RUN, $sformatf("s16w (PWR_GATE=0): request %0d ignored, ack RUN", m));
    chk(busy[sb] === 1'b0, "s16w (PWR_GATE=0): not busy");
    rd_chk(s, 9, 0, "PWR_GATE=0");
  end
  set_mode(sb, 0, RUN);
  row("s16w   PWR_GATE = 0: every request ignored, ack stays RUN, accesses work");
  test_done("test_power");
endtask
