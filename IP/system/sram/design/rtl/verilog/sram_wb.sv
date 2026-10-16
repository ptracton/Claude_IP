// sram_wb.sv — Wishbone B4 top-level of the sram IP.
//
// Instantiates claude_wb_mem_if (IP/common) and sram_core. Contains no
// logic — only port declarations and submodule wiring (plus the reset inversion Wishbone needs).
//
// Parameters (see doc/spec.md):
//   TECH            sram_pkg::TECH_* (GENERIC, XILINX, ALTERA, SAED90, SAED32, SAED14, SKY130)
//   ADDR_W          bus byte-address width (default 32)
//   WIDTH, DEPTH    word width (= bus data width) and number of words
//   BYTE_EN         byte-lane writes; PARTIAL_WR_ERR: with BYTE_EN = 0 a partial
//                   write is a bus error (1) or writes the whole word (0)
//   READ_LATENCY    1, or 2 for an output register
//   PWR_GATE        power modes; BANK_PG: one power domain per bank
//   NUM_BANKS       banks (power of two)
//   ECC_EN, BIST_EN SECDED ECC, March C- self-test
//   INIT_FILE       preload (GENERIC / FPGA)
//   RST_POL         0 = active-low reset (polarity is carried by the bus reset pin)
// Side-band ports of disabled options are present; tie their inputs to 0.

