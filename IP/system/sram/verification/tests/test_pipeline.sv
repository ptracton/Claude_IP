// test_pipeline.sv — Pipelining and read latency.
//
// On the directly attached SRAMs (s32p READ_LATENCY = 1, s32q
// READ_LATENCY = 2), where the beats go straight into the SRAM's adapter
// (pipelined on AHB, back to back on the other buses):
//   - single read and write cycle counts; READ_LATENCY = 2 adds one cycle
//     to both (every response comes READ_LATENCY cycles after the grant)
//   - 16-beat read / write throughput (AHB INCR16: bounded cycles per beat)
//   - back-to-back pipelined write then read of the same word (the read's
//     address phase overlaps the write's data phase), alternating over 8
//     words, plus read-write-read of one word: every read returns the data
//     of the write before it
// Through the bus_matrix: s32 (RL1) and s32e (RL2) single-read cycle counts
// differ by the extra output register.
// AXI4-Lite only, with the BFM in pipelined mode (several transactions in
// flight, sram_tb_axi4l_master.sv) on s32p and s32q:
//   - 16 writes and 16 reads back to back: no slower than one at a time
//   - 16 writes interleaved with 16 reads of other words: the read and write
//     channels overlap, so the stream is faster than one at a time
//   - write -> read of the same word x8: the BFM's ordering keeps the read
//     behind the write, so every read returns the new data

task automatic latency(input int s, output int unsigned c_rd, output int unsigned c_wr);
  logic [63:0] rd;
  logic        er;
  wr(s, 5, rnd(s));
  c_wr = m_cycles(slv[s].m);
  rd_chk(s, 5, 0, "latency");
  c_rd = m_cycles(slv[s].m);
endtask

