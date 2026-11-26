// sram_leaf_fv.sv — VC Formal helper for the generic single-port leaf
// (sram_macro_generic), ECC configurations only.
//
// Bound into every sram_macro_generic by sram_fv_block_binds.svh, with the
// leaf geometry as literals from sram_fv_cfg.svh (an SV bind cannot see VHDL
// generics). With ECC each write lane of the leaf is one stored SECDED
// codeword ({overall, check, data}, see sram_ecc_enc).
//
// Why: the end-to-end data check (sram_core_fv a_data) needs the fact that
// the stored codeword of the symbolic word is valid, so the decoder passes
// its data through. That is an XOR relation over a whole codeword, which the
// prover did not find on its own (core_ecc a_data inconclusive at 30 min,
// while the same check without ECC, core_base, is proven). This checker
// states it per lane with one bit of state:
//   ok_q[i][l]  the last write to lane l of word i was a valid codeword
//   a_lane_ok   ok_q[i][l] -> the stored lane is a valid codeword
// It is inductive by construction (every write sets ok_q to the validity of
// what it writes), so it holds with BIST's raw march patterns as well, and
// the prover can use it as a proven lemma.
// Shutdown content loss is simulation-only in the leaf (translate_off), so
// formal sees retained contents; sram_core_fv allows zeros after shutdown.
//
// CLR = 1 (one leaf, one power domain, no BIST): a_word_ok — after the reset
// clear (sram_clr, CLEAR_ON_RESET with ECC) every word's lanes are known
// valid (ok_q all set), and during that pass every word already written.

module sram_leaf_fv #(
  parameter int unsigned W      = 22,   // stored word width
  parameter int unsigned D      = 8,    // words
  parameter int unsigned NLANES = 1,    // write lanes (= codewords with ECC)
  parameter bit          ECC    = 1,    // lanes are SECDED codewords
  parameter bit          CLR    = 0     // a_word_ok: one leaf, one power domain, no BIST
) (
  input  logic                 clk,
  input  logic                 rst_n,     // sram_core's reset (upward reference in the bind)
  input  logic                 cs_i,
  input  logic                 we_i,
  input  logic [$clog2(D)-1:0] addr_i,
  input  logic [W-1:0]         wdata_i,
  input  logic [NLANES-1:0]    lane_we_i,
  input  logic [W-1:0]         mem [D],
  // sram_clr state (upward references in the bind; used only when CLR = 1)
  input  logic                 clr_init,    // init_q[0]: not yet cleared since reset
  input  logic                 clr_active,  // active_q: a pass is running
  input  logic [$clog2(D):0]   clr_idx      // idx_q: next word of the pass
);

  localparam int unsigned LW = W / NLANES;   // lane (codeword) width

  // Data bits K of an LW-bit codeword: LW = K + R + 1 with 2^R >= K + R + 1.
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

  // COVER[i*K +: K]: data bits whose Hamming position has bit i set (the
  // same position sequence as sram_ecc_enc).
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

  // A codeword is valid when its syndrome and overall parity are zero.
  function automatic logic valid(logic [LW-1:0] c);
    logic v;
    v = !(^c);
    for (int unsigned i = 0; i < R; i++) begin
      v &= !(c[K+i] ^ (^(c[K-1:0] & COVER[i*K +: K])));
    end
    return v;
  endfunction

  if (ECC) begin : g_ecc
    // Reset: no lane is known valid. The leaf has no reset, so the bind
    // connects sram_core's; an initial block is not a formal start state (VC
    // Formal leaves unreset registers free after its reset simulation).
    logic [NLANES-1:0] ok_q [D];

    always_ff @(posedge clk) begin : p_ok
      if (!rst_n) begin
        for (int unsigned i = 0; i < D; i++) ok_q[i] <= '0;
      end else if (cs_i && we_i) begin
        for (int unsigned l = 0; l < NLANES; l++) begin
          if (lane_we_i[l]) begin
            ok_q[addr_i][l] <= valid(wdata_i[LW*l +: LW]);
          end
        end
      end
    end

    default clocking cb @(posedge clk); endclocking
    default disable iff (!rst_n);

    for (genvar i = 0; i < D; i++) begin : g_word
      for (genvar l = 0; l < NLANES; l++) begin : g_lane
        a_lane_ok: assert property (ok_q[i][l] |-> valid(mem[i][LW*l +: LW]));
      end
    end

    // Every word is known valid once the reset clear has finished, and
    // during that pass every word it has already written. Clear writes zero
    // (a valid codeword) to all lanes, the port only writes encoder output,
    // and nothing else writes the leaf when there is no BIST, so this is
    // inductive. It gives the port pipeline lemmas (sram_port_fv) the fact
    // that a granted read finds valid codewords: without it they did not
    // converge once the read-modify-write gained its s2 stage (Step 10).
    // Single domain and leaf only (CLR): with BANK_PG and BIST the domain
    // mapping and the March C- patterns are not modelled here.
    if (CLR) begin : g_clr
      for (genvar i = 0; i < D; i++) begin : g_word_ok
        a_word_ok: assert property ((!clr_init || (clr_active && clr_idx > i)) |-> &ok_q[i]);
      end
    end

    // A valid codeword is written (sanity: the lemma is not vacuous).
    c_valid_write: cover property (cs_i && we_i && lane_we_i[0] && valid(wdata_i[LW-1:0]));
  end

endmodule : sram_leaf_fv
