// bus_matrix_ahb_bfm.sv — One AHB-Lite master for the bus matrix testbench.
//
// Wraps the shared AHB-Lite task library (IP/common/verification/tasks/
// tasks_ahb.sv) around one master port, so a testbench can run several
// masters at once: u_m0.write_reg(...), u_m1.read_reg(...), u_m0.bfm_err.
// Addresses are 32 bits wide.

`define CLAUDE_BFM_ADDR_W 32

`timescale 1ns / 1ps

module bus_matrix_ahb_bfm (
  input  logic        clk,
  output logic        HSEL,
  output logic [31:0] HADDR,
  output logic [1:0]  HTRANS,
  output logic        HWRITE,
  output logic [31:0] HWDATA,
  output logic [3:0]  HWSTRB,
  input  logic        HREADY,
  input  logic [31:0] HRDATA,
  input  logic        HRESP
);

  logic rst_n; // driven by apply_reset only; the testbench owns the real reset

  `include "tasks_ahb.sv"

  initial begin
    HSEL   = 1'b0;
    HADDR  = '0;
    HTRANS = 2'b00;
    HWRITE = 1'b0;
    HWDATA = '0;
    HWSTRB = 4'h0;
    bfm_err = 1'b0;
  end

endmodule : bus_matrix_ahb_bfm

`undef CLAUDE_BFM_ADDR_W
