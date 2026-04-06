// bus_matrix_decoder.sv — Bus Matrix address decoder.
//
// Decodes an address to a one-hot slave selection using base+mask scheme.
// Match condition: (addr & s_mask) == (s_base & s_mask)
// All NUM_SLAVES entries are checked; lowest-numbered slave wins on multi-match.
// Address map is fully static, defined via S_BASE and S_MASK parameters.
// Combinational logic only.

module bus_matrix_decoder #(
  parameter int NUM_SLAVES = 2,                          // 1-32 active slaves
  parameter int ADDR_W     = 32,                         // address width (must be 32)
  parameter logic [NUM_SLAVES*32-1:0] S_BASE = '0,      // slave j base at [j*32+:32]
  parameter logic [NUM_SLAVES*32-1:0] S_MASK = '0       // slave j mask at [j*32+:32]
) (
  input  logic [ADDR_W-1:0]     addr,       // address to decode
  output logic [NUM_SLAVES-1:0] slave_sel,  // one-hot slave selection (0 if no match)
  output logic                  decode_err  // 1 if no slave matched
);

  logic [NUM_SLAVES-1:0] match; // combinational match flags

  // Match: (addr & mask) == (base & mask) for each slave
  genvar gi;
  generate
    for (gi = 0; gi < NUM_SLAVES; gi = gi + 1) begin : gen_match
      assign match[gi] = ((addr & S_MASK[gi*32+:32]) ==
                          (S_BASE[gi*32+:32] & S_MASK[gi*32+:32]));
    end
  endgenerate

  // Priority encoder: lowest-numbered matching slave wins (one-hot output).
  // Track whether a lower-indexed slave already matched.
  always_comb begin : p_priority_encode
    logic found;
    slave_sel = '0;
    found = 1'b0;
    for (int j = 0; j < NUM_SLAVES; j = j + 1) begin
      if (match[j] && !found) begin
        slave_sel[j] = 1'b1;
        found = 1'b1;
      end
    end
  end

  assign decode_err = ~(|slave_sel);

endmodule : bus_matrix_decoder
