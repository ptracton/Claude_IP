// sram_scoreboard.sv — Bus-level reference model and checker of the sram UVM bench.
//
// Inputs: every completed beat of each bus port (sram_bus_monitor) and every
// side-band event (sram_sb_monitor). Monitors report at clock edges; the
// scoreboard queues what arrives, waits until the time step is over, then
// processes it in time order with side-band events before bus beats of the
// same edge (an access that a side-band event of that edge could affect is
// stalled until after it, or ambiguous; see below).
//
// Model (the rules of sram_model, at the bus):
//   - storage: one byte per storage byte (both ports of a dual port address
//     the same bytes, little-endian), known / unknown. ECC_EN: zero after
//     reset; otherwise unknown.
//   - errors: beyond the port's span; requested power mode DS or SD at the
//     grant (PWR_GATE); write to a read-only port B; ECC uncorrectable
//     codeword on a read or on a read-modify-write that writes it back.
//   - shutdown: acknowledged SD -> domain unknown; SD -> RUN -> domain zero.
//   - clr_req: domains requested RUN / LS at the request are zero at
//     clr_done. BIST: everything zero at bist_done; bist_fail as the fault
//     knob predicts.
//   - ECC: injection armed by ecc_inj, consumed by the next port-A write
//     that reaches the array (lands in that word's first codeword, 1 = single
//     = corrected on read, 2 = double = error until rewritten).
//   - status counts (single-clock configs): err_irq high cycles = error
//     responses + corrected checks; ecc_corr / ecc_uncorr = corrected /
//     uncorrectable checks. Separate clocks: port-B pulses merge, so only
//     "not more than predicted, at least one if any" is checked.
//
// Ambiguity (counted, not compared):
//   - a requested-mode change of the beat's domain inside (start - guard,
//     end]: either response is accepted (guard = 0 for port A; a few cycles
//     of both clocks for port B on its own clock);
//   - a clear / BIST request inside [start, end]: the beat may have been
//     granted before the engine; a read is not compared, a write's bytes
//     become unknown.
// The sequences keep ECC injection away from in-flight port-A traffic; an
// ambiguous injection is reported as an error (the test, not the DUT, broke
// the rule).

`ifndef SRAM_SCOREBOARD_SV
`define SRAM_SCOREBOARD_SV

`uvm_analysis_imp_decl(_bus)
`uvm_analysis_imp_decl(_sb)

