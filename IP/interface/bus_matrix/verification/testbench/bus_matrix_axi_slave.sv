// bus_matrix_axi_slave.sv — Non-synthesizable AXI4-Lite slave BFM for bus_matrix testing.
//
// Responds to AXI4-Lite transactions with internal memory.
// AWREADY=WREADY=ARREADY=1 always.

`ifndef BUS_MATRIX_AXI_SLAVE_SV
`define BUS_MATRIX_AXI_SLAVE_SV

module bus_matrix_axi_slave #(
  parameter int DATA_W    = 32,  // data bus width
  parameter int ADDR_W    = 32,  // address width
  parameter int MEM_DEPTH = 256, // memory depth in words
  parameter int SLAVE_IDX = 0    // slave index for debug
) (
  input  logic              clk,    // system clock
  input  logic              rst_n,  // synchronous active-low reset

  // AXI4-Lite master port (connects to bus_matrix S_* ports)
  // Write address channel
  input  logic              AWVALID,                     // write address valid
  output logic              AWREADY,                     // write address ready
  input  logic [ADDR_W-1:0] AWADDR,                      // write address
  // Write data channel
  input  logic              WVALID,                      // write data valid
  output logic              WREADY,                      // write data ready
  input  logic [DATA_W-1:0] WDATA,                       // write data
  input  logic [DATA_W/8-1:0] WSTRB,                     // byte enables
  // Write response channel
  output logic              BVALID,                      // write response valid
  input  logic              BREADY,                      // write response ready
  output logic [1:0]        BRESP,                       // write response (OKAY)
  // Read address channel
  input  logic              ARVALID,                     // read address valid
  output logic              ARREADY,                     // read address ready
  input  logic [ADDR_W-1:0] ARADDR,                      // read address
  // Read data channel
  output logic              RVALID,                      // read data valid
  input  logic              RREADY,                      // read data ready
  output logic [DATA_W-1:0] RDATA,                       // read data
  output logic [1:0]        RRESP                        // read response (OKAY)
);

  logic [DATA_W-1:0] mem [0:MEM_DEPTH-1];

  // Write path state
  logic              aw_captured_q;
  logic [ADDR_W-1:0] aw_addr_q;
  logic              w_captured_q;
  logic [DATA_W-1:0] w_data_q;
  logic [DATA_W/8-1:0] w_strb_q;
  logic              bvalid_q;

  // Read path state
  logic              ar_captured_q;
  logic [ADDR_W-1:0] ar_addr_q;
  logic              rvalid_q;
  logic [DATA_W-1:0] rdata_q;

  integer i;

  initial begin
    for (i = 0; i < MEM_DEPTH; i = i + 1) begin
      mem[i] = {DATA_W{1'b0}};
    end
  end

  logic [$clog2(MEM_DEPTH)-1:0] wr_idx;
  logic [$clog2(MEM_DEPTH)-1:0] rd_idx;

  // Write path
  always_ff @(posedge clk) begin : p_write
    if (!rst_n) begin
      aw_captured_q <= 1'b0;
      aw_addr_q     <= {ADDR_W{1'b0}};
      w_captured_q  <= 1'b0;
      w_data_q      <= {DATA_W{1'b0}};
      w_strb_q      <= {(DATA_W/8){1'b0}};
      bvalid_q      <= 1'b0;
    end else begin
      if (AWVALID && AWREADY) begin
        aw_captured_q <= 1'b1;
        aw_addr_q     <= AWADDR;
      end else if (aw_captured_q && w_captured_q) begin
        aw_captured_q <= 1'b0;
      end

      if (WVALID && WREADY) begin
        w_captured_q <= 1'b1;
        w_data_q     <= WDATA;
        w_strb_q     <= WSTRB;
      end else if (aw_captured_q && w_captured_q) begin
        w_captured_q <= 1'b0;
      end

      if (aw_captured_q && w_captured_q) begin
        wr_idx = aw_addr_q[$clog2(MEM_DEPTH)+1:2];
        if (w_strb_q[0]) mem[wr_idx][7:0]   <= w_data_q[7:0];
        if (w_strb_q[1]) mem[wr_idx][15:8]  <= w_data_q[15:8];
        if (w_strb_q[2]) mem[wr_idx][23:16] <= w_data_q[23:16];
        if (w_strb_q[3]) mem[wr_idx][31:24] <= w_data_q[31:24];
        bvalid_q <= 1'b1;
      end else if (BREADY && bvalid_q) begin
        bvalid_q <= 1'b0;
      end
    end
  end

  // Read path
  always_ff @(posedge clk) begin : p_read
    if (!rst_n) begin
      ar_captured_q <= 1'b0;
      ar_addr_q     <= {ADDR_W{1'b0}};
      rvalid_q      <= 1'b0;
      rdata_q       <= {DATA_W{1'b0}};
    end else begin
      if (ARVALID && ARREADY) begin
        ar_captured_q <= 1'b1;
        ar_addr_q     <= ARADDR;
      end else begin
        ar_captured_q <= 1'b0;
      end

      if (ar_captured_q) begin
        rd_idx   = ar_addr_q[$clog2(MEM_DEPTH)+1:2];
        rdata_q  <= mem[rd_idx];
        rvalid_q <= 1'b1;
      end else if (RREADY && rvalid_q) begin
        rvalid_q <= 1'b0;
      end
    end
  end

  // Always ready to accept address and data
  assign AWREADY = 1'b1;
  assign WREADY  = 1'b1;
  assign ARREADY = 1'b1;

  assign BVALID = bvalid_q;
  assign BRESP  = 2'b00; // OKAY

  assign RVALID = rvalid_q;
  assign RDATA  = rdata_q;
  assign RRESP  = 2'b00; // OKAY

endmodule : bus_matrix_axi_slave

`endif // BUS_MATRIX_AXI_SLAVE_SV