module sram_wb #(
  parameter int unsigned TECH           = sram_pkg::TECH_GENERIC, // technology
  parameter int unsigned ADDR_W         = 32,    // bus byte-address width
  parameter int unsigned WIDTH          = 32,    // data width (multiple of 8)
  parameter int unsigned DEPTH          = 1024,  // words (power of two)
  parameter bit          BYTE_EN        = 1,     // byte-lane writes
  parameter bit          PARTIAL_WR_ERR = 1,     // BYTE_EN = 0: partial write is an error
  parameter int unsigned READ_LATENCY   = 1,     // 1 or 2
  parameter bit          PWR_GATE       = 1,     // power modes
  parameter bit          ECC_EN         = 0,     // SECDED
  parameter bit          BANK_PG        = 0,     // one power domain per bank
  parameter int unsigned NUM_BANKS      = 1,     // banks (power of two)
  parameter bit          BIST_EN        = 0,     // March C- engine
  parameter string       INIT_FILE      = "",    // preload (GENERIC/FPGA)
  /* verilator lint_off UNUSEDPARAM */
  parameter int unsigned RST_POL        = 0,     // 0 = active-low; polarity carried by RST_I
  /* verilator lint_on UNUSEDPARAM */
  // Derived
  localparam int unsigned NPD           = BANK_PG ? NUM_BANKS : 1
) (
  input  logic                      CLK_I,              // bus clock
  input  logic                      RST_I,              // Wishbone active-high synchronous reset

  // Wishbone B4 bus
  input  logic                      CYC_I,              // bus cycle valid
  input  logic                      STB_I,              // strobe
  input  logic                      WE_I,               // 1 = write
  input  logic [ADDR_W-1:0]         ADR_I,              // byte address
  input  logic [WIDTH-1:0]          DAT_I,              // write data
  input  logic [WIDTH/8-1:0]        SEL_I,              // byte selects
  output logic [WIDTH-1:0]          DAT_O,              // read data
  output logic                      ACK_O,              // normal termination
  output logic                      ERR_O,              // error termination

  // Side-band: power, clear, status, ECC, BIST
  input  logic [2*NPD-1:0]          pwr_mode_req_i,     // requested power mode per domain
  output logic [2*NPD-1:0]          pwr_mode_ack_o,     // power mode in effect per domain
  input  logic                      clr_req_i,          // clear the array (pulse)
  output logic                      clr_done_o,         // clear pass finished (pulse)
  output logic                      busy_o,             // clear/BIST/wake/RMW in progress
  output logic                      err_irq_o,          // bus error or ECC event (pulse)
  input  logic [1:0]                ecc_inj_i,          // ECC: arm 1-bit [0] / 2-bit [1] error
  output logic                      ecc_corr_o,         // ECC: corrected error (pulse)
  output logic                      ecc_uncorr_o,       // ECC: uncorrectable error (pulse)
  input  logic                      bist_start_i,       // BIST: start March C- (pulse)
  output logic                      bist_done_o,        // BIST: finished (pulse)
  output logic                      bist_fail_o,        // BIST: a word failed
  output logic [$clog2(DEPTH)-1:0]  bist_fail_addr_o    // BIST: first failing word
);

  // Wishbone uses an active-high synchronous reset; the core uses active-low.
  logic rst_n;
  assign rst_n = ~RST_I;

  // Memory bus between the adapter and the core
  logic                      mem_req;
  logic                      mem_gnt;
  logic                      mem_we;
  logic [ADDR_W-1:0]         mem_addr;
  logic [WIDTH/8-1:0]        mem_be;
  logic [WIDTH-1:0]          mem_wdata;
  logic                      mem_rvalid;
  logic [WIDTH-1:0]          mem_rdata;
  logic                      mem_err;

  claude_wb_mem_if #(
    .DATA_W(WIDTH),
    .ADDR_W(ADDR_W)
  ) u_if (
    .CLK_I       (CLK_I),
    .RST_I       (RST_I),
    .CYC_I       (CYC_I),
    .STB_I       (STB_I),
    .WE_I        (WE_I),
    .ADR_I       (ADR_I),
    .DAT_I       (DAT_I),
    .SEL_I       (SEL_I),
    .DAT_O       (DAT_O),
    .ACK_O       (ACK_O),
    .ERR_O       (ERR_O),
    .mem_req_o   (mem_req),
    .mem_gnt_i   (mem_gnt),
    .mem_we_o    (mem_we),
    .mem_addr_o  (mem_addr),
    .mem_be_o    (mem_be),
    .mem_wdata_o (mem_wdata),
    .mem_rvalid_i(mem_rvalid),
    .mem_rdata_i (mem_rdata),
    .mem_err_i   (mem_err)
  );

  sram_core #(
    .TECH          (TECH),
    .ADDR_W        (ADDR_W),
    .WIDTH         (WIDTH),
    .DEPTH         (DEPTH),
    .BYTE_EN       (BYTE_EN),
    .PARTIAL_WR_ERR(PARTIAL_WR_ERR),
    .READ_LATENCY  (READ_LATENCY),
    .PWR_GATE      (PWR_GATE),
    .ECC_EN        (ECC_EN),
    .BANK_PG       (BANK_PG),
    .NUM_BANKS     (NUM_BANKS),
    .BIST_EN       (BIST_EN),
    .DUAL_PORT     (0),
    .INIT_FILE     (INIT_FILE)
  ) u_core (
    .clk             (CLK_I),
    .rst_n           (rst_n),
    .mem_req_i       (mem_req),
    .mem_gnt_o       (mem_gnt),
    .mem_we_i        (mem_we),
    .mem_addr_i      (mem_addr),
    .mem_be_i        (mem_be),
    .mem_wdata_i     (mem_wdata),
    .mem_rvalid_o    (mem_rvalid),
    .mem_rdata_o     (mem_rdata),
    .mem_err_o       (mem_err),
    .mem_b_req_i     (1'b0),
    .mem_b_gnt_o     (),
    .mem_b_we_i      (1'b0),
    .mem_b_addr_i    ('0),
    .mem_b_be_i      ('0),
    .mem_b_wdata_i   ('0),
    .mem_b_rvalid_o  (),
    .mem_b_rdata_o   (),
    .mem_b_err_o     (),
    .pwr_mode_req_i  (pwr_mode_req_i),
    .pwr_mode_ack_o  (pwr_mode_ack_o),
    .clr_req_i       (clr_req_i),
    .clr_done_o      (clr_done_o),
    .busy_o          (busy_o),
    .err_irq_o       (err_irq_o),
    .ecc_inj_i       (ecc_inj_i),
    .ecc_corr_o      (ecc_corr_o),
    .ecc_uncorr_o    (ecc_uncorr_o),
    .bist_start_i    (bist_start_i),
    .bist_done_o     (bist_done_o),
    .bist_fail_o     (bist_fail_o),
    .bist_fail_addr_o(bist_fail_addr_o)
  );

endmodule : sram_wb
