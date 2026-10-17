// sram_apb_dp.sv — APB4 dual-port top-level of the sram IP.
//
// Instantiates claude_apb_mem_if (one per port) (IP/common) and sram_core. Contains no
// logic — only port declarations and submodule wiring.
// Dual-port variant: two APB4 slave ports (A_*, B_*) on a two-port
// array (sram_core DUAL_PORT = 1). Port B may be narrower or wider
// (WIDTH_B; same capacity). Each port has its own clock and reset pins:
// with COMMON_CLK = 1 drive B_PCLK from the same clock as A_PCLK
// (same-word conflicts then complete in the order A then B); with
// COMMON_CLK = 0 the clocks are unrelated and same-word collisions are
// undefined. The side-band runs on port A's clock. With TECH_SKY130 port B
// is read-only (writes get a bus error); TECH_SAED14 needs COMMON_CLK = 1.
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
//   WIDTH_B         port B data width: WIDTH / WIDTH_B a power of two either way;
//                   port B has WIDTH * DEPTH / WIDTH_B words (same storage)
//   BYTE_EN_B, PARTIAL_WR_ERR_B, READ_LATENCY_B   port B options (default: A's)
//   COMMON_CLK      1: B_<clock> is the same clock as A_<clock>; 0: unrelated clocks
//   INIT_FILE       preload (GENERIC / FPGA)
//   RST_POL         0 = active-low reset (polarity is carried by the bus reset pin)
// Side-band ports of disabled options are present; tie their inputs to 0.

module sram_apb_dp #(
  parameter int unsigned TECH             = sram_pkg::TECH_GENERIC, // technology
  parameter int unsigned ADDR_W           = 32,             // bus byte-address width
  parameter int unsigned WIDTH            = 32,             // data width (multiple of 8)
  parameter int unsigned DEPTH            = 1024,           // words (power of two)
  parameter bit          BYTE_EN          = 1,              // byte-lane writes
  parameter bit          PARTIAL_WR_ERR   = 1,              // BYTE_EN = 0: partial write errors
  parameter int unsigned READ_LATENCY     = 1,              // 1 or 2
  parameter bit          PWR_GATE         = 1,              // power modes
  parameter bit          ECC_EN           = 0,              // SECDED
  parameter bit          BANK_PG          = 0,              // one power domain per bank
  parameter int unsigned NUM_BANKS        = 1,              // banks (power of two)
  parameter bit          BIST_EN          = 0,              // March C- engine
  parameter int unsigned WIDTH_B          = WIDTH,          // port B data width (multiple of 8)
  parameter bit          BYTE_EN_B        = BYTE_EN,        // port B byte-lane writes
  parameter bit          PARTIAL_WR_ERR_B = PARTIAL_WR_ERR, // port B partial-write error
  parameter int unsigned READ_LATENCY_B   = READ_LATENCY,   // port B: 1 or 2
  parameter bit          COMMON_CLK       = 1,              // 1: B clock is A's clock; 0: separate
  parameter string       INIT_FILE        = "",             // preload (GENERIC/FPGA)
  /* verilator lint_off UNUSEDPARAM */
  parameter int unsigned RST_POL          = 0,              // 0 = active-low (reset pins)
  /* verilator lint_on UNUSEDPARAM */
  // Derived
  localparam int unsigned NPD             = BANK_PG ? NUM_BANKS : 1
) (
  input  logic                      A_PCLK,             // port A bus clock (core, side-band)
  input  logic                      A_PRESETn,          // port A APB active-low reset
  input  logic                      B_PCLK,             // port B bus clock (= A's if COMMON_CLK)
  input  logic                      B_PRESETn,          // port B APB active-low reset

  // APB4 bus, port A
  input  logic                      A_PSEL,             // slave select
  input  logic                      A_PENABLE,          // enable (ACCESS phase)
  input  logic [ADDR_W-1:0]         A_PADDR,            // byte address
  input  logic                      A_PWRITE,           // 1 = write
  input  logic [WIDTH-1:0]          A_PWDATA,           // write data
  input  logic [WIDTH/8-1:0]        A_PSTRB,            // byte write strobes
  output logic [WIDTH-1:0]          A_PRDATA,           // read data
  output logic                      A_PREADY,           // transfer complete
  output logic                      A_PSLVERR,          // transfer failed

  // APB4 bus, port B
  input  logic                      B_PSEL,             // slave select
  input  logic                      B_PENABLE,          // enable (ACCESS phase)
  input  logic [ADDR_W-1:0]         B_PADDR,            // byte address
  input  logic                      B_PWRITE,           // 1 = write
  input  logic [WIDTH_B-1:0]        B_PWDATA,           // write data
  input  logic [WIDTH_B/8-1:0]      B_PSTRB,            // byte write strobes
  output logic [WIDTH_B-1:0]        B_PRDATA,           // read data
  output logic                      B_PREADY,           // transfer complete
  output logic                      B_PSLVERR,          // transfer failed

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
  logic [WIDTH_B/8-1:0]      b_mem_be;
  logic [WIDTH_B-1:0]        b_mem_wdata;
  logic                      b_mem_rvalid;
  logic [WIDTH_B-1:0]        b_mem_rdata;
  logic                      b_mem_err;

  claude_apb_mem_if #(
    .DATA_W(WIDTH),
    .ADDR_W(ADDR_W)
  ) u_if_a (
    .PCLK        (A_PCLK),
    .PRESETn     (A_PRESETn),
    .PSEL        (A_PSEL),
    .PENABLE     (A_PENABLE),
    .PADDR       (A_PADDR),
    .PWRITE      (A_PWRITE),
    .PWDATA      (A_PWDATA),
    .PSTRB       (A_PSTRB),
    .PRDATA      (A_PRDATA),
    .PREADY      (A_PREADY),
    .PSLVERR     (A_PSLVERR),
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

  claude_apb_mem_if #(
    .DATA_W(WIDTH_B),
    .ADDR_W(ADDR_W)
  ) u_if_b (
    .PCLK        (B_PCLK),
    .PRESETn     (B_PRESETn),
    .PSEL        (B_PSEL),
    .PENABLE     (B_PENABLE),
    .PADDR       (B_PADDR),
    .PWRITE      (B_PWRITE),
    .PWDATA      (B_PWDATA),
    .PSTRB       (B_PSTRB),
    .PRDATA      (B_PRDATA),
    .PREADY      (B_PREADY),
    .PSLVERR     (B_PSLVERR),
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
    .TECH            (TECH),
    .ADDR_W          (ADDR_W),
    .WIDTH           (WIDTH),
    .DEPTH           (DEPTH),
    .BYTE_EN         (BYTE_EN),
    .PARTIAL_WR_ERR  (PARTIAL_WR_ERR),
    .READ_LATENCY    (READ_LATENCY),
    .PWR_GATE        (PWR_GATE),
    .ECC_EN          (ECC_EN),
    .BANK_PG         (BANK_PG),
    .NUM_BANKS       (NUM_BANKS),
    .BIST_EN         (BIST_EN),
    .DUAL_PORT       (1),
    .WIDTH_B         (WIDTH_B),
    .BYTE_EN_B       (BYTE_EN_B),
    .PARTIAL_WR_ERR_B(PARTIAL_WR_ERR_B),
    .READ_LATENCY_B  (READ_LATENCY_B),
    .COMMON_CLK      (COMMON_CLK),
    .INIT_FILE       (INIT_FILE)
  ) u_core (
    .clk             (A_PCLK),
    .rst_n           (A_PRESETn),
    .clk_b           (B_PCLK),
    .rst_b_n         (B_PRESETn),
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

endmodule : sram_apb_dp
