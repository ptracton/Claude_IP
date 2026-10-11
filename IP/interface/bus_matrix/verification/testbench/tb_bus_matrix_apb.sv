// tb_bus_matrix_apb.sv — APB4 bus_matrix directed testbench.
//
// DUT: bus_matrix_apb with its default parameters (bus_matrix_pkg), so the
// same testbench runs the RTL and the Design Compiler gate-level netlist.
//   Masters: u_m0, u_m1 — bus_matrix_apb_bfm (shared tasks_apb.sv)
//   Slaves:  gen_slv[j] — shared claude_apb_if bridge + bus_matrix_tb_mem
// Tests are protocol-neutral (verification/tests/test_*.sv).

`timescale 1ns / 1ps

module tb_bus_matrix_apb;

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
  wire [NM-1:0]         M_PSEL;
  wire [NM-1:0]         M_PENABLE;
  wire [NM*AW-1:0]      M_PADDR;
  wire [NM-1:0]         M_PWRITE;
  wire [NM*DW-1:0]      M_PWDATA;
  wire [NM*SW-1:0]      M_PSTRB;
  wire [NM*DW-1:0]      M_PRDATA;
  wire [NM-1:0]         M_PREADY;
  wire [NM-1:0]         M_PSLVERR;
  wire [NS-1:0]         S_PSEL;
  wire [NS-1:0]         S_PENABLE;
  wire [NS*AW-1:0]      S_PADDR;
  wire [NS-1:0]         S_PWRITE;
  wire [NS*DW-1:0]      S_PWDATA;
  wire [NS*SW-1:0]      S_PSTRB;
  wire [NS*DW-1:0]      S_PRDATA;
  wire [NS-1:0]         S_PREADY;
  wire [NS-1:0]         S_PSLVERR;

  bus_matrix_apb u_dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .M_PSEL    (M_PSEL),
    .M_PENABLE (M_PENABLE),
    .M_PADDR   (M_PADDR),
    .M_PWRITE  (M_PWRITE),
    .M_PWDATA  (M_PWDATA),
    .M_PSTRB   (M_PSTRB),
    .M_PRDATA  (M_PRDATA),
    .M_PREADY  (M_PREADY),
    .M_PSLVERR (M_PSLVERR),
    .S_PSEL    (S_PSEL),
    .S_PENABLE (S_PENABLE),
    .S_PADDR   (S_PADDR),
    .S_PWRITE  (S_PWRITE),
    .S_PWDATA  (S_PWDATA),
    .S_PSTRB   (S_PSTRB),
    .S_PRDATA  (S_PRDATA),
    .S_PREADY  (S_PREADY),
    .S_PSLVERR (S_PSLVERR)
  );

  // -------------------------------------------------------------------------
  // Masters
  // -------------------------------------------------------------------------
  bus_matrix_apb_bfm u_m0 (
    .clk     (clk),
    .PSEL    (M_PSEL[0]),
    .PENABLE (M_PENABLE[0]),
    .PADDR   (M_PADDR[0*AW+:AW]),
    .PWRITE  (M_PWRITE[0]),
    .PWDATA  (M_PWDATA[0*DW+:DW]),
    .PSTRB   (M_PSTRB[0*SW+:SW]),
    .PRDATA  (M_PRDATA[0*DW+:DW]),
    .PREADY  (M_PREADY[0]),
    .PSLVERR (M_PSLVERR[0])
  );

  bus_matrix_apb_bfm u_m1 (
    .clk     (clk),
    .PSEL    (M_PSEL[1]),
    .PENABLE (M_PENABLE[1]),
    .PADDR   (M_PADDR[1*AW+:AW]),
    .PWRITE  (M_PWRITE[1]),
    .PWDATA  (M_PWDATA[1*DW+:DW]),
    .PSTRB   (M_PSTRB[1*SW+:SW]),
    .PRDATA  (M_PRDATA[1*DW+:DW]),
    .PREADY  (M_PREADY[1]),
    .PSLVERR (M_PSLVERR[1])
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

    claude_apb_if #(
      .DATA_W (DW),
      .ADDR_W (MEM_AW)
    ) u_if (
      .PCLK    (clk),
      .PRESETn (rst_n),
      .PSEL    (S_PSEL[gj]),
      .PENABLE (S_PENABLE[gj]),
      .PADDR   (S_PADDR[gj*AW+:12]),
      .PWRITE  (S_PWRITE[gj]),
      .PWDATA  (S_PWDATA[gj*DW+:DW]),
      .PSTRB   (S_PSTRB[gj*SW+:SW]),
      .PRDATA  (S_PRDATA[gj*DW+:DW]),
      .PREADY  (S_PREADY[gj]),
      .PSLVERR (S_PSLVERR[gj]),
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
  initial $vcdpluson(0, tb_bus_matrix_apb);
`endif

  // Xcelium: $shm_open/$shm_probe write a SimVision waveform database to
  // waves.shm/ in the sim work directory.  INCA is predefined by xrun.
`ifdef INCA
  initial begin
    $shm_open("waves.shm");
    $shm_probe(tb_bus_matrix_apb, "AS");
  end
`endif

  // -------------------------------------------------------------------------
  // Simulation timeout watchdog
  // -------------------------------------------------------------------------
  initial begin
    #2000000;
    $display("FAIL tb_bus_matrix_apb: simulation timeout");
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

    $display("PASS tb_bus_matrix_apb: all tests passed");
    $finish;
  end

endmodule : tb_bus_matrix_apb
