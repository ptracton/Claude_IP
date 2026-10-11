// bus_matrix_decerr_seq.sv — decode errors on every gap of the address map.
//
// Each address below matches no slave of the bus_matrix_pkg map, so the
// matrix itself must answer SLVERR without touching any slave:
//   - the first byte past S0, S1, S2 and S3,
//   - the last word before S1, S2 and S3,
//   - inside each gap and at the top of the address space.
// With check_guards set, the sequence first writes a guard value into every
// slave word that one of these addresses would alias to if it were wrongly
// routed (offsets 0x000 and 0xFFC of each slave), and reads the guards back
// after the error accesses. Errors are issued back to back, and a good
// access follows them.

`ifndef BUS_MATRIX_DECERR_SEQ_SV
`define BUS_MATRIX_DECERR_SEQ_SV

class bus_matrix_decerr_seq extends bus_matrix_base_seq;
  `uvm_object_utils(bus_matrix_decerr_seq)

  int unsigned master_id    = 0;
  bit          check_guards = 1'b1;

  localparam int NH = 12;
  localparam logic [31:0] HOLES [NH] = '{
    32'h0001_0000,  // first byte past S0 (Boot ROM, 64 KB)
    32'h1000_0000,  // gap S0..S1
    32'h1FFF_FFFC,  // last word before S1
    32'h2002_0000,  // first byte past S1 (SRAM, 128 KB)
    32'h3000_0004,  // gap S1..S2
    32'h3FFF_FFFC,  // last word before S2
    32'h4001_0000,  // first byte past S2 (Peripherals, 64 KB)
    32'h5000_0FFC,  // gap S2..S3
    32'h5FFF_FFFC,  // last word before S3
    32'h7000_0000,  // first byte past S3 (External, 256 MB)
    32'hA5A5_A5A4,  // above S3
    32'hFFFF_FFFC   // top of the address space
  };

  function new(string name = "bus_matrix_decerr_seq");
    super.new(name);
  endfunction

  function automatic logic [31:0] guard(int j, int k);
    return 32'h6A00_0000 | (j << 16) | (k << 8) | master_id;
  endfunction

  task body();
    logic [31:0] rdata;
    int          order [NH];

    // Master 1 walks the holes in reverse so both masters hit different
    // holes at the same time.
    foreach (order[i]) order[i] = master_id ? NH - 1 - i : i;

    if (check_guards)
      for (int j = 0; j < bus_matrix_pkg::BM_NUM_SLAVES; j++) begin
        do_write(slv_base(j),                   guard(j, 0));
        do_write(slv_base(j) + slv_size(j) - 4, guard(j, 1));
      end

    // Back-to-back error writes, then error reads
    foreach (order[i])
      do_write(HOLES[order[i]], 32'hDEC0_0000 | order[i], 4'hF, 1'b1);
    foreach (order[i])
      do_read(HOLES[order[i]], rdata, 1'b1);
    // Interleaved partial-strobe write and read per hole
    foreach (order[i]) begin
      do_write(HOLES[order[i]], 32'hDEC1_0000 | order[i], 4'h1, 1'b1);
      do_read(HOLES[order[i]] ^ 32'h4, rdata, 1'b1);
    end

    if (check_guards)
      for (int j = 0; j < bus_matrix_pkg::BM_NUM_SLAVES; j++) begin
        check_read(slv_base(j),                   guard(j, 0), $sformatf("S%0d guard @0x000", j));
        check_read(slv_base(j) + slv_size(j) - 4, guard(j, 1), $sformatf("S%0d guard @0xFFC", j));
      end
  endtask

endclass : bus_matrix_decerr_seq

`endif // BUS_MATRIX_DECERR_SEQ_SV
