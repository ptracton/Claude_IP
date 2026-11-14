// test_dp.sv — Dual ports: different settings on A and B.
//
//   dp0  A 32-bit ECC (8-bit codewords) on clk_a, B 8-bit on clk_b (own clock)
//   dp1  A 16-bit, B 64-bit BYTE_EN = 0 RL2, one clock
//   dp2  A 32-bit RL2, B 32-bit, ECC with byte enables on both, 2 banks, one clock
//
//   - width conversion both ways: words written on one port read back on the
//     other with little-endian packing (narrow word j = bits (j % R) of wide
//     word j / R)
//   - both ports busy at once on different words (dp0 with two clocks, dp2
//     with the CPU on A and the DMA on B)
//   - same-word races with one clock (dp1, dp2): writes from both ports to
//     the same word in the same cycle, write against read, and ECC read-
//     modify-writes from both ports (dp2). The bench accepts either order;
//     the reference model, which sees the grant order, checks the exact
//     result, and the same-word holds are counted
//   - port B under port A's side-band: DS -> B gets ERROR, LS -> a B access
//     wakes the domain (through the CDC on dp0), SD -> cleared; per bank on
//     dp2 (the other bank keeps working for both ports)
//   - clear with port B reading right after the request (dp0, dp2)
//   - ECC: error injected through A, corrected by a port-B read-modify-write
//     (dp2); B partial writes on dp1 (BYTE_EN = 0) get ERROR
// On SKY130 port B is read-only: B writes are expected to fail and the
// checks that need them use port A instead.

// Expected word after two writes in either order: returns 1 if `got` matches
// "first then second" or "second then first" on the lanes of `s`.
function automatic bit either_order(input int s, input int idx, input logic [63:0] got,
                                    input logic [63:0] base, input logic [63:0] da,
                                    input logic [7:0] la, input logic [63:0] db,
                                    input logic [7:0] lb);
  logic [63:0] ab, ba;
  ab = base;
  ba = base;
  for (int b = 0; b < nb(s); b++) begin
    if (la[b]) ab[8*b +: 8] = da[8*b +: 8];
    if (lb[b]) ab[8*b +: 8] = db[8*b +: 8];
    if (lb[b]) ba[8*b +: 8] = db[8*b +: 8];
    if (la[b]) ba[8*b +: 8] = da[8*b +: 8];
  end
  return ((got ^ ab) & wmask(s)) == 0 || ((got ^ ba) & wmask(s)) == 0;
endfunction

