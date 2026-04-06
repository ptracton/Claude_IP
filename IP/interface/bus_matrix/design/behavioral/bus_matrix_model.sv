// bus_matrix_model.sv — Non-synthesizable behavioral reference model.
//
// Used by UVM scoreboards to predict correct routing behavior.
// Provides a function to determine which slave index an address maps to,
// given flat-packed S_BASE/S_MASK parameter values.
//
// Not synthesizable — for simulation only.

`ifndef BUS_MATRIX_MODEL_SV
`define BUS_MATRIX_MODEL_SV

module bus_matrix_model #(
  parameter int NUM_SLAVES = 2,   // 1-32 active slaves
  parameter int ADDR_W     = 32,  // address width
  parameter logic [NUM_SLAVES*32-1:0] S_BASE = '0,
  parameter logic [NUM_SLAVES*32-1:0] S_MASK = '0
) (
  input logic clk   // clock (for sequencing reference only)
);

  // -----------------------------------------------------------------------
  // Function: predict_slave
  //
  // Given an address, returns the index of the slave that should receive
  // the transaction, or -1 if no slave matches (decode error).
  //
  // Match condition: (addr & mask) == (base & mask)
  // Lowest-numbered matching slave wins (matches bus_matrix_decoder priority).
  // -----------------------------------------------------------------------
  function automatic int predict_slave(
    input logic [ADDR_W-1:0] addr
  );
    logic [31:0] base_j;
    logic [31:0] mask_j;

    predict_slave = -1;
    for (int j = 0; j < NUM_SLAVES; j = j + 1) begin
      if (predict_slave == -1) begin
        base_j = S_BASE[j*32+:32];
        mask_j = S_MASK[j*32+:32];
        if ((addr[ADDR_W-1:0] & mask_j[ADDR_W-1:0]) ==
            (base_j[ADDR_W-1:0] & mask_j[ADDR_W-1:0])) begin
          predict_slave = j;
        end
      end
    end
  endfunction

  // -----------------------------------------------------------------------
  // Function: is_decode_error
  //
  // Returns 1 if the address does not match any configured slave.
  // -----------------------------------------------------------------------
  function automatic logic is_decode_error(
    input logic [ADDR_W-1:0] addr
  );
    is_decode_error = (predict_slave(addr) == -1);
  endfunction

endmodule : bus_matrix_model

`endif // BUS_MATRIX_MODEL_SV
