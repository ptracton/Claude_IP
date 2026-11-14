// test_ecc.sv — ECC controller: injection, correction, detection, RMW.
//
// Single-port ECC SRAMs (s32e 32-bit with 2 banks and RL2, s24, s64):
//   - ecc_inj_i 1-bit: the next write stores a word with one flipped bit;
//     reads return the right data with OKAY and pulse ecc_corr_o and
//     err_irq_o each time (a read does not scrub); a rewrite heals it
//   - ecc_inj_i 2-bit: reads answer ERROR and pulse ecc_uncorr_o and
//     err_irq_o; a full rewrite heals it
//   - read-modify-write (sub-word write): clean word (busy_o during the
//     write-back); single-error word (corrected, merged, healed: later reads
//     are clean); double-error word (ERROR, word left as it was, and the
//     armed injection is not used up)
//   - backdoor (GENERIC): every stored bit, data and check bits, flipped on
//     its own is corrected; every adjacent pair, and pairs far apart, are
//     detected
// Dual port dp0 (32-bit A, 8-bit B, 8-bit codewords, B on its own clock):
//   - an error injected through port A in codeword 0 is corrected / detected
//     when port B reads that narrow word; the other narrow words of the wide
//     word stay clean; port B's ECC pulses reach ecc_*_o (port A clock)
//   - a narrow-port write of the bad codeword heals it with no RMW
//   - an A write that does not store codeword 0 uses up the injection
//     without leaving an error; byte writes need no RMW (whole codewords)
// Every instance without ECC ignores ecc_inj_i.

// Counter deltas after a few cycles (pulses are registered).
task automatic ecc_deltas(input int sb, input int unsigned c0, input int unsigned u0,
                          input int unsigned i0, input int unsigned ec, input int unsigned eu,
                          input int unsigned ei, input string what);
  sb_cyc(sb, (sb == SB_DP0) ? 12 : 4);
  chk(n_corr[sb] - c0 == ec && n_uncorr[sb] - u0 == eu && n_irq[sb] - i0 == ei,
      $sformatf("%s: ecc_corr +%0d (exp %0d), ecc_uncorr +%0d (exp %0d), err_irq +%0d (exp %0d)",
                what, n_corr[sb] - c0, ec, n_uncorr[sb] - u0, eu, n_irq[sb] - i0, ei));
endtask

