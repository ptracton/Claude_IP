// sram_tb_helpers.sv — Shared helpers for the sram system testbench.
//
// `include inside tb_sram_<proto> (module scope, via sram_tb_body.svh) before the test_*.sv files.
// Provides:
//   - reporting: test_start / row / fail / test_done. A test prints one row
//     per check group; every single comparison is counted (n_cmp) and the
//     first wrong one stops the simulation with the details.
//   - master dispatch (m_*): drive any of the 8 BFMs by index, data up to
//     64 bits.
//   - slave helpers: addresses, byte lanes, shadow updates and checked
//     accesses (wr / rd_chk / sub / burst_* ) on any slave port by SL_* index.
//   - side-band helpers: power modes, clear, ECC injection, BIST.

int unsigned n_cmp;          // single comparisons, whole run
int unsigned t_rows;         // rows printed in the current test
int unsigned t_cmp0;         // n_cmp at test start
int unsigned n_tests;
localparam bit IS_AHB = (`TB_PROTO == "ahb");  // HSIZE, HTRANS bursts and BUSY on the bus
localparam bit IS_AXI = (`TB_PROTO == "axi4l"); // separate read and write channels
string       cur_test;
int          a_slave [NSB];  // port-A (or only) slave of each instance

localparam logic [1:0] NONSEQ = 2'b10, SEQ = 2'b11;
localparam logic [2:0] B_SINGLE = 3'd0, B_INCR = 3'd1, B_WRAP4 = 3'd2, B_INCR4 = 3'd3,
                       B_WRAP8 = 3'd4, B_INCR8 = 3'd5, B_WRAP16 = 3'd6, B_INCR16 = 3'd7;
localparam logic [1:0] RUN = 2'd0, LS = 2'd1, DS = 2'd2, SD = 2'd3;

// ---------------------------------------------------------------------------
// Reporting
// ---------------------------------------------------------------------------
task automatic test_start(input string name);
  cur_test = name;
  t_rows   = 0;
  t_cmp0   = n_cmp;
  $display("\n=== %s ===", name);
  $display("%-5s %-66s %s", "#", "Check", "Status");
  $display("%s", {78{"-"}});
endtask

task automatic row(input string what);
  $display("[%3d] %-66s PASS", t_rows, what);
  t_rows++;
endtask

