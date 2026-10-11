// tb_bus_matrix_wb.sv — Wishbone B4 bus_matrix directed testbench.
//
// DUT: bus_matrix_wb with its default parameters (bus_matrix_pkg), so the
// same testbench runs the RTL and the Design Compiler gate-level netlist.
//   Masters: u_m0, u_m1 — bus_matrix_wb_bfm (shared tasks_wb.sv)
//   Slaves:  gen_slv[j] — shared claude_wb_if bridge + bus_matrix_tb_mem
// Tests are protocol-neutral (verification/tests/test_*.sv).

`timescale 1ns / 1ps

module tb_bus_matrix_wb;

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
  wire [NM-1:0]         M_CYC;
  wire [NM-1:0]         M_STB;
  wire [NM-1:0]         M_WE;
  wire [NM*AW-1:0]      M_ADR;
  wire [NM*DW-1:0]      M_DAT_I;
  wire [NM*SW-1:0]      M_SEL;
  wire [NM*DW-1:0]      M_DAT_O;
  wire [NM-1:0]         M_ACK;
  wire [NM-1:0]         M_ERR;
  wire [NS-1:0]         S_CYC;
  wire [NS-1:0]         S_STB;
  wire [NS-1:0]         S_WE;
  wire [NS*AW-1:0]      S_ADR;
  wire [NS*DW-1:0]      S_DAT_O;
  wire [NS*SW-1:0]      S_SEL;
  wire [NS*DW-1:0]      S_DAT_I;
  wire [NS-1:0]         S_ACK;
  wire [NS-1:0]         S_ERR;

  bus_matrix_wb u_dut (
    .clk     (clk),
    .rst_n   (rst_n),
    .M_CYC   (M_CYC),
    .M_STB   (M_STB),
    .M_WE    (M_WE),
    .M_ADR   (M_ADR),
    .M_DAT_I (M_DAT_I),
    .M_SEL   (M_SEL),
    .M_DAT_O (M_DAT_O),
    .M_ACK   (M_ACK),
    .M_ERR   (M_ERR),
    .S_CYC   (S_CYC),
    .S_STB   (S_STB),
    .S_WE    (S_WE),
    .S_ADR   (S_ADR),
    .S_DAT_O (S_DAT_O),
    .S_SEL   (S_SEL),
    .S_DAT_I (S_DAT_I),
    .S_ACK   (S_ACK),
    .S_ERR   (S_ERR)
  );

  // -------------------------------------------------------------------------
  // Masters
  // -------------------------------------------------------------------------
  bus_matrix_wb_bfm u_m0 (
    .clk   (clk),
    .CYC_I (M_CYC[0]),
    .STB_I (M_STB[0]),
    .WE_I  (M_WE[0]),
    .ADR_I (M_ADR[0*AW+:AW]),
    .DAT_I (M_DAT_I[0*DW+:DW]),
    .SEL_I (M_SEL[0*SW+:SW]),
    .DAT_O (M_DAT_O[0*DW+:DW]),
    .ACK_O (M_ACK[0]),
    .ERR_O (M_ERR[0])
  );

  bus_matrix_wb_bfm u_m1 (
    .clk   (clk),
    .CYC_I (M_CYC[1]),
    .STB_I (M_STB[1]),
    .WE_I  (M_WE[1]),
    .ADR_I (M_ADR[1*AW+:AW]),
    .DAT_I (M_DAT_I[1*DW+:DW]),
    .SEL_I (M_SEL[1*SW+:SW]),
    .DAT_O (M_DAT_O[1*DW+:DW]),
    .ACK_O (M_ACK[1]),
    .ERR_O (M_ERR[1])
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

    claude_wb_if #(
      .DATA_W (DW),
      .ADDR_W (MEM_AW)
    ) u_if (
      .CLK_I   (clk),
      .RST_I   (~rst_n),
      .CYC_I   (S_CYC[gj]),
      .STB_I   (S_STB[gj]),
      .WE_I    (S_WE[gj]),
      .ADR_I   (S_ADR[gj*AW+:12]),
      .DAT_I   (S_DAT_O[gj*DW+:DW]),
      .SEL_I   (S_SEL[gj*SW+:SW]),
      .DAT_O   (S_DAT_I[gj*DW+:DW]),
      .ACK_O   (S_ACK[gj]),
      .ERR_O   (S_ERR[gj]),
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
  initial $vcdpluson(0, tb_bus_matrix_wb);
`endif

  // Xcelium: $shm_open/$shm_probe write a SimVision waveform database to
  // waves.shm/ in the sim work directory.  INCA is predefined by xrun.
`ifdef INCA
  initial begin
    $shm_open("waves.shm");
    $shm_probe(tb_bus_matrix_wb, "AS");
  end
`endif

  // -------------------------------------------------------------------------
  // Simulation timeout watchdog
  // -------------------------------------------------------------------------
  initial begin
    #2000000;
    $display("FAIL tb_bus_matrix_wb: simulation timeout");
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

    $display("PASS tb_bus_matrix_wb: all tests passed");
    $finish;
  end

endmodule : tb_bus_matrix_wb
