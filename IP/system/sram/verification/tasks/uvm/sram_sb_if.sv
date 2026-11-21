// sram_sb_if.sv — UVM signal bundle of the sram side band (Step 6).
//
// Synchronous to port A's clock (clk), like the side-band pins themselves.
// Domain fields are sized for the largest power-domain count (MAX_PD = 4);
// the top-level connects the low 2*NPD bits.
//
// Testbench knobs that are not DUT pins:
//   bf_on / bf_addr / bf_bit / bf_val  read-path fault: while bf_on, every
//                    array read of word bf_addr sees stored bit bf_bit stuck
//                    at bf_val (a force in the top; BIST and ECC tests)
//   n_checked / n_mismatch  the embedded sram_model's response counters
//
// UVM exception (.agents/uvm.md): SV interfaces are allowed in
// verification/tasks/uvm/ only.

`timescale 1ns / 1ps

interface sram_sb_if (
  input logic clk,
  input logic rst_n
);

  localparam int unsigned MAX_PD = 4;

  logic [2*MAX_PD-1:0] pwr_mode_req;
  logic [2*MAX_PD-1:0] pwr_mode_ack;
  logic                clr_req;
  logic                clr_done;
  logic                busy;
  logic                err_irq;
  logic [1:0]          ecc_inj;
  logic                ecc_corr;
  logic                ecc_uncorr;
  logic                bist_start;
  logic                bist_done;
  logic                bist_fail;
  logic [15:0]         bist_fail_addr;

  bit                  bf_on;
  int unsigned         bf_addr;
  int unsigned         bf_bit;
  bit                  bf_val;
  int unsigned         n_checked;
  int unsigned         n_mismatch;

  function automatic void idle_all();
    pwr_mode_req = '0;
    clr_req      = 1'b0;
    ecc_inj      = 2'b00;
    bist_start   = 1'b0;
    bf_on        = 1'b0;
    bf_addr      = 0;
    bf_bit       = 3;
    bf_val       = 1'b0;
  endfunction

endinterface : sram_sb_if