task automatic fail(input string msg);
  $display("[%3d] %-66s FAIL", t_rows, msg);
  $display("FAIL %s: %s: %s (t = %0t)", `TB_STR, cur_test, msg, $time);
  $finish(1);
endtask

task automatic test_done(input string name);
  $display("%s", {78{"-"}});
  $display("%s: PASS  (%0d checks, %0d comparisons)", name, t_rows, n_cmp - t_cmp0);
  n_tests++;
endtask

task automatic chk(input bit ok, input string msg);
  n_cmp++;
  if (!ok) fail(msg);
endtask

// ---------------------------------------------------------------------------
// Clocks
// ---------------------------------------------------------------------------
task automatic cyc_a(input int unsigned n);
  repeat (n) @(posedge clk_a);
endtask

task automatic cyc_b(input int unsigned n);
  repeat (n) @(posedge clk_b);
endtask

// n cycles of an instance's side-band clock
task automatic sb_cyc(input int sb, input int unsigned n);
  if (slv[a_slave[sb]].on_b) cyc_b(n);
  else cyc_a(n);
endtask

// ---------------------------------------------------------------------------
// Master dispatch
// ---------------------------------------------------------------------------
`define MCASE(OP) \
  case (m) \
    0: u_m0.OP; \
    1: u_m1.OP; \
    2: u_m2.OP; \
    3: u_m3.OP; \
    4: u_m4.OP; \
    5: u_m5.OP; \
    6: g_direct[0].u_m.OP; \
    7: g_direct[1].u_m.OP; \
    default: fail($sformatf("bad master %0d", m)); \
  endcase

`define MGET(DST, FIELD) \
  case (m) \
    0: DST = 64'(u_m0.FIELD); \
    1: DST = 64'(u_m1.FIELD); \
    2: DST = 64'(u_m2.FIELD); \
    3: DST = 64'(u_m3.FIELD); \
    4: DST = 64'(u_m4.FIELD); \
    5: DST = 64'(u_m5.FIELD); \
    6: DST = 64'(g_direct[0].u_m.FIELD); \
    7: DST = 64'(g_direct[1].u_m.FIELD); \
    default: DST = 'x; \
  endcase

task automatic m_set(input int m, input int i, input logic we, input logic [31:0] addr,
                     input logic [2:0] size, input logic [1:0] trans, input logic [2:0] burst,
                     input logic [63:0] wdata, input logic [7:0] strb, input int busy = 0);
  `MCASE(set_beat(i, we, addr, size, trans, burst, wdata, strb, busy))
endtask

task automatic m_load_burst(input int m, input logic we, input logic [31:0] addr,
                            input logic [2:0] size, input logic [2:0] kind, input int beats,
                            input logic [63:0] busy_mask);
  `MCASE(load_burst(we, addr, size, kind, beats, busy_mask))
endtask

task automatic m_data(input int m, input int i, input logic [63:0] wdata, input logic [7:0] strb);
  case (m)
    0: begin u_m0.bt_wdata[i] = wdata; u_m0.bt_strb[i] = strb; end
    1: begin u_m1.bt_wdata[i] = wdata; u_m1.bt_strb[i] = strb; end
    2: begin u_m2.bt_wdata[i] = wdata; u_m2.bt_strb[i] = strb; end
    3: begin u_m3.bt_wdata[i] = wdata; u_m3.bt_strb[i] = strb; end
    4: begin u_m4.bt_wdata[i] = wdata; u_m4.bt_strb[i] = strb; end
    5: begin u_m5.bt_wdata[i] = wdata; u_m5.bt_strb[i] = strb; end
    6: begin g_direct[0].u_m.bt_wdata[i] = wdata; g_direct[0].u_m.bt_strb[i] = strb; end
    7: begin g_direct[1].u_m.bt_wdata[i] = wdata; g_direct[1].u_m.bt_strb[i] = strb; end
    default: ;
  endcase
endtask

task automatic m_run(input int m, input int n);
  `MCASE(run_beats(n))
endtask

// m_pipe — pipelined mode of master m (AXI4-Lite BFM only; others ignore it).
task automatic m_pipe(input int m, input bit on);
  `MCASE(set_pipelined(on))
endtask

function automatic logic [63:0] m_wdata(input int m, input int i);
  logic [63:0] d;
  `MGET(d, bt_wdata[i])
  return d;
endfunction

task automatic m_get(input int m, input int i, output logic [63:0] rdata, output logic err);
  logic [63:0] e;
  `MGET(rdata, bt_rdata[i])
  `MGET(e, bt_err[i])
  err = e[0];
endtask

function automatic logic [31:0] m_addr(input int m, input int i);
  logic [63:0] a;
  `MGET(a, bt_addr[i])
  return a[31:0];
endfunction

function automatic int unsigned m_cycles(input int m);
  logic [63:0] c;
  `MGET(c, last_cycles)
  return c;
endfunction

function automatic int unsigned m_waits(input int m);
  logic [63:0] c;
  `MGET(c, last_wait)
  return c;
endfunction

// ---------------------------------------------------------------------------
// Slave geometry
// ---------------------------------------------------------------------------
function automatic int nb(input int s);            // bytes per word
  return slv[s].w / 8;
endfunction

function automatic int offw(input int s);          // log2 of the word stride
  return (nb(s) > 1) ? $clog2(nb(s)) : 0;
endfunction

function automatic logic [2:0] fsz(input int s);   // HSIZE of a full word
  return 3'(offw(s));
endfunction

function automatic logic [31:0] woff(input int s, input int idx); // byte offset of a word
  return 32'(idx) << offw(s);
endfunction

// ECC codeword bytes: the narrower port's word on a dual port, else the word.
function automatic int cw_bytes(input int s);
  if (slv[s].peer >= 0 && nb(slv[s].peer) < nb(s)) return nb(slv[s].peer);
  return nb(s);
endfunction

function automatic logic [7:0] all_lanes(input int s);
  return 8'((1 << nb(s)) - 1);
endfunction

// Lanes of a 2**size-byte transfer at byte offset off (naturally aligned block).
function automatic logic [7:0] lane_mask(input int s, input logic [2:0] size, input int off);
  logic [7:0] m;
  int         o;
  o = off & ((1 << offw(s)) - 1);
  m = '0;
  for (int b = 0; b < nb(s); b++) m[b] = ((b >> size) == (o >> size));
  return m;
endfunction

function automatic logic [63:0] wmask(input int s);
  return (slv[s].w == 64) ? '1 : ((64'd1 << slv[s].w) - 1);
endfunction

// Storage bytes of an instance (its port-A word bytes x depth).
function automatic int st_bytes(input int sb);
  return slv[a_slave[sb]].depth * nb(a_slave[sb]);
endfunction

// ---------------------------------------------------------------------------
// Shadow memory
// ---------------------------------------------------------------------------
function automatic logic [63:0] sh_word(input int s, input int idx);
  logic [63:0] w;
  w = '0;
  for (int b = 0; b < nb(s); b++) w[8*b +: 8] = sh_byte(slv[s].sb, idx * nb(s) + b);
  return w;
endfunction

task automatic sh_put(input int s, input int idx, input logic [63:0] data, input logic [7:0] lanes);
  for (int b = 0; b < nb(s); b++) begin
    if (lanes[b]) shadow[slv[s].sb][idx * nb(s) + b] = data[8*b +: 8];
  end
endtask

// Fill storage bytes [p0, p1) of an instance (X: unknown).
task automatic sh_fill(input int sb, input int p0, input int p1, input logic [7:0] v);
  for (int p = p0; p < p1; p++) begin
    if (v === 8'hxx) shadow[sb].delete(p);
    else shadow[sb][p] = v;
  end
endtask

// Fill power domain d of an instance.
task automatic sh_fill_dom(input int sb, input int d, input logic [7:0] v);
  int n, npd;
  n   = st_bytes(sb);
  npd = slv[a_slave[sb]].npd;
  sh_fill(sb, d * n / npd, (d + 1) * n / npd, v);
endtask

// Compare read data with the shadow on the given lanes (X bytes skipped).
task automatic cmp_lanes(input int s, input int idx, input logic [63:0] got,
                         input logic [7:0] lanes, input string what);
  logic [63:0] exp;
  exp = sh_word(s, idx);
  for (int b = 0; b < nb(s); b++) begin
    if (lanes[b] && exp[8*b +: 8] !== 8'hxx) begin
      chk(got[8*b +: 8] === exp[8*b +: 8],
          $sformatf("%s: %s word %0d lane %0d got %h exp %h (word got %h exp %h)",
                    what, slv[s].name, idx, b, got[8*b +: 8], exp[8*b +: 8],
                    got & wmask(s), exp & wmask(s)));
    end
  end
endtask

// Pseudo-random data of the slave's width.
function automatic logic [63:0] rnd(input int s);
  return {$urandom, $urandom} & wmask(s);
endfunction

// ---------------------------------------------------------------------------
// Checked accesses. Offsets are byte offsets inside the slave's window.
// ---------------------------------------------------------------------------
task automatic xfer(input int s, input logic we, input logic [31:0] off, input logic [2:0] size,
                    input logic [63:0] wdata, input logic [7:0] strb,
                    output logic [63:0] rdata, output logic err, input int mo = -1);
  int m;
  m = (mo >= 0) ? mo : slv[s].m;
  m_set(m, 0, we, slv[s].base + off, size, NONSEQ, B_SINGLE, wdata, strb);
  m_run(m, 1);
  m_get(m, 0, rdata, err);
endtask

// Lanes a successful write stores (BYTE_EN = 0 without the error: all).
function automatic logic [7:0] stored_lanes(input int s, input logic [7:0] lanes);
  return slv[s].be ? (lanes & all_lanes(s)) : all_lanes(s);
endfunction

// Expected error of a write with these lanes (range / power errors are the
// caller's: pass exp_err).
function automatic bit wr_err(input int s, input logic [7:0] lanes);
  return slv[s].ro || (!slv[s].be && slv[s].pwe && (lanes & all_lanes(s)) != all_lanes(s));
endfunction

// Full-size write of word idx with strobes.
task automatic wr(input int s, input int idx, input logic [63:0] data,
                  input logic [7:0] strb = 8'hFF, input bit exp_err = 0, input string what = "wr",
                  input int mo = -1);
  logic [63:0] rd;
  logic        er;
  bit          e;
  e = exp_err || wr_err(s, strb);
  xfer(s, 1'b1, woff(s, idx), fsz(s), data, strb & all_lanes(s), rd, er, mo);
  chk(er === e, $sformatf("%s: %s write word %0d response %b, expected %s", what, slv[s].name,
                          idx, er, e ? "ERROR" : "OKAY"));
  if (!er) sh_put(s, idx, data, stored_lanes(s, strb));
endtask

// Full-size read of word idx, compared with the shadow.
task automatic rd_chk(input int s, input int idx, input bit exp_err = 0,
                      input string what = "rd", input int mo = -1);
  logic [63:0] rd;
  logic        er;
  xfer(s, 1'b0, woff(s, idx), fsz(s), '0, '0, rd, er, mo);
  chk(er === exp_err, $sformatf("%s: %s read word %0d response %b, expected %s", what,
                                slv[s].name, idx, er, exp_err ? "ERROR" : "OKAY"));
  if (!er) cmp_lanes(s, idx, rd, all_lanes(s), what);
endtask

// Read word idx and return it (no comparison).
task automatic rd_raw(input int s, input int idx, output logic [63:0] rd, output logic er);
  xfer(s, 1'b0, woff(s, idx), fsz(s), '0, '0, rd, er);
endtask

// Transfer of 2**size bytes at byte offset off (sub-word or full), checked.
// Write data is given on the full bus (lanes chosen by the address).
task automatic sub(input int s, input int off, input logic [2:0] size, input bit we,
                   input logic [63:0] data, input string what);
  logic [63:0] rd;
  logic        er;
  logic [7:0]  ln;
  int          idx;
  bit          e;
  ln  = lane_mask(s, size, off);
  idx = off >> offw(s);
  e   = we && wr_err(s, ln);
  xfer(s, we, off, size, data, we ? '1 : '0, rd, er);
  chk(er === e, $sformatf("%s: %s %s size %0d at 0x%0h response %b", what, slv[s].name,
                          we ? "write" : "read", size, off, er));
  if (er) return;
  if (we) sh_put(s, idx, data, stored_lanes(s, ln));
  else    cmp_lanes(s, idx, rd, ln, what);
endtask

// Burst: kind/beats/size from byte offset off; busy_mask bit i = one BUSY
// before beat i. mo (here and in xfer / wr / rd_chk) overrides the master. Writes take random data and update the shadow; reads are
// compared beat by beat. Returns the cycle count of the burst.
task automatic burst(input int s, input bit we, input int off, input logic [2:0] size,
                     input logic [2:0] kind, input int beats, input logic [63:0] busy_mask,
                     input string what, output int unsigned cycles, input int mo = -1);
  int          m, idx;
  logic [63:0] d, rd;
  logic        er;
  logic [31:0] a;
  logic [7:0]  ln;
  bit          e;
  m = (mo >= 0) ? mo : slv[s].m;
  m_load_burst(m, we, slv[s].base + off, size, kind, beats, busy_mask);
  for (int i = 0; i < beats; i++) m_data(m, i, rnd(s), '1);
  m_run(m, beats);
  cycles = m_cycles(m);
  for (int i = 0; i < beats; i++) begin
    a   = m_addr(m, i) - slv[s].base;
    idx = a >> offw(s);
    ln  = lane_mask(s, size, a);
    e   = we && wr_err(s, ln);
    m_get(m, i, rd, er);
    chk(er === e, $sformatf("%s: %s beat %0d at 0x%0h response %b", what, slv[s].name, i, a, er));
    if (er) continue;
    if (we) begin
      case (m)
        0: d = 64'(u_m0.bt_wdata[i]);
        1: d = 64'(u_m1.bt_wdata[i]);
        2: d = 64'(u_m2.bt_wdata[i]);
        3: d = 64'(u_m3.bt_wdata[i]);
        4: d = 64'(u_m4.bt_wdata[i]);
        5: d = 64'(u_m5.bt_wdata[i]);
        6: d = 64'(g_direct[0].u_m.bt_wdata[i]);
        default: d = 64'(g_direct[1].u_m.bt_wdata[i]);
      endcase
      sh_put(s, idx, d, stored_lanes(s, ln));
    end else begin
      cmp_lanes(s, idx, rd, ln, $sformatf("%s beat %0d", what, i));
    end
  end
endtask

// ---------------------------------------------------------------------------
// Side-band
// ---------------------------------------------------------------------------
function automatic logic [1:0] ack(input int sb, input int d);
  return pwr_ack[sb][2*d +: 2];
endfunction

task automatic set_mode(input int sb, input int d, input logic [1:0] mode);
  sb_cyc(sb, 1);
  pwr_req[sb][2*d +: 2] <= mode;
endtask

task automatic wait_mode(input int sb, input int d, input logic [1:0] mode,
                         output int unsigned cycles);
  cycles = 0;
  while (ack(sb, d) !== mode) begin
    sb_cyc(sb, 1);
    cycles++;
    if (cycles > 50000) fail($sformatf("%s domain %0d: no ack of mode %0d (req %0d, ack %0d, busy %b)",
                                      slv[a_slave[sb]].name, d, mode, pwr_req[sb][2*d +: 2],
                                      ack(sb, d), busy[sb]));
  end
endtask

// Request a mode on every domain and wait for all acks.
task automatic set_mode_all(input int sb, input logic [1:0] mode);
  int unsigned c;
  for (int d = 0; d < slv[a_slave[sb]].npd; d++) set_mode(sb, d, mode);
  for (int d = 0; d < slv[a_slave[sb]].npd; d++) wait_mode(sb, d, mode, c);
endtask

task automatic inject(input int sb, input logic [1:0] kind);
  sb_cyc(sb, 1);
  ecc_inj[sb] <= kind;
  sb_cyc(sb, 1);
  ecc_inj[sb] <= 2'b00;
endtask

// Wait (in the instance's clock) until busy_o is low.
task automatic wait_idle(input int sb);
  int unsigned c;
  c = 0;
  while (busy[sb] !== 1'b0) begin
    sb_cyc(sb, 1);
    if (++c > 200000) fail($sformatf("instance %0d stays busy", sb));
  end
endtask

// ---------------------------------------------------------------------------
// Setup and teardown
// ---------------------------------------------------------------------------
function automatic slv_t mk(input string name, input int m, input logic [31:0] base, input int w,
                            input int depth, input int sb, input bit ecc = 0, input bit be = 1,
                            input bit pwe = 1, input int rl = 1, input int npd = 1,
                            input bit bist = 0, input bit port_b = 0, input bit ro = 0,
                            input bit on_b = 0, input int peer = -1, input bit pg = 1);
  slv_t t;
  t.name = name; t.m = m; t.base = base; t.w = w; t.depth = depth; t.sb = sb; t.ecc = ecc;
  t.be = be; t.pwe = pwe; t.rl = rl; t.npd = npd; t.bist = bist; t.port_b = port_b;
  t.ro = ro; t.on_b = on_b; t.peer = peer; t.pg = pg;
  return t;
endfunction

task automatic tb_init();
  slv[SL_S32]  = mk("s32",  0, 32'h0000_0000, 32, 1024, SB_S32);
  slv[SL_S32E] = mk("s32e", 0, 32'h0001_0000, 32, 512,  SB_S32E, 1, 1, 1, 2, 2, 1);
  slv[SL_DP0A] = mk("dp0.A", 0, 32'h0002_0000, 32, 256, SB_DP0, 1, .bist(1), .peer(SL_DP0B));
  slv[SL_S8]   = mk("s8",   2, 32'h0000_0000, 8, 2048, SB_S8, .rl(2), .on_b(1));
  slv[SL_DP0B] = mk("dp0.B", 2, 32'h0001_0000, 8, 1024, SB_DP0, 1, .port_b(1), .ro(SKY130),
                    .on_b(1), .peer(SL_DP0A));
  slv[SL_S16]  = mk("s16",  3, 32'h0000_0000, 16, 4096, SB_S16, .be(0), .pwe(1));
  slv[SL_S16W] = mk("s16w", 3, 32'h0001_0000, 16, 64,   SB_S16W, .be(0), .pwe(0), .pg(0));
  slv[SL_DP1A] = mk("dp1.A", 3, 32'h0002_0000, 16, 1024, SB_DP1, .bist(1), .peer(SL_DP1B));
  slv[SL_S24]  = mk("s24",  4, 32'h0000_0000, 24, 256,  SB_S24, 1);
  slv[SL_S24B] = mk("s24b", 4, 32'h0001_0000, 24, 128,  SB_S24B, .npd(4));
  slv[SL_S64]  = mk("s64",  5, 32'h0000_0000, 64, 512,  SB_S64, 1, .rl(2), .bist(1));
  slv[SL_DP1B] = mk("dp1.B", 5, 32'h0001_0000, 64, 256, SB_DP1, .be(0), .pwe(1), .rl(2),
                    .bist(1), .port_b(1), .ro(SKY130), .peer(SL_DP1A));
  slv[SL_S32P] = mk("s32p", 6, 32'h0000_0000, 32, 256,  SB_S32P);
  slv[SL_S32Q] = mk("s32q", 7, 32'h0000_0000, 32, 256,  SB_S32Q, .rl(2));
  slv[SL_DP2A] = mk("dp2.A", 0, 32'h0003_0000, 32, 256,  SB_DP2, 1, .rl(2), .npd(2),
                    .peer(SL_DP2B));
  slv[SL_DP2B] = mk("dp2.B", 1, 32'h0004_0000, 32, 256,  SB_DP2, 1, .rl(2), .npd(2), .port_b(1),
                    .ro(SKY130), .peer(SL_DP2A));
  slv[SL_DP3A] = mk("dp3.A", 2, 32'h0002_0000, 8, 4096,  SB_DP3, .on_b(1), .peer(SL_DP3B));
  slv[SL_DP3B] = mk("dp3.B", 2, 32'h0003_0000, 8, 4096,  SB_DP3, .port_b(1), .ro(SKY130),
                    .on_b(1), .peer(SL_DP3A));
  for (int s = 0; s < NSL; s++) if (!slv[s].port_b) a_slave[slv[s].sb] = s;
  $display("%s: TECH = %0d (%s)", `TB_STR, TECH,
           TECH == 0 ? "GENERIC" : TECH == 3 ? "SAED90" : TECH == 4 ? "SAED32" :
           TECH == 5 ? "SAED14" : TECH == 6 ? "SKY130" : "other");
