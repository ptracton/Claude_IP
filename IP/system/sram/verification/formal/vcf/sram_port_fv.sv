// sram_port_fv.sv — VC Formal helper for sram_port, ECC single-port jobs.
//
// Bound into every sram_port by sram_fv_block_binds.svh (SRAM_FV_LEAF_BIND:
// single-port configurations, where every port has the leaf's stored width
// and codeword lanes). With ECC the stored word is NCW SECDED codewords
// ({overall, check, data}, see sram_ecc_enc), CWS bits each.
//
// Why: a read-modify-write (and, with READ_LATENCY 2, every read) keeps its
// raw stored word in rd_q for one more cycle before it is decoded in s2.
// sram_leaf_fv proves that written lanes in the array hold valid codewords,
// but nothing related rd_q to the array, so the error prediction
// (sram_core_fv a_err_rule) stopped converging once the RMW was registered
// (core_ecc: inconclusive at depth 23, proven before). These two lemmas
// carry the fact through the pipeline:
//   a_s1_rd_ok  s1 holds an error-free read or RMW -> the array output is valid
//   a_s2_rd_ok  s2 holds an error-free read or RMW -> rd_q is valid
// a_s2_rd_ok follows from a_s1_rd_ok in one step (rd_q loads arr_rdata_i
// whenever s1 is valid). A full write's array output is not decoded, so it
// is excluded.

module sram_port_fv #(
  parameter int unsigned MW  = 22,   // stored word width
  parameter int unsigned NCW = 1,    // codewords per stored word
  parameter bit          ECC = 1
) (
  input  logic          clk,
  input  logic          rst_n,
  input  logic          s1_valid_q,
  input  logic          s1_err_q,
  input  logic          s1_we_q,
  input  logic          s1_rmw_q,
  input  logic [MW-1:0] arr_rdata_i,
  input  logic          s2_valid_q,
  input  logic          s2_err_q,
  input  logic          s2_we_q,
  input  logic          s2_rmw_q,
  input  logic [MW-1:0] rd_q
);

  localparam int unsigned LW = MW / NCW;   // stored codeword width

  function automatic int unsigned hamming_bits(int unsigned k);
    int unsigned r;
    r = 0;
    while ((1 << r) < k + r + 1) r++;
    return r;
  endfunction

  function automatic int unsigned data_bits(int unsigned lw);
    for (int unsigned k = 1; k < lw; k++) begin
      if (k + hamming_bits(k) + 1 == lw) return k;
    end
    return 1;
  endfunction

  localparam int unsigned K = data_bits(LW);
  localparam int unsigned R = hamming_bits(K);

  // Same position sequence as sram_ecc_enc / sram_leaf_fv.
  function automatic logic [R*K-1:0] cover_masks();
    logic [R*K-1:0] m;
    int unsigned pos;
    m   = '0;
    pos = 2;
    for (int unsigned j = 0; j < K; j++) begin
      pos++;
      if ((pos & (pos - 1)) == 0) pos++;
      for (int unsigned i = 0; i < R; i++) m[i*K + j] = ((pos >> i) & 1) != 0;
    end
    return m;
  endfunction

  localparam logic [R*K-1:0] COVER = cover_masks();

  function automatic logic valid(logic [LW-1:0] c);
    logic v;
    v = !(^c);
    for (int unsigned i = 0; i < R; i++) begin
      v &= !(c[K+i] ^ (^(c[K-1:0] & COVER[i*K +: K])));
    end
    return v;
  endfunction

  function automatic logic all_valid(logic [MW-1:0] w);
    logic v;
    v = 1'b1;
    for (int unsigned c = 0; c < NCW; c++) v &= valid(w[LW*c +: LW]);
    return v;
  endfunction

  if (ECC) begin : g_ecc
    default clocking cb @(posedge clk); endclocking
    default disable iff (!rst_n);

    a_s1_rd_ok: assert property ((s1_valid_q && !s1_err_q && (!s1_we_q || s1_rmw_q))
                                 |-> all_valid(arr_rdata_i));
    a_s2_rd_ok: assert property ((s2_valid_q && !s2_err_q && (!s2_we_q || s2_rmw_q))
                                 |-> all_valid(rd_q));

    c_s2_rmw: cover property (s2_valid_q && s2_rmw_q && !s2_err_q);
  end

endmodule : sram_port_fv
