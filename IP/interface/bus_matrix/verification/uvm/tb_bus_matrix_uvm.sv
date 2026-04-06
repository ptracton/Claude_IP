// tb_bus_matrix_uvm.sv — Top-level UVM testbench for bus_matrix AXI4-Lite variant.
//
// Instantiates the DUT (bus_matrix_axi) with 2 masters and 2 slaves.
// Address map configured via parameters (no admin port).
//   S0: base=0x1000_0000 mask=0xF000_0000
//   S1: base=0x2000_0000 mask=0xF000_0000

`timescale 1ns/1ps

`include "uvm_macros.svh"
import uvm_pkg::*;
import bus_matrix_uvm_pkg::*;

module tb_bus_matrix_uvm;

  // ---- Parameters ----------------------------------------------------------
  localparam int NUM_MASTERS = 2;
  localparam int NUM_SLAVES  = 2;
  localparam int DATA_W      = 32;
  localparam int ADDR_W      = 32;

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
  bus_matrix_axi_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) m0_if (.clk(clk), .rst_n(rst_n));
  bus_matrix_axi_if #(.DATA_W(DATA_W), .ADDR_W(ADDR_W)) m1_if (.clk(clk), .rst_n(rst_n));

  // ---- Slave nets ----------------------------------------------------------
  // S0
  logic s0_awvalid, s0_awready; logic [ADDR_W-1:0] s0_awaddr;
  logic s0_wvalid,  s0_wready;  logic [DATA_W-1:0] s0_wdata; logic [DATA_W/8-1:0] s0_wstrb;
  logic s0_bvalid,  s0_bready;  logic [1:0] s0_bresp;
  logic s0_arvalid, s0_arready; logic [ADDR_W-1:0] s0_araddr;
  logic s0_rvalid,  s0_rready;  logic [DATA_W-1:0] s0_rdata; logic [1:0] s0_rresp;
  // S1
  logic s1_awvalid, s1_awready; logic [ADDR_W-1:0] s1_awaddr;
  logic s1_wvalid,  s1_wready;  logic [DATA_W-1:0] s1_wdata; logic [DATA_W/8-1:0] s1_wstrb;
  logic s1_bvalid,  s1_bready;  logic [1:0] s1_bresp;
  logic s1_arvalid, s1_arready; logic [ADDR_W-1:0] s1_araddr;
  logic s1_rvalid,  s1_rready;  logic [DATA_W-1:0] s1_rdata; logic [1:0] s1_rresp;

  // ---- Flat-packed master/slave buses --------------------------------------
  logic [NUM_MASTERS-1:0]         M_AWVALID_in, M_AWREADY_out;
  logic [NUM_MASTERS*ADDR_W-1:0]  M_AWADDR_in;
  logic [NUM_MASTERS-1:0]         M_WVALID_in, M_WREADY_out;
  logic [NUM_MASTERS*DATA_W-1:0]  M_WDATA_in;
  logic [NUM_MASTERS*4-1:0]       M_WSTRB_in;
  logic [NUM_MASTERS-1:0]         M_BVALID_out;
  logic [NUM_MASTERS-1:0]         M_BREADY_in;
  logic [NUM_MASTERS*2-1:0]       M_BRESP_out;
  logic [NUM_MASTERS-1:0]         M_ARVALID_in, M_ARREADY_out;
  logic [NUM_MASTERS*ADDR_W-1:0]  M_ARADDR_in;
  logic [NUM_MASTERS-1:0]         M_RVALID_out;
  logic [NUM_MASTERS-1:0]         M_RREADY_in;
  logic [NUM_MASTERS*DATA_W-1:0]  M_RDATA_out;
  logic [NUM_MASTERS*2-1:0]       M_RRESP_out;

  assign M_AWVALID_in = {m1_if.AWVALID, m0_if.AWVALID};
  assign M_AWADDR_in  = {m1_if.AWADDR,  m0_if.AWADDR};
  assign M_WVALID_in  = {m1_if.WVALID,  m0_if.WVALID};
  assign M_WDATA_in   = {m1_if.WDATA,   m0_if.WDATA};
  assign M_WSTRB_in   = {m1_if.WSTRB,   m0_if.WSTRB};
  assign M_BREADY_in  = {m1_if.BREADY,  m0_if.BREADY};
  assign M_ARVALID_in = {m1_if.ARVALID, m0_if.ARVALID};
  assign M_ARADDR_in  = {m1_if.ARADDR,  m0_if.ARADDR};
  assign M_RREADY_in  = {m1_if.RREADY,  m0_if.RREADY};

  assign m0_if.AWREADY = M_AWREADY_out[0];
  assign m1_if.AWREADY = M_AWREADY_out[1];
  assign m0_if.WREADY  = M_WREADY_out[0];
  assign m1_if.WREADY  = M_WREADY_out[1];
  assign m0_if.BVALID  = M_BVALID_out[0];
  assign m1_if.BVALID  = M_BVALID_out[1];
  assign m0_if.BRESP   = M_BRESP_out[1:0];
  assign m1_if.BRESP   = M_BRESP_out[3:2];
  assign m0_if.ARREADY = M_ARREADY_out[0];
  assign m1_if.ARREADY = M_ARREADY_out[1];
  assign m0_if.RVALID  = M_RVALID_out[0];
  assign m1_if.RVALID  = M_RVALID_out[1];
  assign m0_if.RDATA   = M_RDATA_out[DATA_W-1:0];
  assign m1_if.RDATA   = M_RDATA_out[2*DATA_W-1:DATA_W];
  assign m0_if.RRESP   = M_RRESP_out[1:0];
  assign m1_if.RRESP   = M_RRESP_out[3:2];

  // Slave flat bus
  logic [NUM_SLAVES-1:0]          S_AWVALID_out, S_AWREADY_in;
  logic [NUM_SLAVES*ADDR_W-1:0]   S_AWADDR_out;
  logic [NUM_SLAVES-1:0]          S_WVALID_out, S_WREADY_in;
  logic [NUM_SLAVES*DATA_W-1:0]   S_WDATA_out;
  logic [NUM_SLAVES*4-1:0]        S_WSTRB_out;
  logic [NUM_SLAVES-1:0]          S_BVALID_in;
  logic [NUM_SLAVES-1:0]          S_BREADY_out;
  logic [NUM_SLAVES*2-1:0]        S_BRESP_in;
  logic [NUM_SLAVES-1:0]          S_ARVALID_out, S_ARREADY_in;
  logic [NUM_SLAVES*ADDR_W-1:0]   S_ARADDR_out;
  logic [NUM_SLAVES-1:0]          S_RVALID_in;
  logic [NUM_SLAVES-1:0]          S_RREADY_out;
  logic [NUM_SLAVES*DATA_W-1:0]   S_RDATA_in;
  logic [NUM_SLAVES*2-1:0]        S_RRESP_in;

  assign s0_awvalid = S_AWVALID_out[0]; assign s0_awaddr = S_AWADDR_out[ADDR_W-1:0];
  assign s1_awvalid = S_AWVALID_out[1]; assign s1_awaddr = S_AWADDR_out[2*ADDR_W-1:ADDR_W];
  assign s0_wvalid  = S_WVALID_out[0];  assign s0_wdata  = S_WDATA_out[DATA_W-1:0];
  assign s1_wvalid  = S_WVALID_out[1];  assign s1_wdata  = S_WDATA_out[2*DATA_W-1:DATA_W];
  assign s0_wstrb   = S_WSTRB_out[3:0]; assign s1_wstrb  = S_WSTRB_out[7:4];
  assign s0_bready  = S_BREADY_out[0];  assign s1_bready = S_BREADY_out[1];
  assign s0_arvalid = S_ARVALID_out[0]; assign s0_araddr = S_ARADDR_out[ADDR_W-1:0];
  assign s1_arvalid = S_ARVALID_out[1]; assign s1_araddr = S_ARADDR_out[2*ADDR_W-1:ADDR_W];
  assign s0_rready  = S_RREADY_out[0];  assign s1_rready = S_RREADY_out[1];

  assign S_AWREADY_in = {s1_awready, s0_awready};
  assign S_WREADY_in  = {s1_wready,  s0_wready};
  assign S_BVALID_in  = {s1_bvalid,  s0_bvalid};
  assign S_BRESP_in   = {s1_bresp,   s0_bresp};
  assign S_ARREADY_in = {s1_arready, s0_arready};
  assign S_RVALID_in  = {s1_rvalid,  s0_rvalid};
  assign S_RDATA_in   = {s1_rdata,   s0_rdata};
  assign S_RRESP_in   = {s1_rresp,   s0_rresp};

  // Slave BFMs
  bus_matrix_axi_slave #(
    .DATA_W(DATA_W), .ADDR_W(ADDR_W), .MEM_DEPTH(256), .SLAVE_IDX(0)
  ) u_s0 (
    .clk     (clk),        .rst_n   (rst_n),
    .AWVALID (s0_awvalid), .AWREADY (s0_awready), .AWADDR  (s0_awaddr),
    .WVALID  (s0_wvalid),  .WREADY  (s0_wready),  .WDATA   (s0_wdata), .WSTRB (s0_wstrb),
    .BVALID  (s0_bvalid),  .BREADY  (s0_bready),  .BRESP   (s0_bresp),
    .ARVALID (s0_arvalid), .ARREADY (s0_arready), .ARADDR  (s0_araddr),
    .RVALID  (s0_rvalid),  .RREADY  (s0_rready),  .RDATA   (s0_rdata), .RRESP (s0_rresp)
  );

  bus_matrix_axi_slave #(
    .DATA_W(DATA_W), .ADDR_W(ADDR_W), .MEM_DEPTH(256), .SLAVE_IDX(1)
  ) u_s1 (
    .clk     (clk),        .rst_n   (rst_n),
    .AWVALID (s1_awvalid), .AWREADY (s1_awready), .AWADDR  (s1_awaddr),
    .WVALID  (s1_wvalid),  .WREADY  (s1_wready),  .WDATA   (s1_wdata), .WSTRB (s1_wstrb),
    .BVALID  (s1_bvalid),  .BREADY  (s1_bready),  .BRESP   (s1_bresp),
    .ARVALID (s1_arvalid), .ARREADY (s1_arready), .ARADDR  (s1_araddr),
    .RVALID  (s1_rvalid),  .RREADY  (s1_rready),  .RDATA   (s1_rdata), .RRESP (s1_rresp)
  );

  // ---- DUT -----------------------------------------------------------------
  bus_matrix_axi #(
    .NUM_MASTERS (NUM_MASTERS),
    .NUM_SLAVES  (NUM_SLAVES),
    .DATA_W      (DATA_W),
    .ADDR_W      (ADDR_W),
    .ARB_MODE    (0),
    .M_PRIORITY  (8'h21),                         // M0=1, M1=2
    .S_BASE      (64'h2000_0000_1000_0000),       // S0=0x10000000, S1=0x20000000
    .S_MASK      (64'hF000_0000_F000_0000)        // S0=0xF0000000, S1=0xF0000000
  ) u_dut (
    .clk       (clk),
    .rst_n     (rst_n),
    .M_AWVALID (M_AWVALID_in),  .M_AWREADY (M_AWREADY_out), .M_AWADDR (M_AWADDR_in),
    .M_WVALID  (M_WVALID_in),   .M_WREADY  (M_WREADY_out),  .M_WDATA  (M_WDATA_in),
    .M_WSTRB   (M_WSTRB_in),
    .M_BVALID  (M_BVALID_out),  .M_BREADY  (M_BREADY_in),   .M_BRESP  (M_BRESP_out),
    .M_ARVALID (M_ARVALID_in),  .M_ARREADY (M_ARREADY_out), .M_ARADDR (M_ARADDR_in),
    .M_RVALID  (M_RVALID_out),  .M_RREADY  (M_RREADY_in),
    .M_RDATA   (M_RDATA_out),   .M_RRESP   (M_RRESP_out),
    .S_AWVALID (S_AWVALID_out), .S_AWREADY (S_AWREADY_in),  .S_AWADDR (S_AWADDR_out),
    .S_WVALID  (S_WVALID_out),  .S_WREADY  (S_WREADY_in),   .S_WDATA  (S_WDATA_out),
    .S_WSTRB   (S_WSTRB_out),
    .S_BVALID  (S_BVALID_in),   .S_BREADY  (S_BREADY_out),  .S_BRESP  (S_BRESP_in),
    .S_ARVALID (S_ARVALID_out), .S_ARREADY (S_ARREADY_in),  .S_ARADDR (S_ARADDR_out),
    .S_RVALID  (S_RVALID_in),   .S_RREADY  (S_RREADY_out),
    .S_RDATA   (S_RDATA_in),    .S_RRESP   (S_RRESP_in)
  );

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
