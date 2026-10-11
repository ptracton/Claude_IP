// tb_bus_matrix_uvm.sv — Top-level UVM testbench for the bus_matrix AXI4-Lite variant.
//
// DUT: bus_matrix_axi4l with its default parameters (bus_matrix_pkg): 2 masters
// (M0 = CPU, M1 = DMA), 4 slaves, round robin, the real address map.
//   Masters: m0_if / m1_if — driven by the UVM AXI4-Lite master agents
//   Slaves:  S0/S1 — shared claude_axi4l_if bridge + bus_matrix_tb_mem
//            S2/S3 — bus_matrix_tb_axi4l_slave (wait states, SLVERR window)
//            Each slave holds 4 KB, aliased across its region.

`timescale 1ns / 1ps

`include "uvm_macros.svh"
import uvm_pkg::*;
import bus_matrix_uvm_pkg::*;

module tb_bus_matrix_uvm;

  localparam int NM     = bus_matrix_pkg::BM_NUM_MASTERS;
  localparam int NS     = bus_matrix_pkg::BM_NUM_SLAVES;
  localparam int DW     = 32;
  localparam int AW     = 32;
  localparam int SW     = DW / 8;
  localparam int MEM_AW = 10; // 1024 words = 4 KB per slave

  // ---- Clock and reset -----------------------------------------------------
  logic clk;
  logic rst_n;

  initial clk = 1'b0;
  always #5 clk = ~clk;   // 100 MHz

  initial begin
    rst_n = 1'b0;
    repeat (10) @(posedge clk);
    rst_n = 1'b1;
  end

  // ---- Virtual interfaces --------------------------------------------------
  bus_matrix_axi_if #(.DATA_W(DW), .ADDR_W(AW)) m0_if (.clk(clk), .rst_n(rst_n));
  bus_matrix_axi_if #(.DATA_W(DW), .ADDR_W(AW)) m1_if (.clk(clk), .rst_n(rst_n));

  // ---- DUT ports (flat-packed) ---------------------------------------------
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


  assign M_AWVALID[0]           = m0_if.AWVALID;
  assign M_AWADDR[0*AW+:AW]     = m0_if.AWADDR;
  assign M_WVALID[0]            = m0_if.WVALID;
  assign M_WDATA[0*DW+:DW]      = m0_if.WDATA;
  assign M_WSTRB[0*SW+:SW]      = m0_if.WSTRB;
  assign M_BREADY[0]            = m0_if.BREADY;
  assign M_ARVALID[0]           = m0_if.ARVALID;
  assign M_ARADDR[0*AW+:AW]     = m0_if.ARADDR;
  assign M_RREADY[0]            = m0_if.RREADY;
  assign m0_if.AWREADY  = M_AWREADY[0];
  assign m0_if.WREADY   = M_WREADY[0];
  assign m0_if.BVALID   = M_BVALID[0];
  assign m0_if.BRESP    = M_BRESP[0*2+:2];
  assign m0_if.ARREADY  = M_ARREADY[0];
  assign m0_if.RVALID   = M_RVALID[0];
  assign m0_if.RDATA    = M_RDATA[0*DW+:DW];
  assign m0_if.RRESP    = M_RRESP[0*2+:2];

  assign M_AWVALID[1]           = m1_if.AWVALID;
  assign M_AWADDR[1*AW+:AW]     = m1_if.AWADDR;
  assign M_WVALID[1]            = m1_if.WVALID;
  assign M_WDATA[1*DW+:DW]      = m1_if.WDATA;
  assign M_WSTRB[1*SW+:SW]      = m1_if.WSTRB;
  assign M_BREADY[1]            = m1_if.BREADY;
  assign M_ARVALID[1]           = m1_if.ARVALID;
  assign M_ARADDR[1*AW+:AW]     = m1_if.ARADDR;
  assign M_RREADY[1]            = m1_if.RREADY;
  assign m1_if.AWREADY  = M_AWREADY[1];
  assign m1_if.WREADY   = M_WREADY[1];
  assign m1_if.BVALID   = M_BVALID[1];
  assign m1_if.BRESP    = M_BRESP[1*2+:2];
  assign m1_if.ARREADY  = M_ARREADY[1];
  assign m1_if.RVALID   = M_RVALID[1];
  assign m1_if.RDATA    = M_RDATA[1*DW+:DW];
  assign m1_if.RRESP    = M_RRESP[1*2+:2];

  // ---- DUT -----------------------------------------------------------------
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
  // Slaves: shared bus bridge + memory
  // -------------------------------------------------------------------------
  // S0/S1: the shared claude_axi4l_if bridge + memory (as in the directed
  // testbench) — always OKAY, no wait states.
  // S2/S3: bus_matrix_tb_axi4l_slave — random wait states on every channel
  // and SLVERR on offsets 0xE00-0xEFF (slave-error propagation).
  for (genvar gj = 0; gj < NS; gj++) begin : gen_slv
    if (gj < 2) begin : g_bridge
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
    end else begin : g_model
      bus_matrix_tb_axi4l_slave #(
        .MEM_AW     (MEM_AW),
        .MAX_WAIT   (gj == 2 ? 2 : 4),
        .ERR_PAGE   (bus_matrix_uvm_pkg::SLV_ERR_PAGE)
      ) u_slv (
        .clk     (clk),
        .rst_n   (rst_n),
        .AWVALID (S_AWVALID[gj]),
        .AWREADY (S_AWREADY[gj]),
        .AWADDR  (S_AWADDR[gj*AW+:AW]),
        .WVALID  (S_WVALID[gj]),
        .WREADY  (S_WREADY[gj]),
        .WDATA   (S_WDATA[gj*DW+:DW]),
        .WSTRB   (S_WSTRB[gj*SW+:SW]),
        .BVALID  (S_BVALID[gj]),
        .BREADY  (S_BREADY[gj]),
        .BRESP   (S_BRESP[gj*2+:2]),
        .ARVALID (S_ARVALID[gj]),
        .ARREADY (S_ARREADY[gj]),
        .ARADDR  (S_ARADDR[gj*AW+:AW]),
        .RVALID  (S_RVALID[gj]),
        .RREADY  (S_RREADY[gj]),
        .RDATA   (S_RDATA[gj*DW+:DW]),
        .RRESP   (S_RRESP[gj*2+:2])
      );
    end
  end

  // ---- UVM start -----------------------------------------------------------
  initial begin
    uvm_config_db #(virtual bus_matrix_axi_if)::set(null, "uvm_test_top.env.m0_agent.*",
                                                     "vif", m0_if);
    uvm_config_db #(virtual bus_matrix_axi_if)::set(null, "uvm_test_top.env.m1_agent.*",
                                                     "vif", m1_if);
    run_test();
  end

  // ---- Timeout watchdog ----------------------------------------------------
  initial begin
    #1_000_000;
    `uvm_fatal("TIMEOUT", "Simulation timeout — hung transaction?")
  end

endmodule : tb_bus_matrix_uvm
