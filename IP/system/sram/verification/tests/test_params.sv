// test_params.sv — Each configuration's width and depth, end to end.
//
// For every slave port:
//   - data walking 1s and 0s on word 0 (every bit lane / primitive column)
//   - words 0 and last, and both sides of every power-of-two boundary
//     (primitive rows, banks and domains are all power-of-two sized)
//   - address walking 1s: one distinct word at each address bit, all read
//     back after all are written (address aliasing)
//   - full sweep: every word written, then every word read
//   - range error inside the 64 KB window, past the last word (SRAM error,
//     also counted on err_irq_o), and decode error outside every window
//     (matrix error); neither changes the contents
// Read-only ports (SKY130 port B) check that writes are refused and read
// what port A wrote.

task automatic test_params();
  int          s, w, d;
  logic [63:0] v, rd;
  logic        er;
  int unsigned irq0;
  test_start("test_params");
  for (s = 0; s < NSL; s++) begin
    w = slv[s].w;
    d = slv[s].depth;
    if (slv[s].ro) begin
      // Read-only port (SKY130 port B): the same data and address patterns,
      // writes answered with ERROR, reads of what port A wrote.
      for (int b = 0; b < w; b++) begin
        wr(s, 0, 64'd1 << b, '1, 1, "ro walk1");
        wr(s, 0, ~(64'd1 << b) & wmask(s), '1, 1, "ro walk0");
      end
      for (int k = 0; (1 << k) < d; k++) begin
        wr(s, 1 << k, rnd(s), '1, 1, "ro addr walk");
        rd_chk(s, 1 << k, 0, "ro addr walk");
      end
      rd_chk(s, 0);
      rd_chk(s, d - 1);
      xfer(s, 1'b0, woff(s, d), fsz(s), '0, '0, rd, er);
      chk(er === 1'b1, $sformatf("%s read past the end: ERROR", slv[s].name));
      xfer(s, 1'b0, 32'h0000_FFF8 & ~((32'd1 << offw(s)) - 1), fsz(s), '0, '0, rd, er);
      chk(er === 1'b1, $sformatf("%s read at the window end: ERROR", slv[s].name));
      row($sformatf("%-6s W=%0d D=%0d read-only port: walks (writes ERROR), range errors",
                    slv[s].name, w, d));
      continue;
    end
    // Data walking 1s / 0s
    for (int b = 0; b < w; b++) begin
      wr(s, 0, 64'd1 << b);
      rd_chk(s, 0, 0, "walk1");
      wr(s, 0, ~(64'd1 << b) & wmask(s));
      rd_chk(s, 0, 0, "walk0");
    end
    // Boundaries
    wr(s, 0, rnd(s));
    wr(s, d - 1, rnd(s));
    for (int k = 1; (1 << k) < d; k++) begin
      wr(s, (1 << k) - 1, rnd(s));
      wr(s, 1 << k, rnd(s));
    end
    rd_chk(s, 0);
    rd_chk(s, d - 1);
    for (int k = 1; (1 << k) < d; k++) begin
      rd_chk(s, (1 << k) - 1, 0, "boundary");
      rd_chk(s, 1 << k, 0, "boundary");
    end
    // Address walking 1s
    wr(s, 0, 64'h5A5A_5A5A_5A5A_5A5A & wmask(s));
    for (int k = 0; (1 << k) < d; k++) wr(s, 1 << k, (64'h0101_0101_0101_0101 * (k + 1))
                                           & wmask(s));
    rd_chk(s, 0, 0, "addr walk");
    for (int k = 0; (1 << k) < d; k++) rd_chk(s, 1 << k, 0, "addr walk");
    // Full sweep
    for (int i = 0; i < d; i++) wr(s, i, ({$urandom, $urandom} ^ (64'(i) << 3)) & wmask(s));
    for (int i = 0; i < d; i++) rd_chk(s, i, 0, "sweep");
    // Range and decode errors
    // The errors are spaced out: a port B on its own clock reaches err_irq_o
    // through claude_pulse_sync, which merges events closer than about three
    // port-A cycles (documented), and each error must give its own pulse.
    irq0 = n_irq[slv[s].sb];
    wr(s, d, rnd(s), '1, 1, "range");
    sb_cyc(slv[s].sb, 8);
    xfer(s, 1'b0, woff(s, d), fsz(s), '0, '0, rd, er);
    chk(er === 1'b1, $sformatf("%s read past the end: ERROR", slv[s].name));
    sb_cyc(slv[s].sb, 8);
    xfer(s, 1'b0, 32'h0000_FFF8 & ~((32'd1 << offw(s)) - 1), fsz(s), '0, '0, rd, er);
    chk(er === 1'b1, $sformatf("%s read at the window end: ERROR", slv[s].name));
    sb_cyc(slv[s].sb, 8);
    chk(n_irq[slv[s].sb] - irq0 == 3, $sformatf("%s err_irq_o pulses for range errors (%0d)",
                                                slv[s].name, n_irq[slv[s].sb] - irq0));
    if (slv[s].m <= 5) begin
      m_set(slv[s].m, 0, 1'b0, 32'h000F_0000, fsz(s), NONSEQ, B_SINGLE, '0, '0);
      m_run(slv[s].m, 1);
      m_get(slv[s].m, 0, rd, er);
      chk(er === 1'b1, $sformatf("%s matrix decode error", slv[s].name));
    end
    rd_chk(s, d - 1, 0, "after errors");
    row($sformatf("%-6s W=%0d D=%0d: walks, %0d boundaries, sweep, range/decode errors",
                  slv[s].name, w, d, 2 * $clog2(d)));
  end
  test_done("test_params");
endtask
