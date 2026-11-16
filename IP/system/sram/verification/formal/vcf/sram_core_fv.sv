// sram_core_fv.sv — VC Formal checker for sram_core (SV and VHDL).
//
// Bound into sram_core by sram_fv_block_binds.svh. Every port is an input;
// besides the core's ports it reads a few internal signals that the SV and
// VHDL cores both declare (clr_busy, bist_busy, bist_active, b_cs, a_stall, b_stall,
// a_rmw_pend, b_rmw_pend, b_dom_err). Parameters arrive as literals from the
// generated sram_fv_cfg.svh (an SV bind cannot see VHDL generics).
//
// Memory bus (claude_mem_fv, IP/common), one per port:
//   core-level jobs  INITIATOR_IS_DUT = 0: target rules asserted, the
//                    solver plays a legal initiator
//   top-level jobs   BOTH_DUT = 1 (ENV_IS_RTL): the initiator is the real
//                    bus adapter, so its rules are asserted too
//   Response bounds (MAX_WAIT) need the environment rule am_sideband_quiet:
//   clear / BIST requests and power-request changes only while the port has
//   nothing in flight. Otherwise a stream of engine requests may hold the
//   bus off for ever (by design: a pending engine stalls new grants).
//   CHECK_BOUNDS = 0 (separate clocks, random clk_b) drops bounds and rule.
//
// Errors (a_err_rule / b_err_rule): the response error is predicted at the
// grant (address beyond the array, domain requested DS/SD, partial write
// with BYTE_EN = 0 and PARTIAL_WR_ERR, write to a read-only port B) and
// compared at the response. ECC error injection is held off (am_no_inject):
// the SECDED code itself is proven by the separate ecc job.
//
// Data integrity, one symbolic byte `sym` of the array (any byte, fixed for
// a trace). Writes take effect at their grant and reads return the byte as
// it was at their grant: a read-modify-write is written back one cycle
// after its grant, and the core grants no conflicting access before that,
// which this model checks. With two ports on one clock, port A's grant is
// applied before port B's in the same cycle (the core's A-then-B order).
// Byte lanes, BYTE_EN = 0 full-word writes, port-width packing (little
// endian) and ECC codeword lanes all reduce to "what happened to this byte".
// A clear request, BIST start, or a shutdown request of the byte's domain
// makes zero an accepted value as well (the clear engine zeroes, BIST leaves
// zeros, a deep-sleep domain skipped by a clear keeps its data).
// Separate clocks (COMMON_CLK = 0): same-word accesses in overlapping cycles
// are undefined, so each port has its own symbolic byte that the other port
// never accesses (assumed), and port B's zero allowance becomes sticky.
//
// Engines and array:
//   a_eng_exclusive   a clear pass never overlaps the BIST march (a clear
//                     may run while BIST still waits for the port or power)
//   a_eng_no_grant_a  no port-A grant while an engine runs
//   a_eng_no_b_access port B never accesses the array while an engine runs
//                     (checked on clk_b: the sram_cdc permission handshake)

