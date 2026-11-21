// sram_coverage.sv — Functional coverage of the sram UVM bench.
//
// The scoreboard samples it: it knows, for every beat, what the model
// predicted (error cause, requested mode at the grant, where the compared
// bytes came from, ECC outcome), which the monitors alone do not.
//
// Coverpoints of a feature the configuration lacks have weight 0, so 100 %
// is reachable in every configuration (target: 100 % per configuration,
// merged over its tests and seeds).

`ifndef SRAM_COVERAGE_SV
`define SRAM_COVERAGE_SV

typedef enum int unsigned {
  CauseNone  = 0,
  CauseOor   = 1,
  CausePower = 2,
  CauseRo    = 3,
  CauseEcc   = 4
} sram_cause_e;

typedef enum int unsigned {
  SrcInit  = 0,   // reset clear (ECC)
  SrcWrite = 1,
  SrcClear = 2,
  SrcBist  = 3,
  SrcWake  = 4,   // zero after a wake from shutdown
  SrcOther = 5    // written through the other port
} sram_src_e;

typedef enum int unsigned {
  GapOverlap = 0, // started before the previous beat of this port ended
  GapB2b     = 1, // started at the edge the previous one ended, or one later
  GapIdle    = 2
} sram_gap_e;

typedef enum int unsigned {
  RegFirst  = 0,
  RegLast   = 1,
  RegMiddle = 2,
  RegOor    = 3
} sram_region_e;

typedef enum int unsigned {
  StrbFull    = 0,
  StrbPartial = 1,
  StrbNone    = 2
} sram_strb_e;

typedef enum int unsigned {
  EccNone      = 0,
  EccCorrRead  = 1,
  EccCorrRmw   = 2,
  EccUncRead   = 3,
  EccUncRmw    = 4
} sram_ecc_e;

class sram_beat_info;
  int unsigned  port;
  bit           we;
  int unsigned  size;
  bit           err;
  sram_cause_e  cause;
  int unsigned  mode;         // requested mode at the grant
  sram_region_e region;
  sram_strb_e   strb;
  sram_gap_e    gap;
  sram_src_e    src;          // read: origin of the compared bytes
  bit           src_valid;
  sram_ecc_e    ecc;
  int unsigned  ahb_beat;     // AHB: index in its NONSEQ/SEQ run
  bit           ahb_wrap;     // AHB: this beat wrapped below the previous one
  int unsigned  ahb_busy;     // AHB: BUSY cycles before this beat
  bit           axi_overlap;
  bit           both_ports;   // dual port: the other port had a beat in flight
  int unsigned  lane;         // narrow port: word index modulo the width ratio
  bit           amb;          // ambiguous (power or engine overlap)
endclass : sram_beat_info

// ---- bus beats -------------------------------------------------------------
covergroup sram_cg_beat(int unsigned max_sz, bit multi_byte, bit has_pg, bit is_ahb,
                   bit is_axi, bit has_ro, bit has_ecc, bit has_bist, bit rd_sub) with function
    sample(sram_beat_info b);
  option.per_instance = 1;
  cp_we: coverpoint b.we;
  cp_size: coverpoint b.size {
    bins s[] = {[0:max_sz]};
  }
  cp_err: coverpoint b.err;
  cp_cause: coverpoint b.cause {
    bins none  = {CauseNone};
    bins oor   = {CauseOor};
    ignore_bins other = {CausePower, CauseRo, CauseEcc};
  }
  cp_cause_pwr: coverpoint (b.cause == CausePower) {
    option.weight = has_pg;
    bins hit = {1};
  }
  cp_cause_ro: coverpoint (b.cause == CauseRo) {
    option.weight = has_ro;
    bins hit = {1};
  }
  cp_cause_ecc: coverpoint (b.cause == CauseEcc) {
    option.weight = has_ecc;
    bins hit = {1};
  }
  cp_region: coverpoint b.region;
  cp_strb: coverpoint b.strb iff (b.we) {
    bins full = {StrbFull};
    bins none = {StrbNone};
    ignore_bins part = {StrbPartial};
  }
  cp_strb_part: coverpoint (b.strb == StrbPartial) iff (b.we) {
    option.weight = multi_byte;
    bins hit = {1};
  }
  cp_gap: coverpoint b.gap {
    bins b2b  = {GapB2b};
    bins idle = {GapIdle};
    ignore_bins ovl = {GapOverlap};
  }
  cp_gap_ovl: coverpoint (b.gap == GapOverlap) {
    option.weight = is_ahb || is_axi;
    bins hit = {1};
  }
  cp_mode: coverpoint b.mode iff (!b.amb && b.cause inside {CauseNone, CausePower}) {
    option.weight = has_pg;
    bins m[] = {[0:3]};
  }
  cp_src: coverpoint b.src iff (b.src_valid) {
    bins write = {SrcWrite};
    ignore_bins other = {SrcInit, SrcClear, SrcBist, SrcWake, SrcOther};
  }
  cp_src_clear: coverpoint (b.src == SrcClear) iff (b.src_valid) {
    bins hit = {1};
  }
  cp_src_wake: coverpoint (b.src == SrcWake) iff (b.src_valid) {
    option.weight = has_pg;
    bins hit = {1};
  }
  cp_src_init: coverpoint (b.src == SrcInit) iff (b.src_valid) {
    option.weight = has_ecc;
    bins hit = {1};
  }
  cp_src_bist: coverpoint (b.src == SrcBist) iff (b.src_valid) {
    option.weight = has_bist;
    bins hit = {1};
  }
  cp_ahb_run: coverpoint b.ahb_beat {
    option.weight = is_ahb;
    bins single = {0};
    bins seq_2_4  = {[1:3]};
    bins seq_5_8  = {[4:7]};
    bins seq_9_16 = {[8:15]};
  }
  cp_ahb_wrap: coverpoint b.ahb_wrap {
    option.weight = is_ahb;
    bins hit = {1};
  }
  cp_ahb_busy: coverpoint (b.ahb_busy > 0) {
    option.weight = is_ahb;
    bins hit = {1};
  }
  cp_axi_ovl: coverpoint b.axi_overlap {
    option.weight = is_axi;
    bins hit = {1};
  }
  // APB / AXI4-Lite reads are whole words (rd_sub = 0: AHB HSIZE, WB SEL only)
  cx_we_size_err: cross cp_we, cp_size, cp_err {
    ignore_bins rd_word_only = cx_we_size_err with (!rd_sub && cp_we == 0 && cp_size < max_sz);
  }
  cx_we_gap: cross cp_we, cp_gap;
  cx_we_region: cross cp_we, cp_region;
