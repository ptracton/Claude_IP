// tb_bus_matrix_axi.sv — Top-level AXI4-Lite bus_matrix testbench.
//
// Instantiates bus_matrix_axi DUT (NUM_MASTERS=2, NUM_SLAVES=2).
// Address map is configured via DUT parameters (no admin port).
// Slave map: S0 at 0x10000000/F0000000, S1 at 0x20000000/F0000000.

module tb_bus_matrix_axi;

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
  logic [NM-1:0]      M_AWVALID;
  logic [NM-1:0]      M_AWREADY;
  logic [NM*AW-1:0]   M_AWADDR;
  logic [NM-1:0]      M_WVALID;
  logic [NM-1:0]      M_WREADY;
  logic [NM*DW-1:0]   M_WDATA;
  logic [NM*4-1:0]    M_WSTRB;
  logic [NM-1:0]      M_BVALID;
  logic [NM-1:0]      M_BREADY;
  logic [NM*2-1:0]    M_BRESP;
  logic [NM-1:0]      M_ARVALID;
  logic [NM-1:0]      M_ARREADY;
  logic [NM*AW-1:0]   M_ARADDR;
  logic [NM-1:0]      M_RVALID;
  logic [NM-1:0]      M_RREADY;
  logic [NM*DW-1:0]   M_RDATA;
  logic [NM*2-1:0]    M_RRESP;

  // -------------------------------------------------------------------------
  // Matrix slave ports (flat-packed, NS slots)
  // -------------------------------------------------------------------------
  logic [NS-1:0]      S_AWVALID;
  logic [NS-1:0]      S_AWREADY;
  logic [NS*AW-1:0]   S_AWADDR;
  logic [NS-1:0]      S_WVALID;
  logic [NS-1:0]      S_WREADY;
  logic [NS*DW-1:0]   S_WDATA;
  logic [NS*4-1:0]    S_WSTRB;
  logic [NS-1:0]      S_BVALID;
  logic [NS-1:0]      S_BREADY;
  logic [NS*2-1:0]    S_BRESP;
  logic [NS-1:0]      S_ARVALID;
  logic [NS-1:0]      S_ARREADY;
  logic [NS*AW-1:0]   S_ARADDR;
  logic [NS-1:0]      S_RVALID;
  logic [NS-1:0]      S_RREADY;
  logic [NS*DW-1:0]   S_RDATA;
  logic [NS*2-1:0]    S_RRESP;

  // -------------------------------------------------------------------------
  // DUT: bus_matrix_axi — address map baked into parameters
  // -------------------------------------------------------------------------
  bus_matrix_axi #(
    .NUM_MASTERS (NM),
    .NUM_SLAVES  (NS),
    .DATA_W      (DW),
    .ADDR_W      (AW),
    .ARB_MODE    (0),
    .M_PRIORITY  (8'h00),
    .S_BASE      (64'h2000_0000_1000_0000),
    .S_MASK      (64'hF000_0000_F000_0000)
  ) u_dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .M_AWVALID (M_AWVALID),
    .M_AWREADY (M_AWREADY),
    .M_AWADDR  (M_AWADDR),
    .M_WVALID  (M_WVALID),
    .M_WREADY  (M_WREADY),
    .M_WDATA   (M_WDATA),
    .M_WSTRB   (M_WSTRB),
    .M_BVALID  (M_BVALID),
    .M_BREADY  (M_BREADY),
    .M_BRESP   (M_BRESP),
    .M_ARVALID (M_ARVALID),
    .M_ARREADY (M_ARREADY),
    .M_ARADDR  (M_ARADDR),
    .M_RVALID  (M_RVALID),
    .M_RREADY  (M_RREADY),
    .M_RDATA   (M_RDATA),
    .M_RRESP   (M_RRESP),
    .S_AWVALID (S_AWVALID),
    .S_AWREADY (S_AWREADY),
    .S_AWADDR  (S_AWADDR),
    .S_WVALID  (S_WVALID),
    .S_WREADY  (S_WREADY),
    .S_WDATA   (S_WDATA),
    .S_WSTRB   (S_WSTRB),
    .S_BVALID  (S_BVALID),
    .S_BREADY  (S_BREADY),
    .S_BRESP   (S_BRESP),
    .S_ARVALID (S_ARVALID),
    .S_ARREADY (S_ARREADY),
    .S_ARADDR  (S_ARADDR),
    .S_RVALID  (S_RVALID),
    .S_RREADY  (S_RREADY),
    .S_RDATA   (S_RDATA),
    .S_RRESP   (S_RRESP)
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
  // Master BFMs
  // -------------------------------------------------------------------------
  bus_matrix_axi_master #(.DATA_W(DW), .ADDR_W(AW)) u_m0 (
    .clk(clk), .rst_n(rst_n),
    .AWVALID(M_AWVALID[0]), .AWREADY(M_AWREADY[0]), .AWADDR(M_AWADDR[31:0]),
    .WVALID(M_WVALID[0]),   .WREADY(M_WREADY[0]),   .WDATA(M_WDATA[31:0]),  .WSTRB(M_WSTRB[3:0]),
    .BVALID(M_BVALID[0]),   .BREADY(M_BREADY[0]),   .BRESP(M_BRESP[1:0]),
    .ARVALID(M_ARVALID[0]), .ARREADY(M_ARREADY[0]), .ARADDR(M_ARADDR[31:0]),
    .RVALID(M_RVALID[0]),   .RREADY(M_RREADY[0]),   .RDATA(M_RDATA[31:0]),  .RRESP(M_RRESP[1:0]),
    .req(m0_req), .req_addr(m0_req_addr), .req_write(m0_req_write),
    .req_wdata(m0_req_wdata), .req_strb(m0_req_strb),
    .done(m0_done), .rdata(m0_rdata), .error(m0_error)
  );

  bus_matrix_axi_master #(.DATA_W(DW), .ADDR_W(AW)) u_m1 (
    .clk(clk), .rst_n(rst_n),
    .AWVALID(M_AWVALID[1]), .AWREADY(M_AWREADY[1]), .AWADDR(M_AWADDR[63:32]),
    .WVALID(M_WVALID[1]),   .WREADY(M_WREADY[1]),   .WDATA(M_WDATA[63:32]),  .WSTRB(M_WSTRB[7:4]),
    .BVALID(M_BVALID[1]),   .BREADY(M_BREADY[1]),   .BRESP(M_BRESP[3:2]),
    .ARVALID(M_ARVALID[1]), .ARREADY(M_ARREADY[1]), .ARADDR(M_ARADDR[63:32]),
    .RVALID(M_RVALID[1]),   .RREADY(M_RREADY[1]),   .RDATA(M_RDATA[63:32]),  .RRESP(M_RRESP[3:2]),
    .req(m1_req), .req_addr(m1_req_addr), .req_write(m1_req_write),
    .req_wdata(m1_req_wdata), .req_strb(m1_req_strb),
    .done(m1_done), .rdata(m1_rdata), .error(m1_error)
  );

  // -------------------------------------------------------------------------
  // Slave BFMs
  // -------------------------------------------------------------------------
  bus_matrix_axi_slave #(.DATA_W(DW), .ADDR_W(AW), .MEM_DEPTH(256), .SLAVE_IDX(0)) u_s0 (
    .clk(clk), .rst_n(rst_n),
    .AWVALID(S_AWVALID[0]), .AWREADY(S_AWREADY[0]), .AWADDR(S_AWADDR[31:0]),
    .WVALID(S_WVALID[0]),   .WREADY(S_WREADY[0]),   .WDATA(S_WDATA[31:0]),  .WSTRB(S_WSTRB[3:0]),
    .BVALID(S_BVALID[0]),   .BREADY(S_BREADY[0]),   .BRESP(S_BRESP[1:0]),
    .ARVALID(S_ARVALID[0]), .ARREADY(S_ARREADY[0]), .ARADDR(S_ARADDR[31:0]),
    .RVALID(S_RVALID[0]),   .RREADY(S_RREADY[0]),   .RDATA(S_RDATA[31:0]),  .RRESP(S_RRESP[1:0])
  );

  bus_matrix_axi_slave #(.DATA_W(DW), .ADDR_W(AW), .MEM_DEPTH(256), .SLAVE_IDX(1)) u_s1 (
    .clk(clk), .rst_n(rst_n),
    .AWVALID(S_AWVALID[1]), .AWREADY(S_AWREADY[1]), .AWADDR(S_AWADDR[63:32]),
    .WVALID(S_WVALID[1]),   .WREADY(S_WREADY[1]),   .WDATA(S_WDATA[63:32]),  .WSTRB(S_WSTRB[7:4]),
    .BVALID(S_BVALID[1]),   .BREADY(S_BREADY[1]),   .BRESP(S_BRESP[3:2]),
    .ARVALID(S_ARVALID[1]), .ARREADY(S_ARREADY[1]), .ARADDR(S_ARADDR[63:32]),
    .RVALID(S_RVALID[1]),   .RREADY(S_RREADY[1]),   .RDATA(S_RDATA[63:32]),  .RRESP(S_RRESP[3:2])
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

    $display("\nPASS tb_bus_matrix_axi");
    $finish(0);
  end

  initial begin
    #100000;
    $display("FATAL_ERROR: simulation timeout in tb_bus_matrix_axi");
    $finish(1);
  end

endmodule : tb_bus_matrix_axi
