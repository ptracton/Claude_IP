// claude_axi4l_fv.sv — Reusable AXI4-Lite formal checker + transaction observer.
//
// Attach to any AXI4-Lite slave port (claude_axi4l_if pin set). Every port
// is an input, so it can be bound into SV or VHDL designs.
//
// Roles (MASTER_IS_ENV): see claude_apb_fv.sv.
//
// Master rules (AXI, IHI0022 A3.2):
//   m_aw_hold / m_w_hold / m_ar_hold
//                  VALID stays high and payload stable until READY
//   m_single_wr / m_single_rd
//                  at most one outstanding write / read (claude_axi4l_if
//                  documents "single outstanding transaction per channel")
// Slave rules:
//   s_b_hold / s_r_hold      BVALID/RVALID + payload held until READY
//   s_b_after_aw_w           no write response before AW and W handshakes
//   s_r_after_ar             no read data before the AR handshake
//   s_b_bounded / s_r_bounded  responses within MAX_WAIT cycles
//   s_aw_ready / s_w_ready / s_ar_ready  requests accepted within MAX_WAIT
//
// Transaction observer: a write completes (obs_wr_vld) on the B handshake,
// a read is requested (obs_rd_req) on the AR handshake and completes
// (obs_rd_vld) on the R handshake. obs_wr_busy covers every cycle from the
// first AW/W VALID to the B handshake. Word address = ADDR[ADDR_W+1:2].

`include "claude_fv_defines.svh"

module claude_axi4l_fv #(
  parameter int unsigned DATA_W        = 32,
  parameter int unsigned ADDR_W        = 4,
  parameter int unsigned AXADDR_W      = 12,
  parameter bit          MASTER_IS_ENV = 1,
  parameter int unsigned MAX_WAIT      = 16
) (
  input  logic                  ACLK,
  input  logic                  ARESETn,
  input  logic                  AWVALID,
  input  logic                  AWREADY,
  input  logic [AXADDR_W-1:0]   AWADDR,
  input  logic                  WVALID,
  input  logic                  WREADY,
  input  logic [DATA_W-1:0]     WDATA,
  input  logic [DATA_W/8-1:0]   WSTRB,
  input  logic                  BVALID,
  input  logic                  BREADY,
  input  logic [1:0]            BRESP,
  input  logic                  ARVALID,
  input  logic                  ARREADY,
  input  logic [AXADDR_W-1:0]   ARADDR,
  input  logic                  RVALID,
  input  logic                  RREADY,
  input  logic [DATA_W-1:0]     RDATA,
  input  logic [1:0]            RRESP,

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

  default clocking cb @(posedge ACLK); endclocking
  default disable iff (!ARESETn);

  logic aw_hs, w_hs, b_hs, ar_hs, r_hs;
  assign aw_hs = AWVALID & AWREADY;
  assign w_hs  = WVALID  & WREADY;
  assign b_hs  = BVALID  & BREADY;
  assign ar_hs = ARVALID & ARREADY;
  assign r_hs  = RVALID  & RREADY;

  // Outstanding-transaction tracking (at most one per direction).
  logic                aw_done_q, w_done_q, ar_done_q;
  logic [ADDR_W-1:0]   aw_addr_q, ar_addr_q;
  logic [DATA_W-1:0]   w_data_q;
  logic [DATA_W/8-1:0] w_strb_q;
  logic                both_q;

  always_ff @(posedge ACLK) begin
    if (!ARESETn) begin
      aw_done_q <= 1'b0;
      w_done_q  <= 1'b0;
      ar_done_q <= 1'b0;
      aw_addr_q <= '0;
      ar_addr_q <= '0;
      w_data_q  <= '0;
      w_strb_q  <= '0;
    end else begin
      if (b_hs) begin
        aw_done_q <= 1'b0;
        w_done_q  <= 1'b0;
      end else begin
        if (aw_hs) begin
          aw_done_q <= 1'b1;
          aw_addr_q <= AWADDR[ADDR_W+1:2];
        end
        if (w_hs) begin
          w_done_q <= 1'b1;
          w_data_q <= WDATA;
          w_strb_q <= WSTRB;
        end
      end
      if (r_hs) begin
        ar_done_q <= 1'b0;
      end else if (ar_hs) begin
        ar_done_q <= 1'b1;
        ar_addr_q <= ARADDR[ADDR_W+1:2];
      end
    end
  end

  assign both_q = aw_done_q & w_done_q;

  // -------------------------------------------------------------------------
  // Master rules
  // -------------------------------------------------------------------------
  `CLAUDE_FV_MASTER(m_aw_hold, (AWVALID && !AWREADY) |=> (AWVALID && $stable(AWADDR)))
  `CLAUDE_FV_MASTER(m_w_hold,  (WVALID  && !WREADY)  |=> (WVALID  && $stable({WDATA, WSTRB})))
  `CLAUDE_FV_MASTER(m_ar_hold, (ARVALID && !ARREADY) |=> (ARVALID && $stable(ARADDR)))
  `CLAUDE_FV_MASTER(m_single_wr, !(aw_done_q && AWVALID) && !(w_done_q && WVALID))
  `CLAUDE_FV_MASTER(m_single_rd, !(ar_done_q && ARVALID))

  // -------------------------------------------------------------------------
  // Slave rules
  // -------------------------------------------------------------------------
  `CLAUDE_FV_SLAVE(s_b_hold, (BVALID && !BREADY) |=> (BVALID && $stable(BRESP)))
  `CLAUDE_FV_SLAVE(s_r_hold, (RVALID && !RREADY) |=> (RVALID && $stable({RDATA, RRESP})))
  `CLAUDE_FV_SLAVE(s_b_after_aw_w, BVALID |-> both_q)
  `CLAUDE_FV_SLAVE(s_r_after_ar,   RVALID |-> ar_done_q)
  `CLAUDE_FV_SLAVE(s_b_bounded, (both_q && !$past(both_q)) |-> ##[0:MAX_WAIT] BVALID)
  `CLAUDE_FV_SLAVE(s_r_bounded, (ar_done_q && !$past(ar_done_q)) |-> ##[0:MAX_WAIT] RVALID)
  `CLAUDE_FV_SLAVE(s_aw_ready, AWVALID |-> ##[0:MAX_WAIT] AWREADY)
  `CLAUDE_FV_SLAVE(s_w_ready,  WVALID  |-> ##[0:MAX_WAIT] WREADY)
  `CLAUDE_FV_SLAVE(s_ar_ready, ARVALID |-> ##[0:MAX_WAIT] ARREADY)

  // -------------------------------------------------------------------------
  // Coverage
  // -------------------------------------------------------------------------
  c_write:          cover property (b_hs);
  c_read:           cover property (r_hs);
  c_w_before_aw:    cover property (w_hs && !aw_done_q && !aw_hs);
  c_b_backpressure: cover property (BVALID && !BREADY);
  c_r_backpressure: cover property (RVALID && !RREADY);
  c_rd_wr_overlap:  cover property (ar_done_q && both_q);

  // -------------------------------------------------------------------------
  // Transaction observer
  // -------------------------------------------------------------------------
  assign obs_wr_vld  = b_hs;
  assign obs_wr_addr = aw_addr_q;
  assign obs_wr_data = w_data_q;
  assign obs_wr_strb = w_strb_q;
  assign obs_wr_busy = AWVALID | WVALID | aw_done_q | w_done_q;
  assign obs_rd_req  = ar_hs;
  assign obs_rd_vld  = r_hs;
  assign obs_rd_addr = ar_addr_q;
  assign obs_rd_data = RDATA;

endmodule : claude_axi4l_fv