task automatic test_dp();
  int          a, b, sb, ra, rb, w;
  int unsigned c, h0;
  logic [63:0] v, va, vb, rd, base;
  logic        er;
  test_start("test_dp");
  // ---- width conversion, both directions, every dual port
  for (int n = 0; n < 3; n++) begin
    a = (n == 0) ? SL_DP0A : (n == 1) ? SL_DP1A : SL_DP2A;
    b = slv[a].peer;
    for (int i = 0; i < 8; i++) wr(a, 40 + i, rnd(a));
    // the same bytes, seen as port-B words
    for (int j = 40 * nb(a) / nb(b); j < 48 * nb(a) / nb(b); j++) rd_chk(b, j, 0, "A->B");
    if (!slv[b].ro) begin
      for (int j = 0; j < 4; j++) wr(b, 100 + j, rnd(b));
      for (int i = 100 * nb(b) / nb(a); i < 104 * nb(b) / nb(a); i++) rd_chk(a, i, 0, "B->A");
      if (!slv[b].be && slv[b].pwe) wr(b, 100, rnd(b), 8'h0F, 0, "B partial");   // ERROR
    end
    row($sformatf("%-6s A %0d-bit <-> B %0d-bit: little-endian packing both ways%s",
                  slv[a].name.substr(0, 2), slv[a].w, slv[b].w,
                  slv[b].ro ? " (B read-only)" : ""));
  end
  // ---- both ports at once, different words (dp0, then dp2: dp0.A and
  // dp2.A share the CPU master)
  fork
    for (int i = 0; i < 4; i++) begin
      burst(SL_DP0A, 1'b1, 64 * i, 3'd2, B_INCR16, 16, '0, "dp0 A concurrent", c);
      burst(SL_DP0A, 1'b0, 64 * i, 3'd2, B_INCR16, 16, '0, "dp0 A concurrent", c);
    end
    for (int i = 0; i < 4; i++) begin
      burst(SL_DP0B, 1'b1, 512 + 16 * i, 3'd0, B_INCR16, 16, '0, "dp0 B concurrent", c);
      burst(SL_DP0B, 1'b0, 512 + 16 * i, 3'd0, B_INCR16, 16, '0, "dp0 B concurrent", c);
    end
  join
  fork
    for (int i = 0; i < 4; i++) begin
      burst(SL_DP2A, 1'b1, 64 * i, 3'd2, B_INCR16, 16, '0, "dp2 A concurrent", c);
      burst(SL_DP2A, 1'b0, 64 * i, 3'd2, B_INCR16, 16, '0, "dp2 A concurrent", c);
    end
    for (int i = 0; i < 4; i++) begin
      burst(SL_DP2B, 1'b1, 512 + 64 * i, 3'd2, B_INCR16, 16, '0, "dp2 B concurrent", c);
      burst(SL_DP2B, 1'b0, 512 + 64 * i, 3'd2, B_INCR16, 16, '0, "dp2 B concurrent", c);
    end
  join
  row("dp0/2  A and B busy at once on different words (dp0: two clocks; dp2: CPU + DMA)");
  // ---- same-word races (one clock): dp1 and dp2
  h0 = n_dp1_hold + n_dp2_hold;
  for (int n = 0; n < 2; n++) begin
    a = n ? SL_DP2A : SL_DP1A;
    b = slv[a].peer;
    for (int k = 0; k < 24; k++) begin
      bit b_rd;                                  // B reads this time (always if read-only)
      logic [7:0] la, lb;
      // B word wb covers A words ra..ra+R-1 (or the reverse); pick a common byte range.
      w  = 8 + k;
      rb = (nb(a) <= nb(b)) ? w : w * nb(a) / nb(b);
      ra = (nb(a) <= nb(b)) ? w * nb(b) / nb(a) + (k % (nb(b) / nb(a))) : w;
      b_rd = slv[b].ro || (k % 4) == 3;
      if (!slv[b].ro) wr(b, rb, rnd(b));        // every byte of the word known
      else for (int i = 0; i < nb(b) / nb(a); i++) wr(a, rb * nb(b) / nb(a) + i, rnd(a));
      wr(a, ra, rnd(a));
      rd_raw(b, rb, base, er);
      va = rnd(a);
      vb = rnd(b);
      la = (k % 3 == 2 && slv[a].be) ? 8'b0001 : all_lanes(a);   // partial: RMW on dp2
      lb = (k % 3 == 1 && slv[b].be) ? 8'b0010 : all_lanes(b);
      // A write and B write (or read) of the same bytes in the same cycle.
      fork
        begin
          logic [63:0] r0;
          logic        e0;
          xfer(a, 1'b1, woff(a, ra), fsz(a), va, la, r0, e0);
        end
        begin
          logic [63:0] r1;
          logic        e1;
          xfer(b, !b_rd, woff(b, rb), fsz(b), vb, lb, r1, e1);
          if (b_rd) begin
            // B read raced A's write: old or new data, never a mix.
            logic [63:0] nw;
            nw = base;
            for (int i = 0; i < nb(a); i++) begin
              int pos;
              pos = (ra * nb(a) + i) - rb * nb(b);
              if (la[i] && pos >= 0 && pos < nb(b)) nw[8*pos +: 8] = va[8*i +: 8];
            end
            chk(((r1 ^ base) & wmask(b)) == 0 || ((r1 ^ nw) & wmask(b)) == 0,
                $sformatf("%s race read: old or new (got %h)", slv[b].name, r1));
          end
        end
      join
      // Result: either order; the model checks the exact one.
      rd_raw(b, rb, rd, er);
      begin
        logic [63:0] da, ma;
        logic [7:0]  lab;
        int          off;
        // A's write expressed in B's word
        off = ra * nb(a) - rb * nb(b);
        da  = '0;
        lab = '0;
        for (int i = 0; i < nb(a); i++) begin
          if (off + i >= 0 && off + i < nb(b) && la[i]) begin
            da[8*(off + i) +: 8] = va[8*i +: 8];
            lab[off + i] = 1'b1;
          end
        end
        if (b_rd) begin
          chk(either_order(b, rb, rd, base, da, lab, '0, '0), $sformatf("%s race result",
                                                                        slv[b].name));
        end else begin
          chk(either_order(b, rb, rd, base, da, lab, vb, slv[b].be ? lb : all_lanes(b)),
              $sformatf("%s write/write race: one order (got %h)", slv[b].name, rd));
        end
        sh_put(b, rb, rd, all_lanes(b));          // adopt the order the RTL chose
      end
    end
  end
  sb_cyc(SB_DP1, 2);
  chk(n_dp1_hold + n_dp2_hold > h0, $sformatf("same-word holds exercised (%0d cycles)",
                                              n_dp1_hold + n_dp2_hold - h0));
  row($sformatf("dp1/2  same-word races (write/write, write/read, RMW): one order; %0d hold cycles",
                n_dp1_hold + n_dp2_hold - h0));
  // ---- port B under port A's side-band (dp0 via CDC, dp2 per bank)
  for (int n = 0; n < 2; n++) begin
    a  = n ? SL_DP2A : SL_DP0A;
    b  = slv[a].peer;
    sb = slv[a].sb;
    for (int d = 0; d < slv[a].npd; d++) begin
      int ia, ib;
      ia = dom_word(a, d, 2);
      ib = ia * nb(a) / nb(b);
      wr(a, ia, rnd(a));
      set_mode(sb, d, DS);
      wait_mode(sb, d, DS, c);
      cyc_b(8);
      rd_chk(b, ib, 1, "B in DS");
      if (slv[a].npd > 1) rd_chk(b, dom_word(b, 1 - d, 2), 0, "B other bank");
      set_mode(sb, d, LS);
      wait_mode(sb, d, LS, c);
      cyc_b(8);
      rd_chk(b, ib, 0, "B wakes LS");
      wait_mode(sb, d, LS, c);
      set_mode(sb, d, SD);
      wait_mode(sb, d, SD, c);
      sh_forget_dom(sb, d);
      cyc_b(8);
      rd_chk(b, ib, 1, "B in SD");
      set_mode(sb, d, RUN);
      wait_mode(sb, d, RUN, c);
      sh_fill_dom(sb, d, 8'h00);
      cyc_b(8);
      rd_chk(b, ib, 0, "B after SD");
    end
    row($sformatf("%-6s port B: DS ERROR, LS wake%s, SD cleared%s", slv[a].name.substr(0, 2),
                  n ? "" : " through the CDC", slv[a].npd > 1 ? ", other bank works" : ""));
  end
  // ---- clear with port B reading right after the request
  for (int n = 0; n < 2; n++) begin
    b  = n ? SL_DP2B : SL_DP0B;
    sb = slv[b].sb;
    wr(slv[b].peer, 5, rnd(slv[b].peer));
    wr(slv[b].peer, 6, rnd(slv[b].peer));
    sb_cyc(sb, 1);
    `TB_DRV; clr_req[sb] <= 1'b1;
    sb_cyc(sb, 1);
    `TB_DRV; clr_req[sb] <= 1'b0;
    if (n == 0) begin
      // Port B on its own clock: a read issued with the request may be
      // granted before the CDC takes B's permission away, so it returns the
      // old word or zero (the model checks which). A read issued after the
      // handshake must wait for the clear and return zero.
      logic [63:0] r0;
      logic        e0;
      logic [63:0] old;
      old = sh_word(b, 5 * nb(slv[b].peer) / nb(b));
      rd_raw(b, 5 * nb(slv[b].peer) / nb(b), r0, e0);
      chk(e0 === 1'b0 && ((r0 & wmask(b)) == 0 || ((r0 ^ old) & wmask(b)) == 0),
          $sformatf("dp0.B read with the clear request: old word or zero (%h)", r0));
      sh_fill(sb, 0, st_bytes(sb), 8'h00);
      wr(slv[b].peer, 6, rnd(slv[b].peer));
      sb_cyc(sb, 1);
      `TB_DRV; clr_req[sb] <= 1'b1;
      sb_cyc(sb, 1);
      `TB_DRV; clr_req[sb] <= 1'b0;
      cyc_b(8);
    end
    sh_fill(sb, 0, st_bytes(sb), 8'h00);
    rd_chk(b, 6 * nb(slv[b].peer) / nb(b), 0, "B read during clear");
    wait_idle(sb);
    row($sformatf("%-6s clear: port B read issued with the request waits and reads zero",
                  slv[b].name));
  end
  // ---- ECC: injected through A, corrected by a port-B read-modify-write (dp2)
  if (!slv[SL_DP2B].ro) begin
    int unsigned c0;
    inject(SB_DP2, 2'b01);
    wr(SL_DP2A, 60, rnd(SL_DP2A));
    c0 = n_corr[SB_DP2];
    wr(SL_DP2B, 60, rnd(SL_DP2B), 8'b0100, 0, "B RMW of a 1-bit word");
    sb_cyc(SB_DP2, 4);
    chk(n_corr[SB_DP2] - c0 == 1, "dp2: B RMW corrects the injected error");
    c0 = n_corr[SB_DP2];
    rd_chk(SL_DP2A, 60, 0, "after B RMW");
    sb_cyc(SB_DP2, 4);
    chk(n_corr[SB_DP2] == c0, "dp2: word clean after the B RMW");
    inject(SB_DP2, 2'b10);
    wr(SL_DP2A, 61, rnd(SL_DP2A));
    wr(SL_DP2B, 61, rnd(SL_DP2B), 8'b0001, 1, "B RMW of a 2-bit word");
    rd_chk(SL_DP2B, 61, 1, "2-bit word unchanged");
    wr(SL_DP2B, 61, rnd(SL_DP2B));
    rd_chk(SL_DP2A, 61, 0, "healed by B");
    row("dp2    ECC through port B: RMW corrects a 1-bit word, refuses a 2-bit word");
  end
  test_done("test_dp");
endtask
