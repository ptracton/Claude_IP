// tb_bus_matrix_ahb.sv — AHB-Lite bus_matrix directed testbench.
//
// DUT: bus_matrix_ahb with its default parameters (bus_matrix_pkg), so the
// same testbench runs the RTL and the Design Compiler gate-level netlist.
//   Masters: u_m0, u_m1 — bus_matrix_ahb_bfm (shared tasks_ahb.sv)
//   Slaves:  gen_slv[j] — shared claude_ahb_if bridge + bus_matrix_tb_mem
// Tests are protocol-neutral (verification/tests/test_*.sv).

`timescale 1ns / 1ps

module tb_bus_matrix_ahb;

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
  wire [NM-1:0]         M_HSEL;
  wire [NM*AW-1:0]      M_HADDR;
  wire [NM*2-1:0]       M_HTRANS;
  wire [NM-1:0]         M_HWRITE;
  wire [NM*DW-1:0]      M_HWDATA;
  wire [NM*SW-1:0]      M_HWSTRB;
  wire [NM-1:0]         M_HREADY;
  wire [NM*DW-1:0]      M_HRDATA;
  wire [NM-1:0]         M_HRESP;
  wire [NS-1:0]         S_HSEL;
  wire [NS*AW-1:0]      S_HADDR;
  wire [NS*2-1:0]       S_HTRANS;
  wire [NS-1:0]         S_HWRITE;
  wire [NS*DW-1:0]      S_HWDATA;
  wire [NS*SW-1:0]      S_HWSTRB;
  wire [NS-1:0]         S_HREADY;
  wire [NS*DW-1:0]      S_HRDATA;
  wire [NS-1:0]         S_HRESP;

  bus_matrix_ahb u_dut (
    .clk      (clk),
    .rst_n    (rst_n),
    .M_HSEL   (M_HSEL),
    .M_HADDR  (M_HADDR),
    .M_HTRANS (M_HTRANS),
    .M_HWRITE (M_HWRITE),
    .M_HWDATA (M_HWDATA),
    .M_HWSTRB (M_HWSTRB),
    .M_HREADY (M_HREADY),
    .M_HRDATA (M_HRDATA),
    .M_HRESP  (M_HRESP),
    .S_HSEL   (S_HSEL),
    .S_HADDR  (S_HADDR),
    .S_HTRANS (S_HTRANS),
    .S_HWRITE (S_HWRITE),
    .S_HWDATA (S_HWDATA),
    .S_HWSTRB (S_HWSTRB),
    .S_HREADY (S_HREADY),
    .S_HRDATA (S_HRDATA),
    .S_HRESP  (S_HRESP)
  );

  // -------------------------------------------------------------------------
  // Masters
  // -------------------------------------------------------------------------
  bus_matrix_ahb_bfm u_m0 (
    .clk    (clk),
    .HSEL   (M_HSEL[0]),
    .HADDR  (M_HADDR[0*AW+:AW]),
    .HTRANS (M_HTRANS[0*2+:2]),
    .HWRITE (M_HWRITE[0]),
    .HWDATA (M_HWDATA[0*DW+:DW]),
    .HWSTRB (M_HWSTRB[0*SW+:SW]),
    .HREADY (M_HREADY[0]),
    .HRDATA (M_HRDATA[0*DW+:DW]),
    .HRESP  (M_HRESP[0])
  );

  bus_matrix_ahb_bfm u_m1 (
    .clk    (clk),
    .HSEL   (M_HSEL[1]),
    .HADDR  (M_HADDR[1*AW+:AW]),
    .HTRANS (M_HTRANS[1*2+:2]),
    .HWRITE (M_HWRITE[1]),
    .HWDATA (M_HWDATA[1*DW+:DW]),
    .HWSTRB (M_HWSTRB[1*SW+:SW]),
    .HREADY (M_HREADY[1]),
    .HRDATA (M_HRDATA[1*DW+:DW]),
    .HRESP  (M_HRESP[1])
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

    claude_ahb_if #(
      .DATA_W (DW),
      .ADDR_W (MEM_AW)
    ) u_if (
      .HCLK    (clk),
      .HRESETn (rst_n),
      .HSEL    (S_HSEL[gj]),
      .HADDR   (S_HADDR[gj*AW+:12]),
      .HTRANS  (S_HTRANS[gj*2+:2]),
      .HWRITE  (S_HWRITE[gj]),
      .HWDATA  (S_HWDATA[gj*DW+:DW]),
      .HWSTRB  (S_HWSTRB[gj*SW+:SW]),
      .HREADY  (S_HREADY[gj]),
      .HRDATA  (S_HRDATA[gj*DW+:DW]),
      .HRESP   (S_HRESP[gj]),
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
  initial $vcdpluson(0, tb_bus_matrix_ahb);
`endif

  // Xcelium: $shm_open/$shm_probe write a SimVision waveform database to
  // waves.shm/ in the sim work directory.  INCA is predefined by xrun.
`ifdef INCA
  initial begin
    $shm_open("waves.shm");
    $shm_probe(tb_bus_matrix_ahb, "AS");
  end
`endif

  // -------------------------------------------------------------------------
  // Simulation timeout watchdog
  // -------------------------------------------------------------------------
  initial begin
    #2000000;
    $display("FAIL tb_bus_matrix_ahb: simulation timeout");
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

    $display("PASS tb_bus_matrix_ahb: all tests passed");
    $finish;
  end

endmodule : tb_bus_matrix_ahb
