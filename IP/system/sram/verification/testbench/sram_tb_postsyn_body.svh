// sram_tb_postsyn_body.svh — Gate-level (post-synthesis) body of tb_sram_<proto>.
//
// `include'd by tb_sram_<proto>.sv instead of sram_tb_body.svh when
// +define+SRAM_POSTSYN is set (sim_sram.py --postsyn, Step 10). It uses the
// same wiring macros (XBAR_WIRES / LINK / MST / SLV / CLKRST) and master BFMs
// as the system bench, but drives the Design Compiler netlists, which
// cannot be re-parameterized and have no internal memory-bus signals for the
// system bench's reference models:
//
//   Instance  Netlist (define)  Configuration (run_vendor_synth.py)        Masters
//   u_base    `PS_BASE          32 x 1024, BYTE_EN, PWR_GATE               u_m0 (clk_a)
//   u_opts    `PS_OPTS          base + ECC, BANK_PG x2, BIST, RL2          u_m1 (clk_a)
//   u_dp      `PS_DP            opts + port B 8-bit on clk_b               u_m2 A (clk_a), u_m3 B (clk_b)
//                               (SAED14: one clock, clk_b = clk_a)
//
// Each SRAM is attached directly to its master (ADDR_W 32, the netlists'
// RTL default). The netlist names come from sim_sram.py (+define+PS_BASE=
// sram_apb, +define+PS_OPTS=sram_apb_opts, ...; the _vhdl netlists for the
// VHDL-synthesized set).
//
// Checking: every read is compared with a byte-level shadow memory in the
// bench (one per SRAM; the dual port's two ports share it, little-endian
// packing), and the side-band pulses are counted. Sequence, per SRAM:
//   access    full words at the corners and at random, sub-word writes (ECC:
//             read-modify-write), 16-beat back-to-back writes and reads,
//             out-of-range read and write -> bus error
//   ecc       (opts, dp) 1-bit injection -> corrected data + ecc_corr_o;
//             2-bit injection -> bus error + ecc_uncorr_o
//   power     per domain: LS (access wakes it), DS (access -> error,
//             contents kept), SD (cleared on wake; the other domain kept)
//   clear     clr_req_i -> clr_done_o, array reads zero
//   bist      (opts, dp) March C- passes, array reads zero
//   dp        port B reads of port-A words and port-A reads of port-B
//             writes (SKY130: port B is read-only, its writes get an error),
//             port B range error, both ports at once on different words
// The run passes when no check failed: "PASS <tb> postsyn ...".

  import sram_tb_pkg::TB_TECH_SKY130;
  import sram_tb_pkg::TB_TECH_SAED14;

  localparam int unsigned TECH   = `TECH;
  localparam bit          SKY130 = (TECH == TB_TECH_SKY130);
  localparam bit          SAED14 = (TECH == TB_TECH_SAED14);
  localparam bit          DP_CC  = SAED14;    // dp netlist COMMON_CLK
  localparam int unsigned SAW    = 32;        // netlist ADDR_W (RTL default)
  localparam int unsigned WORDS  = 1024;      // DEPTH of every netlist
  localparam int unsigned DOMW   = WORDS / 2; // words per power domain (opts, dp)
  localparam int unsigned NI     = 3;         // SRAM instances
  localparam int unsigned I_BASE = 0, I_OPTS = 1, I_DP = 2;
  localparam int unsigned M_B    = 3;         // master index of dp port B

  // -------------------------------------------------------------------------
  // Clocks and resets (as the system bench: clk_b 13.7 ns, unrelated)
  // -------------------------------------------------------------------------
  logic clk_a = 1'b0;
  logic clk_b = 1'b0;
  logic rst_a_n;
  logic rst_b_n;

  if (DP_CC) begin : g_one_clk
    always #5 begin
      clk_a = ~clk_a;
      clk_b = ~clk_b;
    end
  end else begin : g_two_clk
    always #5 clk_a = ~clk_a;
    always #6.85 clk_b = ~clk_b;
  end

  // -------------------------------------------------------------------------
  // Masters, one direct link per port
  // -------------------------------------------------------------------------
  `XBAR_WIRES(pb, 1, 1, 32)
  `XBAR_WIRES(po, 1, 1, 32)
  `XBAR_WIRES(pa, 1, 1, 32)
  `XBAR_WIRES(pq, 1, 1, 8)
  `LINK(pb)
  `LINK(po)
  `LINK(pa)
  `LINK(pq)
  `MST(u_m0, pb, 0, 32, clk_a)
  `MST(u_m1, po, 0, 32, clk_a)
  `MST(u_m2, pa, 0, 32, clk_a)
  `MST(u_m3, pq, 0, 8,  clk_b)

  // -------------------------------------------------------------------------
  // Side-band, one set per SRAM
  // -------------------------------------------------------------------------
  logic [3:0]  pwr_req    [NI];
  logic [3:0]  pwr_ack    [NI];
  logic        clr_req    [NI];
  logic        clr_done   [NI];
  logic        busy       [NI];
  logic        err_irq    [NI];
  logic [1:0]  ecc_inj    [NI];
  logic        ecc_corr   [NI];
  logic        ecc_uncorr [NI];
  logic        bist_start [NI];
  logic        bist_done  [NI];
  logic        bist_fail  [NI];
  logic [9:0]  bist_fail_addr [NI];

  initial begin
    for (int i = 0; i < NI; i++) begin
      pwr_req[i]    = '0;
      clr_req[i]    = 1'b0;
      ecc_inj[i]    = 2'b00;
      bist_start[i] = 1'b0;
    end
  end

`define PSB(N, NPD) \
  .pwr_mode_req_i(pwr_req[N][2*NPD-1:0]), .pwr_mode_ack_o(pwr_ack[N][2*NPD-1:0]), \
  .clr_req_i(clr_req[N]), .clr_done_o(clr_done[N]), .busy_o(busy[N]), .err_irq_o(err_irq[N]), \
  .ecc_inj_i(ecc_inj[N]), .ecc_corr_o(ecc_corr[N]), .ecc_uncorr_o(ecc_uncorr[N]), \
  .bist_start_i(bist_start[N]), .bist_done_o(bist_done[N]), .bist_fail_o(bist_fail[N]), \
  .bist_fail_addr_o(bist_fail_addr[N])

  // -------------------------------------------------------------------------
  // Netlists
  // -------------------------------------------------------------------------
  `PS_BASE u_base (
    `CLKRST(, clk_a, rst_a_n), `SLV(, pb, 0, 32), `PSB(I_BASE, 1));

  `PS_OPTS u_opts (
    `CLKRST(, clk_a, rst_a_n), `SLV(, po, 0, 32), `PSB(I_OPTS, 2));

  `PS_DP u_dp (
    `CLKRST(A_, clk_a, rst_a_n), `CLKRST(B_, clk_b, rst_b_n),
    `SLV(A_, pa, 0, 32), `SLV(B_, pq, 0, 8), `PSB(I_DP, 2));

  // -------------------------------------------------------------------------
  // Side-band pulse counters (all on clk_a: port A's domain)
  // -------------------------------------------------------------------------
  int unsigned n_corr      [NI];
  int unsigned n_uncorr    [NI];
  int unsigned n_irq       [NI];
  int unsigned n_clr_done  [NI];
  int unsigned n_bist_done [NI];

  always @(posedge clk_a) begin
    for (int i = 0; i < NI; i++) begin
      if (ecc_corr[i] === 1'b1)   n_corr[i]++;
      if (ecc_uncorr[i] === 1'b1) n_uncorr[i]++;
      if (err_irq[i] === 1'b1)    n_irq[i]++;
      if (clr_done[i] === 1'b1)   n_clr_done[i]++;
      if (bist_done[i] === 1'b1)  n_bist_done[i]++;
    end
  end

  // -------------------------------------------------------------------------
  // Bookkeeping
  // -------------------------------------------------------------------------
  int unsigned n_fail;
  int unsigned n_checks;
  string       cur;

  task automatic fail(input string msg);
    n_fail++;
    $display("FAIL [%s] %s at %0t", cur, msg, $time);
    if (n_fail >= 20) begin
      $display("FAIL %s postsyn: too many failures, stopping", `TB_STR);
      $finish(1);
    end
  endtask

  task automatic chk(input bit ok, input string msg);
    n_checks++;
    if (!ok) fail(msg);
  endtask

  task automatic cyc(input int unsigned n);
    repeat (n) @(posedge clk_a);
  endtask

  function automatic string iname(input int i);
    return (i == I_BASE) ? "base" : (i == I_OPTS) ? "opts" : "dp";
  endfunction

  // Shadow memory per SRAM: data and known lanes of every 32-bit word.
  logic [31:0] sh   [NI][WORDS];
  logic [3:0]  shv  [NI][WORDS];

  task automatic sh_put(input int i, input int w, input logic [31:0] d, input logic [3:0] lanes);
    for (int b = 0; b < 4; b++) begin
      if (lanes[b]) begin
        sh[i][w][8*b +: 8] = d[8*b +: 8];
        shv[i][w][b]       = 1'b1;
      end
    end
  endtask

  task automatic sh_zero(input int i, input int w0, input int w1);
    for (int w = w0; w <= w1; w++) begin
      sh[i][w]  = '0;
      shv[i][w] = 4'hF;
    end
  endtask

  // -------------------------------------------------------------------------
  // Transfers (m: 0..2 = port A of SRAM m, 3 = dp port B)
  // -------------------------------------------------------------------------
  task automatic xf(input int m, input logic we, input logic [31:0] addr, input logic [2:0] size,
                    input logic [31:0] wd, input logic [3:0] strb,
                    output logic [31:0] rd, output logic er);
    logic [7:0] rd8;
    case (m)
      0:       u_m0.single(we, addr, size, wd, strb, rd, er);
      1:       u_m1.single(we, addr, size, wd, strb, rd, er);
      2:       u_m2.single(we, addr, size, wd, strb, rd, er);
      default: begin
        u_m3.single(we, addr, size, wd[7:0], strb[0], rd8, er);
        rd = {24'h0, rd8};
      end
    endcase
  endtask

  // Write a whole 32-bit word through port A and record it.
  task automatic wr(input int i, input int w, input logic [31:0] d, input bit exp_err = 0);
    logic [31:0] rd;
    logic        er;
    xf(i, 1'b1, 32'(w) << 2, 3'd2, d, 4'hF, rd, er);
    chk(er === exp_err, $sformatf("%s write word %0d: err %b, expected %b", iname(i), w, er, exp_err));
    if (!exp_err) sh_put(i, w, d, 4'hF);
  endtask

  // Read a word through port A and compare its known lanes.
  task automatic rd_chk(input int i, input int w, input bit exp_err = 0);
    logic [31:0] rd;
    logic        er;
    xf(i, 1'b0, 32'(w) << 2, 3'd2, '0, 4'h0, rd, er);
    chk(er === exp_err, $sformatf("%s read word %0d: err %b, expected %b", iname(i), w, er, exp_err));
    if (!exp_err && er === 1'b0) begin
      for (int b = 0; b < 4; b++) begin
        if (shv[i][w][b]) chk(rd[8*b +: 8] === sh[i][w][8*b +: 8],
                              $sformatf("%s word %0d lane %0d: got %h, expected %h",
                                        iname(i), w, b, rd[8*b +: 8], sh[i][w][8*b +: 8]));
      end
    end
  endtask

  task automatic set_mode(input int i, input int d, input logic [1:0] mode);
    @(posedge clk_a);
    `TB_DRV; pwr_req[i][2*d +: 2] <= mode;
  endtask

  task automatic wait_mode(input int i, input int d, input logic [1:0] mode);
    int unsigned c;
    c = 0;
    while (pwr_ack[i][2*d +: 2] !== mode) begin
      cyc(1);
      if (++c > 50000) begin
        fail($sformatf("%s domain %0d: no ack of mode %0d (ack %b)", iname(i), d, mode,
                       pwr_ack[i][2*d +: 2]));
        return;
      end
    end
  endtask

  task automatic wait_idle(input int i);
    int unsigned c;
    c = 0;
    while (busy[i] !== 1'b0) begin
      cyc(1);
      if (++c > 400000) begin
        fail($sformatf("%s stays busy", iname(i)));
        return;
      end
    end
  endtask

  // Wait until a pulse counter moves past c0 (the engine finished).
  task automatic wait_cnt(ref int unsigned cnt, input int unsigned c0, input string what);
    int unsigned c;
    c = 0;
    while (cnt == c0) begin
      cyc(1);
      if (++c > 400000) begin
        fail($sformatf("no %s pulse", what));
        return;
      end
    end
  endtask

  // One-cycle side-band pulses (clk_a)
  task automatic pulse_clr(input int i);
    @(posedge clk_a);
    `TB_DRV; clr_req[i] <= 1'b1;
    @(posedge clk_a);
    `TB_DRV; clr_req[i] <= 1'b0;
  endtask

  task automatic pulse_bist(input int i);
    @(posedge clk_a);
    `TB_DRV; bist_start[i] <= 1'b1;
    @(posedge clk_a);
    `TB_DRV; bist_start[i] <= 1'b0;
  endtask

  // -------------------------------------------------------------------------
  // Tests
  // -------------------------------------------------------------------------
  task automatic t_access(input int i);
    int          ws [$];
    logic [31:0] rd;
    logic        er;
    int          w;
    logic [31:0] d;
    int unsigned irq0;
    cur = {iname(i), " access"};
    // corners, domain boundary and random words
    ws = '{0, 1, 2, 3, DOMW - 1, DOMW, WORDS - 2, WORDS - 1};
    repeat (24) ws.push_back($urandom_range(WORDS - 1));
    foreach (ws[k]) wr(i, ws[k], $urandom);
    foreach (ws[k]) rd_chk(i, ws[k]);
    // sub-word writes: bytes, then halfwords (ECC: read-modify-write)
    for (int k = 0; k < 8; k++) begin
      w = ws[k];
      for (int b = 0; b < 4; b++) begin
        d = $urandom;
        xf(i, 1'b1, (32'(w) << 2) + b, 3'd0, d, 4'(1 << b), rd, er);
        chk(er === 1'b0, $sformatf("byte write word %0d lane %0d: err %b", w, b, er));
        sh_put(i, w, d, 4'(1 << b));
        rd_chk(i, w);
      end
      d = $urandom;
      xf(i, 1'b1, (32'(w) << 2) + 2, 3'd1, d, 4'hC, rd, er);
      chk(er === 1'b0, $sformatf("halfword write word %0d: err %b", w, er));
      sh_put(i, w, d, 4'hC);
      rd_chk(i, w);
    end
    // 16 back-to-back writes, then 16 back-to-back reads
    w = 16 * $urandom_range(WORDS / 16 - 1);   // 64-byte aligned: no AHB 1 KB crossing
    burst16(i, 1'b1, w);
    burst16(i, 1'b0, w);
    // out of range: no write, bus error, err_irq_o
    irq0 = n_irq[i];
    xf(i, 1'b0, 32'(WORDS) << 2, 3'd2, '0, 4'h0, rd, er);
    chk(er === 1'b1, $sformatf("read past the end: err %b, expected 1", er));
    xf(i, 1'b1, (32'(WORDS) << 2) + 4, 3'd2, 32'hDEAD_BEEF, 4'hF, rd, er);
    chk(er === 1'b1, $sformatf("write past the end: err %b, expected 1", er));
    cyc(4);
    chk(n_irq[i] >= irq0 + 2, $sformatf("err_irq_o pulses %0d, expected 2", n_irq[i] - irq0));
    rd_chk(i, 0);
  endtask

  // 16 consecutive words from w, one beat list (back to back on the bus).
  task automatic burst16(input int i, input bit we, input int w);
    logic [31:0] d [16];
    logic [31:0] rd;
    logic        er;
    for (int k = 0; k < 16; k++) d[k] = $urandom;
    case (i)
      0: begin
        for (int k = 0; k < 16; k++) u_m0.set_beat(k, we, 32'(w + k) << 2, 3'd2, (k == 0) ? 2'b10 : 2'b11,
                                                   3'd1, d[k], 4'hF);
        u_m0.run_beats(16);
      end
      1: begin
        for (int k = 0; k < 16; k++) u_m1.set_beat(k, we, 32'(w + k) << 2, 3'd2, (k == 0) ? 2'b10 : 2'b11,
                                                   3'd1, d[k], 4'hF);
        u_m1.run_beats(16);
      end
      default: begin
        for (int k = 0; k < 16; k++) u_m2.set_beat(k, we, 32'(w + k) << 2, 3'd2, (k == 0) ? 2'b10 : 2'b11,
                                                   3'd1, d[k], 4'hF);
        u_m2.run_beats(16);
      end
    endcase
    for (int k = 0; k < 16; k++) begin
      case (i)
        0:       begin rd = u_m0.bt_rdata[k]; er = u_m0.bt_err[k]; end
        1:       begin rd = u_m1.bt_rdata[k]; er = u_m1.bt_err[k]; end
        default: begin rd = u_m2.bt_rdata[k]; er = u_m2.bt_err[k]; end
      endcase
      chk(er === 1'b0, $sformatf("burst %s beat %0d: err %b", we ? "write" : "read", k, er));
      if (we) sh_put(i, w + k, d[k], 4'hF);
      else if (shv[i][w + k] == 4'hF)
        chk(rd === sh[i][w + k], $sformatf("burst read word %0d: got %h, expected %h",
                                          w + k, rd, sh[i][w + k]));
    end
  endtask

  task automatic t_ecc(input int i);
    int          w;
    logic [31:0] d, rd;
    logic        er;
    int unsigned c0, u0;
    cur = {iname(i), " ecc"};
    w = $urandom_range(WORDS - 1);
    // 1-bit error: corrected, ecc_corr_o
    c0 = n_corr[i];
    @(posedge clk_a); `TB_DRV; ecc_inj[i] <= 2'b01;
    @(posedge clk_a); `TB_DRV; ecc_inj[i] <= 2'b00;
    d = $urandom;
    wr(i, w, d);
    rd_chk(i, w);
    cyc(4);
    chk(n_corr[i] > c0, "1-bit injected error: no ecc_corr_o pulse");
    // 2-bit error: bus error, ecc_uncorr_o
    u0 = n_uncorr[i];
    @(posedge clk_a); `TB_DRV; ecc_inj[i] <= 2'b10;
    @(posedge clk_a); `TB_DRV; ecc_inj[i] <= 2'b00;
    wr(i, w, $urandom);
    xf(i, 1'b0, 32'(w) << 2, 3'd2, '0, 4'h0, rd, er);
    chk(er === 1'b1, $sformatf("2-bit injected error: read err %b, expected 1", er));
    cyc(4);
    chk(n_uncorr[i] > u0, "2-bit injected error: no ecc_uncorr_o pulse");
    wr(i, w, $urandom);       // clean word again
    rd_chk(i, w);
  endtask

  task automatic t_power(input int i);
    int npd, w, wo;
    cur = {iname(i), " power"};
    npd = (i == I_BASE) ? 1 : 2;
    for (int d = 0; d < npd; d++) begin
      w  = (npd == 1) ? $urandom_range(WORDS - 1) : d * DOMW + $urandom_range(DOMW - 1);
      wo = (npd == 1) ? -1 : (1 - d) * DOMW + $urandom_range(DOMW - 1);
      wr(i, w, $urandom);
      if (wo >= 0) wr(i, wo, $urandom);
      // light sleep: an access wakes the domain, contents kept
      set_mode(i, d, 2'd1);
      wait_mode(i, d, 2'd1);
      cyc(20);
      rd_chk(i, w);
      set_mode(i, d, 2'd0);
      wait_mode(i, d, 2'd0);
      // deep sleep: access is an error, contents kept
      set_mode(i, d, 2'd2);
      wait_mode(i, d, 2'd2);
      rd_chk(i, w, 1'b1);
      if (wo >= 0) rd_chk(i, wo);          // the other domain keeps working
      set_mode(i, d, 2'd0);
      wait_mode(i, d, 2'd0);
      wait_idle(i);
      rd_chk(i, w);
      // shutdown: cleared on wake, the other domain kept
      set_mode(i, d, 2'd3);
      wait_mode(i, d, 2'd3);
      rd_chk(i, w, 1'b1);
      set_mode(i, d, 2'd0);
      wait_mode(i, d, 2'd0);
      wait_idle(i);
      if (npd == 1) sh_zero(i, 0, WORDS - 1);
      else          sh_zero(i, d * DOMW, d * DOMW + DOMW - 1);
      rd_chk(i, w);
      if (wo >= 0) rd_chk(i, wo);
    end
  endtask

  task automatic t_clear(input int i);
    int unsigned c0;
    int ws [4];
    cur = {iname(i), " clear"};
    ws = '{0, $urandom_range(WORDS - 1), $urandom_range(WORDS - 1), WORDS - 1};
    foreach (ws[k]) wr(i, ws[k], $urandom | 32'h1);
    c0 = n_clr_done[i];
    pulse_clr(i);
    wait_cnt(n_clr_done[i], c0, "clr_done_o");   // busy_o may rise a cycle or two later
    wait_idle(i);
    cyc(4);
    chk(n_clr_done[i] == c0 + 1, $sformatf("clr_done_o pulses %0d, expected 1", n_clr_done[i] - c0));
    sh_zero(i, 0, WORDS - 1);
    foreach (ws[k]) rd_chk(i, ws[k]);
  endtask

  task automatic t_bist(input int i);
    int unsigned c0;
    cur = {iname(i), " bist"};
    wr(i, 5, $urandom);
    c0 = n_bist_done[i];
    pulse_bist(i);
    wait_cnt(n_bist_done[i], c0, "bist_done_o");
    wait_idle(i);
    cyc(4);
    chk(n_bist_done[i] == c0 + 1, $sformatf("bist_done_o pulses %0d, expected 1", n_bist_done[i] - c0));
    chk(bist_fail[i] === 1'b0, $sformatf("bist_fail_o %b at word %0d", bist_fail[i], bist_fail_addr[i]));
    sh_zero(i, 0, WORDS - 1);           // the march leaves the array all-zero
    rd_chk(i, 5);
    rd_chk(i, WORDS - 1);
  endtask

  // Port B (8-bit): byte j of the array = lane j % 4 of word j / 4.
  task automatic rd_b(input int j, input bit exp_err = 0);
    logic [31:0] rd;
    logic        er;
    int          w, b;
    w = j / 4;
    b = j % 4;
    xf(M_B, 1'b0, 32'(j), 3'd0, '0, 4'h0, rd, er);
    chk(er === exp_err, $sformatf("port B read byte %0d: err %b, expected %b", j, er, exp_err));
    if (!exp_err && er === 1'b0 && shv[I_DP][w][b])
      chk(rd[7:0] === sh[I_DP][w][8*b +: 8],
          $sformatf("port B byte %0d: got %h, expected %h", j, rd[7:0], sh[I_DP][w][8*b +: 8]));
  endtask

  task automatic wr_b(input int j, input logic [7:0] d);
    logic [31:0] rd;
    logic        er;
    xf(M_B, 1'b1, 32'(j), 3'd0, {24'h0, d}, 4'h1, rd, er);
    if (SKY130) begin
      chk(er === 1'b1, $sformatf("SKY130 port B write byte %0d: err %b, expected 1 (read-only)", j, er));
    end else begin
      chk(er === 1'b0, $sformatf("port B write byte %0d: err %b", j, er));
      if (er === 1'b0) sh_put(I_DP, j / 4, {4{d}}, 4'(1 << (j % 4)));
    end
  endtask

  task automatic t_dp();
    int w, j;
    cur = "dp ports";
    // A writes, B reads every byte
    for (int k = 0; k < 8; k++) begin
      w = $urandom_range(WORDS - 1);
      wr(I_DP, w, $urandom);
      for (int b = 0; b < 4; b++) rd_b(4 * w + b);
    end
    // B writes, A reads
    for (int k = 0; k < 8; k++) begin
      j = $urandom_range(4 * WORDS - 1);
      wr_b(j, 8'($urandom));
      rd_chk(I_DP, j / 4);
      rd_b(j);
    end
    // B range error
    rd_b(4 * WORDS, 1'b1);
    // B under A's side-band: DS -> error, LS -> a B access wakes the domain
    w = $urandom_range(DOMW - 1);
    wr(I_DP, w, $urandom);
    set_mode(I_DP, 0, 2'd2);
    wait_mode(I_DP, 0, 2'd2);
    rd_b(4 * w, 1'b1);
    set_mode(I_DP, 0, 2'd1);
    wait_mode(I_DP, 0, 2'd1);
    cyc(20);
    rd_b(4 * w + 1);
    set_mode(I_DP, 0, 2'd0);
    wait_mode(I_DP, 0, 2'd0);
    wait_idle(I_DP);
    // both ports at once, on different words (A: words 0..63, B: bytes of 512..575)
    fork
      begin
        for (int k = 0; k < 64; k++) wr(I_DP, k, $urandom);
        for (int k = 0; k < 64; k++) rd_chk(I_DP, k);
      end
      begin
        for (int k = 0; k < 64; k++) wr_b(4 * (DOMW + k) + (k % 4), 8'($urandom));
        for (int k = 0; k < 64; k++) rd_b(4 * (DOMW + k) + (k % 4));
      end
    join
  endtask

  // -------------------------------------------------------------------------
  // Sequence
  // -------------------------------------------------------------------------
`ifdef VCS
  initial if ($test$plusargs("waves")) $vcdpluson(0, `TB_NAME);
`endif

  // +saif (sim_sram.py --power, Step 12): backward SAIF per netlist instance,
  // recorded by VCS from the end of reset (and the post-reset clear) to the end
  // of the sequence, written as saif_base.saif / saif_opts.saif / saif_dp.saif.
  bit saif_on;
  initial begin
    saif_on = $test$plusargs("saif");
`ifdef VCS
    if (saif_on) begin
      $set_gate_level_monitoring("on");
      $set_toggle_region(u_base, u_opts, u_dp);
    end
`endif
  end

  task automatic saif_start();
`ifdef VCS
    if (saif_on) $toggle_start();
`endif
  endtask

  task automatic saif_stop();
`ifdef VCS
    if (saif_on) begin
      $toggle_stop();
      $toggle_report("saif_base.saif", 1.0e-9, u_base);
      $toggle_report("saif_opts.saif", 1.0e-9, u_opts);
      $toggle_report("saif_dp.saif", 1.0e-9, u_dp);
    end
`endif
  endtask

  initial begin
    n_fail   = 0;
    n_checks = 0;
    cur      = "reset";
    for (int i = 0; i < NI; i++)
      for (int w = 0; w < WORDS; w++) begin
        sh[i][w]  = 'x;
        shv[i][w] = 4'h0;
      end
    rst_a_n = 1'b0;
    rst_b_n = 1'b0;
    repeat (8) @(posedge clk_b);
    cyc(8);
    rst_a_n = 1'b1;
    rst_b_n = 1'b1;
    cyc(4);
    // ECC netlists clear the array after reset
    for (int i = 0; i < NI; i++) wait_idle(i);
    sh_zero(I_OPTS, 0, WORDS - 1);
    sh_zero(I_DP, 0, WORDS - 1);
    saif_start();
    $display("[postsyn] %s: base / opts / dp netlists, TECH %0d", `TB_STR, TECH);
    for (int i = 0; i < NI; i++) t_access(i);
    t_ecc(I_OPTS);
    t_ecc(I_DP);
    for (int i = 0; i < NI; i++) t_power(i);
    for (int i = 0; i < NI; i++) t_clear(i);
    t_bist(I_OPTS);
    t_bist(I_DP);
    t_dp();
    cyc(10);
    saif_stop();
    if (n_fail == 0) $display("PASS %s postsyn: %0d checks", `TB_STR, n_checks);
    else             $display("FAIL %s postsyn: %0d of %0d checks failed", `TB_STR, n_fail, n_checks);
    $finish;
  end

  initial begin
    #50ms;
    $display("FAIL %s postsyn: global timeout", `TB_STR);
    $finish(1);
  end
