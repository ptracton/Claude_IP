// bus_matrix_wb_bfm.sv — One Wishbone B4 master for the bus matrix testbench.
//
// Wraps the shared Wishbone task library (IP/common/verification/tasks/
// tasks_wb.sv) around one master port, so a testbench can run several
// masters at once: u_m0.write_reg(...), u_m1.read_reg(...), u_m0.bfm_err.
// Addresses are 32 bits wide. The library's port names are from the slave's
// point of view (CYC_I, DAT_I = write data, DAT_O = read data, ...).

`define CLAUDE_BFM_ADDR_W 32

`timescale 1ns / 1ps

module bus_matrix_wb_bfm (
  input  logic        clk,
  output logic        CYC_I,
  output logic        STB_I,
  output logic        WE_I,
  output logic [31:0] ADR_I,
  output logic [31:0] DAT_I,
  output logic [3:0]  SEL_I,
  input  logic [31:0] DAT_O,
  input  logic        ACK_O,
  input  logic        ERR_O
);

  logic RST_I; // driven by apply_reset only; the testbench owns the real reset

  `include "tasks_wb.sv"

  initial begin
    CYC_I   = 1'b0;
    STB_I   = 1'b0;
    WE_I    = 1'b0;
    ADR_I   = '0;
    DAT_I   = '0;
    SEL_I   = 4'h0;
    bfm_err = 1'b0;
  end

endmodule : bus_matrix_wb_bfm

`undef CLAUDE_BFM_ADDR_W