class sram_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(sram_scoreboard)

  uvm_analysis_imp_bus #(sram_bus_item, sram_scoreboard) bus_export;
  uvm_analysis_imp_sb  #(sram_sb_event, sram_scoreboard) sb_export;

  sram_uvm_cfg       cfg;
  virtual sram_sb_if sb_vif;
  sram_coverage      cov;           // set by the env (may stay null)

  // ---- model state -----------------------------------------------------------
  logic [7:0]  mem   [];
  bit          kn    [];
  int unsigned fault [];        // per codeword: 0 none, 1 single, 2 double
  sram_src_e   src   [];        // where each byte's value came from (coverage)
  int unsigned wport [];        // port that wrote it
  int unsigned cw_bytes;

  typedef struct {
    realtime     t;
    int unsigned val;
  } chg_t;
  chg_t        req_hist [4][$];  // requested-mode changes per domain
  int unsigned req_now  [4];
  int unsigned ack_now  [4];

  bit [1:0]    inj_armed;
  realtime     inj_t;
  bit [3:0]    clr_mask;
  bit          clr_open;
  bit          bist_open;
  bit          bist_fault_on;
  int unsigned bist_fault_addr;
  realtime     eng_t [$];        // clear / BIST request times
  bit          knob_on;         // read-path fault knob (stuck data bit of one word)
  int unsigned knob_word, knob_bit;
  bit          knob_val;
  int unsigned clr_modes;       // requested modes at the clear request (bit per mode)
  int unsigned eng_beats;       // beats completed while an engine was requested

  // per port, for coverage
  realtime     prev_end   [2];
  realtime     prev_start [2];
  bit [31:0]   prev_addr  [2];

  // ---- pending inputs ------------------------------------------------------------
  typedef struct {
    realtime      t;
    int unsigned  pri;          // 0 side band, 1 bus
    int unsigned  seq;
    sram_bus_item it;
    sram_sb_event ev;
  } in_t;
  in_t         inq [$];
  int unsigned in_seq;
  event        in_ev;

  // ---- statistics --------------------------------------------------------------
  int unsigned n_beats [2];
  int unsigned n_rd_cmp;        // reads with at least one byte compared
  int unsigned n_bytes_cmp;
  int unsigned n_err_ok;        // predicted error responses seen
  int unsigned n_amb_pwr;
  int unsigned n_amb_eng;
  int unsigned n_mis;
  int unsigned exp_irq, exp_corr, exp_uncorr;
  int unsigned obs_irq, obs_corr, obs_uncorr;
  int unsigned n_bist [2];      // pass / fail runs
  bit          cnt_amb;         // an engine overlapped a faulty codeword's check

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    bus_export = new("bus_export", this);
    sb_export  = new("sb_export", this);
    if (!uvm_config_db #(sram_uvm_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("SB", "no sram_uvm_cfg (cfg)")
    end
    if (!uvm_config_db #(virtual sram_sb_if)::get(this, "", "sb_vif", sb_vif)) begin
      `uvm_fatal("SB", "no virtual interface (sb_vif)")
    end
    mem      = new [cfg.total_bytes];
    kn       = new [cfg.total_bytes];
    src      = new [cfg.total_bytes];
    wport    = new [cfg.total_bytes];
    cw_bytes = cfg.dual_port ? ((cfg.width[1] < cfg.width[0]) ? cfg.width[1] : cfg.width[0]) / 8
                             : cfg.width[0] / 8;
    fault    = new [cfg.total_bytes / cw_bytes];
    for (int unsigned i = 0; i < cfg.total_bytes; i++) begin
      mem[i]   = cfg.ecc ? 8'h00 : 8'hxx;
      kn[i]    = cfg.ecc;
      src[i]   = SrcInit;
      wport[i] = 0;
    end
    prev_end   = '{default: -1.0};
    prev_start = '{default: -1.0};
    foreach (fault[i]) fault[i] = 0;
    for (int unsigned d = 0; d < 4; d++) begin
      req_now[d] = 0;
      ack_now[d] = 0;
    end
  endfunction

  // ---- input ---------------------------------------------------------------------
  function void write_bus(sram_bus_item it);
    in_t x;
    x.t   = it.t_end;
    x.pri = 1;
    x.seq = in_seq++;
    x.it  = it;
    x.ev  = null;
    inq.push_back(x);
    ->in_ev;
  endfunction

  function void write_sb(sram_sb_event ev);
    in_t x;
    x.t   = ev.t;
    x.pri = 0;
    x.seq = in_seq++;
    x.it  = null;
    x.ev  = ev;
    inq.push_back(x);
    ->in_ev;
  endfunction

  task run_phase(uvm_phase phase);
    forever begin
      @(in_ev);
      #1ps;                     // every monitor of this time step has reported
      drain();
    end
  endtask

  function void drain();
    in_t x;
    inq.sort() with ({64'($rtoi(item.t * 1000.0)), 32'(item.pri), 32'(item.seq)});  // ps
    while (inq.size() > 0) begin
      x = inq.pop_front();
      if (x.ev != null) do_event(x.ev);
      else do_beat(x.it);
    end
  endfunction

  // ---- helpers ---------------------------------------------------------------------
  function void fill_domain(int unsigned d, bit known, sram_src_e why = SrcClear);
    int unsigned per;
    per = cfg.total_bytes / cfg.npd;
    for (int unsigned i = d * per; i < (d + 1) * per; i++) begin
      mem[i] = known ? 8'h00 : 8'hxx;
      kn[i]  = known;
      src[i] = why;
      fault[i / cw_bytes] = 0;
    end
  endfunction

  // Requested mode of domain d at time t (last change at or before t).
  function int unsigned req_at(int unsigned d, realtime t);
    int unsigned v;
    v = 0;
    foreach (req_hist[d][i]) begin
      if (req_hist[d][i].t <= t) v = req_hist[d][i].val;
    end
    return v;
  endfunction

  function bit req_changed(int unsigned d, realtime t0, realtime t1);
    foreach (req_hist[d][i]) begin
      if (req_hist[d][i].t > t0 && req_hist[d][i].t <= t1) return 1'b1;
    end
    return 1'b0;
  endfunction

  function realtime guard(int unsigned p);
    if (p == 0 || cfg.single_clk()) return 0;
    return 4 * cfg.clk_period[0] + 4 * cfg.clk_period[1];
  endfunction

  function bit eng_overlap(realtime t0, realtime t1);
    foreach (eng_t[i]) begin
      if (eng_t[i] >= t0 && eng_t[i] <= t1) return 1'b1;
    end
    return 1'b0;
  endfunction

  // err_irq_o is the OR of both ports' registered pulses (one cycle after
  // each response): events on the same edge are one pulse cycle. Count
  // response edges, not events (exact on one clock; with separate clocks
  // port B's pulses are also merged by the synchronizer, checked loosely).
  bit irq_edge [longint];

  function void irq_at(realtime t);
    longint k;
    k = $rtoi(t * 1000.0);
    if (!irq_edge.exists(k)) begin
      irq_edge[k] = 1'b1;
      exp_irq++;
    end
  endfunction

  function void mismatch(string msg);
    n_mis++;
    `uvm_error("SB", msg)
  endfunction

  // ---- side band -------------------------------------------------------------------
  function void do_event(sram_sb_event ev);
    chg_t c;
    case (ev.kind)
      EvReq: begin
        c.t   = ev.t;
        c.val = ev.val;
        req_hist[ev.dom].push_back(c);
        req_now[ev.dom] = ev.val;
        if (cov != null) cov.sample_pwr(ev.dom, ev.old, ev.val);
      end
      EvAck: begin
        if (ev.val == 3 && ev.old != 3) fill_domain(ev.dom, 1'b0);
        if (ev.val == 0 && ev.old == 3) fill_domain(ev.dom, 1'b1, SrcWake);
        ack_now[ev.dom] = ev.val;
      end
      EvClrReq: begin
        clr_modes = 0;
        for (int unsigned d = 0; d < cfg.npd; d++) begin
          if (!cfg.pwr_gate || req_now[d] <= 1) clr_mask[d] = 1'b1;
          clr_modes |= 1 << req_now[d];
        end
        if (!clr_open) eng_beats = 0;
        clr_open = 1'b1;
        eng_t.push_back(ev.t);
      end
      EvClrDone: begin
        for (int unsigned d = 0; d < cfg.npd; d++) if (clr_mask[d]) fill_domain(d, 1'b1);
        clr_mask = '0;
        clr_open = 1'b0;
        if (cov != null) cov.sample_clr(clr_modes, eng_beats > 0);
      end
      EvBistStart: begin
        bist_open       = 1'b1;
        eng_beats       = 0;
        bist_fault_on   = sb_vif.bf_on;
        bist_fault_addr = sb_vif.bf_addr;
        eng_t.push_back(ev.t);
      end
      EvBistDone: begin
        for (int unsigned d = 0; d < cfg.npd; d++) fill_domain(d, 1'b1, SrcBist);
        bist_open = 1'b0;
        n_bist[ev.fail]++;
        if (cov != null) cov.sample_bist(ev.fail, eng_beats > 0);
        if (ev.fail != bist_fault_on) begin
          mismatch($sformatf("BIST: fail = %0b, expected %0b", ev.fail, bist_fault_on));
        end else if (ev.fail && ev.fail_addr != bist_fault_addr) begin
          mismatch($sformatf("BIST: fail_addr = %0d, expected %0d", ev.fail_addr,
                             bist_fault_addr));
        end
      end
      EvInj: begin
        if (cfg.ecc) begin
          inj_armed = inj_armed | 2'(ev.val);
          inj_t     = ev.t;
        end
      end
      EvFault: begin
        knob_on   = ev.val;
        knob_word = ev.dom;
        knob_bit  = ev.old;
        knob_val  = ev.fail;
      end
      EvIrq:    obs_irq++;
      EvCorr:   obs_corr++;
      EvUncorr: obs_uncorr++;
      default: ;
    endcase
  endfunction

  // ---- bus beat --------------------------------------------------------------------
  function void do_beat(sram_bus_item it);
    sram_beat_info bi;
    int unsigned   p, nb, idx, q;
    bit            full, none;
    p  = it.port;
    q  = 1 - p;
    nb = cfg.bytes_per_word(p);
    idx = it.addr / cfg.stride[p];
    bi            = new();
    bi.port       = p;
    bi.we         = it.we;
    bi.size       = it.size;
    bi.err        = it.err;
    bi.cause      = CauseNone;
    bi.ecc        = EccNone;
    bi.src_valid  = 1'b0;
    bi.region     = (it.addr >= cfg.span(p)) ? RegOor :
                    (idx == 0)               ? RegFirst :
                    (idx == cfg.depth[p] - 1) ? RegLast : RegMiddle;
    full = 1'b1;
    none = 1'b1;
    for (int unsigned b = 0; b < nb; b++) begin
      if (!it.be[b]) full = 1'b0;
      else none = 1'b0;
    end
    bi.strb       = full ? StrbFull : none ? StrbNone : StrbPartial;
    bi.gap        = (prev_end[p] < 0)                             ? GapIdle :
                    (it.t_start < prev_end[p])                     ? GapOverlap :
                    (it.t_start <= prev_end[p] + cfg.clk_period[p]) ? GapB2b : GapIdle;
    bi.ahb_beat   = it.beat;
    bi.ahb_wrap   = (it.beat > 0) && (it.addr < prev_addr[p]);
    bi.ahb_busy   = (it.busy.size() > 0) ? it.busy[0] : 0;
    bi.axi_overlap = it.overlap;
    bi.both_ports = cfg.dual_port && (prev_end[q] >= it.t_start);
    bi.lane       = (p == 1) ? idx % (cfg.width[0] / cfg.width[1]) : 0;
    check_beat(it, bi);
    if (cov != null) cov.sample_beat(bi);
    prev_end[p]   = it.t_end;
    prev_start[p] = it.t_start;
    prev_addr[p]  = it.addr;
    if (clr_open || bist_open) eng_beats++;
  endfunction

  function void check_beat(sram_bus_item it, sram_beat_info bi);
    int unsigned p, nb, idx, pos0, d, cw0, ncw;
    bit          oor, pwr_amb, eng_amb, exp_err, stat_err, pwr_err, full, any;
    int unsigned rq;
    bit [7:0]    touch_cw;
    string       what;

    p  = it.port;
    nb = cfg.bytes_per_word(p);
    n_beats[p]++;
    oor  = (it.addr >= cfg.span(p));
    idx  = it.addr / cfg.stride[p];
    pos0 = oor ? 0 : cfg.storage_byte(p, idx, 0);
    d    = cfg.domain_of(pos0);

    // Power: requested mode at the grant
    pwr_amb = !oor && cfg.pwr_gate && req_changed(d, it.t_start - guard(p), it.t_end);
    rq      = req_at(d, it.t_start);
    eng_amb = eng_overlap(it.t_start, it.t_end);

    // Codewords covered by this word (ECC)
    cw0 = pos0 / cw_bytes;
    ncw = (nb > cw_bytes) ? nb / cw_bytes : 1;
    full = 1'b1;
    for (int unsigned b = 0; b < nb; b++) if (!it.be[b]) full = 1'b0;

    // Errors decided before the array: range, port options, power mode
    stat_err = 1'b0;
    what     = "";
    if (oor) begin
      stat_err = 1'b1;
      what     = "out of range";
    end else if (it.we && cfg.read_only[p]) begin
      stat_err = 1'b1;
      what     = "read-only port";
    end else if (it.we && !cfg.byte_en[p] && !full) begin
      stat_err = 1'b1;
      what     = "partial write";
    end
    pwr_err = !oor && cfg.pwr_gate && (rq >= 2);
    if (pwr_amb) pwr_err = !stat_err && (it.err === 1'b1);   // either outcome is legal
    if (pwr_err && !stat_err) what = "power mode";
    exp_err = stat_err || pwr_err;
    bi.mode = rq;
    bi.amb  = pwr_amb || eng_amb;
    bi.cause = oor ? CauseOor : (it.we && cfg.read_only[p]) ? CauseRo :
               pwr_err ? CausePower : CauseNone;

    // ECC check of the stored codewords (reads, and read-modify-writes)
    if (cfg.ecc && !exp_err) begin
      bit rmw, s, dbl;
      rmw      = 1'b0;
      touch_cw = '0;
      for (int unsigned k = 0; k < ncw; k++) begin
        bit t, pt;
        t  = 1'b0;
        pt = 1'b0;
        for (int unsigned b = 0; b < cw_bytes; b++) begin
          if (it.be[k * cw_bytes + b]) t = 1'b1; else pt = 1'b1;
        end
        touch_cw[k] = t;
        if (t && pt) rmw = 1'b1;
      end
      rmw = rmw && cfg.byte_en[p];
      if (!it.we || rmw) begin
        s   = 1'b0;
        dbl = 1'b0;
        for (int unsigned k = 0; k < ncw; k++) begin
          if (!it.we || touch_cw[k]) begin
            if (fault[cw0 + k] == 2) dbl = 1'b1;
            if (fault[cw0 + k] == 1) s = 1'b1;
          end
        end
        // Read-path fault knob: the stuck data bit is an extra error when the
        // stored bit differs. With an injected single error (stored bit 0 of
        // the codeword flipped) the two add up: knob on bit 0 replaces it,
        // another bit makes a double error. Anything else is ambiguous.
        if (knob_on && p == 0 && idx == knob_word) begin
          int unsigned kb, kc, kp, nerr;
          bit          flip;
          kb = knob_bit / 8;
          kc = kb / cw_bytes;
          kp = cfg.storage_byte(0, idx, kb);
          if (!it.we || touch_cw[kc]) begin
            flip = kn[kp] && (mem[kp][knob_bit % 8] != knob_val);
            if (!kn[kp] || fault[cw0 + kc] == 2 || (fault[cw0 + kc] == 1 && kc != 0)) begin
              cnt_amb = 1'b1;
              dbl     = (it.err === 1'b1);
              s       = 1'b0;
            end else begin
              if (fault[cw0 + kc] == 0) nerr = flip;
              else if (knob_bit == 0) nerr = flip;           // the knob overrides bit 0
              else nerr = 1 + flip;
              s   = (nerr == 1);
              dbl = (nerr == 2);
            end
          end
        end
        if (eng_amb && (s || dbl)) begin
          // granted before or after the engine rewrote the codeword
          cnt_amb = 1'b1;
          dbl     = (it.err === 1'b1);
          s       = 1'b0;
        end
        if (dbl) begin
          exp_err  = 1'b1;
          what     = it.we ? "uncorrectable RMW" : "uncorrectable read";
          exp_uncorr++;
          bi.cause = CauseEcc;
          bi.ecc   = it.we ? EccUncRmw : EccUncRead;
        end else if (s) begin
          exp_corr++;
          irq_at(it.t_end);
          bi.ecc   = it.we ? EccCorrRmw : EccCorrRead;
        end
      end
    end

    // ---- response -------------------------------------------------------------------
    if (pwr_amb) begin
      n_amb_pwr++;
    end else if (it.err !== exp_err) begin
      mismatch($sformatf("%s: err = %0b, expected %0b%s", it.convert2string(), it.err, exp_err,
                         exp_err ? {" (", what, ")"} : ""));
    end else if (exp_err) begin
      n_err_ok++;
    end
    if (it.err === 1'b1) irq_at(it.t_end);
    if (it.err === 1'b1) return;

    if (eng_amb) n_amb_eng++;

    // ---- read data ----------------------------------------------------------------
    if (!it.we) begin
      if (eng_amb) return;
      any = 1'b0;
      for (int unsigned b = 0; b < nb; b++) begin
        int unsigned pos;
        if (!it.be[b]) continue;
        pos = cfg.storage_byte(p, idx, b);
        if (!kn[pos]) continue;
        if (!any) begin
          bi.src_valid = 1'b1;
          bi.src       = (src[pos] == SrcWrite && wport[pos] != p) ? SrcOther : src[pos];
        end
        any = 1'b1;
        n_bytes_cmp++;
        if (it.rdata[8*b +: 8] !== mem[pos]) begin
          mismatch($sformatf("%s: byte %0d = 0x%02x, expected 0x%02x", it.convert2string(), b,
                             it.rdata[8*b +: 8], mem[pos]));
          break;
        end
      end
      if (any) n_rd_cmp++;
      return;
    end

    // ---- write ------------------------------------------------------------------------
    for (int unsigned b = 0; b < nb; b++) begin
      int unsigned pos;
      if (cfg.byte_en[p] && !it.be[b]) continue;
      pos      = cfg.storage_byte(p, idx, b);
      mem[pos]   = eng_amb ? 8'hxx : it.wdata[0][8*b +: 8];
      kn[pos]    = !eng_amb;
      src[pos]   = SrcWrite;
      wport[pos] = p;
      fault[pos / cw_bytes] = 0;
    end
    if (p == 0 && cfg.ecc && inj_armed != 2'b00 && it.t_end > inj_t) begin
      if (it.t_start <= inj_t) begin
        mismatch($sformatf("%s: ECC injection while this write was in flight (bench rule)",
                           it.convert2string()));
      end
      for (int unsigned b = 0; b < cw_bytes; b++) begin
        if (it.be[b] || !cfg.byte_en[p]) fault[cw0] = inj_armed[1] ? 2 : 1;
      end
      if (cov != null) cov.sample_inj(inj_armed[1] ? 2 : 1, (full || !cfg.byte_en[p]) ? 0 : 1);
      inj_armed = 2'b00;
    end
  endfunction

  // ---- end of test -------------------------------------------------------------------
  function void check_phase(uvm_phase phase);
    drain();
    if (cnt_amb) begin
      `uvm_warning("SB", "status counts not checked: an engine overlapped an ECC check")
    end else if (cfg.single_clk()) begin
      if (obs_irq != exp_irq) begin
        mismatch($sformatf("err_irq: %0d pulse cycles, expected %0d", obs_irq, exp_irq));
      end
      if (obs_corr != exp_corr) begin
        mismatch($sformatf("ecc_corr: %0d, expected %0d", obs_corr, exp_corr));
      end
      if (obs_uncorr != exp_uncorr) begin
        mismatch($sformatf("ecc_uncorr: %0d, expected %0d", obs_uncorr, exp_uncorr));
      end
    end else begin
      if (obs_irq > exp_irq || (exp_irq > 0 && obs_irq == 0)) begin
        mismatch($sformatf("err_irq: %0d pulse cycles, expected 1..%0d (merged)", obs_irq,
                           exp_irq));
      end
    end
    if (sb_vif.n_mismatch != 0) begin
      mismatch($sformatf("sram_model: %0d of %0d responses mismatched", sb_vif.n_mismatch,
                         sb_vif.n_checked));
    end
    if (sb_vif.n_checked == 0) mismatch("sram_model checked no response");
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SB", $sformatf({"beats A=%0d B=%0d, reads compared=%0d (bytes %0d), ",
                               "errors as predicted=%0d, ambiguous power=%0d engine=%0d, ",
                               "irq=%0d/%0d corr=%0d/%0d uncorr=%0d/%0d, BIST pass=%0d fail=%0d, ",
                               "sram_model checked=%0d mismatched=%0d, mismatches=%0d"},
                              n_beats[0], n_beats[1], n_rd_cmp, n_bytes_cmp, n_err_ok,
                              n_amb_pwr, n_amb_eng, obs_irq, exp_irq, obs_corr, exp_corr,
                              obs_uncorr, exp_uncorr, n_bist[0], n_bist[1], sb_vif.n_checked,
                              sb_vif.n_mismatch, n_mis), UVM_NONE)
  endfunction

endclass : sram_scoreboard

`endif // SRAM_SCOREBOARD_SV