endtask

// Shadow after reset: ECC arrays are cleared, others unknown.
task automatic sh_reset();
  for (int sb = 0; sb < NSB; sb++) begin
    shadow[sb].delete();
    if (slv[a_slave[sb]].ecc) sh_fill(sb, 0, st_bytes(sb), 8'h00);
  end
endtask

task automatic reset_all();
  rst_a_n = 1'b0;
  rst_b_n = 1'b0;
  cyc_a(10);
  cyc_b(10);
  @(posedge clk_a) rst_a_n <= 1'b1;
  @(posedge clk_b) rst_b_n <= 1'b1;
  sh_reset();
  for (int sb = 0; sb < NSB; sb++) wait_idle(sb);
  cyc_a(4);
endtask

task automatic finish_all();
  int unsigned tot, mis;
  $display("\n=== reference models ===");
  tot = 0;
  mis = 0;
  for (int sb = 0; sb < NSB; sb++) begin
    $display("  %-6s responses checked %6d  mismatches %0d", slv[a_slave[sb]].name, n_chk[sb],
             n_mis[sb]);
    tot += n_chk[sb];
    mis += n_mis[sb];
  end
  if (mis != 0) begin
    $display("FAIL %s: %0d reference-model mismatches", `TB_STR, mis);
    $finish(1);
  end
  $display("\nPASS %s: %0d tests, %0d comparisons, %0d model-checked responses",
           `TB_STR, n_tests, n_cmp, tot);
  $finish;
endtask

// ---------------------------------------------------------------------------
// Backdoor (GENERIC only): stored words of the single-port ECC instances,
// through IP/common/verification/dpi/claude_backdoor.c. The reference model
// is told about every change (set_fault).
// ---------------------------------------------------------------------------
`ifdef VHDL_DUT
// VHDL storage: the VHPI entry points of the same helper
import "DPI-C" function string claude_bd_vget(input string path);
import "DPI-C" function int    claude_bd_vput(input string path, input string bits);
function automatic string bd_get(input string path);
  return claude_bd_vget(path);
endfunction
function automatic int bd_put(input string path, input string bits);
  return claude_bd_vput(path, bits);
endfunction
`else
import "DPI-C" function string claude_bd_get(input string path);
import "DPI-C" function int    claude_bd_put(input string path, input string bits);
function automatic string bd_get(input string path);
  return claude_bd_get(path);
endfunction
function automatic int bd_put(input string path, input string bits);
  return claude_bd_put(path, bits);
endfunction
`endif

// Leaf array word holding word idx of instance sb (GENERIC leaf, one per bank).
function automatic string bd_path(input int sb, input int idx);
  string u;
  int    bank_d, k;
  case (sb)
    SB_S32E: u = "u_s32e";
    SB_S24:  u = "u_s24";
    SB_S64:  u = "u_s64";
    default: u = "";
  endcase
  // s32e has 2 banks; the others 1
  bank_d = (sb == SB_S32E) ? slv[a_slave[sb]].depth / 2 : slv[a_slave[sb]].depth;
  k      = idx / bank_d;
`ifdef VHDL_DUT
  return $sformatf("%s.%s.u_core.u_array.gen_bank(%0d).gen_port.u_macro.gen_tech.u_leaf.mem(%0d)",
                   `TB_STR, u, k, idx % bank_d);
`else
  return $sformatf("%s.%s.u_core.u_array.g_bank[%0d].g_sp.u_macro.g_generic.u_leaf.mem[%0d]",
                   `TB_STR, u, k, idx % bank_d);
`endif
endfunction

// Flip stored bit `bitpos` (0 = LSB) of word idx; returns the stored width.
task automatic bd_flip(input int sb, input int idx, input int bitpos, output int mw);
  string p, v;
  p  = bd_path(sb, idx);
  v  = bd_get(p);
  mw = v.len();
  if (mw == 0) fail($sformatf("backdoor path not found: %s", p));
  v[mw - 1 - bitpos] = (v[mw - 1 - bitpos] == "1") ? "0" : "1";
  if (bd_put(p, v) == 0) fail($sformatf("backdoor deposit failed: %s", p));
  // A VHPI deposit on VCS is seen from the next delta cycle: wait for it, so
  // that the next backdoor read (or flip) sees the new value.
  for (int n = 0; n < 4 && bd_get(p) != v; n++) #0;
  if (bd_get(p) != v) fail($sformatf("backdoor deposit not visible: %s", p));
endtask

task automatic mdl_fault(input int sb, input int u, input logic [1:0] f);
  case (sb)
    SB_S32E: u_mdl_s32e.set_fault(u, f);
    SB_S24:  u_mdl_s24.set_fault(u, f);
    SB_S64:  u_mdl_s64.set_fault(u, f);
    default: ;
  endcase
endtask
