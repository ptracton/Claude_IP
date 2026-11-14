// sram_fv_ecc_top.sv — Formal harness for the SECDED code (sram_ecc_enc /
// sram_ecc_dec), SV and VHDL.
//
// Top-level of the "ecc" job. For each data width K in 8, 16, 24, 32 and 64
// (the codeword widths the sram uses for 8..64-bit words and narrow-port
// codewords) the solver picks any data word, a flip count n (0, 1 or 2) and
// two distinct bit positions of the codeword; the word is encoded, the bits
// flipped, and decoded:
//   a_clean   n = 0: data back, no flag
//   a_single  n = 1: data corrected, single_o only
//   a_double  n = 2: double_o only (detected, not miscorrected)
// Every bit of every input is free, so each property covers every data word
// and every error position. The check-bit count is computed here (the same
// formula as sram_pkg::ecc_check_bits) so the harness also builds against
// the VHDL entities, where the SV package is not compiled.
//
// clk / rst_n exist only because the run script needs a clock and a reset.

module sram_fv_ecc_top (
  input  logic        clk,
  input  logic        rst_n,
  input  logic [63:0] data,     // data word (low K bits used)
  input  logic [1:0]  nflip,    // bits to flip: 0, 1 or 2
  input  logic [6:0]  pos1,     // first flipped codeword bit
  input  logic [6:0]  pos2      // second flipped codeword bit
);

  function automatic int unsigned check_bits(int unsigned k);
    int unsigned r;
    r = 1;
    while ((2 ** r) < (k + r + 1)) r++;
    return r + 1;
  endfunction

  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  localparam int unsigned NK = 5;
  localparam int unsigned KS [NK] = '{8, 16, 24, 32, 64};

  for (genvar g = 0; g < NK; g++) begin : g_k
    localparam int unsigned K  = KS[g];
    localparam int unsigned CW = K + check_bits(K);

    logic [CW-1:0] code, bad, err;
    logic [K-1:0]  dout;
    logic          single, double;
    logic          p1_ok, p2_ok;

    sram_ecc_enc #(.K(K)) u_enc (.data_i(data[K-1:0]), .code_o(code));

    assign p1_ok = (pos1 < CW);
    assign p2_ok = (pos2 < CW) && (pos2 != pos1);
    always_comb begin
      err = '0;
      if (nflip >= 2'd1 && p1_ok) err[pos1] = 1'b1;
      if (nflip == 2'd2 && p2_ok) err[pos2] = 1'b1;
    end
    assign bad = code ^ err;

    sram_ecc_dec #(.K(K)) u_dec (.code_i(bad), .data_o(dout), .single_o(single),
                                 .double_o(double));

    a_clean:  assert property (nflip == 2'd0 |-> dout == data[K-1:0] && !single && !double);
    a_single: assert property ((nflip == 2'd1 && p1_ok) |->
                               dout == data[K-1:0] && single && !double);
    a_double: assert property ((nflip == 2'd2 && p1_ok && p2_ok) |-> double && !single);

    c_single: cover property (nflip == 2'd1 && p1_ok && single);
    c_double: cover property (nflip == 2'd2 && p1_ok && p2_ok && double);
  end

endmodule : sram_fv_ecc_top

// Bind-only module required by the run script (the harness has no binds).
module sram_fv_ecc_bind;
endmodule : sram_fv_ecc_bind