endgroup

// ---- dual port ---------------------------------------------------------------
covergroup sram_cg_dp(int unsigned ratio) with function sample(sram_beat_info b);
  option.per_instance = 1;
  cp_port: coverpoint b.port {
    bins a = {0};
    bins b = {1};
  }
  cp_flow: coverpoint b.src iff (b.src_valid) {
    bins other = {SrcOther};
    ignore_bins rest = {SrcInit, SrcWrite, SrcClear, SrcBist, SrcWake};
  }
  cp_both: coverpoint b.both_ports {
    bins hit = {1};
  }
  cp_lane: coverpoint b.lane iff (b.port == 1) {
    bins l[] = {[0:ratio-1]};
  }
  cx_port_flow: cross cp_port, cp_flow;
  cx_port_both: cross cp_port, cp_both;
endgroup

// ---- power requests ------------------------------------------------------------
covergroup sram_cg_pwr(int unsigned npd) with function sample(int unsigned d, int unsigned f,
                                                          int unsigned t);
  option.per_instance = 1;
  cp_dom: coverpoint d {
    bins d[] = {[0:npd-1]};
  }
  cp_from: coverpoint f {
    bins m[] = {[0:3]};
  }
  cp_to: coverpoint t {
    bins m[] = {[0:3]};
  }
  cx_trans: cross cp_from, cp_to {
    ignore_bins same = cx_trans with (cp_from == cp_to);
  }
endgroup

