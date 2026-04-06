// bus_matrix_wb_slave.sv — Non-synthesizable Wishbone slave BFM for bus_matrix testing.
//
// Responds to Wishbone B4 transactions with internal memory.
// ACK one cycle after STB assertion.

`ifndef BUS_MATRIX_WB_SLAVE_SV
`define BUS_MATRIX_WB_SLAVE_SV

module bus_matrix_wb_slave #(
  parameter int DATA_W    = 32,  // data bus width
  parameter int ADDR_W    = 32,  // address width
  parameter int MEM_DEPTH = 256, // memory depth in words
  parameter int SLAVE_IDX = 0    // slave index for debug
) (
  input  logic              clk,    // system clock
  input  logic              rst_n,  // synchronous active-low reset

  // Wishbone master port (connects to bus_matrix S_* ports)
  input  logic              CYC,                         // bus cycle valid
  input  logic              STB,                         // strobe
  input  logic              WE,                          // 1=write, 0=read
  input  logic [ADDR_W-1:0] ADR,                         // address
  input  logic [DATA_W-1:0] DAT_O,                       // write data from master
  input  logic [DATA_W/8-1:0] SEL,                       // byte selects
  output logic [DATA_W-1:0] DAT_I,                       // read data to master
  output logic              ACK,                         // acknowledge
  output logic              ERR                          // error (always 0)
);

  logic [DATA_W-1:0] mem [0:MEM_DEPTH-1];

  // Capture STB to generate one-cycle ACK and perform operation
  logic stb_prev_q;
  logic ack_q;
  logic [DATA_W-1:0] rdata_q;
  logic [$clog2(MEM_DEPTH)-1:0] widx;

  integer i;

  initial begin
    for (i = 0; i < MEM_DEPTH; i = i + 1) begin
      mem[i] = {DATA_W{1'b0}};
    end
  end

  always_ff @(posedge clk) begin : p_slave
    if (!rst_n) begin
      stb_prev_q <= 1'b0;
      ack_q      <= 1'b0;
      rdata_q    <= {DATA_W{1'b0}};
    end else begin
      stb_prev_q <= CYC & STB & ~stb_prev_q;

      if (CYC && STB && !stb_prev_q) begin
        // New transaction: perform operation and ACK next cycle
        ack_q <= 1'b1;
        widx = ADR[$clog2(MEM_DEPTH)+1:2];
        if (WE) begin
          // Write
          if (SEL[0]) mem[widx][7:0]   <= DAT_O[7:0];
          if (SEL[1]) mem[widx][15:8]  <= DAT_O[15:8];
          if (SEL[2]) mem[widx][23:16] <= DAT_O[23:16];
          if (SEL[3]) mem[widx][31:24] <= DAT_O[31:24];
        end else begin
          // Read
          rdata_q <= mem[widx];
        end
      end else begin
        ack_q <= 1'b0;
      end
    end
  end

  assign ACK   = ack_q;
  assign DAT_I = rdata_q;
  assign ERR   = 1'b0;

endmodule : bus_matrix_wb_slave

`endif // BUS_MATRIX_WB_SLAVE_SV
