// bus_matrix_scoreboard.sv — reference-memory scoreboard for the bus_matrix UVM env.
//
// Both master agents' monitors feed this scoreboard. It predicts every
// response from the address alone:
//   - unmapped (bus_matrix_pkg map)            -> SLVERR (decode error)
//   - slave in SLV_ERR_SLAVES, page SLV_ERR_PAGE -> SLVERR (slave error)
//   - otherwise                                 -> OKAY
// OKAY writes update a reference memory (strobe-aware); OKAY reads are checked
// against it. Each testbench slave holds 4 KB aliased across its region, so the
// model is keyed by {slave, addr[11:2]}. Unwritten words read as 0.
//
// The two monitors report a transaction at its response handshake, which can
// trail the slave-side access by a cycle or more. When both masters write the
// same word, a read may therefore legitimately return the value written just
// before the latest one reported, so a read matches the latest or the
// previous value of that word.

`ifndef BUS_MATRIX_SCOREBOARD_SV
`define BUS_MATRIX_SCOREBOARD_SV

`uvm_analysis_imp_decl(_m0)
`uvm_analysis_imp_decl(_m1)

class bus_matrix_scoreboard extends uvm_scoreboard;
  `uvm_component_utils(bus_matrix_scoreboard)

  uvm_analysis_imp_m0 #(bus_matrix_axi_seq_item, bus_matrix_scoreboard) m0_export;
  uvm_analysis_imp_m1 #(bus_matrix_axi_seq_item, bus_matrix_scoreboard) m1_export;

  logic [31:0] mem_q    [logic [31:0]]; // latest value per {slave, word}
  logic [31:0] mem_prev [logic [31:0]]; // value before the latest write

  int unsigned n_writes, n_reads, n_dec_errors, n_slv_errors, n_mismatches;

  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    m0_export = new("m0_export", this);
    m1_export = new("m1_export", this);
  endfunction

  function void write_m0(bus_matrix_axi_seq_item t); score(0, t); endfunction
  function void write_m1(bus_matrix_axi_seq_item t); score(1, t); endfunction

  // Slave selected by the bus_matrix_pkg map (lowest match), or -1.
  function automatic int slave_of(logic [31:0] a);
    for (int j = 0; j < bus_matrix_pkg::BM_NUM_SLAVES; j++) begin
      logic [31:0] base = bus_matrix_pkg::BM_S_BASE[j*32+:32];
      logic [31:0] mask = bus_matrix_pkg::BM_S_MASK[j*32+:32];
      if ((a & mask) == (base & mask)) return j;
    end
    return -1;
  endfunction

  function void score(int m, bus_matrix_axi_seq_item t);
    int          j       = slave_of(t.addr);
    bit          dec_err = (j < 0);
    bit          slv_err = !dec_err && SLV_ERR_SLAVES[j] && (t.addr[11:8] == SLV_ERR_PAGE);
    logic [1:0]  exp     = (dec_err || slv_err) ? 2'b10 : 2'b00;
    logic [31:0] w       = {j[3:0], 16'h0, t.addr[11:2], 2'b00}; // model key
    logic [31:0] cur, prv;

    if (t.resp !== exp) begin
      n_mismatches++;
      `uvm_error("SB", $sformatf("M%0d %s: resp=%02b, expected %02b (%s)", m,
                 t.convert2string(), t.resp, exp,
                 dec_err ? "decode error" : slv_err ? "slave error" : "OKAY"))
    end
    if (dec_err) begin n_dec_errors++; return; end
    if (slv_err) begin n_slv_errors++; return; end

    cur = mem_q.exists(w)    ? mem_q[w]    : '0;
    prv = mem_prev.exists(w) ? mem_prev[w] : cur;
    if (t.write) begin
      logic [31:0] nxt = cur;
      for (int b = 0; b < 4; b++)
        if (t.wstrb[b]) nxt[b*8+:8] = t.wdata[b*8+:8];
      mem_prev[w] = cur;
      mem_q[w]    = nxt;
      n_writes++;
    end else begin
      n_reads++;
      if (t.rdata !== cur && t.rdata !== prv) begin
        n_mismatches++;
        `uvm_error("SB", $sformatf("M%0d read 0x%08x: got 0x%08x, expected 0x%08x",
                                   m, t.addr, t.rdata, cur))
      end
    end
  endfunction

  function void report_phase(uvm_phase phase);
    `uvm_info("SB", $sformatf("writes=%0d reads=%0d decode errors=%0d slave errors=%0d mismatches=%0d",
                              n_writes, n_reads, n_dec_errors, n_slv_errors, n_mismatches), UVM_NONE)
  endfunction

endclass : bus_matrix_scoreboard

`endif // BUS_MATRIX_SCOREBOARD_SV