task automatic test_ecc();
  int          sl [3];
  int          s, sb, idx, idx2, mw, nflip;
  int unsigned c0, u0, i0, b0;
  logic [63:0] v, rd;
  logic        er;
  sl = '{SL_S32E, SL_S24, SL_S64};
  test_start("test_ecc");
  foreach (sl[n]) begin
    s    = sl[n];
    sb   = slv[s].sb;
    idx  = slv[s].depth / 2 + 5;   // in the upper bank of s32e
    idx2 = 7;
    // ---- injected single-bit error
    inject(sb, 2'b01);
    wr(s, idx, rnd(s));
    c0 = n_corr[sb]; u0 = n_uncorr[sb]; i0 = n_irq[sb];
    rd_chk(s, idx, 0, "1-bit");
    rd_chk(s, idx, 0, "1-bit again");
    ecc_deltas(sb, c0, u0, i0, 2, 0, 2, $sformatf("%s 1-bit x2 reads", slv[s].name));
    wr(s, idx, rnd(s));
    c0 = n_corr[sb]; u0 = n_uncorr[sb]; i0 = n_irq[sb];
    rd_chk(s, idx, 0, "healed");
    ecc_deltas(sb, c0, u0, i0, 0, 0, 0, $sformatf("%s rewritten", slv[s].name));
    row($sformatf("%-6s injected 1-bit error: corrected, ecc_corr_o/err_irq_o per read, healed",
                  slv[s].name));
    // ---- injected double-bit error
    inject(sb, 2'b10);
    wr(s, idx, rnd(s));
    c0 = n_corr[sb]; u0 = n_uncorr[sb]; i0 = n_irq[sb];
    rd_chk(s, idx, 1, "2-bit");
    ecc_deltas(sb, c0, u0, i0, 0, 1, 1, $sformatf("%s 2-bit read", slv[s].name));
    wr(s, idx, rnd(s));
    rd_chk(s, idx, 0, "2-bit healed");
    row($sformatf("%-6s injected 2-bit error: ERROR response, ecc_uncorr_o, healed by rewrite",
                  slv[s].name));
    // ---- read-modify-write on a clean word
    b0 = n_busy[sb];
    c0 = n_corr[sb]; u0 = n_uncorr[sb]; i0 = n_irq[sb];
    wr(s, idx, rnd(s), 8'b0000_0010, 0, "rmw clean");
    wr(s, idx, rnd(s), 8'b0000_0101, 0, "rmw clean");
    rd_chk(s, idx, 0, "rmw clean");
    ecc_deltas(sb, c0, u0, i0, 0, 0, 0, $sformatf("%s clean RMW", slv[s].name));
    chk(n_busy[sb] - b0 >= 2, $sformatf("%s busy_o during RMW (%0d cycles)", slv[s].name,
                                        n_busy[sb] - b0));
    row($sformatf("%-6s RMW (byte / sparse strobes) on a clean word, busy_o %0d cycles",
                  slv[s].name, n_busy[sb] - b0));
    // ---- RMW on a single-error word
    inject(sb, 2'b01);
    wr(s, idx, rnd(s));
    c0 = n_corr[sb]; u0 = n_uncorr[sb]; i0 = n_irq[sb];
    wr(s, idx, rnd(s), 8'b0000_0001, 0, "rmw 1-bit");
    ecc_deltas(sb, c0, u0, i0, 1, 0, 1, $sformatf("%s RMW of a 1-bit word", slv[s].name));
    c0 = n_corr[sb]; u0 = n_uncorr[sb]; i0 = n_irq[sb];
    rd_chk(s, idx, 0, "rmw 1-bit healed");
    ecc_deltas(sb, c0, u0, i0, 0, 0, 0, $sformatf("%s after RMW", slv[s].name));
    row($sformatf("%-6s RMW of a 1-bit-error word: corrected, merged, written back clean",
                  slv[s].name));
    // ---- RMW on a double-error word; the armed injection survives it
    inject(sb, 2'b10);
    wr(s, idx, rnd(s));
    inject(sb, 2'b01);
    c0 = n_corr[sb]; u0 = n_uncorr[sb]; i0 = n_irq[sb];
    wr(s, idx, rnd(s), 8'b0000_0010, 1, "rmw 2-bit");
    ecc_deltas(sb, c0, u0, i0, 0, 1, 1, $sformatf("%s RMW of a 2-bit word", slv[s].name));
    rd_chk(s, idx, 1, "rmw 2-bit unchanged");
    wr(s, idx2, rnd(s));              // takes the injection armed before the failed RMW
    c0 = n_corr[sb]; u0 = n_uncorr[sb]; i0 = n_irq[sb];
    rd_chk(s, idx2, 0, "injection kept");
    ecc_deltas(sb, c0, u0, i0, 1, 0, 1, $sformatf("%s injection kept", slv[s].name));
    wr(s, idx, rnd(s));
    wr(s, idx2, rnd(s));
    rd_chk(s, idx, 0, "healed");
    row($sformatf("%-6s RMW of a 2-bit word: ERROR, unchanged, armed injection not used up",
                  slv[s].name));
    // ---- backdoor: every stored bit (GENERIC, simulators with VPI / VHPI)
    if (TECH == 0 && !BD_OK) begin
      row($sformatf("%-6s backdoor bit flips SKIPPED (no VPI/VHPI backdoor on this simulator)",
                    slv[s].name));
    end
    if (TECH == 0 && BD_OK) begin
      wr(s, idx, rnd(s));
      bd_flip(sb, idx, 0, mw);
      bd_flip(sb, idx, 0, mw);
      nflip = 0;
      for (int k = 0; k < mw; k++) begin
        bd_flip(sb, idx, k, mw);
        mdl_fault(sb, idx, 2'd1);
        c0 = n_corr[sb]; u0 = n_uncorr[sb]; i0 = n_irq[sb];
        rd_chk(s, idx, 0, $sformatf("backdoor bit %0d", k));
        ecc_deltas(sb, c0, u0, i0, 1, 0, 1, $sformatf("%s backdoor bit %0d", slv[s].name, k));
        bd_flip(sb, idx, k, mw);
        mdl_fault(sb, idx, 2'd0);
        nflip++;
      end
      row($sformatf("%-6s backdoor: each of the %0d stored bits flipped alone is corrected",
                    slv[s].name, mw));
      for (int k = 0; k < mw; k++) begin
        for (int j = 0; j < 2; j++) begin
          int k2;
          k2 = j ? (k + mw / 2) % mw : (k + 1) % mw;
          bd_flip(sb, idx, k, mw);
          bd_flip(sb, idx, k2, mw);
          mdl_fault(sb, idx, 2'd2);
          c0 = n_corr[sb]; u0 = n_uncorr[sb]; i0 = n_irq[sb];
          rd_chk(s, idx, 1, $sformatf("backdoor bits %0d,%0d", k, k2));
          ecc_deltas(sb, c0, u0, i0, 0, 1, 1, $sformatf("%s backdoor bits %0d,%0d",
                                                        slv[s].name, k, k2));
          bd_flip(sb, idx, k, mw);
          bd_flip(sb, idx, k2, mw);
          mdl_fault(sb, idx, 2'd0);
        end
      end
      rd_chk(s, idx, 0, "backdoor restored");
      row($sformatf("%-6s backdoor: %0d double-bit patterns (adjacent and far) detected",
                    slv[s].name, 2 * mw));
    end
  end
  // ---- dual port dp0
  sb  = SB_DP0;
  idx = 40;                           // wide word; narrow words 160..163
  inject(sb, 2'b01);
  wr(SL_DP0A, idx, rnd(SL_DP0A));
  c0 = n_corr[sb]; u0 = n_uncorr[sb]; i0 = n_irq[sb];
  rd_chk(SL_DP0B, 4 * idx, 0, "dp0 B 1-bit");
  ecc_deltas(sb, c0, u0, i0, 1, 0, 1, "dp0 B read of the 1-bit codeword");
  c0 = n_corr[sb]; u0 = n_uncorr[sb]; i0 = n_irq[sb];
  rd_chk(SL_DP0B, 4 * idx + 1, 0, "dp0 B clean codeword");
  rd_chk(SL_DP0B, 4 * idx + 3, 0, "dp0 B clean codeword");
  ecc_deltas(sb, c0, u0, i0, 0, 0, 0, "dp0 B reads of clean codewords");
  rd_chk(SL_DP0A, idx, 0, "dp0 A 1-bit");
  ecc_deltas(sb, c0, u0, i0, 1, 0, 1, "dp0 A read of the word");
  row("dp0    1-bit error injected via A: corrected on B (codeword 0 only) and on A");
  inject(sb, 2'b10);
  wr(SL_DP0A, idx, rnd(SL_DP0A));
  c0 = n_corr[sb]; u0 = n_uncorr[sb]; i0 = n_irq[sb];
  rd_chk(SL_DP0B, 4 * idx, 1, "dp0 B 2-bit");
  rd_chk(SL_DP0B, 4 * idx + 2, 0, "dp0 B other codeword");
  rd_chk(SL_DP0A, idx, 1, "dp0 A 2-bit");
  ecc_deltas(sb, c0, u0, i0, 0, 2, 2, "dp0 2-bit reads (B, A)");
  if (!slv[SL_DP0B].ro) begin
    b0 = n_busy[sb];
    wr(SL_DP0B, 4 * idx, rnd(SL_DP0B), 8'h01, 0, "dp0 B heal");
  end else begin
    wr(SL_DP0A, idx, rnd(SL_DP0A), 8'h01, 0, "dp0 A heal");
  end
  rd_chk(SL_DP0A, idx, 0, "dp0 healed");
  row($sformatf("dp0    2-bit error: ERROR on B and A, other codewords clean; healed by a %s write",
                slv[SL_DP0B].ro ? "port-A byte" : "port-B"));
  inject(sb, 2'b10);
  b0 = n_busy[sb];
  wr(SL_DP0A, idx, rnd(SL_DP0A), 8'b1000, 0, "dp0 lane 3");
  wr(SL_DP0A, idx + 1, rnd(SL_DP0A));
  c0 = n_corr[sb]; u0 = n_uncorr[sb]; i0 = n_irq[sb];
  rd_chk(SL_DP0A, idx, 0, "dp0 consumed");
  rd_chk(SL_DP0A, idx + 1, 0, "dp0 consumed");
  ecc_deltas(sb, c0, u0, i0, 0, 0, 0, "dp0 injection used up by a lane-3 write");
  chk(n_busy[sb] == b0, "dp0 byte writes need no RMW");
  row("dp0    injection taken by a write not storing codeword 0: no error; no RMW");
  // ---- dp2 (32/32, common clock, 2 banks) through port A
  sb = SB_DP2;
  for (int k = 1; k <= 2; k++) begin
    idx = 10 + (k - 1) * 128;                    // one word per bank
    inject(sb, 2'(k));
    wr(SL_DP2A, idx, rnd(SL_DP2A));
    c0 = n_corr[sb]; u0 = n_uncorr[sb]; i0 = n_irq[sb];
    rd_chk(SL_DP2A, idx, k == 2, "dp2 A injected");
    rd_chk(SL_DP2B, idx, k == 2, "dp2 B injected");
    ecc_deltas(sb, c0, u0, i0, (k == 1) ? 2 : 0, (k == 2) ? 2 : 0, 2,
               $sformatf("dp2 %0d-bit error read on A and B", k));
    wr(SL_DP2A, idx, rnd(SL_DP2A), 8'b0010, k == 2, "dp2 A RMW");
    wr(SL_DP2A, idx, rnd(SL_DP2A));
    rd_chk(SL_DP2B, idx, 0, "dp2 healed");
  end
  row("dp2    1-bit / 2-bit errors via port A: seen on both ports; A RMW corrects / refuses");
  // ---- ECC_EN = 0: ecc_inj_i is ignored
  for (int sbi = 0; sbi < NSB; sbi++) begin
    s = a_slave[sbi];
    if (slv[s].ecc) continue;
    c0 = n_corr[sbi]; u0 = n_uncorr[sbi]; i0 = n_irq[sbi];
    inject(sbi, 2'b01);
    wr(s, 4, rnd(s));
    inject(sbi, 2'b10);
    wr(s, 5, rnd(s));
    inject(sbi, 2'b11);
    rd_chk(s, 4, 0, "no ECC: injection ignored");
    rd_chk(s, 5, 0, "no ECC: injection ignored");
    ecc_deltas(sbi, c0, u0, i0, 0, 0, 0, $sformatf("%s (ECC_EN = 0)", slv[s].name));
  end
  row("ECC_EN = 0 instances: ecc_inj_i ignored, no ECC pulses");
  test_done("test_ecc");
endtask
