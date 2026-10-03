// claude_wb_fv.sv — Reusable Wishbone B4 (classic) formal checker + observer.
//
// Attach to any Wishbone B4 classic slave port (claude_wb_if pin set:
// CYC_I/STB_I/WE_I/ADR_I/DAT_I/SEL_I in, DAT_O/ACK_O/ERR_O out, RST_I
// synchronous active-high). Every port is an input, so it can be bound into
// SV or VHDL designs.
//
// Roles (MASTER_IS_ENV): see claude_apb_fv.sv.
//
// Master rules (Wishbone B4, classic cycles):
//   m_stb_needs_cyc   STB_I only inside a bus cycle (CYC_I)
//   m_hold            request held until ACK_O or ERR_O terminates it
// Slave rules:
//   s_ack_needs_stb   ACK_O / ERR_O only in response to CYC_I & STB_I
//   s_ack_err_excl    ACK_O and ERR_O never together
//   s_ack_bounded     every request terminated within MAX_WAIT cycles
//
// Transaction observer: transfers complete (obs_wr_vld / obs_rd_vld) in the
// ACK_O cycle; a read is requested (obs_rd_req) in its first STB cycle.
// Word address = ADR_I[ADDR_W+1:2] (matches claude_wb_if).

`include "claude_fv_defines.svh"

module claude_wb_fv #(
  parameter int unsigned DATA_W        = 32,
  parameter int unsigned ADDR_W        = 4,
  parameter int unsigned ADR_W         = 12,
  parameter bit          MASTER_IS_ENV = 1,
  parameter int unsigned MAX_WAIT      = 16
) (
  input  logic                  CLK_I,
  input  logic                  RST_I,
  input  logic                  CYC_I,
  input  logic                  STB_I,
  input  logic                  WE_I,
  input  logic [ADR_W-1:0]      ADR_I,
  input  logic [DATA_W-1:0]     DAT_I,
  input  logic [DATA_W/8-1:0]   SEL_I,
  input  logic [DATA_W-1:0]     DAT_O,
  input  logic                  ACK_O,
  input  logic                  ERR_O,

  output logic                  obs_wr_vld,
  output logic [ADDR_W-1:0]     obs_wr_addr,
  output logic [DATA_W-1:0]     obs_wr_data,
  output logic [DATA_W/8-1:0]   obs_wr_strb,
  output logic                  obs_wr_busy,
  output logic                  obs_rd_req,
  output logic                  obs_rd_vld,
  output logic [ADDR_W-1:0]     obs_rd_addr,
  output logic [DATA_W-1:0]     obs_rd_data
);

  default clocking cb @(posedge CLK_I); endclocking
  default disable iff (RST_I);

  logic req;        // request presented
  logic term;       // request terminated this cycle
  logic in_xfer_q;  // request presented earlier and not yet terminated

  assign req  = CYC_I & STB_I;
  assign term = req & (ACK_O | ERR_O);

  always_ff @(posedge CLK_I) begin
    if (RST_I) in_xfer_q <= 1'b0;
    else       in_xfer_q <= req & ~term;
  end

  // -------------------------------------------------------------------------
  // Master rules
  // -------------------------------------------------------------------------
  `CLAUDE_FV_MASTER(m_stb_needs_cyc, STB_I |-> CYC_I)
  `CLAUDE_FV_MASTER(m_hold,
    (req && !ACK_O && !ERR_O) |=> (req && $stable({WE_I, ADR_I, DAT_I, SEL_I})))

  // -------------------------------------------------------------------------
  // Slave rules
  // -------------------------------------------------------------------------
  `CLAUDE_FV_SLAVE(s_ack_needs_stb, (ACK_O || ERR_O) |-> req)
  `CLAUDE_FV_SLAVE(s_ack_err_excl,  !(ACK_O && ERR_O))
  `CLAUDE_FV_SLAVE(s_ack_bounded,   req |-> ##[0:MAX_WAIT] (ACK_O || ERR_O))

  // -------------------------------------------------------------------------
  // Coverage
  // -------------------------------------------------------------------------
  c_write:      cover property (term && ACK_O &&  WE_I);
  c_read:       cover property (term && ACK_O && !WE_I);
  c_back2back:  cover property (term ##1 req);
  c_err:        cover property (term && ERR_O);

  // -------------------------------------------------------------------------
  // Transaction observer
  // -------------------------------------------------------------------------
  assign obs_wr_vld  = req & ACK_O & WE_I;
  assign obs_wr_addr = ADR_I[ADDR_W+1:2];
  assign obs_wr_data = DAT_I;
  assign obs_wr_strb = SEL_I;
  assign obs_wr_busy = req & WE_I & ~ACK_O;
  assign obs_rd_req  = req & ~WE_I & ~in_xfer_q;
  assign obs_rd_vld  = req & ACK_O & ~WE_I;
  assign obs_rd_addr = ADR_I[ADDR_W+1:2];
  assign obs_rd_data = DAT_O;

endmodule : claude_wb_fv