// mixed — 16 writes (words wbase..) interleaved with 16 reads (words
// rbase.., all different from the written ones) on s's direct master,
// pipelined or one at a time; checks every response, returns the cycles.
task automatic mixed(input int s, input int wbase, input int rbase, input bit pipe,
                     output int unsigned cycles);
  int          m;
  logic [63:0] rd;
  logic        er;
  m = slv[s].m;
  for (int i = 0; i < 16; i++) begin
    m_set(m, 2 * i, 1'b1, slv[s].base + woff(s, wbase + i), fsz(s), NONSEQ, B_SINGLE, rnd(s), '1);
    m_set(m, 2 * i + 1, 1'b0, slv[s].base + woff(s, rbase + i), fsz(s), NONSEQ, B_SINGLE, '0, '0);
  end
  m_pipe(m, pipe);
  m_run(m, 32);
  m_pipe(m, 1'b0);
  cycles = m_cycles(m);
  for (int i = 0; i < 16; i++) begin
    m_get(m, 2 * i, rd, er);
    chk(er === 1'b0, $sformatf("%s mixed write %0d OKAY", slv[s].name, i));
    sh_put(s, wbase + i, m_wdata(m, 2 * i), '1);
    m_get(m, 2 * i + 1, rd, er);
    chk(er === 1'b0, $sformatf("%s mixed read %0d OKAY", slv[s].name, i));
    cmp_lanes(s, rbase + i, rd, '1, "mixed read");
  end
endtask

// axi_pipelined — the AXI4-Lite pipelined-mode checks (see the header).
task automatic axi_pipelined(input int s);
  int unsigned sw, sr, pw, pr, sm, pm, c;
  int          m;
  logic [63:0] d, rd;
  logic        er;
  m = slv[s].m;
  burst(s, 1'b1, woff(s, 128), fsz(s), B_INCR16, 16, '0, "serial writes", sw);
  burst(s, 1'b0, woff(s, 128), fsz(s), B_INCR16, 16, '0, "serial reads", sr);
  m_pipe(m, 1'b1);
  burst(s, 1'b1, woff(s, 128), fsz(s), B_INCR16, 16, '0, "pipelined writes", pw);
  burst(s, 1'b0, woff(s, 128), fsz(s), B_INCR16, 16, '0, "pipelined reads", pr);
  m_pipe(m, 1'b0);
  chk(pw <= sw && pr <= sr, $sformatf("%s pipelined 16 writes / reads no slower (%0d/%0d vs %0d/%0d)",
                                      slv[s].name, pw, pr, sw, sr));
  mixed(s, 144, 128, 1'b0, sm);
  mixed(s, 160, 144, 1'b1, pm);
  chk(pm < sm, $sformatf("%s pipelined mixed stream faster (%0d vs %0d cycles)",
                         slv[s].name, pm, sm));
  row($sformatf("%-6s AXI pipelined: 16 writes %0d (serial %0d), 16 reads %0d (serial %0d), 16w+16r interleaved %0d (serial %0d) cycles",
                slv[s].name, pw, sw, pr, sr, pm, sm));
  // Same-word write -> read: program order kept
  for (int i = 0; i < 8; i++) begin
    m_set(m, 2 * i, 1'b1, slv[s].base + woff(s, 176 + i), fsz(s), NONSEQ, B_SINGLE, rnd(s), '1);
    m_set(m, 2 * i + 1, 1'b0, slv[s].base + woff(s, 176 + i), fsz(s), NONSEQ, B_SINGLE, '0, '0);
  end
  m_pipe(m, 1'b1);
  m_run(m, 16);
  m_pipe(m, 1'b0);
  c = m_cycles(m);
  for (int i = 0; i < 8; i++) begin
    m_get(m, 2 * i, rd, er);
    chk(er === 1'b0, "pipelined same-word write OKAY");
    sh_put(s, 176 + i, m_wdata(m, 2 * i), '1);
    m_get(m, 2 * i + 1, rd, er);
    chk(er === 1'b0, "pipelined same-word read OKAY");
    cmp_lanes(s, 176 + i, rd, '1, "pipelined write->read");
  end
  row($sformatf("%-6s AXI pipelined write->read of one word x8 (%0d cycles): reads see the writes",
                slv[s].name, c));
endtask

task automatic test_pipeline();
  int unsigned r1, w1, r2, w2, c, cw1, cr1, cw2, cr2;
  int          m, s;
  logic [63:0] d, rd;
  logic        er;
  test_start("test_pipeline");
  latency(SL_S32P, r1, w1);
  latency(SL_S32Q, r2, w2);
  chk(r2 == r1 + 1, $sformatf("RL2 read takes one cycle more (%0d vs %0d)", r2, r1));
  // Every response (writes too) comes READ_LATENCY cycles after the grant.
  chk(w2 == w1 + 1, $sformatf("RL2 write response one cycle later (%0d vs %0d)", w2, w1));
  row($sformatf("direct single read: RL1 %0d cycles, RL2 %0d cycles; write %0d / %0d",
                r1, r2, w1, w2));
  burst(SL_S32P, 1'b1, 'h100, 3'd2, B_INCR16, 16, '0, "rl1 burst", cw1);
  burst(SL_S32P, 1'b0, 'h100, 3'd2, B_INCR16, 16, '0, "rl1 burst", cr1);
  burst(SL_S32Q, 1'b1, 'h100, 3'd2, B_INCR16, 16, '0, "rl2 burst", cw2);
  burst(SL_S32Q, 1'b0, 'h100, 3'd2, B_INCR16, 16, '0, "rl2 burst", cr2);
  if (IS_AHB) begin
    // AHB pipelines the beats: one wait state per beat at RL1, two at RL2.
    chk(cw1 <= 2 * 16 + 2 && cr1 <= 2 * 16 + 2,
        $sformatf("RL1 INCR16 at most 2 cycles per beat (%0d / %0d)", cw1, cr1));
    chk(cr2 <= 3 * 16 + 2, $sformatf("RL2 INCR16 read at most 3 cycles per beat (%0d)", cr2));
  end
  chk(cr2 > cr1, $sformatf("RL2 16-beat read slower than RL1 (%0d vs %0d)", cr2, cr1));
  row($sformatf("direct %s: RL1 write %0d / read %0d cycles; RL2 write %0d / read %0d",
                IS_AHB ? "INCR16" : "16 back-to-back", cw1, cr1, cw2, cr2));
  // Pipelined write -> read of the same word (and read -> write -> read).
  for (int t = 0; t < 2; t++) begin
    s = t ? SL_S32Q : SL_S32P;
    m = slv[s].m;
    for (int i = 0; i < 8; i++) begin
      d = rnd(s);
      m_set(m, 2 * i, 1'b1, slv[s].base + woff(s, 64 + i), 3'd2, NONSEQ, B_SINGLE, d, '1);
      m_set(m, 2 * i + 1, 1'b0, slv[s].base + woff(s, 64 + i), 3'd2, NONSEQ, B_SINGLE, '0, '0);
    end
    m_run(m, 16);
    c = m_cycles(m);
    for (int i = 0; i < 8; i++) begin
      m_get(m, 2 * i, rd, er);
      chk(er === 1'b0, "pipelined write OKAY");
      d = (m == 6) ? 64'(g_direct[0].u_m.bt_wdata[2 * i]) : 64'(g_direct[1].u_m.bt_wdata[2 * i]);
      sh_put(s, 64 + i, d, '1);
      m_get(m, 2 * i + 1, rd, er);
      chk(er === 1'b0, "pipelined read OKAY");
      cmp_lanes(s, 64 + i, rd, '1, "write->read");
    end
    // read, write, read of one word
    d = rnd(s);
    m_set(m, 0, 1'b0, slv[s].base + woff(s, 80), 3'd2, NONSEQ, B_SINGLE, '0, '0);
    m_set(m, 1, 1'b1, slv[s].base + woff(s, 80), 3'd2, NONSEQ, B_SINGLE, d, '1);
    m_set(m, 2, 1'b0, slv[s].base + woff(s, 80), 3'd2, NONSEQ, B_SINGLE, '0, '0);
    m_run(m, 3);
    m_get(m, 0, rd, er);
    cmp_lanes(s, 80, rd, '1, "read before write");
    sh_put(s, 80, d, '1);
    m_get(m, 2, rd, er);
    cmp_lanes(s, 80, rd, '1, "read after write");
    row($sformatf("%-6s pipelined write->read x8 (%0d cycles), read-write-read",
                  slv[s].name, c));
  end
  // An error beat followed at once by a good one (AHB: the next address
  // phase is accepted in the second cycle of the ERROR response).
  for (int t = 0; t < 2; t++) begin
    s = t ? SL_S32Q : SL_S32P;
    m = slv[s].m;
    m_set(m, 0, 1'b0, slv[s].base + woff(s, slv[s].depth), 3'd2, NONSEQ, B_SINGLE, '0, '0);
    m_set(m, 1, 1'b0, slv[s].base + woff(s, 64), 3'd2, NONSEQ, B_SINGLE, '0, '0);
    m_set(m, 2, 1'b1, slv[s].base + woff(s, slv[s].depth + 1), 3'd2, NONSEQ, B_SINGLE, '0, '1);
    m_set(m, 3, 1'b0, slv[s].base + woff(s, 65), 3'd2, NONSEQ, B_SINGLE, '0, '0);
    m_run(m, 4);
    for (int i = 0; i < 4; i++) begin
      m_get(m, i, rd, er);
      chk(er === (i % 2 == 0), $sformatf("%s error/good beat %0d response %b", slv[s].name, i, er));
      if (i % 2) cmp_lanes(s, 64 + i / 2, rd, '1, "beat after an error");
    end
  end
  row("s32p/q error beats followed at once by good ones: errors, then right data");
  if (IS_AXI) begin
    axi_pipelined(SL_S32P);
    axi_pipelined(SL_S32Q);
  end
  // Through the matrix
  latency(SL_S32, r1, w1);
  latency(SL_S32E, r2, w2);
  chk(r2 == r1 + 1, $sformatf("matrix: RL2 read one cycle more (%0d vs %0d)", r2, r1));
  row($sformatf("through bus_matrix: s32 (RL1) read %0d cycles, s32e (RL2) %0d", r1, r2));
  test_done("test_pipeline");
endtask
