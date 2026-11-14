// sram_ecc_enc.sv — SECDED (extended Hamming) encoder for the sram IP.
//
// Codeword layout (stored in the array):
//   code_o = {overall parity, hamming check[R-1:0], data[K-1:0]}
// check[i] is the XOR of the data bits whose Hamming position (as
// sram_pkg::ecc_data_pos) has bit i set; the overall parity covers data and
// check bits, which turns single-error correction into SECDED.
// All-zero data encodes to an all-zero codeword (used by the clear engine).

module sram_ecc_enc #(
  parameter int unsigned K = 32                         // data bits
) (
  input  logic [K-1:0]                                   data_i,  // data to protect
  output logic [K+sram_pkg::ecc_check_bits(K)-1:0]       code_o   // stored codeword
);

  localparam int unsigned R = sram_pkg::ecc_hamming_bits(K);

  // COVER[i*K +: K] = the data bits whose Hamming position has bit i set. Computed
  // at elaboration in O(K) (sram_pkg::ecc_data_pos(j) for every j, without
  // its 1024-step search), so no simulator evaluates a loop at run time
  // (and no loop has to be unrolled, which ran Verilator out of memory).
  function automatic logic [R*K-1:0] cover_masks();
    logic [R*K-1:0] m;
    int unsigned pos;
    m   = '0;
    pos = 2;
    for (int unsigned j = 0; j < K; j++) begin
      pos++;                                    // next position ...
      if ((pos & (pos - 1)) == 0) pos++;        // ... that is not a power of two
      for (int unsigned i = 0; i < R; i++) m[i*K + j] = ((pos >> i) & 1) != 0;
    end
    return m;
  endfunction

  localparam logic [R*K-1:0] COVER = cover_masks();  // COVER[i*K +: K]

  logic [R-1:0] check;
  logic         overall;

  // Hamming check bits and overall parity.
  for (genvar i = 0; i < R; i++) begin : g_check
    assign check[i] = ^(data_i & COVER[i*K +: K]);
  end
  assign overall = (^data_i) ^ (^check);

  assign code_o = {overall, check, data_i};

endmodule : sram_ecc_enc
