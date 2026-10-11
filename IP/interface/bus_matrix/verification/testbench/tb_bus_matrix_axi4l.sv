// tb_bus_matrix_axi4l.sv — AXI4-Lite bus_matrix directed testbench.
//
// DUT: bus_matrix_axi4l with its default parameters (bus_matrix_pkg), so the
// same testbench runs the RTL and the Design Compiler gate-level netlist.
//   Masters: u_m0, u_m1 — bus_matrix_axi4l_bfm (shared tasks_axi4l.sv)
//   Slaves:  gen_slv[j] — shared claude_axi4l_if bridge + bus_matrix_tb_mem
// Tests are protocol-neutral (verification/tests/test_*.sv).

`timescale 1ns / 1ps

module tb_bus_matrix_axi4l;

  localparam int NM     = bus_matrix_pkg::BM_NUM_MASTERS;
  localparam int NS     = bus_matrix_pkg::BM_NUM_SLAVES;
  localparam int DW     = 32;
  localparam int AW     = 32;
  localparam int SW     = DW / 8;
  localparam int MEM_AW = 10; // 1024 words = 4 KB per slave

  // -------------------------------------------------------------------------
  // Clock and reset
  // -------------------------------------------------------------------------
  logic clk;
  logic rst_n;

  initial clk = 1'b0;
  always #5 clk = ~clk; // 100 MHz

  // -------------------------------------------------------------------------
  // DUT ports (flat-packed)
  // -------------------------------------------------------------------------
  wire [NM-1:0]         M_AWVALID;
  wire [NM-1:0]         M_AWREADY;
  wire [NM*AW-1:0]      M_AWADDR;
  wire [NM-1:0]         M_WVALID;
  wire [NM-1:0]         M_WREADY;
  wire [NM*DW-1:0]      M_WDATA;
  wire [NM*SW-1:0]      M_WSTRB;
  wire [NM-1:0]         M_BVALID;
  wire [NM-1:0]         M_BREADY;
  wire [NM*2-1:0]       M_BRESP;
  wire [NM-1:0]         M_ARVALID;
  wire [NM-1:0]         M_ARREADY;
  wire [NM*AW-1:0]      M_ARADDR;
  wire [NM-1:0]         M_RVALID;
  wire [NM-1:0]         M_RREADY;
  wire [NM*DW-1:0]      M_RDATA;
  wire [NM*2-1:0]       M_RRESP;
  wire [NS-1:0]         S_AWVALID;
  wire [NS-1:0]         S_AWREADY;
  wire [NS*AW-1:0]      S_AWADDR;
  wire [NS-1:0]         S_WVALID;
  wire [NS-1:0]         S_WREADY;
  wire [NS*DW-1:0]      S_WDATA;
  wire [NS*SW-1:0]      S_WSTRB;
  wire [NS-1:0]         S_BVALID;
  wire [NS-1:0]         S_BREADY;
  wire [NS*2-1:0]       S_BRESP;
  wire [NS-1:0]         S_ARVALID;
  wire [NS-1:0]         S_ARREADY;
  wire [NS*AW-1:0]      S_ARADDR;
  wire [NS-1:0]         S_RVALID;
  wire [NS-1:0]         S_RREADY;
  wire [NS*DW-1:0]      S_RDATA;
  wire [NS*2-1:0]       S_RRESP;

  bus_matrix_axi4l u_dut (
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
  // Masters
  // -------------------------------------------------------------------------
  bus_matrix_axi4l_bfm u_m0 (
    .clk     (clk),
    .AWVALID (M_AWVALID[0]),
    .AWREADY (M_AWREADY[0]),
    .AWADDR  (M_AWADDR[0*AW+:AW]),
    .WVALID  (M_WVALID[0]),
    .WREADY  (M_WREADY[0]),
    .WDATA   (M_WDATA[0*DW+:DW]),
    .WSTRB   (M_WSTRB[0*SW+:SW]),
    .BVALID  (M_BVALID[0]),
    .BREADY  (M_BREADY[0]),
    .BRESP   (M_BRESP[0*2+:2]),
    .ARVALID (M_ARVALID[0]),
    .ARREADY (M_ARREADY[0]),
    .ARADDR  (M_ARADDR[0*AW+:AW]),
    .RVALID  (M_RVALID[0]),
    .RREADY  (M_RREADY[0]),
    .RDATA   (M_RDATA[0*DW+:DW]),
    .RRESP   (M_RRESP[0*2+:2])
  );

  bus_matrix_axi4l_bfm u_m1 (
    .clk     (clk),
    .AWVALID (M_AWVALID[1]),
    .AWREADY (M_AWREADY[1]),
    .AWADDR  (M_AWADDR[1*AW+:AW]),
    .WVALID  (M_WVALID[1]),
    .WREADY  (M_WREADY[1]),
    .WDATA   (M_WDATA[1*DW+:DW]),
    .WSTRB   (M_WSTRB[1*SW+:SW]),
    .BVALID  (M_BVALID[1]),
    .BREADY  (M_BREADY[1]),
    .BRESP   (M_BRESP[1*2+:2]),
    .ARVALID (M_ARVALID[1]),
    .ARREADY (M_ARREADY[1]),
    .ARADDR  (M_ARADDR[1*AW+:AW]),
    .RVALID  (M_RVALID[1]),
    .RREADY  (M_RREADY[1]),
    .RDATA   (M_RDATA[1*DW+:DW]),
    .RRESP   (M_RRESP[1*2+:2])
  );

  // -------------------------------------------------------------------------
  // Slaves: shared bus bridge + memory
  // -------------------------------------------------------------------------
  for (genvar gj = 0; gj < NS; gj++) begin : gen_slv
    logic              wr_en;
    logic [MEM_AW-1:0] wr_addr;
    logic [DW-1:0]     wr_data;
    logic [SW-1:0]     wr_strb;
    logic              rd_en;
    logic [MEM_AW-1:0] rd_addr;
    logic [DW-1:0]     rd_data;

    claude_axi4l_if #(
      .DATA_W (DW),
      .ADDR_W (MEM_AW)
    ) u_if (
      .ACLK    (clk),
      .ARESETn (rst_n),
      .AWVALID (S_AWVALID[gj]),
      .AWREADY (S_AWREADY[gj]),
      .AWADDR  (S_AWADDR[gj*AW+:12]),
      .WVALID  (S_WVALID[gj]),
      .WREADY  (S_WREADY[gj]),
      .WDATA   (S_WDATA[gj*DW+:DW]),
      .WSTRB   (S_WSTRB[gj*SW+:SW]),
      .BVALID  (S_BVALID[gj]),
      .BREADY  (S_BREADY[gj]),
      .BRESP   (S_BRESP[gj*2+:2]),
      .ARVALID (S_ARVALID[gj]),
      .ARREADY (S_ARREADY[gj]),
      .ARADDR  (S_ARADDR[gj*AW+:12]),
      .RVALID  (S_RVALID[gj]),
      .RREADY  (S_RREADY[gj]),
      .RDATA   (S_RDATA[gj*DW+:DW]),
      .RRESP   (S_RRESP[gj*2+:2]),
      .wr_en   (wr_en),
      .wr_addr (wr_addr),
      .wr_data (wr_data),
      .wr_strb (wr_strb),
      .rd_en   (rd_en),
      .rd_addr (rd_addr),
      .rd_data (rd_data)
    );

    bus_matrix_tb_mem #(
      .ADDR_W (MEM_AW)
    ) u_mem (
      .clk     (clk),
      .wr_en   (wr_en),
      .wr_addr (wr_addr),
      .wr_data (wr_data),
      .wr_strb (wr_strb),
      .rd_en   (rd_en),
      .rd_addr (rd_addr),
      .rd_data (rd_data)
    );
  end

  // -------------------------------------------------------------------------
  // Test helpers and directed tests
  // -------------------------------------------------------------------------
  `include "ip_test_pkg.sv"
  `include "test_helpers.sv"
  `include "test_reset.sv"
  `include "test_route.sv"
  `include "test_strobe.sv"
  `include "test_decode_err.sv"
  `include "test_contention.sv"
  `include "test_arb.sv"

  // -------------------------------------------------------------------------
  // Waveform dump
  // -------------------------------------------------------------------------
  // $vcdpluson is a VCS-only PLI task; Xcelium's xrun aborts if it is
  // referenced without being registered, so it must be excluded from any
  // non-VCS compile.  VCS predefines the `VCS macro automatically.
`ifdef VCS
  initial $vcdpluson(0, tb_bus_matrix_axi4l);
`endif

  // Xcelium: $shm_open/$shm_probe write a SimVision waveform database to
  // waves.shm/ in the sim work directory.  INCA is predefined by xrun.
`ifdef INCA
  initial begin
    $shm_open("waves.shm");
    $shm_probe(tb_bus_matrix_axi4l, "AS");
  end
`endif

  // -------------------------------------------------------------------------
  // Simulation timeout watchdog
  // -------------------------------------------------------------------------
  initial begin
    #2000000;
    $display("FAIL tb_bus_matrix_axi4l: simulation timeout");
    $finish(1);
  end

  // -------------------------------------------------------------------------
  // Test stimulus
  // -------------------------------------------------------------------------
  initial begin
    rst_n = 1'b0;
    repeat (8) @(posedge clk);
    rst_n <= 1'b1;
    @(posedge clk);

    test_reset;
    test_route;
    test_strobe;
    test_decode_err;
    test_contention;
    test_arb;

    $display("PASS tb_bus_matrix_axi4l: all tests passed");
    $finish;
  end

endmodule : tb_bus_matrix_axi4l
