// sram_ecc_enc.sv — SECDED (extended Hamming) encoder for the sram IP.
//
// Codeword layout (stored in the array):
//   code_o = {overall parity, hamming check[R-1:0], data[K-1:0]}
// check[i] is the XOR of the data bits whose Hamming position (sram_pkg::
// ecc_data_pos) has bit i set; the overall parity covers data and check
// bits, which turns single-error correction into SECDED.
// All-zero data encodes to an all-zero codeword (used by the clear engine).

module sram_ecc_enc #(
  parameter int unsigned K = 32                         // data bits
) (
  input  logic [K-1:0]                                   data_i,  // data to protect
  output logic [K+sram_pkg::ecc_check_bits(K)-1:0]       code_o   // stored codeword
);

  localparam int unsigned R = sram_pkg::ecc_hamming_bits(K);

  logic [R-1:0] check;
  logic         overall;

  // Hamming check bits and overall parity.
  always_comb begin : p_encode
    check = '0;
    for (int unsigned j = 0; j < K; j++) begin
      for (int unsigned i = 0; i < R; i++) begin
        if (((sram_pkg::ecc_data_pos(j) >> i) & 1) != 0) begin
          check[i] = check[i] ^ data_i[j];
        end
      end
    end
    overall = (^data_i) ^ (^check);
  end

  assign code_o = {overall, check, data_i};

endmodule : sram_ecc_enc
