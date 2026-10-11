// bus_matrix_apb_bfm.sv — One APB4 master for the bus matrix testbench.
//
// Wraps the shared APB4 task library (IP/common/verification/tasks/
// tasks_apb.sv) around one master port, so a testbench can run several
// masters at once: u_m0.write_reg(...), u_m1.read_reg(...), u_m0.bfm_err.
// Addresses are 32 bits wide.

`define CLAUDE_BFM_ADDR_W 32

`timescale 1ns / 1ps

module bus_matrix_apb_bfm (
  input  logic        clk,
  output logic        PSEL,
  output logic        PENABLE,
  output logic [31:0] PADDR,
  output logic        PWRITE,
  output logic [31:0] PWDATA,
  output logic [3:0]  PSTRB,
  input  logic [31:0] PRDATA,
  input  logic        PREADY,
  input  logic        PSLVERR
);

  logic rst_n; // driven by apply_reset only; the testbench owns the real reset

  `include "tasks_apb.sv"

  initial begin
    PSEL    = 1'b0;
    PENABLE = 1'b0;
    PADDR   = '0;
    PWRITE  = 1'b0;
    PWDATA  = '0;
    PSTRB   = 4'h0;
    bfm_err = 1'b0;
  end

endmodule : bus_matrix_apb_bfm

`undef CLAUDE_BFM_ADDR_W
