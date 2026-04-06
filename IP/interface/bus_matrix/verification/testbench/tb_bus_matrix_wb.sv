// tb_bus_matrix_wb.sv — Top-level Wishbone bus_matrix testbench.
//
// Instantiates bus_matrix_wb DUT (NUM_MASTERS=2, NUM_SLAVES=2).
// Address map is configured via DUT parameters (no admin port).
// Slave map: S0 at 0x10000000/F0000000, S1 at 0x20000000/F0000000.

module tb_bus_matrix_wb;

  localparam int NM = 2;
  localparam int NS = 2;
  localparam int DW = 32;
  localparam int AW = 32;

  // -------------------------------------------------------------------------
  // Clock and reset
  // -------------------------------------------------------------------------
  logic clk;
  logic rst_n;

  initial clk = 1'b0;
  always #5 clk = ~clk; // 100 MHz

  // -------------------------------------------------------------------------
  // Matrix master ports (flat-packed, NM slots)
  // -------------------------------------------------------------------------
  logic [NM-1:0]      M_CYC;
  logic [NM-1:0]      M_STB;
  logic [NM-1:0]      M_WE;
  logic [NM*AW-1:0]   M_ADR;
  logic [NM*DW-1:0]   M_DAT_I;
  logic [NM*4-1:0]    M_SEL;
  logic [NM*DW-1:0]   M_DAT_O;
  logic [NM-1:0]      M_ACK;
  logic [NM-1:0]      M_ERR;

  // -------------------------------------------------------------------------
  // Matrix slave ports (flat-packed, NS slots)
  // -------------------------------------------------------------------------
  logic [NS-1:0]      S_CYC;
  logic [NS-1:0]      S_STB;
  logic [NS-1:0]      S_WE;
  logic [NS*AW-1:0]   S_ADR;
  logic [NS*DW-1:0]   S_DAT_O;
  logic [NS*4-1:0]    S_SEL;
  logic [NS*DW-1:0]   S_DAT_I;
  logic [NS-1:0]      S_ACK;
  logic [NS-1:0]      S_ERR;

  // -------------------------------------------------------------------------
  // DUT: bus_matrix_wb — address map baked into parameters
  // -------------------------------------------------------------------------
  bus_matrix_wb #(
    .NUM_MASTERS (NM),
    .NUM_SLAVES  (NS),
    .DATA_W      (DW),
    .ADDR_W      (AW),
    .ARB_MODE    (0),
    .M_PRIORITY  (8'h00),
    .S_BASE      (64'h2000_0000_1000_0000),
    .S_MASK      (64'hF000_0000_F000_0000)
  ) u_dut (
    .clk    (clk),
    .rst_n  (rst_n),
    .M_CYC  (M_CYC),
    .M_STB  (M_STB),
    .M_WE   (M_WE),
    .M_ADR  (M_ADR),
    .M_DAT_I(M_DAT_I),
    .M_SEL  (M_SEL),
    .M_DAT_O(M_DAT_O),
    .M_ACK  (M_ACK),
    .M_ERR  (M_ERR),
    .S_CYC  (S_CYC),
    .S_STB  (S_STB),
    .S_WE   (S_WE),
    .S_ADR  (S_ADR),
    .S_DAT_O(S_DAT_O),
    .S_SEL  (S_SEL),
    .S_DAT_I(S_DAT_I),
    .S_ACK  (S_ACK),
    .S_ERR  (S_ERR)
  );

  // -------------------------------------------------------------------------
  // BFM control signals — master 0
  // -------------------------------------------------------------------------
  logic        m0_req;
  logic [31:0] m0_req_addr;
  logic        m0_req_write;
  logic [31:0] m0_req_wdata;
  logic [3:0]  m0_req_strb;
  logic        m0_done;
  logic [31:0] m0_rdata;
  logic        m0_error;

  // -------------------------------------------------------------------------
  // BFM control signals — master 1
  // -------------------------------------------------------------------------
  logic        m1_req;
  logic [31:0] m1_req_addr;
  logic        m1_req_write;
  logic [31:0] m1_req_wdata;
  logic [3:0]  m1_req_strb;
  logic        m1_done;
  logic [31:0] m1_rdata;
  logic        m1_error;

  // -------------------------------------------------------------------------
  // Master 0 BFM
  // -------------------------------------------------------------------------
  bus_matrix_wb_master #(.DATA_W(DW), .ADDR_W(AW)) u_m0 (
    .clk(clk), .rst_n(rst_n),
    .CYC(M_CYC[0]), .STB(M_STB[0]), .WE(M_WE[0]),
    .ADR(M_ADR[31:0]), .DAT_O(M_DAT_I[31:0]), .SEL(M_SEL[3:0]),
    .DAT_I(M_DAT_O[31:0]), .ACK(M_ACK[0]), .ERR(M_ERR[0]),
    .req(m0_req), .req_addr(m0_req_addr), .req_write(m0_req_write),
    .req_wdata(m0_req_wdata), .req_strb(m0_req_strb),
    .done(m0_done), .rdata(m0_rdata), .error(m0_error)
  );

  // -------------------------------------------------------------------------
  // Master 1 BFM
  // -------------------------------------------------------------------------
  bus_matrix_wb_master #(.DATA_W(DW), .ADDR_W(AW)) u_m1 (
    .clk(clk), .rst_n(rst_n),
    .CYC(M_CYC[1]), .STB(M_STB[1]), .WE(M_WE[1]),
    .ADR(M_ADR[63:32]), .DAT_O(M_DAT_I[63:32]), .SEL(M_SEL[7:4]),
    .DAT_I(M_DAT_O[63:32]), .ACK(M_ACK[1]), .ERR(M_ERR[1]),
    .req(m1_req), .req_addr(m1_req_addr), .req_write(m1_req_write),
    .req_wdata(m1_req_wdata), .req_strb(m1_req_strb),
    .done(m1_done), .rdata(m1_rdata), .error(m1_error)
  );

  // -------------------------------------------------------------------------
  // Slave BFMs
  // -------------------------------------------------------------------------
  bus_matrix_wb_slave #(.DATA_W(DW), .ADDR_W(AW), .MEM_DEPTH(256), .SLAVE_IDX(0)) u_s0 (
    .clk(clk), .rst_n(rst_n),
    .CYC(S_CYC[0]), .STB(S_STB[0]), .WE(S_WE[0]),
    .ADR(S_ADR[31:0]), .DAT_O(S_DAT_O[31:0]), .SEL(S_SEL[3:0]),
    .DAT_I(S_DAT_I[31:0]), .ACK(S_ACK[0]), .ERR(S_ERR[0])
  );

  bus_matrix_wb_slave #(.DATA_W(DW), .ADDR_W(AW), .MEM_DEPTH(256), .SLAVE_IDX(1)) u_s1 (
    .clk(clk), .rst_n(rst_n),
    .CYC(S_CYC[1]), .STB(S_STB[1]), .WE(S_WE[1]),
    .ADR(S_ADR[63:32]), .DAT_O(S_DAT_O[63:32]), .SEL(S_SEL[7:4]),
    .DAT_I(S_DAT_I[63:32]), .ACK(S_ACK[1]), .ERR(S_ERR[1])
  );

  // -------------------------------------------------------------------------
  // Includes
  // -------------------------------------------------------------------------
  `include "ip_test_pkg.sv"
  `include "test_bus_matrix_ops.sv"

  // -------------------------------------------------------------------------
  // Stimulus
  // -------------------------------------------------------------------------
  initial begin
    m0_req       = 1'b0;
    m0_req_addr  = 32'h0;
    m0_req_write = 1'b0;
    m0_req_wdata = 32'h0;
    m0_req_strb  = 4'hF;
    m1_req       = 1'b0;
    m1_req_addr  = 32'h0;
    m1_req_write = 1'b0;
    m1_req_wdata = 32'h0;
    m1_req_strb  = 4'hF;

    rst_n = 1'b0;
    repeat(4) @(posedge clk);
    rst_n = 1'b1;
    repeat(2) @(posedge clk);

    test_bus_matrix_ops();

    $display("\nPASS tb_bus_matrix_wb");
    $finish(0);
  end

  initial begin
    #100000;
    $display("FATAL_ERROR: simulation timeout in tb_bus_matrix_wb");
    $finish(1);
  end

endmodule : tb_bus_matrix_wb
