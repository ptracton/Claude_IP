// sram_ecc_dec.sv — SECDED (extended Hamming) decoder for the sram IP.
//
// Input layout as produced by sram_ecc_enc: {overall, check[R-1:0], data[K-1:0]}.
//   syndrome = recomputed check XOR stored check
//   parity   = XOR of every stored bit (0 for a valid codeword)
//   parity = 0, syndrome = 0   no error
//   parity = 1                 single error: corrected (a data bit whose
//                              position equals the syndrome is flipped; a
//                              flipped check or parity bit leaves data intact)
//   parity = 0, syndrome != 0  double error: uncorrectable

module sram_ecc_dec #(
  parameter int unsigned K = 32                         // data bits
) (
  input  logic [K+sram_pkg::ecc_check_bits(K)-1:0]       code_i,    // stored codeword
  output logic [K-1:0]                                   data_o,    // corrected data
  output logic                                           single_o,  // corrected error
  output logic                                           double_o   // uncorrectable error
);

  localparam int unsigned R = sram_pkg::ecc_hamming_bits(K);

  // POS[j*R +: R] = Hamming position of data bit j (as sram_pkg::ecc_data_pos(j)),
  // computed at elaboration in O(K); COVER[i*K +: K] = data bits whose position has
  // bit i set. Constants, so no simulator runs a position search at run time.
  function automatic logic [K*R-1:0] data_positions();
    logic [K*R-1:0] p;
    int unsigned pos;
    pos = 2;
    for (int unsigned j = 0; j < K; j++) begin
      pos++;                                    // next position ...
      if ((pos & (pos - 1)) == 0) pos++;        // ... that is not a power of two
      p[j*R +: R] = R'(pos);
    end
    return p;
  endfunction

  localparam logic [K*R-1:0] POS = data_positions();   // POS[j*R +: R]

  // (Recomputes the positions instead of reading POS: some tools reject a
  // localparam indexed by a loop variable inside a constant function.)
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

  localparam logic [R*K-1:0] COVER = cover_masks();  // COVER[i*K +: K]

  logic [K-1:0] data;
  logic [R-1:0] stored_check;
  logic         stored_overall;
  logic [R-1:0] syndrome;
  logic         parity;

  assign data           = code_i[K-1:0];
  assign stored_check   = code_i[K+R-1:K];
  assign stored_overall = code_i[K+R];

  // Syndrome and overall parity.
  for (genvar i = 0; i < R; i++) begin : g_syn
    assign syndrome[i] = stored_check[i] ^ (^(data & COVER[i*K +: K]));
  end
  assign parity = ^code_i;

  // Single-bit correction: flip the data bit whose position equals the
  // syndrome (a flipped check or parity bit leaves the data intact).
  for (genvar j = 0; j < K; j++) begin : g_fix
    assign data_o[j] = data[j] ^ (parity && (syndrome == POS[j*R +: R]));
  end

  assign single_o = parity;
  assign double_o = !parity && (syndrome != '0);

endmodule : sram_ecc_dec
