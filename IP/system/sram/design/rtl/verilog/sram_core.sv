// sram_core.sv — Protocol-independent core of the sram IP.
//
// Target side of the Claude memory bus plus the side-band power, clear,
// ECC and BIST controls. Submodules:
//   sram_port      bus requests: checks, ECC, read-modify-write, response
//   sram_pwr_ctrl  one power state machine per domain (NPD domains)
//   sram_clr       clear engine (software request, and after shutdown)
//   sram_bist      March C- self-test (BIST_EN)
//   sram_array     the macros (TECH), tiled into NUM_BANKS banks
//
// Array ownership, highest first: BIST (while testing), clear engine (while
// clearing), bus port. An engine that is pending stalls new bus grants, and
// only starts once the port has nothing in flight; BIST and the clear engine
// never run together.
//
// With ECC_EN the clear engine zeroes the array after reset, so every word
// holds a valid codeword; bus requests stall until it finishes.
//
// DUAL_PORT: a second bus port (mem_b_*) on a two-port array. Both ports
// run in parallel; when they would access the same word in the same cycle
// and either writes, port B waits a cycle, and a port waits while the other
// port's read-modify-write of that word is pending. Conflicting accesses
// therefore complete in the order A then B; none is dropped. The clear and
// BIST engines use port A and stall both ports. With TECH_SKY130, port B is
// read-only (OpenRAM 1rw1r): its writes get a bus error. ECC error
// injection applies to port A writes.
//
// Power domains: NPD = NUM_BANKS when BANK_PG, else 1 (the whole array).
// pwr_mode_req_i / pwr_mode_ack_o carry 2 bits per domain (domain d in bits
// [2d+1:2d]). While BIST runs every domain is held in RUN.

