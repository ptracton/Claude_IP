// tb_bus_matrix_ahb.sv — Top-level AHB bus_matrix testbench.
//
// Instantiates bus_matrix_ahb DUT (NUM_MASTERS=2, NUM_SLAVES=2).
// Address map is configured via DUT parameters (no admin port).
// Slave map: S0 at 0x10000000/F0000000, S1 at 0x20000000/F0000000.

module tb_bus_matrix_ahb;

  // -------------------------------------------------------------------------
  // Parameters matching DUT instantiation
  // -------------------------------------------------------------------------
  localparam int NM     = 2;
  localparam int NS     = 2;
  localparam int DW     = 32;
  localparam int AW     = 32;

  // -------------------------------------------------------------------------
  // Clock and reset
  // -------------------------------------------------------------------------
  logic clk;
  logic rst_n;

  initial clk = 1'b0;
  always #5 clk = ~clk; // 100 MHz

  // -------------------------------------------------------------------------
  // Per-master BFM I/O signals
  // -------------------------------------------------------------------------
  // Master 0
  logic        m0_HSEL;
  logic [31:0] m0_HADDR;
  logic [1:0]  m0_HTRANS;
  logic        m0_HWRITE;
  logic [31:0] m0_HWDATA;
  logic [3:0]  m0_HWSTRB;
  logic        m0_HREADY;
  logic [31:0] m0_HRDATA;
  logic        m0_HRESP;
  // Master 1
  logic        m1_HSEL;
  logic [31:0] m1_HADDR;
  logic [1:0]  m1_HTRANS;
  logic        m1_HWRITE;
  logic [31:0] m1_HWDATA;
  logic [3:0]  m1_HWSTRB;
  logic        m1_HREADY;
  logic [31:0] m1_HRDATA;
  logic        m1_HRESP;

  // -------------------------------------------------------------------------
  // Per-slave BFM I/O signals
  // -------------------------------------------------------------------------
  // Slave 0
  logic        s0_HSEL;
  logic [31:0] s0_HADDR;
  logic [1:0]  s0_HTRANS;
  logic        s0_HWRITE;
  logic [31:0] s0_HWDATA;
  logic [3:0]  s0_HWSTRB;
  logic        s0_HREADY;
  logic [31:0] s0_HRDATA;
  logic        s0_HRESP;
  // Slave 1
  logic        s1_HSEL;
  logic [31:0] s1_HADDR;
  logic [1:0]  s1_HTRANS;
  logic        s1_HWRITE;
  logic [31:0] s1_HWDATA;
  logic [3:0]  s1_HWSTRB;
  logic        s1_HREADY;
  logic [31:0] s1_HRDATA;
  logic        s1_HRESP;

  // -------------------------------------------------------------------------
  // Flat-packed buses for DUT (NM=2, NS=2)
  // -------------------------------------------------------------------------
  logic [NM-1:0]      M_HSEL_in;
  logic [NM*AW-1:0]   M_HADDR_in;
  logic [NM*2-1:0]    M_HTRANS_in;
  logic [NM-1:0]      M_HWRITE_in;
  logic [NM*DW-1:0]   M_HWDATA_in;
  logic [NM*4-1:0]    M_HWSTRB_in;
  assign M_HSEL_in    = {m1_HSEL,   m0_HSEL};
  assign M_HADDR_in   = {m1_HADDR,  m0_HADDR};
  assign M_HTRANS_in  = {m1_HTRANS, m0_HTRANS};
  assign M_HWRITE_in  = {m1_HWRITE, m0_HWRITE};
  assign M_HWDATA_in  = {m1_HWDATA, m0_HWDATA};
  assign M_HWSTRB_in  = {m1_HWSTRB, m0_HWSTRB};

  logic [NM-1:0]      M_HREADY_out;
  logic [NM*DW-1:0]   M_HRDATA_out;
  logic [NM-1:0]      M_HRESP_out;
  assign m0_HREADY = M_HREADY_out[0];
  assign m0_HRDATA = M_HRDATA_out[31:0];
  assign m0_HRESP  = M_HRESP_out[0];
  assign m1_HREADY = M_HREADY_out[1];
  assign m1_HRDATA = M_HRDATA_out[63:32];
  assign m1_HRESP  = M_HRESP_out[1];

  logic [NS-1:0]      S_HREADY_in;
  logic [NS*DW-1:0]   S_HRDATA_in;
  logic [NS-1:0]      S_HRESP_in;
  assign S_HREADY_in = {s1_HREADY, s0_HREADY};
  assign S_HRDATA_in = {s1_HRDATA, s0_HRDATA};
  assign S_HRESP_in  = {s1_HRESP,  s0_HRESP};

  logic [NS-1:0]      S_HSEL_out;
  logic [NS*AW-1:0]   S_HADDR_out;
  logic [NS*2-1:0]    S_HTRANS_out;
  logic [NS-1:0]      S_HWRITE_out;
  logic [NS*DW-1:0]   S_HWDATA_out;
  logic [NS*4-1:0]    S_HWSTRB_out;
  assign s0_HSEL   = S_HSEL_out[0];
  assign s0_HADDR  = S_HADDR_out[31:0];
  assign s0_HTRANS = S_HTRANS_out[1:0];
  assign s0_HWRITE = S_HWRITE_out[0];
  assign s0_HWDATA = S_HWDATA_out[31:0];
  assign s0_HWSTRB = S_HWSTRB_out[3:0];
  assign s1_HSEL   = S_HSEL_out[1];
  assign s1_HADDR  = S_HADDR_out[63:32];
  assign s1_HTRANS = S_HTRANS_out[3:2];
  assign s1_HWRITE = S_HWRITE_out[1];
  assign s1_HWDATA = S_HWDATA_out[63:32];
  assign s1_HWSTRB = S_HWSTRB_out[7:4];

  // -------------------------------------------------------------------------
  // DUT: bus_matrix_ahb — address map baked into parameters
  //   S0: base=0x10000000, mask=0xF0000000
  //   S1: base=0x20000000, mask=0xF0000000
  // -------------------------------------------------------------------------
  bus_matrix_ahb #(
    .NUM_MASTERS (NM),
    .NUM_SLAVES  (NS),
    .DATA_W      (DW),
    .ADDR_W      (AW),
    .ARB_MODE    (0),
    .M_PRIORITY  (8'h00),           // both masters priority 0 (tie-break by index)
    .S_BASE      (64'h2000_0000_1000_0000),  // [63:32]=S1_BASE, [31:0]=S0_BASE
    .S_MASK      (64'hF000_0000_F000_0000)   // [63:32]=S1_MASK, [31:0]=S0_MASK
  ) u_dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .M_HSEL   (M_HSEL_in),
    .M_HADDR  (M_HADDR_in),
    .M_HTRANS (M_HTRANS_in),
    .M_HWRITE (M_HWRITE_in),
    .M_HWDATA (M_HWDATA_in),
    .M_HWSTRB (M_HWSTRB_in),
    .M_HREADY (M_HREADY_out),
    .M_HRDATA (M_HRDATA_out),
    .M_HRESP  (M_HRESP_out),
    .S_HSEL   (S_HSEL_out),
    .S_HADDR  (S_HADDR_out),
    .S_HTRANS (S_HTRANS_out),
    .S_HWRITE (S_HWRITE_out),
    .S_HWDATA (S_HWDATA_out),
    .S_HWSTRB (S_HWSTRB_out),
    .S_HREADY (S_HREADY_in),
    .S_HRDATA (S_HRDATA_in),
    .S_HRESP  (S_HRESP_in)
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
  bus_matrix_ahb_master #(
    .DATA_W (DW),
    .ADDR_W (AW)
  ) u_m0 (
    .clk       (clk),
    .rst_n     (rst_n),
    .HSEL      (m0_HSEL),
    .HADDR     (m0_HADDR),
    .HTRANS    (m0_HTRANS),
    .HWRITE    (m0_HWRITE),
    .HWDATA    (m0_HWDATA),
    .HWSTRB    (m0_HWSTRB),
    .HREADY    (m0_HREADY),
    .HRDATA    (m0_HRDATA),
    .HRESP     (m0_HRESP),
    .req       (m0_req),
    .req_addr  (m0_req_addr),
    .req_write (m0_req_write),
    .req_wdata (m0_req_wdata),
    .req_strb  (m0_req_strb),
    .done      (m0_done),
    .rdata     (m0_rdata),
    .error     (m0_error)
  );

  // -------------------------------------------------------------------------
  // Master 1 BFM
  // -------------------------------------------------------------------------
  bus_matrix_ahb_master #(
    .DATA_W (DW),
    .ADDR_W (AW)
  ) u_m1 (
    .clk       (clk),
    .rst_n     (rst_n),
    .HSEL      (m1_HSEL),
    .HADDR     (m1_HADDR),
    .HTRANS    (m1_HTRANS),
    .HWRITE    (m1_HWRITE),
    .HWDATA    (m1_HWDATA),
    .HWSTRB    (m1_HWSTRB),
    .HREADY    (m1_HREADY),
    .HRDATA    (m1_HRDATA),
    .HRESP     (m1_HRESP),
    .req       (m1_req),
    .req_addr  (m1_req_addr),
    .req_write (m1_req_write),
    .req_wdata (m1_req_wdata),
    .req_strb  (m1_req_strb),
    .done      (m1_done),
    .rdata     (m1_rdata),
    .error     (m1_error)
  );

  // -------------------------------------------------------------------------
  // Slave 0 BFM
  // -------------------------------------------------------------------------
  bus_matrix_ahb_slave #(
    .DATA_W    (DW),
    .ADDR_W    (AW),
    .MEM_DEPTH (256),
    .SLAVE_IDX (0)
  ) u_s0 (
    .clk    (clk),
    .rst_n  (rst_n),
    .HSEL   (s0_HSEL),
    .HADDR  (s0_HADDR),
    .HTRANS (s0_HTRANS),
    .HWRITE (s0_HWRITE),
    .HWDATA (s0_HWDATA),
    .HWSTRB (s0_HWSTRB),
    .HREADY (s0_HREADY),
    .HRDATA (s0_HRDATA),
    .HRESP  (s0_HRESP)
  );

  // -------------------------------------------------------------------------
  // Slave 1 BFM
  // -------------------------------------------------------------------------
  bus_matrix_ahb_slave #(
    .DATA_W    (DW),
    .ADDR_W    (AW),
    .MEM_DEPTH (256),
    .SLAVE_IDX (1)
  ) u_s1 (
    .clk    (clk),
    .rst_n  (rst_n),
    .HSEL   (s1_HSEL),
    .HADDR  (s1_HADDR),
    .HTRANS (s1_HTRANS),
    .HWRITE (s1_HWRITE),
    .HWDATA (s1_HWDATA),
    .HWSTRB (s1_HWSTRB),
    .HREADY (s1_HREADY),
    .HRDATA (s1_HRDATA),
    .HRESP  (s1_HRESP)
  );

  // -------------------------------------------------------------------------
  // Includes — placed after all signal/module declarations
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

    // Reset
    rst_n = 1'b0;
    repeat(4) @(posedge clk);
    rst_n = 1'b1;
    repeat(2) @(posedge clk);

    // Address map is already active via parameters — run fabric tests immediately
    test_bus_matrix_ops();

    $display("\nPASS tb_bus_matrix_ahb");
    $finish(0);
  end

  // -------------------------------------------------------------------------
  // Simulation timeout watchdog
  // -------------------------------------------------------------------------
  initial begin
    #50000;
    $display("FATAL_ERROR: simulation timeout in tb_bus_matrix_ahb");
    $finish(1);
  end

endmodule : tb_bus_matrix_ahb
