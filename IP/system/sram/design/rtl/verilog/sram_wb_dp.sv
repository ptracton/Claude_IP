// sram_wb_dp.sv — Wishbone B4 dual-port top-level of the sram IP.
//
// Instantiates claude_wb_mem_if (one per port) (IP/common) and sram_core. Contains no
// logic — only port declarations and submodule wiring (plus the reset inversion Wishbone needs).
// Dual-port variant: two Wishbone B4 slave ports (A_*, B_*) on one clock and
// reset, on a two-port array (sram_core DUAL_PORT = 1). Same-word conflicts
// complete in the order A then B. With TECH_SKY130 port B is read-only
// (writes get a bus error).
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

module sram_wb_dp #(
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
  input  logic                      CLK_I,              // bus clock (both ports)
  input  logic                      RST_I,              // Wishbone active-high synchronous reset

  // Wishbone B4 bus, port A
  input  logic                      A_CYC_I,            // bus cycle valid
  input  logic                      A_STB_I,            // strobe
  input  logic                      A_WE_I,             // 1 = write
  input  logic [ADDR_W-1:0]         A_ADR_I,            // byte address
  input  logic [WIDTH-1:0]          A_DAT_I,            // write data
  input  logic [WIDTH/8-1:0]        A_SEL_I,            // byte selects
  output logic [WIDTH-1:0]          A_DAT_O,            // read data
  output logic                      A_ACK_O,            // normal termination
  output logic                      A_ERR_O,            // error termination

  // Wishbone B4 bus, port B
  input  logic                      B_CYC_I,            // bus cycle valid
  input  logic                      B_STB_I,            // strobe
  input  logic                      B_WE_I,             // 1 = write
  input  logic [ADDR_W-1:0]         B_ADR_I,            // byte address
  input  logic [WIDTH-1:0]          B_DAT_I,            // write data
  input  logic [WIDTH/8-1:0]        B_SEL_I,            // byte selects
  output logic [WIDTH-1:0]          B_DAT_O,            // read data
  output logic                      B_ACK_O,            // normal termination
  output logic                      B_ERR_O,            // error termination

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

  // Memory bus between the adapters and the core
  logic                      a_mem_req;
  logic                      a_mem_gnt;
  logic                      a_mem_we;
  logic [ADDR_W-1:0]         a_mem_addr;
  logic [WIDTH/8-1:0]        a_mem_be;
  logic [WIDTH-1:0]          a_mem_wdata;
  logic                      a_mem_rvalid;
  logic [WIDTH-1:0]          a_mem_rdata;
  logic                      a_mem_err;
  logic                      b_mem_req;
  logic                      b_mem_gnt;
  logic                      b_mem_we;
  logic [ADDR_W-1:0]         b_mem_addr;
  logic [WIDTH/8-1:0]        b_mem_be;
  logic [WIDTH-1:0]          b_mem_wdata;
  logic                      b_mem_rvalid;
  logic [WIDTH-1:0]          b_mem_rdata;
  logic                      b_mem_err;

  claude_wb_mem_if #(
    .DATA_W(WIDTH),
    .ADDR_W(ADDR_W)
  ) u_if_a (
    .CLK_I       (CLK_I),
    .RST_I       (RST_I),
    .CYC_I       (A_CYC_I),
    .STB_I       (A_STB_I),
    .WE_I        (A_WE_I),
    .ADR_I       (A_ADR_I),
    .DAT_I       (A_DAT_I),
    .SEL_I       (A_SEL_I),
    .DAT_O       (A_DAT_O),
    .ACK_O       (A_ACK_O),
    .ERR_O       (A_ERR_O),
    .mem_req_o   (a_mem_req),
    .mem_gnt_i   (a_mem_gnt),
    .mem_we_o    (a_mem_we),
    .mem_addr_o  (a_mem_addr),
    .mem_be_o    (a_mem_be),
    .mem_wdata_o (a_mem_wdata),
    .mem_rvalid_i(a_mem_rvalid),
    .mem_rdata_i (a_mem_rdata),
    .mem_err_i   (a_mem_err)
  );

  claude_wb_mem_if #(
    .DATA_W(WIDTH),
    .ADDR_W(ADDR_W)
  ) u_if_b (
    .CLK_I       (CLK_I),
    .RST_I       (RST_I),
    .CYC_I       (B_CYC_I),
    .STB_I       (B_STB_I),
    .WE_I        (B_WE_I),
    .ADR_I       (B_ADR_I),
    .DAT_I       (B_DAT_I),
    .SEL_I       (B_SEL_I),
    .DAT_O       (B_DAT_O),
    .ACK_O       (B_ACK_O),
    .ERR_O       (B_ERR_O),
    .mem_req_o   (b_mem_req),
    .mem_gnt_i   (b_mem_gnt),
    .mem_we_o    (b_mem_we),
    .mem_addr_o  (b_mem_addr),
    .mem_be_o    (b_mem_be),
    .mem_wdata_o (b_mem_wdata),
    .mem_rvalid_i(b_mem_rvalid),
    .mem_rdata_i (b_mem_rdata),
    .mem_err_i   (b_mem_err)
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
    .DUAL_PORT     (1),
    .INIT_FILE     (INIT_FILE)
  ) u_core (
    .clk             (CLK_I),
    .rst_n           (rst_n),
    .mem_req_i       (a_mem_req),
    .mem_gnt_o       (a_mem_gnt),
    .mem_we_i        (a_mem_we),
    .mem_addr_i      (a_mem_addr),
    .mem_be_i        (a_mem_be),
    .mem_wdata_i     (a_mem_wdata),
    .mem_rvalid_o    (a_mem_rvalid),
    .mem_rdata_o     (a_mem_rdata),
    .mem_err_o       (a_mem_err),
    .mem_b_req_i     (b_mem_req),
    .mem_b_gnt_o     (b_mem_gnt),
    .mem_b_we_i      (b_mem_we),
    .mem_b_addr_i    (b_mem_addr),
    .mem_b_be_i      (b_mem_be),
    .mem_b_wdata_i   (b_mem_wdata),
    .mem_b_rvalid_o  (b_mem_rvalid),
    .mem_b_rdata_o   (b_mem_rdata),
    .mem_b_err_o     (b_mem_err),
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

endmodule : sram_wb_dp