module sram_core #(
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
  parameter bit          DUAL_PORT      = 0,     // second bus port (mem_b_*)
  parameter string       INIT_FILE      = "",    // preload (GENERIC/FPGA)
  // Derived
  localparam int unsigned NPD            = BANK_PG ? NUM_BANKS : 1
) (
  input  logic                     clk,              // clock
  input  logic                     rst_n,            // synchronous active-low reset

  // Memory bus (target side)
  input  logic                     mem_req_i,        // request
  output logic                     mem_gnt_o,        // request accepted
  input  logic                     mem_we_i,         // 1 = write
  input  logic [ADDR_W-1:0]        mem_addr_i,       // byte address
  input  logic [WIDTH/8-1:0]       mem_be_i,         // byte enables
  input  logic [WIDTH-1:0]         mem_wdata_i,      // write data
  output logic                     mem_rvalid_o,     // response
  output logic [WIDTH-1:0]         mem_rdata_o,      // read data
  output logic                     mem_err_o,        // response is an error

  // Memory bus, port B (DUAL_PORT; tie inputs to 0 otherwise)
  input  logic                     mem_b_req_i,      // request
  output logic                     mem_b_gnt_o,      // request accepted
  input  logic                     mem_b_we_i,       // 1 = write
  input  logic [ADDR_W-1:0]        mem_b_addr_i,     // byte address
  input  logic [WIDTH/8-1:0]       mem_b_be_i,       // byte enables
  input  logic [WIDTH-1:0]         mem_b_wdata_i,    // write data
  output logic                     mem_b_rvalid_o,   // response
  output logic [WIDTH-1:0]         mem_b_rdata_o,    // read data
  output logic                     mem_b_err_o,      // response is an error

  // Power
  input  logic [2*NPD-1:0]         pwr_mode_req_i,   // requested mode per domain
  output logic [2*NPD-1:0]         pwr_mode_ack_o,   // mode in effect per domain

  // Clear, status
  input  logic                     clr_req_i,        // clear the array (pulse)
  output logic                     clr_done_o,       // clear pass finished (pulse)
  output logic                     busy_o,           // clear/BIST/wake/RMW in progress
  output logic                     err_irq_o,        // bus error or ECC event (pulse)

  // ECC (ECC_EN)
  input  logic [1:0]               ecc_inj_i,        // arm 1-bit [0] / 2-bit [1] error
  output logic                     ecc_corr_o,       // corrected error (pulse)
  output logic                     ecc_uncorr_o,     // uncorrectable error (pulse)

  // BIST (BIST_EN)
  input  logic                     bist_start_i,     // start March C- (pulse)
  output logic                     bist_done_o,      // test finished (pulse)
  output logic                     bist_fail_o,      // a word failed
  output logic [$clog2(DEPTH)-1:0] bist_fail_addr_o  // first failing word
);

  localparam int unsigned IdxW   = $clog2(DEPTH);
  localparam int unsigned EccW   = ECC_EN ? sram_pkg::ecc_check_bits(WIDTH) : 0;
  localparam int unsigned MW     = WIDTH + EccW;
  localparam int unsigned NLanes = (BYTE_EN && !ECC_EN) ? WIDTH / 8 : 1;
  localparam int unsigned BanksPerDom = NUM_BANKS / NPD;

  // -------------------------------------------------------------------------
  // Parameter checks (elaboration time)
  // -------------------------------------------------------------------------
  // synopsys translate_off
  initial begin : p_param_check
    if (WIDTH % 8 != 0 || WIDTH < 8 || WIDTH > 128)
      $fatal(1, "sram_core: WIDTH must be a multiple of 8 in 8..128");
    if ((DEPTH & (DEPTH - 1)) != 0 || DEPTH < 2)
      $fatal(1, "sram_core: DEPTH must be a power of two >= 2");
    if ((NUM_BANKS & (NUM_BANKS - 1)) != 0 || NUM_BANKS > DEPTH / 2)
      $fatal(1, "sram_core: NUM_BANKS must be a power of two <= DEPTH/2");
    if (READ_LATENCY != 1 && READ_LATENCY != 2)
      $fatal(1, "sram_core: READ_LATENCY must be 1 or 2");
    if (BANK_PG && !PWR_GATE)
      $fatal(1, "sram_core: BANK_PG needs PWR_GATE");
  end
  // synopsys translate_on

  // -------------------------------------------------------------------------
  // Wiring
  // -------------------------------------------------------------------------
  logic [NPD-1:0]  dom_awake, dom_ok, dom_err, dom_wakeable, dom_busy;
  logic [NPD-1:0]  dom_clr_req, dom_clr_done, dom_pwr_busy;
  logic [NPD-1:0]  port_wake, clr_wake;
  logic [NPD-1:0]  dom_ls, dom_ds, dom_sd;
  logic            port_idle, port_busy;

  // Per-port signals (A = mem_*, B = mem_b_*)
  logic [NPD-1:0]  a_wake, b_wake, a_dom_busy, b_dom_busy;
  logic            a_idle, b_idle, a_busy, b_busy, a_stall, b_stall;
  logic            a_ecc_corr, b_ecc_corr, a_ecc_uncorr, b_ecc_uncorr, a_irq, b_irq;
  logic [IdxW-1:0] a_req_idx, b_req_idx, a_rmw_idx, b_rmw_idx;
  logic            a_req_we, b_req_we, a_acc, b_acc, a_rmw_pend, b_rmw_pend;
  logic              b_cs, b_we;
  logic [IdxW-1:0]   b_idx;
  logic [MW-1:0]     b_wdata, b_rdata;
  logic [NLanes-1:0] b_lane_we;

  logic            clr_pending, clr_busy, clr_cs;
  logic [IdxW-1:0] clr_idx;

  logic            bist_pending, bist_busy, bist_active, bist_force, bist_cs, bist_we;
  logic [IdxW-1:0] bist_idx;
  logic [MW-1:0]   bist_wdata;

  logic              p_cs, p_we;
  logic [IdxW-1:0]   p_idx;
  logic [MW-1:0]     p_wdata;
  logic [NLanes-1:0] p_lane_we;

  logic              arr_cs, arr_we;
  logic [IdxW-1:0]   arr_idx;
  logic [MW-1:0]     arr_wdata, arr_rdata;
  logic [NLanes-1:0] arr_lane_we;

  // -------------------------------------------------------------------------
  // Bus port
  // -------------------------------------------------------------------------
  sram_port #(
    .ADDR_W        (ADDR_W),
    .WIDTH         (WIDTH),
    .DEPTH         (DEPTH),
    .BYTE_EN       (BYTE_EN),
    .PARTIAL_WR_ERR(PARTIAL_WR_ERR),
    .READ_LATENCY  (READ_LATENCY),
    .ECC_EN        (ECC_EN),
    .NPD           (NPD)
  ) u_port (
    .clk          (clk),
    .rst_n        (rst_n),
    .mem_req_i    (mem_req_i),
    .mem_gnt_o    (mem_gnt_o),
    .mem_we_i     (mem_we_i),
    .mem_addr_i   (mem_addr_i),
    .mem_be_i     (mem_be_i),
    .mem_wdata_i  (mem_wdata_i),
    .mem_rvalid_o (mem_rvalid_o),
    .mem_rdata_o  (mem_rdata_o),
    .mem_err_o    (mem_err_o),
    .dom_awake_i  (dom_awake),
    .dom_err_i    (dom_err),
    .stall_i      (a_stall),
    .wake_o       (a_wake),
    .dom_busy_o   (a_dom_busy),
    .idle_o       (a_idle),
    .req_idx_o    (a_req_idx),
    .req_we_o     (a_req_we),
    .acc_o        (a_acc),
    .rmw_pend_o   (a_rmw_pend),
    .rmw_idx_o    (a_rmw_idx),
    .arr_cs_o     (p_cs),
    .arr_we_o     (p_we),
    .arr_idx_o    (p_idx),
    .arr_wdata_o  (p_wdata),
    .arr_lane_we_o(p_lane_we),
    .arr_rdata_i  (arr_rdata),
    .ecc_inj_i    (ecc_inj_i),
    .ecc_corr_o   (a_ecc_corr),
    .ecc_uncorr_o (a_ecc_uncorr),
    .err_irq_o    (a_irq),
    .busy_o       (a_busy)
  );

  // -------------------------------------------------------------------------
  // Bus port B (DUAL_PORT) and same-word conflict holds
  // -------------------------------------------------------------------------
  // A waits while B's read-modify-write of the same word is pending.
  assign a_stall = clr_pending || bist_pending ||
                   (DUAL_PORT && b_rmw_pend && (a_req_idx == b_rmw_idx));

  if (DUAL_PORT) begin : g_port_b
    // B waits when A accesses the same word this cycle and either writes, or
    // while A's read-modify-write of that word is pending.
    assign b_stall = clr_pending || bist_pending ||
                     (a_acc && (a_req_idx == b_req_idx) && (a_req_we || b_req_we)) ||
                     (a_rmw_pend && (b_req_idx == a_rmw_idx));

    sram_port #(
      .ADDR_W        (ADDR_W),
      .WIDTH         (WIDTH),
      .DEPTH         (DEPTH),
      .BYTE_EN       (BYTE_EN),
      .PARTIAL_WR_ERR(PARTIAL_WR_ERR),
      .READ_LATENCY  (READ_LATENCY),
      .ECC_EN        (ECC_EN),
      .NPD           (NPD),
      .READ_ONLY     (TECH == sram_pkg::TECH_SKY130)
    ) u_port_b (
      .clk          (clk),
      .rst_n        (rst_n),
      .mem_req_i    (mem_b_req_i),
      .mem_gnt_o    (mem_b_gnt_o),
      .mem_we_i     (mem_b_we_i),
      .mem_addr_i   (mem_b_addr_i),
      .mem_be_i     (mem_b_be_i),
      .mem_wdata_i  (mem_b_wdata_i),
      .mem_rvalid_o (mem_b_rvalid_o),
      .mem_rdata_o  (mem_b_rdata_o),
      .mem_err_o    (mem_b_err_o),
      .dom_awake_i  (dom_awake),
      .dom_err_i    (dom_err),
      .stall_i      (b_stall),
      .wake_o       (b_wake),
      .dom_busy_o   (b_dom_busy),
      .idle_o       (b_idle),
      .req_idx_o    (b_req_idx),
      .req_we_o     (b_req_we),
      .acc_o        (b_acc),
      .rmw_pend_o   (b_rmw_pend),
      .rmw_idx_o    (b_rmw_idx),
      .arr_cs_o     (b_cs),
      .arr_we_o     (b_we),
      .arr_idx_o    (b_idx),
      .arr_wdata_o  (b_wdata),
      .arr_lane_we_o(b_lane_we),
      .arr_rdata_i  (b_rdata),
      .ecc_inj_i    (2'b00),
      .ecc_corr_o   (b_ecc_corr),
      .ecc_uncorr_o (b_ecc_uncorr),
      .err_irq_o    (b_irq),
      .busy_o       (b_busy)
    );
  end else begin : g_no_port_b
    assign b_stall        = 1'b0;
    assign mem_b_gnt_o    = 1'b0;
    assign mem_b_rvalid_o = 1'b0;
    assign mem_b_rdata_o  = '0;
    assign mem_b_err_o    = 1'b0;
    assign b_wake         = '0;
    assign b_dom_busy     = '0;
    assign b_idle         = 1'b1;
    assign b_req_idx      = '0;
    assign b_req_we       = 1'b0;
    assign b_acc          = 1'b0;
    assign b_rmw_pend     = 1'b0;
    assign b_rmw_idx      = '0;
    assign b_cs           = 1'b0;
    assign b_we           = 1'b0;
    assign b_idx          = '0;
    assign b_wdata        = '0;
    assign b_lane_we      = '0;
    assign b_ecc_corr     = 1'b0;
    assign b_ecc_uncorr   = 1'b0;
    assign b_irq          = 1'b0;
    assign b_busy         = 1'b0;
  end

  assign port_wake    = a_wake | b_wake;
  assign dom_busy     = a_dom_busy | b_dom_busy;
  assign port_idle    = a_idle && b_idle;
  assign port_busy    = a_busy || b_busy;
  assign ecc_corr_o   = a_ecc_corr || b_ecc_corr;
  assign ecc_uncorr_o = a_ecc_uncorr || b_ecc_uncorr;
  assign err_irq_o    = a_irq || b_irq;

  // -------------------------------------------------------------------------
  // Power domains
  // -------------------------------------------------------------------------
  for (genvar d = 0; d < NPD; d++) begin : g_dom
    logic [1:0] req;   // requested mode (RUN while BIST holds every domain)

    assign req = bist_force ? sram_pkg::PWR_RUN : pwr_mode_req_i[2*d +: 2];

    // Access to a domain requested into deep sleep or shutdown is an error;
    // a domain requested RUN or light sleep may be woken.
    assign dom_err[d]      = PWR_GATE && (pwr_mode_req_i[2*d +: 2] == sram_pkg::PWR_DS ||
                                          pwr_mode_req_i[2*d +: 2] == sram_pkg::PWR_SD);
    assign dom_wakeable[d] = !dom_err[d];

    sram_pwr_ctrl #(
      .PWR_GATE (PWR_GATE),
      .ENTER_CYC(sram_pkg::pwr_enter_cycles(TECH)),
      .WAKE_LS  (sram_pkg::pwr_wake_cycles(TECH, sram_pkg::PWR_LS)),
      .WAKE_DS  (sram_pkg::pwr_wake_cycles(TECH, sram_pkg::PWR_DS)),
      .WAKE_SD  (sram_pkg::pwr_wake_cycles(TECH, sram_pkg::PWR_SD))
    ) u_pwr (
      .clk        (clk),
      .rst_n      (rst_n),
      .mode_req_i (req),
      .wake_i     (port_wake[d] || clr_wake[d]),
      .idle_i     (!dom_busy[d]),
      .clr_done_i (dom_clr_done[d]),
      .ls_o       (dom_ls[d]),
      .ds_o       (dom_ds[d]),
      .sd_o       (dom_sd[d]),
      .awake_o    (dom_awake[d]),
      .engine_ok_o(dom_ok[d]),
      .clr_req_o  (dom_clr_req[d]),
      .busy_o     (dom_pwr_busy[d]),
      .ack_o      (pwr_mode_ack_o[2*d +: 2])
    );
  end

  // -------------------------------------------------------------------------
  // Clear engine
  // -------------------------------------------------------------------------
  // With ECC every word must hold a valid codeword before it is read, so
  // the array is cleared after reset (bus requests stall until it is done).
  sram_clr #(
    .DEPTH         (DEPTH),
    .NPD           (NPD),
    .CLEAR_ON_RESET(ECC_EN)
  ) u_clr (
    .clk        (clk),
    .rst_n      (rst_n),
    .start_i    (clr_req_i),
    .mask_i     ({NPD{1'b1}}),
    .auto_i     (dom_clr_req),
    // Not while the march uses the array; a clear needed while BIST waits
    // for power (shutdown -> RUN) must still run, or BIST would wait forever.
    .port_idle_i(port_idle && !bist_active),
    .ok_i       (dom_ok),
    .wakeable_i (dom_wakeable),
    .wake_o     (clr_wake),
    .pending_o  (clr_pending),
    .busy_o     (clr_busy),
    .done_o     (clr_done_o),
    .dom_done_o (dom_clr_done),
    .cs_o       (clr_cs),
    .idx_o      (clr_idx)
  );

  // -------------------------------------------------------------------------
  // BIST
  // -------------------------------------------------------------------------
  if (BIST_EN) begin : g_bist
    sram_bist #(
      .DEPTH(DEPTH),
      .MW   (MW)
    ) u_bist (
      .clk        (clk),
      .rst_n      (rst_n),
      .start_i    (bist_start_i),
      .port_idle_i(port_idle),
      .all_ok_i   ((&dom_awake) && !clr_pending),
      .pending_o  (bist_pending),
      .force_run_o(bist_force),
      .busy_o     (bist_busy),
      .active_o   (bist_active),
      .done_o     (bist_done_o),
      .fail_o     (bist_fail_o),
      .fail_idx_o (bist_fail_addr_o),
      .cs_o       (bist_cs),
      .we_o       (bist_we),
      .idx_o      (bist_idx),
      .wdata_o    (bist_wdata),
      .rdata_i    (arr_rdata)
    );
  end else begin : g_no_bist
    assign bist_pending     = 1'b0;
    assign bist_force       = 1'b0;
    assign bist_busy        = 1'b0;
    assign bist_active      = 1'b0;
    assign bist_done_o      = 1'b0;
    assign bist_fail_o      = 1'b0;
    assign bist_fail_addr_o = '0;
    assign bist_cs          = 1'b0;
    assign bist_we          = 1'b0;
    assign bist_idx         = '0;
    assign bist_wdata       = '0;
  end

  // -------------------------------------------------------------------------
  // Array ownership: BIST, then clear engine, then the bus port
  // -------------------------------------------------------------------------
  always_comb begin : p_arbiter
    if (bist_cs) begin
      arr_cs      = 1'b1;
      arr_we      = bist_we;
      arr_idx     = bist_idx;
      arr_wdata   = bist_wdata;
      arr_lane_we = '1;
    end else if (clr_cs) begin
      arr_cs      = 1'b1;
      arr_we      = 1'b1;
      arr_idx     = clr_idx;
      arr_wdata   = '0;   // all-zero is also the SECDED codeword of zero
      arr_lane_we = '1;
    end else begin
      arr_cs      = p_cs;
      arr_we      = p_we;
      arr_idx     = p_idx;
      arr_wdata   = p_wdata;
      arr_lane_we = p_lane_we;
    end
  end

  // Sleep pins per bank from the bank's domain.
  logic [NUM_BANKS-1:0] bank_ls, bank_ds, bank_sd;
  for (genvar b = 0; b < NUM_BANKS; b++) begin : g_bank_pins
    assign bank_ls[b] = dom_ls[b / BanksPerDom];
    assign bank_ds[b] = dom_ds[b / BanksPerDom];
    assign bank_sd[b] = dom_sd[b / BanksPerDom];
  end

  sram_array #(
    .TECH     (TECH),
    .MW       (MW),
    .DEPTH    (DEPTH),
    .NUM_BANKS(NUM_BANKS),
    .NLANES   (NLanes),
    .DUAL_PORT(DUAL_PORT),
    .INIT_FILE(INIT_FILE)
  ) u_array (
    .clk        (clk),
    .cs_i       (arr_cs),
    .we_i       (arr_we),
    .idx_i      (arr_idx),
    .wdata_i    (arr_wdata),
    .lane_we_i  (arr_lane_we),
    .ls_i       (bank_ls),
    .ds_i       (bank_ds),
    .sd_i       (bank_sd),
    .rdata_o    (arr_rdata),
    .b_cs_i     (b_cs),
    .b_we_i     (b_we),
    .b_idx_i    (b_idx),
    .b_wdata_i  (b_wdata),
    .b_lane_we_i(b_lane_we),
    .b_rdata_o  (b_rdata)
  );

  assign busy_o = clr_pending || bist_busy || (|dom_pwr_busy) || port_busy;

endmodule : sram_core
