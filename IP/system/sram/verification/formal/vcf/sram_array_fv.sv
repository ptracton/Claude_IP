// sram_array_fv.sv — VC Formal checker for sram_array (ports only).
//
// Bound into sram_array by sram_fv_block_binds.svh. Banks are the top index
// bits on both ports (sram_array). A macro must never be accessed while its
// bank is in light sleep, deep sleep or shutdown:
//   a_pins_off_a  port A access only to a bank with every sleep pin off
//   a_pins_off_b  same for port B, checked on port B's clock (with separate
//                 clocks this is the sram_cdc permission handshake at work)

module sram_array_fv #(
  parameter int unsigned DEPTH     = 16,
  parameter int unsigned DEPTH_B   = 16,
  parameter int unsigned NUM_BANKS = 1,
  parameter bit          DUAL_PORT = 0,
  parameter bit          PWR_GATE  = 1
) (
  input  logic                       clk,
  input  logic                       cs_i,
  input  logic [$clog2(DEPTH)-1:0]   idx_i,
  input  logic [NUM_BANKS-1:0]       ls_i,
  input  logic [NUM_BANKS-1:0]       ds_i,
  input  logic [NUM_BANKS-1:0]       sd_i,
  input  logic                       b_clk,
  input  logic                       b_cs_i,
  input  logic [$clog2(DEPTH_B)-1:0] b_idx_i
);

  localparam int unsigned BankBits = $clog2(NUM_BANKS);
  localparam int unsigned BankW    = (NUM_BANKS > 1) ? BankBits : 1;
  localparam int unsigned IdxW     = $clog2(DEPTH);
  localparam int unsigned IdxWB    = $clog2(DEPTH_B);

  logic [BankW-1:0] a_bank, b_bank;
  logic [NUM_BANKS-1:0] asleep;

  assign a_bank = (NUM_BANKS > 1) ? BankW'(idx_i >> (IdxW - BankBits)) : '0;
  assign b_bank = (NUM_BANKS > 1) ? BankW'(b_idx_i >> (IdxWB - BankBits)) : '0;
  assign asleep = ls_i | ds_i | sd_i;

  // No reset port on sram_array: the checks hold in every cycle.
  a_pins_off_a: assert property (@(posedge clk) cs_i |-> !asleep[a_bank]);
  for (genvar k = 0; k < NUM_BANKS; k++) begin : g_cov
    c_access_bank: cover property (@(posedge clk) cs_i && a_bank == BankW'(k));
    if (PWR_GATE) begin : g_c_sleep
      c_sleep_bank: cover property (@(posedge clk) asleep[k]);
    end
  end

  if (DUAL_PORT) begin : g_b
    a_pins_off_b: assert property (@(posedge b_clk) b_cs_i |-> !asleep[b_bank]);
    c_b_access:   cover property (@(posedge b_clk) b_cs_i);
  end

endmodule : sram_array_fv
