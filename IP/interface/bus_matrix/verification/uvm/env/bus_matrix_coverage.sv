// bus_matrix_coverage.sv — functional coverage for the bus_matrix UVM env.
//
// Samples every completed transaction from both master agents.
//   cg_xact
//     x_master_region_dir  every master reads and writes every slave, and
//                          gets decode errors on reads and writes
//     x_outcome_dir        OKAY on each slave, slave errors from S2/S3,
//                          decode errors, for reads and for writes
//     x_region_strb        every byte-strobe pattern on every slave
//     x_region_pos         first word, last word and interior of every region
//     cp_hole              decode errors in every gap of the address map and
//                          above the last region
//   cg_pair (sampled on each completion, pairing it with the other master's
//            most recent completion)
//     cp_same_slave        back-to-back completions of both masters on the
//                          same slave (arbitration) and on different slaves

`ifndef BUS_MATRIX_COVERAGE_SV
`define BUS_MATRIX_COVERAGE_SV

`uvm_analysis_imp_decl(_cov_m0)
`uvm_analysis_imp_decl(_cov_m1)

class bus_matrix_coverage extends uvm_component;
  `uvm_component_utils(bus_matrix_coverage)

  uvm_analysis_imp_cov_m0 #(bus_matrix_axi_seq_item, bus_matrix_coverage) m0_export;
  uvm_analysis_imp_cov_m1 #(bus_matrix_axi_seq_item, bus_matrix_coverage) m1_export;

  localparam int NS     = bus_matrix_pkg::BM_NUM_SLAVES;
  localparam int DECERR = NS; // region value of an unmapped address

  typedef enum int {
    OUT_OKAY_S0, OUT_OKAY_S1, OUT_OKAY_S2, OUT_OKAY_S3,
    OUT_SLVERR_S2, OUT_SLVERR_S3, OUT_DECERR
  } outcome_e;

  typedef enum int {POS_FIRST, POS_LAST, POS_INTERIOR} pos_e;

  // Gaps of the default map (S0 64 KB @0, S1 128 KB @0x2000_0000,
  // S2 64 KB @0x4000_0000, S3 256 MB @0x6000_0000).
  typedef enum int {HOLE_S0_S1, HOLE_S1_S2, HOLE_S2_S3, HOLE_ABOVE_S3} hole_e;

  int                     master;
  int                     region;
  outcome_e               outcome;
  pos_e                   pos;
  hole_e                  hole;
  bus_matrix_axi_seq_item tr;

  // Most recent completion per master: slave index, or -1 (none / decode error)
  int                     last_slave [2] = '{-1, -1};
  bit                     same_slave;

  covergroup cg_xact;
    cp_master: coverpoint master { bins m[] = {[0:1]}; }
    cp_region: coverpoint region { bins slave[] = {[0:NS-1]}; bins decerr = {DECERR}; }
    cp_dir:    coverpoint tr.write { bins rd = {0}; bins wr = {1}; }
    cp_outcome: coverpoint outcome;
    cp_strb:   coverpoint tr.wstrb iff (tr.write && outcome < OUT_SLVERR_S2) {
                 bins full = {4'hF};
                 bins half[] = {4'h3, 4'hC};
                 bins byte_lane[] = {4'h1, 4'h2, 4'h4, 4'h8};
               }
    cp_slave:  coverpoint region iff (region != DECERR) { bins slave[] = {[0:NS-1]}; }
    cp_pos:    coverpoint pos iff (outcome < OUT_SLVERR_S2);
    cp_hole:   coverpoint hole iff (outcome == OUT_DECERR);

    x_master_region_dir: cross cp_master, cp_region, cp_dir;
    x_outcome_dir:       cross cp_outcome, cp_dir;
    x_region_strb:       cross cp_slave, cp_strb;
    x_region_pos:        cross cp_slave, cp_pos;
  endgroup

  covergroup cg_pair;
    cp_same_slave: coverpoint same_slave { bins different = {0}; bins same = {1}; }
  endgroup

  function new(string name, uvm_component parent);
    super.new(name, parent);
    cg_xact = new();
    cg_pair = new();
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m0_export = new("m0_export", this);
    m1_export = new("m1_export", this);
  endfunction

  function void write_cov_m0(bus_matrix_axi_seq_item t); sample(0, t); endfunction
  function void write_cov_m1(bus_matrix_axi_seq_item t); sample(1, t); endfunction

  function void sample(int m, bus_matrix_axi_seq_item t);
    logic [31:0] base, mask, off, last;
    master = m;
    tr     = t;
    region = DECERR;
    for (int j = NS - 1; j >= 0; j--) begin
      base = bus_matrix_pkg::BM_S_BASE[j*32+:32];
      mask = bus_matrix_pkg::BM_S_MASK[j*32+:32];
      if ((t.addr & mask) == (base & mask)) region = j;
    end

    if (region == DECERR) begin
      outcome = OUT_DECERR;
      if      (t.addr < 32'h2000_0000) hole = HOLE_S0_S1;
      else if (t.addr < 32'h4000_0000) hole = HOLE_S1_S2;
      else if (t.addr < 32'h6000_0000) hole = HOLE_S2_S3;
      else                             hole = HOLE_ABOVE_S3;
    end else begin
      if (SLV_ERR_SLAVES[region] && t.addr[11:8] == SLV_ERR_PAGE)
        outcome = (region == 2) ? OUT_SLVERR_S2 : OUT_SLVERR_S3;
      else
        outcome = outcome_e'(OUT_OKAY_S0 + region);
      mask = bus_matrix_pkg::BM_S_MASK[region*32+:32];
      off  = t.addr & ~mask;
      last = ~mask & ~32'h3;
      pos  = (off[31:2] == 0)         ? POS_FIRST :
             (off[31:2] == last[31:2]) ? POS_LAST  : POS_INTERIOR;
    end
    cg_xact.sample();

    last_slave[m] = (region == DECERR) ? -1 : region;
    if (last_slave[m] >= 0 && last_slave[1-m] >= 0) begin
      same_slave = (last_slave[m] == last_slave[1-m]);
      cg_pair.sample();
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("COV", $sformatf("transaction coverage: %0.1f%% (master x region x dir %0.1f%%, outcome x dir %0.1f%%, region x strobe %0.1f%%, region x position %0.1f%%, holes %0.1f%%); pairing %0.1f%%",
              cg_xact.get_coverage(),
              cg_xact.x_master_region_dir.get_coverage(),
              cg_xact.x_outcome_dir.get_coverage(),
              cg_xact.x_region_strb.get_coverage(),
              cg_xact.x_region_pos.get_coverage(),
              cg_xact.cp_hole.get_coverage(),
              cg_pair.get_coverage()), UVM_NONE)
  endfunction

endclass : bus_matrix_coverage

`endif // BUS_MATRIX_COVERAGE_SV
