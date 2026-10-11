// bus_matrix_axi4l_bfm.sv — One AXI4-Lite master for the bus matrix testbench.
//
// Wraps the shared AXI4-Lite task library (IP/common/verification/tasks/
// tasks_axi4l.sv) around one master port, so a testbench can run several
// masters at once: u_m0.write_reg(...), u_m1.read_reg(...), u_m0.bfm_err.
// Addresses are 32 bits wide.

`define CLAUDE_BFM_ADDR_W 32

`timescale 1ns / 1ps

module bus_matrix_axi4l_bfm (
  input  logic        clk,
  output logic        AWVALID,
  input  logic        AWREADY,
  output logic [31:0] AWADDR,
  output logic        WVALID,
  input  logic        WREADY,
  output logic [31:0] WDATA,
  output logic [3:0]  WSTRB,
  input  logic        BVALID,
  output logic        BREADY,
  input  logic [1:0]  BRESP,
  output logic        ARVALID,
  input  logic        ARREADY,
  output logic [31:0] ARADDR,
  input  logic        RVALID,
  output logic        RREADY,
  input  logic [31:0] RDATA,
  input  logic [1:0]  RRESP
);

  logic rst_n; // driven by apply_reset only; the testbench owns the real reset

  `include "tasks_axi4l.sv"

  initial begin
    AWVALID = 1'b0;
    AWADDR  = '0;
    WVALID  = 1'b0;
    WDATA   = '0;
    WSTRB   = 4'h0;
    BREADY  = 1'b0;
    ARVALID = 1'b0;
    ARADDR  = '0;
    RREADY  = 1'b0;
    bfm_err = 1'b0;
  end

endmodule : bus_matrix_axi4l_bfm

`undef CLAUDE_BFM_ADDR_W
