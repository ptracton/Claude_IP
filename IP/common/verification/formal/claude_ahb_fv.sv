// claude_ahb_fv.sv — Reusable AHB-Lite formal checker + transaction observer.
//
// Attach to any AHB-Lite slave port that uses the claude_ahb_if pin set
// (HSEL/HADDR/HTRANS/HWRITE/HWDATA/HWSTRB in, HRDATA/HREADY/HRESP out; no
// HSIZE/HBURST, HREADY is the slave's HREADYOUT fed back as the bus HREADY).
// Every port is an input, so it can be bound into SV or VHDL designs.
//
// Roles (MASTER_IS_ENV): see claude_apb_fv.sv.
//
// Master rules (AHB-Lite, IHI0033):
//   m_single_only      only IDLE / NONSEQ transfers (SINGLE_ONLY=1): the
//                      claude_ahb_if bridge does not implement bursts
//   m_addr_hold        address/control held while HREADY is low
//   m_wdata_hold       write data/strobes held during a stalled data phase
// Slave rules:
//   s_ready_bounded    a data phase completes within MAX_WAIT cycles
//   s_idle_okay        no data phase in flight -> HREADY high, HRESP OKAY
//   s_error_two_cycle  ERROR response: first cycle HREADY low, then high
//
// Transaction observer: see claude_apb_fv.sv. Writes complete (obs_wr_vld)
// and reads return data (obs_rd_vld) in the data phase with HREADY high;
// reads are requested (obs_rd_req) when the address phase is accepted.
// Word address = HADDR[ADDR_W+1:2] (matches claude_ahb_if).

`include "claude_fv_defines.svh"

module claude_ahb_fv #(
  parameter int unsigned DATA_W        = 32,
  parameter int unsigned ADDR_W        = 4,
  parameter int unsigned HADDR_W       = 12,
  parameter bit          MASTER_IS_ENV = 1,
  parameter bit          SINGLE_ONLY   = 1,  // constrain HTRANS to IDLE/NONSEQ
  parameter int unsigned MAX_WAIT      = 16
) (
  input  logic                  HCLK,
  input  logic                  HRESETn,
  input  logic                  HSEL,
  input  logic [HADDR_W-1:0]    HADDR,
  input  logic [1:0]            HTRANS,
  input  logic                  HWRITE,
  input  logic [DATA_W-1:0]     HWDATA,
  input  logic [DATA_W/8-1:0]   HWSTRB,
  input  logic [DATA_W-1:0]     HRDATA,
  input  logic                  HREADY,
  input  logic                  HRESP,

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

  localparam logic [1:0] HTRANS_IDLE   = 2'b00;
  localparam logic [1:0] HTRANS_NONSEQ = 2'b10;

  default clocking cb @(posedge HCLK); endclocking
  default disable iff (!HRESETn);

  logic              aphase;     // valid address phase presented this cycle
  logic              dphase_q;   // data phase in progress
  logic              dwrite_q;   // data phase is a write
  logic [ADDR_W-1:0] daddr_q;    // data phase word address

  assign aphase = HSEL & HTRANS[1];

  always_ff @(posedge HCLK) begin
    if (!HRESETn) begin
      dphase_q <= 1'b0;
      dwrite_q <= 1'b0;
      daddr_q  <= '0;
    end else if (HREADY) begin
      dphase_q <= aphase;
      dwrite_q <= HWRITE;
      daddr_q  <= HADDR[ADDR_W+1:2];
    end
  end

  // -------------------------------------------------------------------------
  // Master rules
  // -------------------------------------------------------------------------
  if (SINGLE_ONLY) begin : g_single
    `CLAUDE_FV_MASTER(m_single_only,
      HSEL |-> (HTRANS == HTRANS_IDLE || HTRANS == HTRANS_NONSEQ))
  end
  `CLAUDE_FV_MASTER(m_addr_hold,
    (aphase && !HREADY) |=> (aphase && $stable({HADDR, HTRANS, HWRITE})))
  `CLAUDE_FV_MASTER(m_wdata_hold,
    (dphase_q && dwrite_q && !HREADY) |=> $stable({HWDATA, HWSTRB}))

  // -------------------------------------------------------------------------
  // Slave rules
  // -------------------------------------------------------------------------
  `CLAUDE_FV_SLAVE(s_ready_bounded, dphase_q |-> ##[0:MAX_WAIT] HREADY)
  `CLAUDE_FV_SLAVE(s_idle_okay, !dphase_q |-> (HREADY && !HRESP))
  `CLAUDE_FV_SLAVE(s_error_two_cycle, (HRESP && !HREADY) |=> (HRESP && HREADY))

  // -------------------------------------------------------------------------
  // Coverage
  // -------------------------------------------------------------------------
  c_write:      cover property (dphase_q &&  dwrite_q && HREADY);
  c_read:       cover property (dphase_q && !dwrite_q && HREADY);
  c_pipelined:  cover property (dphase_q && aphase && HREADY);
  c_wr_then_rd: cover property (dphase_q && dwrite_q && aphase && !HWRITE && HREADY);
  c_wait:       cover property (dphase_q && !HREADY);

  // -------------------------------------------------------------------------
  // Transaction observer
  // -------------------------------------------------------------------------
  assign obs_wr_vld  = dphase_q & dwrite_q & HREADY;
  assign obs_wr_addr = daddr_q;
  assign obs_wr_data = HWDATA;
  assign obs_wr_strb = HWSTRB;
  assign obs_wr_busy = dphase_q & dwrite_q & ~HREADY;
  assign obs_rd_req  = aphase & ~HWRITE & HREADY;
  assign obs_rd_vld  = dphase_q & ~dwrite_q & HREADY;
  assign obs_rd_addr = daddr_q;
  assign obs_rd_data = HRDATA;

endmodule : claude_ahb_fv