// ---- clear engine --------------------------------------------------------------
covergroup sram_cg_clr(bit banked) with function sample(int unsigned modes, bit traffic);
  option.per_instance = 1;
  cp_traffic: coverpoint traffic;
  cp_skip: coverpoint ((modes & 4'b1100) != 0) {
    option.weight = banked;
    bins hit = {1};
  }
  cp_ls: coverpoint ((modes & 4'b0010) != 0) {
    bins hit = {1};
  }
endgroup

// ---- ECC -----------------------------------------------------------------------
covergroup sram_cg_ecc with function sample(int unsigned kind, int unsigned use_);
  option.per_instance = 1;
  cp_kind: coverpoint kind {
    bins single = {1};
    bins double = {2};
  }
  cp_use: coverpoint use_ {
    bins full = {0};
    bins rmw  = {1};
  }
  cx_kind_use: cross cp_kind, cp_use;
endgroup

covergroup sram_cg_ecc_det with function sample(sram_ecc_e e);
  option.per_instance = 1;
  cp_det: coverpoint e {
    bins corr_rd  = {EccCorrRead};
    bins corr_rmw = {EccCorrRmw};
    bins unc_rd   = {EccUncRead};
    bins unc_rmw  = {EccUncRmw};
  }
endgroup

// ---- BIST ----------------------------------------------------------------------
covergroup sram_cg_bist with function sample(bit fail, bit traffic);
  option.per_instance = 1;
  cp_fail: coverpoint fail;
  cp_traffic: coverpoint traffic;
endgroup


class sram_coverage extends uvm_component;
  `uvm_component_utils(sram_coverage)

  sram_uvm_cfg   cfg;
  sram_cg_beat    cg_beat_a;
  sram_cg_beat    cg_beat_b;
  sram_cg_dp      cg_dp;
  sram_cg_pwr     cg_pwr;
  sram_cg_clr     cg_clr;
  sram_cg_ecc     cg_ecc;
  sram_cg_ecc_det cg_ecc_det;
  sram_cg_bist    cg_bist;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    if (!uvm_config_db #(sram_uvm_cfg)::get(this, "", "cfg", cfg)) begin
      `uvm_fatal("COV", "no sram_uvm_cfg (cfg)")
    end
    cg_beat_a = new(cfg.max_size(0), cfg.width[0] > 8, cfg.pwr_gate, cfg.proto == "ahb",
                    cfg.proto == "axi4l", 1'b0, cfg.ecc, cfg.bist,
                    cfg.proto inside {"ahb", "wb"});
    cg_beat_a.set_inst_name({get_full_name(), ".cg_beat_a"});
    if (cfg.dual_port) begin
      cg_beat_b = new(cfg.max_size(1), cfg.width[1] > 8, cfg.pwr_gate, cfg.proto == "ahb",
                      cfg.proto == "axi4l", cfg.read_only[1], cfg.ecc, cfg.bist,
                      cfg.proto inside {"ahb", "wb"});
      cg_beat_b.set_inst_name({get_full_name(), ".cg_beat_b"});
      cg_dp = new(cfg.width[0] / cfg.width[1]);
    end
    if (cfg.pwr_gate) cg_pwr = new(cfg.npd);
    cg_clr = new(cfg.npd > 2);
    if (cfg.ecc) begin
      cg_ecc     = new();
      cg_ecc_det = new();
    end
    if (cfg.bist) cg_bist = new();
  endfunction

  function void sample_beat(sram_beat_info b);
    if (b.port == 0) cg_beat_a.sample(b);
    else cg_beat_b.sample(b);
    if (cfg.dual_port) cg_dp.sample(b);
    if (cfg.ecc && b.ecc != EccNone) cg_ecc_det.sample(b.ecc);
  endfunction

  function void sample_pwr(int unsigned d, int unsigned f, int unsigned t);
    if (cfg.pwr_gate) cg_pwr.sample(d, f, t);
  endfunction

  function void sample_clr(int unsigned modes, bit traffic);
    cg_clr.sample(modes, traffic);
  endfunction

  function void sample_inj(int unsigned kind, int unsigned use_);
    if (cfg.ecc) cg_ecc.sample(kind, use_);
  endfunction

  function void sample_bist(bit fail, bit traffic);
    if (cfg.bist) cg_bist.sample(fail, traffic);
  endfunction

  function real total();
    real   s;
    int    n;
    s = cg_beat_a.get_inst_coverage();
    n = 1;
    if (cfg.dual_port) begin
      s += cg_beat_b.get_inst_coverage() + cg_dp.get_inst_coverage();
      n += 2;
    end
    if (cfg.pwr_gate) begin
      s += cg_pwr.get_inst_coverage();
      n++;
    end
    s += cg_clr.get_inst_coverage();
    n++;
    if (cfg.ecc) begin
      s += cg_ecc.get_inst_coverage() + cg_ecc_det.get_inst_coverage();
      n += 2;
    end
    if (cfg.bist) begin
      s += cg_bist.get_inst_coverage();
      n++;
    end
    return s / n;
  endfunction

  function void report_phase(uvm_phase phase);
    string s;
    s = $sformatf("beat_a %.1f", cg_beat_a.get_inst_coverage());
    if (cfg.dual_port) begin
      s = {s, $sformatf(" beat_b %.1f dp %.1f", cg_beat_b.get_inst_coverage(),
                        cg_dp.get_inst_coverage())};
    end
    if (cfg.pwr_gate) s = {s, $sformatf(" pwr %.1f", cg_pwr.get_inst_coverage())};
    s = {s, $sformatf(" clr %.1f", cg_clr.get_inst_coverage())};
    if (cfg.ecc) begin
      s = {s, $sformatf(" ecc %.1f ecc_det %.1f", cg_ecc.get_inst_coverage(),
                        cg_ecc_det.get_inst_coverage())};
    end
    if (cfg.bist) s = {s, $sformatf(" bist %.1f", cg_bist.get_inst_coverage())};
    `uvm_info("COV", $sformatf("functional coverage (this test) %.2f %%: %s", total(), s),
              UVM_NONE)
  endfunction

endclass : sram_coverage

`endif // SRAM_COVERAGE_SV
