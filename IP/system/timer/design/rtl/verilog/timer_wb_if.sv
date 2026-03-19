// timer_wb_if.sv — Wishbone B4 (registered feedback) bus interface for Timer IP.
//
// Translates Wishbone B4 transactions into the flat register-file access bus.
//
// Wishbone B4 protocol (registered feedback / pipelined variant):
//   A transaction is valid when CYC_I & STB_I are asserted.
//   ACK_O is asserted the cycle after STB_I (single-cycle latency).
//   ERR_O is never asserted.
//
// Ports (bus side):
//   CLK_I, RST_I — Wishbone clock and synchronous active-high reset
//   CYC_I        — bus cycle valid
//   STB_I        — strobe (initiates transfer)
//   WE_I         — 1=write, 0=read
//   ADR_I[11:0]  — byte address
//   DAT_I[31:0]  — write data
//   SEL_I[3:0]   — byte select
//   DAT_O[31:0]  — read data
//   ACK_O        — acknowledge (one cycle after STB_I)
//   ERR_O        — always 0
//
// Ports (regfile side):
//   wr_en, wr_addr, wr_data, wr_strb — write channel
//   rd_en, rd_addr, rd_data          — read channel

module timer_wb_if #(
  parameter int unsigned DATA_W = 32, // data bus width
  parameter int unsigned ADDR_W = 4   // regfile word-address width
) (
  // Wishbone B4 signals
  input  logic                  CLK_I,         // Wishbone clock
  input  logic                  RST_I,         // Wishbone synchronous active-high reset

  input  logic                  CYC_I,         // bus cycle valid
  input  logic                  STB_I,         // strobe
  input  logic                  WE_I,          // 1=write
  // ADR_I[11:0] per Wishbone B4 spec; only [ADDR_W+1:2] used (4 registers = 16 B).
  /* verilator lint_off UNUSEDSIGNAL */
  input  logic [11:0]           ADR_I,         // byte address
  /* verilator lint_on UNUSEDSIGNAL */
  input  logic [DATA_W-1:0]     DAT_I,         // write data
  input  logic [DATA_W/8-1:0]   SEL_I,         // byte selects
  output logic [DATA_W-1:0]     DAT_O,         // read data
  output logic                  ACK_O,         // acknowledge
  output logic                  ERR_O,         // error (always 0)

  // Register-file write channel
  output logic                  wr_en,         // write enable
  output logic [ADDR_W-1:0]     wr_addr,       // word address
  output logic [DATA_W-1:0]     wr_data,       // write data
  output logic [DATA_W/8-1:0]   wr_strb,       // byte write enables

  // Register-file read channel
  output logic                  rd_en,         // read enable
  output logic [ADDR_W-1:0]     rd_addr,       // word address
  input  logic [DATA_W-1:0]     rd_data        // read data (registered in regfile)
);

  // -------------------------------------------------------------------------
  // Capture STB to generate one-cycle ACK and rd_en/wr_en pulses.
  // ACK_O is registered, asserted one cycle after a valid STB_I.
  // -------------------------------------------------------------------------
  logic stb_prev_q; // STB sampled previous cycle

  always_ff @(posedge CLK_I) begin : p_ack
    if (RST_I) begin
      stb_prev_q <= 1'b0;
    end else begin
      stb_prev_q <= CYC_I & STB_I & ~stb_prev_q; // single-cycle pulse tracking
    end
  end

  // wr_en / rd_en fire in the cycle when STB_I is first seen
  assign wr_en   = CYC_I & STB_I & WE_I  & ~stb_prev_q;
  assign rd_en   = CYC_I & STB_I & ~WE_I & ~stb_prev_q;
  assign wr_addr = ADR_I[ADDR_W+1:2];
  assign rd_addr = ADR_I[ADDR_W+1:2];
  assign wr_data = DAT_I;
  assign wr_strb = SEL_I;

  // -------------------------------------------------------------------------
  // ACK_O: registered one cycle after wr_en/rd_en
  // -------------------------------------------------------------------------
  always_ff @(posedge CLK_I) begin : p_ack_out
    if (RST_I) begin
      ACK_O <= 1'b0;
    end else begin
      ACK_O <= CYC_I & STB_I & ~stb_prev_q;
    end
  end

  assign DAT_O = rd_data;
  assign ERR_O = 1'b0;

endmodule : timer_wb_if
