// claude_apb_fv.sv — Reusable APB4 formal checker + transaction observer.
//
// Attach to any APB4 slave port (typically by binding it, together with an
// IP-specific register-map checker, into an IP's APB top-level). Every port
// is an input, so the module can be bound to SystemVerilog or VHDL designs.
//
// Roles (MASTER_IS_ENV):
//   1 (default) — master rules are ASSUMED (the solver acts as a legal APB4
//                 master), slave rules are ASSERTED against the design.
//   0           — master rules are ASSERTED, slave rules ASSUMED (use when
//                 checking an APB master).
//
// Master rules (APB4, IHI0024):
//   m_enable_needs_sel   PENABLE only while PSEL
//   m_setup_to_access    SETUP is always followed by ACCESS
//   m_access_after_setup ACCESS is entered only from SETUP (or a wait state)
//   m_setup_stable       address/control/data held from SETUP into ACCESS
//   m_wait_hold          ACCESS with PREADY low holds every master signal
//   m_access_to_idle     completed ACCESS leaves PENABLE low next cycle
//   m_read_strb_zero     PSTRB is all-zero for reads
// Slave rules:
//   s_ready_bounded      PREADY arrives within MAX_WAIT cycles of ACCESS
//
// Transaction observer (protocol-neutral, consumed by claude_reg_fv):
//   obs_wr_vld   one-cycle pulse when a write completes on the bus
//   obs_rd_req   one-cycle pulse when a read is first presented (SETUP)
//   obs_rd_vld   one-cycle pulse when a read completes (PRDATA valid)
//   obs_wr_busy  a write is presented but not yet complete
//   *_addr       word address = PADDR[ADDR_W+1:2] (matches claude_apb_if)

`include "claude_fv_defines.svh"

module claude_apb_fv #(
  parameter int unsigned DATA_W        = 32, // data bus width
  parameter int unsigned ADDR_W        = 4,  // register word-address width
  parameter int unsigned PADDR_W       = 12, // PADDR width
  parameter bit          MASTER_IS_ENV = 1,  // 1: assume master, assert slave
  parameter int unsigned MAX_WAIT      = 16  // max ACCESS wait states
) (
  input  logic                  PCLK,
  input  logic                  PRESETn,
  input  logic                  PSEL,
  input  logic                  PENABLE,
  input  logic [PADDR_W-1:0]    PADDR,
  input  logic                  PWRITE,
  input  logic [DATA_W-1:0]     PWDATA,
  input  logic [DATA_W/8-1:0]   PSTRB,
  input  logic [DATA_W-1:0]     PRDATA,
  input  logic                  PREADY,
  input  logic                  PSLVERR,

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

  default clocking cb @(posedge PCLK); endclocking
  default disable iff (!PRESETn);

  logic setup;    // SETUP phase
  logic access;   // ACCESS phase
  logic xfer_done;

  assign setup     = PSEL & ~PENABLE;
  assign access    = PSEL &  PENABLE;
  assign xfer_done = access & PREADY;

  // -------------------------------------------------------------------------
  // Master rules
  // -------------------------------------------------------------------------
  `CLAUDE_FV_MASTER(m_enable_needs_sel, PENABLE |-> PSEL)
  `CLAUDE_FV_MASTER(m_setup_to_access,  setup |=> access)
  `CLAUDE_FV_MASTER(m_access_after_setup,
    access |-> ($past(setup) || $past(access && !PREADY)))
  `CLAUDE_FV_MASTER(m_setup_stable,
    setup |=> $stable({PADDR, PWRITE, PWDATA, PSTRB}))
  `CLAUDE_FV_MASTER(m_wait_hold,
    (access && !PREADY) |=> (access && $stable({PADDR, PWRITE, PWDATA, PSTRB})))
  `CLAUDE_FV_MASTER(m_access_to_idle, xfer_done |=> !PENABLE)
  `CLAUDE_FV_MASTER(m_read_strb_zero, (PSEL && !PWRITE) |-> (PSTRB == '0))

  // -------------------------------------------------------------------------
  // Slave rules
  // -------------------------------------------------------------------------
  `CLAUDE_FV_SLAVE(s_ready_bounded, access |-> ##[0:MAX_WAIT] PREADY)

  // -------------------------------------------------------------------------
  // Coverage
  // -------------------------------------------------------------------------
  c_write:       cover property (xfer_done &&  PWRITE);
  c_read:        cover property (xfer_done && !PWRITE);
  c_back2back:   cover property (xfer_done ##1 setup);
  c_slverr:      cover property (xfer_done && PSLVERR);

  // -------------------------------------------------------------------------
  // Transaction observer
  // -------------------------------------------------------------------------
  assign obs_wr_vld  = xfer_done & PWRITE;
  assign obs_wr_addr = PADDR[ADDR_W+1:2];
  assign obs_wr_data = PWDATA;
  assign obs_wr_strb = PSTRB;
  assign obs_wr_busy = PSEL & PWRITE & ~xfer_done;
  assign obs_rd_req  = setup & ~PWRITE;
  assign obs_rd_vld  = xfer_done & ~PWRITE;
  assign obs_rd_addr = PADDR[ADDR_W+1:2];
  assign obs_rd_data = PRDATA;

endmodule : claude_apb_fv
