// bus_matrix_ahb_slave.sv — Non-synthesizable AHB slave BFM for bus_matrix testing.
//
// Responds to AHB transactions with internal memory.
// Zero wait states; HREADY always asserted.
//
// Intentionally non-pipelined: write data (HWDATA) and address (HADDR) are
// assumed simultaneously valid when HSEL && HTRANS==NONSEQ && HREADY, which
// matches the bus_matrix AHB slave-side adapter that drives both combinatorially
// from the same grant cycle.  This avoids AHB address/data phase mismatch in
// the test environment.
//
// Read path: HRDATA is combinatorial from HADDR — available the same cycle as
// the grant so the master BFM can capture it in the data phase register.

`ifndef BUS_MATRIX_AHB_SLAVE_SV
`define BUS_MATRIX_AHB_SLAVE_SV

module bus_matrix_ahb_slave #(
  parameter int DATA_W    = 32,  // data bus width
  parameter int ADDR_W    = 32,  // address width
  parameter int MEM_DEPTH = 256, // memory depth in words
  parameter int SLAVE_IDX = 0    // slave index for debug messages
) (
  input  logic              clk,     // system clock
  input  logic              rst_n,   // synchronous active-low reset

  // AHB master port (connects to bus_matrix S_* ports)
  input  logic              HSEL,                        // slave select
  input  logic [ADDR_W-1:0] HADDR,                       // byte address
  input  logic [1:0]        HTRANS,                      // transfer type
  input  logic              HWRITE,                      // 1=write, 0=read
  input  logic [DATA_W-1:0] HWDATA,                      // write data
  input  logic [DATA_W/8-1:0] HWSTRB,                    // byte enables
  output logic              HREADY,                      // always 1 (zero wait states)
  output logic [DATA_W-1:0] HRDATA,                      // read data
  output logic              HRESP                        // always 0 (OKAY)
);

  // AHB HTRANS encodings
  localparam logic [1:0] AHB_NONSEQ = 2'b10;
  localparam logic [1:0] AHB_SEQ    = 2'b11;

  // Internal memory array
  logic [DATA_W-1:0] mem [0:MEM_DEPTH-1];

  integer i;

  // Initialize memory to zero at start of simulation
  initial begin
    for (i = 0; i < MEM_DEPTH; i = i + 1) begin
      mem[i] = {DATA_W{1'b0}};
    end
  end

  // -------------------------------------------------------------------------
  // Write: single-cycle — capture address and data on same active cycle.
  // The bus_matrix slave-side adapter drives HWDATA (= mst_wdata = M_HWDATA)
  // combinatorially in the same cycle it asserts HSEL, so the write data is
  // valid when HSEL & HTRANS==NONSEQ & HREADY.
  // -------------------------------------------------------------------------
  logic [$clog2(MEM_DEPTH)-1:0] wr_idx;

  always_ff @(posedge clk) begin : p_write
    if (rst_n && HSEL && ((HTRANS == AHB_NONSEQ) || (HTRANS == AHB_SEQ))
               && HWRITE && HREADY) begin
      wr_idx = HADDR[$clog2(MEM_DEPTH)+1:2];
      if (HWSTRB[0]) mem[wr_idx][7:0]   <= HWDATA[7:0];
      if (HWSTRB[1]) mem[wr_idx][15:8]  <= HWDATA[15:8];
      if (HWSTRB[2]) mem[wr_idx][23:16] <= HWDATA[23:16];
      if (HWSTRB[3]) mem[wr_idx][31:24] <= HWDATA[31:24];
    end
  end

  // -------------------------------------------------------------------------
  // Read: combinational from current HADDR.
  // Since HREADY=1 always, the master BFM is in its data phase the cycle
  // after the address phase — but the matrix drives S_HADDR combinatorially
  // from the grant cycle, so HRDATA is sampled by the core in the same cycle
  // as the grant (not the following cycle).
  // -------------------------------------------------------------------------
  logic [$clog2(MEM_DEPTH)-1:0] rd_idx;

  always_comb begin : p_read
    rd_idx = HADDR[$clog2(MEM_DEPTH)+1:2];
    HRDATA = {DATA_W{1'b0}};
    if (HSEL && ((HTRANS == AHB_NONSEQ) || (HTRANS == AHB_SEQ)) && !HWRITE) begin
      HRDATA = mem[rd_idx];
    end
  end

  // Zero wait states, always OKAY
  assign HREADY = 1'b1;
  assign HRESP  = 1'b0;

endmodule : bus_matrix_ahb_slave

`endif // BUS_MATRIX_AHB_SLAVE_SV
