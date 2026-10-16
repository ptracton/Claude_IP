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

  logic [K-1:0] data;
  logic [R-1:0] stored_check;
  logic         stored_overall;
  logic [R-1:0] syndrome;
  logic         parity;

  assign data           = code_i[K-1:0];
  assign stored_check   = code_i[K+R-1:K];
  assign stored_overall = code_i[K+R];

  // Syndrome, overall parity and single-bit correction.
  always_comb begin : p_decode
    syndrome = stored_check;
    for (int unsigned j = 0; j < K; j++) begin
      for (int unsigned i = 0; i < R; i++) begin
        if (((sram_pkg::ecc_data_pos(j) >> i) & 1) != 0) begin
          syndrome[i] = syndrome[i] ^ data[j];
        end
      end
    end
    parity = (^code_i);
    data_o = data;
    for (int unsigned j = 0; j < K; j++) begin
      if (parity && (syndrome == R'(sram_pkg::ecc_data_pos(j)))) begin
        data_o[j] = ~data[j];
      end
    end
    single_o = parity;
    double_o = !parity && (syndrome != '0);
  end

endmodule : sram_ecc_dec