module sram_core_fv #(
  parameter int unsigned ADDR_W       = 8,
  parameter int unsigned WIDTH        = 16,
  parameter int unsigned DEPTH        = 16,
  parameter bit          BYTE_EN      = 1,
  parameter bit          PWE          = 1,   // PARTIAL_WR_ERR
  parameter bit          PWR_GATE     = 1,
  parameter bit          ECC_EN       = 0,
  parameter int unsigned NPD          = 1,
  parameter bit          BIST_EN      = 0,
  parameter bit          DUAL_PORT    = 0,
  parameter int unsigned WIDTH_B      = WIDTH,
  parameter bit          BYTE_EN_B    = BYTE_EN,
  parameter bit          PWE_B        = PWE,
  parameter bit          COMMON_CLK   = 1,
  parameter bit          READ_ONLY_B  = 0,
  parameter int unsigned MAX_WAIT     = 64,
  parameter bit          CHECK_BOUNDS = 1,
  parameter bit          ENV_IS_RTL   = 0    // the bus adapters are design RTL
) (
  input  logic                   clk,
  input  logic                   rst_n,
  input  logic                   clk_b,
  input  logic                   rst_b_n,
  // Port A
  input  logic                   mem_req_i,
  input  logic                   mem_gnt_o,
  input  logic                   mem_we_i,
  input  logic [ADDR_W-1:0]      mem_addr_i,
  input  logic [WIDTH/8-1:0]     mem_be_i,
  input  logic [WIDTH-1:0]       mem_wdata_i,
  input  logic                   mem_rvalid_o,
  input  logic [WIDTH-1:0]       mem_rdata_o,
  input  logic                   mem_err_o,
  // Port B
  input  logic                   mem_b_req_i,
  input  logic                   mem_b_gnt_o,
  input  logic                   mem_b_we_i,
  input  logic [ADDR_W-1:0]      mem_b_addr_i,
  input  logic [WIDTH_B/8-1:0]   mem_b_be_i,
  input  logic [WIDTH_B-1:0]     mem_b_wdata_i,
  input  logic                   mem_b_rvalid_o,
  input  logic [WIDTH_B-1:0]     mem_b_rdata_o,
  input  logic                   mem_b_err_o,
  // Side band
  input  logic [2*NPD-1:0]       pwr_mode_req_i,
  input  logic [2*NPD-1:0]       pwr_mode_ack_o,
  input  logic                   clr_req_i,
  input  logic                   clr_done_o,
  input  logic [1:0]             ecc_inj_i,
  input  logic                   bist_start_i,
  input  logic                   bist_done_o,
  // Internal signals of sram_core
  input  logic                   clr_busy,
  input  logic                   bist_busy,
  input  logic                   bist_active,
  input  logic                   b_cs,
  input  logic                   a_stall,
  input  logic                   b_stall,
  input  logic                   a_rmw_pend,
  input  logic                   b_rmw_pend,
  input  logic [NPD-1:0]         b_dom_err
);

  localparam int unsigned NB      = WIDTH / 8;
  localparam int unsigned NBB     = WIDTH_B / 8;
  localparam int unsigned OffA    = $clog2(NB);
  localparam int unsigned OffB    = $clog2(NBB);
  localparam int unsigned IdxW    = $clog2(DEPTH);
  localparam int unsigned DEPTH_B = WIDTH * DEPTH / WIDTH_B;
  localparam int unsigned IdxWB   = $clog2(DEPTH_B);
  localparam int unsigned TBW     = OffA + IdxW;              // symbolic byte width
  localparam int unsigned DomBits = $clog2(NPD);
  localparam int unsigned DomW    = (NPD > 1) ? DomBits : 1;
  localparam int unsigned OffWide = (OffA > OffB) ? OffA : OffB; // wide-word byte offset
  localparam bit          Async   = DUAL_PORT && !COMMON_CLK;
  localparam logic [1:0]  PwrDs   = 2'd2;
  localparam logic [1:0]  PwrSd   = 2'd3;

  // ---------------------------------------------------------------------------
  // Helpers
  // ---------------------------------------------------------------------------
  // Domain of global byte g (domains are the top index bits)
  function automatic logic [DomW-1:0] dom_of_byte(input logic [TBW-1:0] g);
    if (NPD > 1) return DomW'(g >> (TBW - DomBits));
    return '0;
  endfunction

  function automatic logic dom_err(input logic [DomW-1:0] d);
    return PWR_GATE && (pwr_mode_req_i[2*d +: 2] == PwrDs || pwr_mode_req_i[2*d +: 2] == PwrSd);
  endfunction

  // ---------------------------------------------------------------------------
  // Memory-bus rules
  // ---------------------------------------------------------------------------
  logic a_outst, b_outst;

  claude_mem_fv #(
    .DATA_W           (WIDTH),
    .ADDR_W           (ADDR_W),
    .INITIATOR_IS_DUT (0),
    .MAX_WAIT         (MAX_WAIT),
    .CHECK_BOUNDS     (CHECK_BOUNDS),
    .BOTH_DUT         (ENV_IS_RTL)
  ) u_mem_a (
    .clk        (clk),
    .rst        (!rst_n),
    .mem_req    (mem_req_i),
    .mem_gnt    (mem_gnt_o),
    .mem_we     (mem_we_i),
    .mem_addr   (mem_addr_i),
    .mem_be     (mem_be_i),
    .mem_wdata  (mem_wdata_i),
    .mem_rvalid (mem_rvalid_o),
    .mem_rdata  (mem_rdata_o),
    .mem_err    (mem_err_o),
    .outstanding(a_outst)
  );

  if (DUAL_PORT) begin : g_mem_b
    claude_mem_fv #(
      .DATA_W           (WIDTH_B),
      .ADDR_W           (ADDR_W),
      .INITIATOR_IS_DUT (0),
      .MAX_WAIT         (MAX_WAIT),
      .CHECK_BOUNDS     (CHECK_BOUNDS),
      .BOTH_DUT         (ENV_IS_RTL)
    ) u_mem_b (
      .clk        (clk_b),
      .rst        (!rst_b_n),
      .mem_req    (mem_b_req_i),
      .mem_gnt    (mem_b_gnt_o),
      .mem_we     (mem_b_we_i),
      .mem_addr   (mem_b_addr_i),
      .mem_be     (mem_b_be_i),
      .mem_wdata  (mem_b_wdata_i),
      .mem_rvalid (mem_b_rvalid_o),
      .mem_rdata  (mem_b_rdata_o),
      .mem_err    (mem_b_err_o),
      .outstanding(b_outst)
    );
  end else begin : g_no_mem_b
    assign b_outst = 1'b0;
  end

  // ---------------------------------------------------------------------------
  // Environment (port-A clock)
  // ---------------------------------------------------------------------------
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);

  // Unused port B inputs are tied to zero by every top-level.
  if (!DUAL_PORT) begin : g_no_b_env
    am_no_b_req: assume property (!mem_b_req_i);
  end

  am_no_inject:  assume property (ecc_inj_i == 2'b00);
  if (!BIST_EN) begin : g_no_bist_env
    am_no_bist: assume property (!bist_start_i);
  end

  if (CHECK_BOUNDS) begin : g_quiet
    logic port_active;
    assign port_active = mem_req_i || a_outst || (DUAL_PORT && (mem_b_req_i || b_outst));
    am_sideband_quiet: assume property (
      (clr_req_i || bist_start_i || pwr_mode_req_i != $past(pwr_mode_req_i)) |-> !port_active);
  end

  // ---------------------------------------------------------------------------
  // Symbolic bytes (free, constant)
  // ---------------------------------------------------------------------------
  // Self-holding registers without reset: the value is free at the start of
  // a proof and constant at every step after that. (Undriven nets with a
  // $stable assumption on clk were X-injected: with a random clk_b the solver
  // could change them between two clk edges, so port B's no-touch assumption
  // used a different byte than port A's model.)
  logic [TBW-1:0] sym_a;   // port A's byte (both ports' with one clock)
  logic [TBW-1:0] sym_b;   // port B's byte (separate clocks only)
  always_ff @(posedge clk) begin : p_sym_hold
    sym_a <= sym_a;
    sym_b <= sym_b;
  end

  logic sym_a_zero_ev;     // the byte may become zero (clear, BIST, shutdown)
  assign sym_a_zero_ev = clr_req_i || (BIST_EN && bist_start_i) ||
                         (PWR_GATE && pwr_mode_req_i[2*dom_of_byte(sym_a) +: 2] == PwrSd);

  // ---------------------------------------------------------------------------
  // Port A: request decode at the grant
  // ---------------------------------------------------------------------------
  logic             a_hs, a_oor, a_xerr, a_hit, a_wr_byte, a_rd_chk;
  logic [IdxW-1:0]  a_idx;
  logic [DomW-1:0]  a_dom;
  logic [OffA:0]    a_lane;    // byte lane of sym_a (one spare bit for OffA = 0)
  logic [7:0]       a_wbyte;

  assign a_hs   = mem_req_i && mem_gnt_o;
  assign a_idx  = mem_addr_i[OffA +: IdxW];
  if (ADDR_W > TBW) begin : g_a_oor
    assign a_oor = (mem_addr_i >> TBW) != '0;
  end else begin : g_a_no_oor
    assign a_oor = 1'b0;
  end
  assign a_dom   = (NPD > 1) ? DomW'(a_idx >> (IdxW - DomBits)) : '0;
  assign a_xerr  = a_oor || dom_err(a_dom) ||
                   (mem_we_i && !BYTE_EN && PWE && mem_be_i != '1);
  assign a_lane  = (OffA > 0) ? (OffA+1)'(sym_a % NB) : '0;
  assign a_hit   = !a_oor && (a_idx == IdxW'(sym_a >> OffA));
  assign a_wbyte = mem_wdata_i[8*a_lane +: 8];
  assign a_wr_byte = a_hs && mem_we_i && !a_xerr && a_hit &&
                     (BYTE_EN ? mem_be_i[a_lane] : 1'b1);

  // ---------------------------------------------------------------------------
  // Port B decode (on clk_b; with one clock clk_b is clk)
  // ---------------------------------------------------------------------------
  logic             b_hs, b_oor, b_xerr, b_derr;
  logic [IdxWB-1:0] b_idx;
  logic [DomW-1:0]  b_dom;
  logic [TBW-1:0]   b_sym;     // the byte port B's model follows
  logic [OffB:0]    b_lane;
  logic             b_hit, b_wr_byte;
  logic [7:0]       b_wbyte;

  assign b_sym  = Async ? sym_b : sym_a;
  assign b_hs   = DUAL_PORT && mem_b_req_i && mem_b_gnt_o;
  assign b_idx  = mem_b_addr_i[OffB +: IdxWB];
  if (ADDR_W > TBW) begin : g_b_oor
    assign b_oor = (mem_b_addr_i >> TBW) != '0;
  end else begin : g_b_no_oor
    assign b_oor = 1'b0;
  end
  assign b_dom  = (NPD > 1) ? DomW'(b_idx >> (IdxWB - DomBits)) : '0;
  // Separate clocks: port B sees the domain errors through sram_cdc.
  assign b_derr = Async ? b_dom_err[b_dom] : dom_err(b_dom);
  assign b_xerr = b_oor || b_derr || (READ_ONLY_B && mem_b_we_i) ||
                  (mem_b_we_i && !BYTE_EN_B && PWE_B && mem_b_be_i != '1);
  assign b_lane = (OffB > 0) ? (OffB+1)'(b_sym % NBB) : '0;
  assign b_hit  = !b_oor && (b_idx == IdxWB'(b_sym >> OffB));
  assign b_wbyte   = mem_b_wdata_i[8*b_lane +: 8];
  assign b_wr_byte = b_hs && mem_b_we_i && !b_xerr && b_hit &&
                     (BYTE_EN_B ? mem_b_be_i[b_lane] : 1'b1);

  // ---------------------------------------------------------------------------
  // Shadow of sym_a (port A's clock): value, known, may-be-zero
  // ---------------------------------------------------------------------------
  logic [7:0] sh_val, sh1_val, sh2_val;
  logic       sh_ok, sh1_ok, sh2_ok, sh_mz, sh1_mz, sh2_mz;
  logic       b_rd_chk_sync;

  // After port A's grant
  assign sh1_val = a_wr_byte ? a_wbyte : sh_val;
  assign sh1_ok  = sh_ok || a_wr_byte;
  assign sh1_mz  = a_wr_byte ? 1'b0 : sh_mz;
  // After port B's grant (one clock only)
  assign b_rd_chk_sync = !Async && b_hs && !mem_b_we_i && !b_xerr && b_hit && sh1_ok;
  assign sh2_val = (!Async && b_wr_byte) ? b_wbyte : sh1_val;
  assign sh2_ok  = sh1_ok || (!Async && b_wr_byte);
  assign sh2_mz  = (!Async && b_wr_byte) ? 1'b0 : sh1_mz;

  always_ff @(posedge clk) begin : p_shadow
    if (!rst_n) begin
      sh_val <= '0;
      sh_ok  <= 1'b0;
      sh_mz  <= 1'b0;
    end else begin
      sh_val <= sh2_val;
      sh_ok  <= sh2_ok;
      sh_mz  <= sh2_mz || sym_a_zero_ev;
    end
  end

  assign a_rd_chk = a_hs && !mem_we_i && !a_xerr && a_hit && sh_ok;

  // ---------------------------------------------------------------------------
  // Port A: expected response, captured at the grant
  // ---------------------------------------------------------------------------
  logic        aq_err, aq_chk, aq_mz;
  logic [7:0]  aq_exp;
  logic [OffA:0] aq_lane;

  always_ff @(posedge clk) begin : p_a_capture
    if (!rst_n) begin
      aq_err  <= 1'b0;
      aq_chk  <= 1'b0;
      aq_mz   <= 1'b0;
      aq_exp  <= '0;
      aq_lane <= '0;
    end else if (a_hs) begin
      aq_err  <= a_xerr;
      aq_chk  <= a_rd_chk;
      aq_mz   <= sh_mz;
      aq_exp  <= sh_val;
      aq_lane <= a_lane;
    end
  end

  a_err_rule: assert property (mem_rvalid_o |-> mem_err_o == aq_err);
  a_data:     assert property ((mem_rvalid_o && aq_chk) |->
                               (mem_rdata_o[8*aq_lane +: 8] == aq_exp ||
                                (aq_mz && mem_rdata_o[8*aq_lane +: 8] == 8'h00)));

  // ---------------------------------------------------------------------------
  // Port B: shadow (separate clocks only), expected response
  // ---------------------------------------------------------------------------
  logic        bq_err, bq_chk, bq_mz;
  logic [7:0]  bq_exp;
  logic [OffB:0] bq_lane;
  logic        b_rd_chk;
  logic [7:0]  bsh_val;
  logic        bsh_ok, bsh_mz;
  logic        zero_sticky;   // port-A-clock: a zero event happened (separate clocks)

  always_ff @(posedge clk) begin : p_zero_sticky
    if (!rst_n) begin
      zero_sticky <= 1'b0;
    end else if (clr_req_i || (BIST_EN && bist_start_i) ||
                 (PWR_GATE && pwr_mode_req_i[2*dom_of_byte(sym_b) +: 2] == PwrSd)) begin
      zero_sticky <= 1'b1;
    end
  end

  if (DUAL_PORT) begin : g_b_model
    if (Async) begin : g_async_shadow
      always_ff @(posedge clk_b) begin : p_b_shadow
        if (!rst_b_n) begin
          bsh_val <= '0;
          bsh_ok  <= 1'b0;
          bsh_mz  <= 1'b0;
        end else if (b_wr_byte) begin
          bsh_val <= b_wbyte;
          bsh_ok  <= 1'b1;
          bsh_mz  <= 1'b0;
        end
      end
      assign b_rd_chk = b_hs && !mem_b_we_i && !b_xerr && b_hit && bsh_ok;
    end else begin : g_sync_shadow
      assign bsh_val  = sh1_val;
      assign bsh_ok   = sh1_ok;
      assign bsh_mz   = sh1_mz;
      assign b_rd_chk = b_rd_chk_sync;
    end

    always_ff @(posedge clk_b) begin : p_b_capture
      if (!rst_b_n) begin
        bq_err  <= 1'b0;
        bq_chk  <= 1'b0;
        bq_mz   <= 1'b0;
        bq_exp  <= '0;
        bq_lane <= '0;
      end else if (b_hs) begin
        bq_err  <= b_xerr;
        bq_chk  <= b_rd_chk;
        bq_mz   <= bsh_mz;
        bq_exp  <= bsh_val;
        bq_lane <= b_lane;
      end
    end

    b_err_rule: assert property (@(posedge clk_b) disable iff (!rst_b_n)
                                 mem_b_rvalid_o |-> mem_b_err_o == bq_err);
    b_data:     assert property (@(posedge clk_b) disable iff (!rst_b_n)
                                 (mem_b_rvalid_o && bq_chk) |->
                                 (mem_b_rdata_o[8*bq_lane +: 8] == bq_exp ||
                                  ((bq_mz || (Async && zero_sticky)) &&
                                   mem_b_rdata_o[8*bq_lane +: 8] == 8'h00)));

    // Separate clocks: neither port touches the other's symbolic byte (its
    // wide word), since same-word accesses in overlapping cycles are undefined.
    if (Async) begin : g_async_env
      logic [TBW-1:0] a_req_byte, b_req_byte;
      assign a_req_byte = TBW'({a_idx, {OffA{1'b0}}});
      assign b_req_byte = TBW'({b_idx, {OffB{1'b0}}});
      am_a_off_sym_b: assume property (mem_req_i |->
                                       (a_req_byte >> OffWide) != (sym_b >> OffWide));
      am_b_off_sym_a: assume property (@(posedge clk_b) mem_b_req_i |->
                                       (b_req_byte >> OffWide) != (sym_a >> OffWide));
    end
  end else begin : g_no_b_model
    assign b_rd_chk = 1'b0;
    assign bsh_val  = '0;
    assign bsh_ok   = 1'b0;
    assign bsh_mz   = 1'b0;
  end

  // ---------------------------------------------------------------------------
  // Engines and the array
  // ---------------------------------------------------------------------------
  a_eng_exclusive:  assert property (!(clr_busy && bist_active));
  a_eng_no_grant_a: assert property ((clr_busy || bist_busy) |-> !mem_gnt_o);
  if (DUAL_PORT) begin : g_eng_b
    a_eng_no_b_access: assert property (@(posedge clk_b) disable iff (!rst_b_n)
                                        b_cs |-> !(clr_busy || bist_busy));
  end

  // ---------------------------------------------------------------------------
  // Coverage
  // ---------------------------------------------------------------------------
  c_a_write_sym:  cover property (a_wr_byte);
  c_a_read_sym:   cover property (mem_rvalid_o && aq_chk && !aq_mz);
  c_a_err_oor:    cover property (a_hs && a_oor);
  if (PWR_GATE) begin : g_c_dom_err
    c_a_err_dom:  cover property (a_hs && !a_oor && dom_err(a_dom));
  end
  c_a_zero_ok:    cover property (mem_rvalid_o && aq_chk && aq_mz && aq_exp != 8'h00 &&
                                  mem_rdata_o[8*aq_lane +: 8] == 8'h00);
  c_clr_done:     cover property (clr_done_o);
  if (!BYTE_EN && PWE) begin : g_c_perr
    c_a_err_partial: cover property (a_hs && mem_we_i && mem_be_i != '1 && mem_be_i != '0);
  end
  if (!BYTE_EN && !PWE) begin : g_c_pfull
    c_a_partial_full: cover property (a_hs && mem_we_i && a_hit && !a_xerr &&
                                      mem_be_i != '1 && mem_be_i != '0);
  end
  if (ECC_EN) begin : g_c_ecc
    c_a_rmw:      cover property (a_rmw_pend);
  end
  if (BIST_EN) begin : g_c_bist
    c_bist_done:  cover property (bist_done_o);
  end
  if (DUAL_PORT) begin : g_c_dp
    c_b_write_sym: cover property (@(posedge clk_b) disable iff (!rst_b_n) b_wr_byte);
    c_b_read_sym:  cover property (@(posedge clk_b) disable iff (!rst_b_n)
                                   mem_b_rvalid_o && bq_chk && !bq_mz);
    if (!Async) begin : g_c_sync
      // B held back by A's access to the same word, and A held back by B's
      // pending read-modify-write of the same word.
      c_b_waits_a:     cover property (mem_b_req_i && b_stall && !clr_busy && !bist_busy &&
                                       a_hs);
      c_both_read_sym: cover property (a_hs && b_hs && !mem_we_i && !mem_b_we_i &&
                                       a_hit && b_hit);
      if (ECC_EN) begin : g_c_rmw
        c_a_waits_b_rmw: cover property (mem_req_i && a_stall && b_rmw_pend);
        c_b_waits_a_rmw: cover property (mem_b_req_i && b_stall && a_rmw_pend);
      end
    end else begin : g_c_async
      c_b_engine_wait: cover property (mem_b_req_i && (clr_busy || bist_busy));
    end
  end

endmodule : sram_core_fv
